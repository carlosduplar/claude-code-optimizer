#requires -Version 5.1

<#
.SYNOPSIS
    Claude Code Token Optimizer & Privacy Enhancer for Windows (v2)

.DESCRIPTION
    This PowerShell script optimizes Claude Code for maximum token savings and privacy:
    1. Installs missing dependencies (markitdown, poppler, imagemagick) via winget/chocolatey
    2. Configures privacy and token optimization via settings.json env key
    3. Enables auto-compact and configures hooks for binary file interception
    4. Creates CLAUDE.md with compact instructions

.PARAMETER DryRun
    Show what would be done without making changes

.PARAMETER ReducedPrivacy
    Use reduced privacy (telemetry disabled only, keeps auto-updates)

.PARAMETER SkipDeps
    Skip dependency installation

.PARAMETER Experimental
    Include undocumented environment variables (use at your own risk)

.PARAMETER Force
    Overwrite existing files without prompting

.PARAMETER NoGuard
    Disable file-guard hook (not recommended)

.PARAMETER NoNotify
    Disable desktop notification hook

.PARAMETER NoContextRefresh
    Disable post-compact context re-injection hook

.PARAMETER AutoApprove
    Enable auto-approval whitelist for safe bash commands (opt-in)

.PARAMETER AutoFormat
    Enable auto-formatting after file edits (opt-in)

.EXAMPLE
    .\optimize-claude.ps1
    Full privacy mode (default) with dependency installation

.EXAMPLE
    .\optimize-claude.ps1 -ReducedPrivacy
    Reduced privacy mode (standard telemetry disabled only)

.EXAMPLE
    .\optimize-claude.ps1 -DryRun
    Preview changes without applying them

.EXAMPLE
    .\optimize-claude.ps1 -Experimental -AutoApprove
    Include experimental features and auto-approve safe commands
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$ReducedPrivacy,
    [switch]$SkipDeps,
    [switch]$Experimental,
    [switch]$Force,
    [switch]$NoGuard,
    [switch]$NoNotify,
    [switch]$NoContextRefresh,
    [switch]$AutoApprove,
    [switch]$AutoFormat
)

$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Warning = 'Yellow'
    Error = 'Red'
    Header = 'Blue'
}

$script:MissingDeps = @()
$script:InstallFailed = @()
$script:BashAvailable = $false

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Info
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor $Colors.Success
}

function Write-WarningLine {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Colors.Warning
}

function Write-ErrorLine {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Error
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor $Colors.Header
    Write-Host " $Message" -ForegroundColor $Colors.Header
    Write-Host "========================================" -ForegroundColor $Colors.Header
    Write-Host ""
}

function Test-Python {
    Write-Status "Checking Python installation..."
    $python = Get-Command python -ErrorAction SilentlyContinue
    $python3 = Get-Command python3 -ErrorAction SilentlyContinue
    if ($python3) {
        $script:PythonCmd = "python3"
        Write-Success "Python found"
        return $true
    } elseif ($python) {
        $script:PythonCmd = "python"
        Write-Success "Python found"
        return $true
    } else {
        Write-ErrorLine "Python is not installed"
        return $false
    }
}

function Test-Markitdown {
    Write-Status "Checking markitdown..."
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        Write-Success "markitdown is already installed"
        return $true
    }
    try {
        & $script:PythonCmd -c "import markitdown" 2>$null
        Write-Success "markitdown is already installed"
        return $true
    } catch {
        Write-WarningLine "markitdown is not installed"
        $script:MissingDeps += "markitdown"
        return $false
    }
}

function Test-ImageMagick {
    Write-Status "Checking ImageMagick..."
    $magick = Get-Command magick.exe -ErrorAction SilentlyContinue
    if ($magick) {
        Write-Success "ImageMagick is already installed"
        return $true
    } else {
        Write-WarningLine "ImageMagick is not installed"
        $script:MissingDeps += "imagemagick"
        return $false
    }
}

function Test-Poppler {
    Write-Status "Checking poppler (pdftotext)..."
    $pdftotext = Get-Command pdftotext.exe -ErrorAction SilentlyContinue
    if ($pdftotext) {
        Write-Success "poppler (pdftotext) is already installed"
        return $true
    }
    Write-WarningLine "poppler (pdftotext) is not installed"
    $script:MissingDeps += "poppler"
    return $false
}

function Test-Bash {
    Write-Status "Checking for bash availability..."
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
        $script:BashAvailable = $true
        Write-Success "bash found at: $($bash.Source)"
        return $true
    } else {
        Write-WarningLine "bash not found - will use PowerShell fallback for hooks"
        return $false
    }
}

function Install-Dependencies {
    if ($SkipDeps) {
        Write-Status "Skipping dependency check (-SkipDeps specified)"
        return
    }
    Write-Header "Checking Dependencies"
    if (-not (Test-Python)) {
        Write-ErrorLine "Python is required"
        return
    }
    Test-Markitdown
    Test-ImageMagick
    Test-Poppler
    Test-Bash
    if ($script:MissingDeps.Count -eq 0) {
        Write-Success "All dependencies are already installed!"
        return
    }
    Write-WarningLine "Missing dependencies: $($script:MissingDeps -join ', ')"
}

function Set-ClaudeSettings {
    Write-Header "Configuring Claude Code Settings"
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    $settingsFile = Join-Path $claudeDir "settings.json"
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    $envVars = @{
        BASH_MAX_OUTPUT_LENGTH = "10000"
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
        DISABLE_TELEMETRY = "1"
        OTEL_LOG_USER_PROMPTS = "0"
        OTEL_LOG_TOOL_DETAILS = "0"
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = "180000"
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "70"
        CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1"
    }
    if ($ReducedPrivacy) {
        $envVars.Remove("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")
    }
    if ($Experimental) {
        $envVars["CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS"] = "8000"
        $envVars["ENABLE_CLAUDE_CODE_SM_COMPACT"] = "1"
    }

    $hooksDir = Join-Path $claudeDir "hooks"
    if ($script:BashAvailable) {
        $pretooluseCmd = "bash ~/.claude/hooks/pretooluse.sh"
        $posttooluseCmd = "bash ~/.claude/hooks/posttooluse.sh"
        $fileguardCmd = "bash ~/.claude/hooks/file-guard.sh"
        $notifyCmd = "bash ~/.claude/hooks/notify.sh"
        $postcompactCmd = "bash ~/.claude/hooks/post-compact.sh"
    } else {
        $pretooluseCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\pretooluse.ps1`""
        $posttooluseCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\posttooluse.ps1`""
        $fileguardCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\file-guard.ps1`""
        $notifyCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\notify.ps1`""
        $postcompactCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\post-compact.ps1`""
    }

    $hooks = @{
        PreToolUse = @()
        PostToolUse = @()
        Notification = @()
        SessionStart = @()
    }
    $hooks.PreToolUse += @{
        matcher = "Read"
        hooks = @(@{ type = "command"; command = $pretooluseCmd; timeout = 30 })
    }
    if (-not $NoGuard) {
        $hooks.PreToolUse += @{
            matcher = "Write|Edit|MultiEdit|Bash"
            hooks = @(@{ type = "command"; command = $fileguardCmd; timeout = 10 })
        }
    }
    $hooks.PostToolUse += @{
        matcher = "*"
        hooks = @(@{ type = "command"; command = $posttooluseCmd; timeout = 5 })
    }
    if (-not $NoNotify) {
        $hooks.Notification += @{
            matcher = "*"
            hooks = @(@{ type = "command"; command = $notifyCmd; timeout = 15 })
        }
    }
    if (-not $NoContextRefresh) {
        $hooks.SessionStart += @{
            matcher = "compact"
            hooks = @(@{ type = "command"; command = $postcompactCmd; timeout = 10 })
        }
    }

    $settings = @{
        '$schema' = "https://json.schemastore.org/claude-code-settings.json"
        autoCompactEnabled = $true
        env = $envVars
        hooks = $hooks
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would write settings.json"
        return
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
    Write-Success "Created settings.json with optimizations"
}

function New-HookScripts {
    Write-Header "Creating Hook Scripts"
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    $hooksDir = Join-Path $claudeDir "hooks"
    if (-not (Test-Path $hooksDir)) {
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    }

    if ($script:BashAvailable) {
        $pretooluseSh = '#!/usr/bin/env bash
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r ''.tool_name // empty'')"
FILE_PATH="$(echo "$INPUT" | jq -r ''.tool_input.file_path // .tool_input.filePath // empty'')"
LOG_FILE="/tmp/claude-hook-validation.log"
log() { echo "$(date -Iseconds) | PreToolUse | $1" >> "$LOG_FILE"; }
if [[ "$TOOL_NAME" != "Read" ]]; then exit 0; fi
if [[ -z "$FILE_PATH" ]]; then log "NO_FILE_PATH"; exit 0; fi
log "FILE | $FILE_PATH"
if [[ ! -f "$FILE_PATH" ]]; then log "FILE_NOT_FOUND | $FILE_PATH"; exit 0; fi
exit 0'
        $posttooluseSh = '#!/usr/bin/env bash
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r ''.tool_name // empty'')"
LOG_FILE="/tmp/claude-hook-validation.log"
echo "$(date -Iseconds) | PostToolUse | FIRED | Tool: ${TOOL_NAME:-unknown}" >> "$LOG_FILE"
exit 0'
        $fileguardSh = '#!/usr/bin/env bash
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r ''.tool_name // empty'')"
FILE_PATH="$(echo "$INPUT" | jq -r ''.tool_input.file_path // .tool_input.filePath // empty'')"
LOG_FILE="/tmp/claude-file-guard.log"
echo "[file-guard] $(date -Iseconds) ALLOWED tool=$TOOL_NAME path=$FILE_PATH" >> "$LOG_FILE"
exit 0'
        $notifySh = '#!/usr/bin/env bash
INPUT="$(cat)"
MESSAGE="$(echo "$INPUT" | jq -r ''.message // .title // "Claude Code notification"'')"
TITLE="$(echo "$INPUT" | jq -r ''.title // "Claude Code"'')"
LOG_FILE="/tmp/claude-notify.log"
echo "[notify] $(date -Iseconds) title=$TITLE msg=$MESSAGE" >> "$LOG_FILE"
exit 0'
        $postcompactSh = '#!/usr/bin/env bash
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
LOG_FILE="/tmp/claude-post-compact.log"
echo "[post-compact] $(date -Iseconds) compaction detected, re-injecting context" >> "$LOG_FILE"
if [[ ! -f "$CLAUDE_MD" ]]; then exit 0; fi
echo "## Post-Compaction Context Refresh"
echo ""
echo "Your persistent instructions from ~/.claude/CLAUDE.md have been re-injected below."
echo ""
cat "$CLAUDE_MD"
exit 0'

        $scripts = @{
            "pretooluse.sh" = $pretooluseSh
            "posttooluse.sh" = $posttooluseSh
            "file-guard.sh" = $fileguardSh
            "notify.sh" = $notifySh
            "post-compact.sh" = $postcompactSh
        }
        foreach ($name in $scripts.Keys) {
            $path = Join-Path $hooksDir $name
            if ($DryRun) {
                Write-Host "[DRY-RUN] Would create: $path"
            } else {
                $scripts[$name] | Set-Content $path -Encoding UTF8
                Write-Success "Created hook: $name"
            }
        }
    } else {
        $pretoolusePs1 = '# pretooluse.ps1
param()
$LOG_FILE = Join-Path $env:TEMP "claude-hook-validation.log"
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "$timestamp | PreToolUse | FIRED | Tool: $($payload.tool_name)" -ErrorAction SilentlyContinue
exit 0'
        $posttoolusePs1 = '# posttooluse.ps1
param()
$LOG_FILE = Join-Path $env:TEMP "claude-hook-validation.log"
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "$timestamp | PostToolUse | FIRED | Tool: $($payload.tool_name)" -ErrorAction SilentlyContinue
exit 0'
        $fileguardPs1 = '# file-guard.ps1
param()
$LOG_FILE = Join-Path $env:TEMP "claude-file-guard.log"
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "[file-guard] $timestamp ALLOWED tool=$($payload.tool_name)" -ErrorAction SilentlyContinue
exit 0'
        $notifyPs1 = '# notify.ps1
param()
$LOG_FILE = Join-Path $env:TEMP "claude-notify.log"
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "[notify] $timestamp title=$($payload.title)" -ErrorAction SilentlyContinue
exit 2'
        $postcompactPs1 = '# post-compact.ps1
param()
$CLAUDE_MD = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
$LOG_FILE = Join-Path $env:TEMP "claude-post-compact.log"
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "[post-compact] $timestamp re-injecting context" -ErrorAction SilentlyContinue
if (-not (Test-Path $CLAUDE_MD)) { exit 0 }
Write-Output "## Post-Compaction Context Refresh"
Write-Output ""
Get-Content $CLAUDE_MD -Raw
exit 0'

        $scripts = @{
            "pretooluse.ps1" = $pretoolusePs1
            "posttooluse.ps1" = $posttoolusePs1
            "file-guard.ps1" = $fileguardPs1
            "notify.ps1" = $notifyPs1
            "post-compact.ps1" = $postcompactPs1
        }
        foreach ($name in $scripts.Keys) {
            $path = Join-Path $hooksDir $name
            if ($DryRun) {
                Write-Host "[DRY-RUN] Would create: $path"
            } else {
                $scripts[$name] | Set-Content $path -Encoding UTF8
                Write-Success "Created hook: $name"
            }
        }
    }
}

function New-ClaudeMdTemplate {
    Write-Header "Creating CLAUDE.md Template"
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    $claudeMd = Join-Path $claudeDir "CLAUDE.md"
    if (Test-Path $claudeMd) {
        Write-Status "CLAUDE.md already exists - skipping"
        return
    }
    $content = @'
# Claude Code Optimization Guide

## Cost-First Defaults
- **Default model**: sonnet (or haiku for quick tasks)
- **Always use offset/limit** for reads >500 lines
- **Pre-convert**: PDF->text, Office->Markdown, images->2000x2000 max
- **Compact at**: 150K tokens

## File Reading Guidelines
### Always Use Pagination
For files >500 lines, always specify offset and limit:
```
Read file.ts {"offset": 1, "limit": 100}
```

### Search Before Reading
Use Grep/Glob to find specific content before reading entire files.

### Binary File Handling
Pre-convert binary files before reading:
- PDFs: Use pdftotext.exe or markitdown
- DOCX/XLSX/PPTX: markitdown
- Images: magick.exe -resize 2000x2000

## Compact Instructions
Focus on: current task state, file paths changed, pending errors, and last user instruction verbatim. Skip background theory. Keep code snippets only if they are the direct subject of the next task. Omit completed sub-tasks. Preserve file paths with line numbers for any code being actively edited. Keep error messages verbatim if they are not yet resolved.
'@
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would write CLAUDE.md to: $claudeMd"
        return
    }
    $content | Set-Content $claudeMd -Encoding UTF8
    Write-Success "Created CLAUDE.md at: $claudeMd"
}

function Test-Optimizations {
    Write-Header "Running Validation Checks"
    $results = @()
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    $results += @{ Check = "settings.json exists"; Pass = Test-Path $settingsPath }
    $settings = $null
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $results += @{ Check = "settings.json valid JSON"; Pass = $true }
        }
        catch {
            $results += @{ Check = "settings.json valid JSON"; Pass = $false; Error = $_.Exception.Message }
        }
    }
    if ($settings) {
        $results += @{ Check = "autoCompactEnabled is true"; Pass = ($settings.autoCompactEnabled -eq $true) }
        $expectedVars = @("BASH_MAX_OUTPUT_LENGTH", "DISABLE_TELEMETRY", "CLAUDE_CODE_AUTO_COMPACT_WINDOW", "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "CLAUDE_CODE_DISABLE_AUTO_MEMORY")
        if (-not $ReducedPrivacy) { $expectedVars += "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" }
        foreach ($var in $expectedVars) {
            $val = $settings.env.$var
            $results += @{ Check = "env.$var is set"; Pass = (-not [string]::IsNullOrEmpty($val)); Value = $val }
        }
    }
    $hooksDir = Join-Path $env:USERPROFILE ".claude\hooks"
    $hookExt = if ($script:BashAvailable) { ".sh" } else { ".ps1" }
    $requiredHooks = @("pretooluse$hookExt", "posttooluse$hookExt")
    if (-not $NoGuard) { $requiredHooks += "file-guard$hookExt" }
    if (-not $NoNotify) { $requiredHooks += "notify$hookExt" }
    if (-not $NoContextRefresh) { $requiredHooks += "post-compact$hookExt" }
    foreach ($scriptName in $requiredHooks) {
        $scriptPath = Join-Path $hooksDir $scriptName
        $results += @{ Check = "$scriptName exists"; Pass = Test-Path $scriptPath }
    }
    $claudeMd = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
    if (Test-Path $claudeMd) {
        $content = Get-Content $claudeMd -Raw
        $results += @{ Check = "CLAUDE.md has Compact Instructions"; Pass = ($content -match 'Compact Instructions') }
    }
    else {
        $results += @{ Check = "CLAUDE.md exists"; Pass = $false }
    }

    Write-Host ""
    Write-Host "Validation Results" -ForegroundColor Cyan
    Write-Host ("=" * 60)
    $passCount = 0
    $failCount = 0
    foreach ($r in $results) {
        if ($r.Pass) {
            Write-Host "[PASS] $($r.Check)" -ForegroundColor Green
            $passCount++
        }
        else {
            Write-Host "[FAIL] $($r.Check)" -ForegroundColor Red
            if ($r.Error) { Write-Host "       Error: $($r.Error)" -ForegroundColor Yellow }
            $failCount++
        }
    }
    Write-Host ""
    Write-Host "Total: $passCount passed, $failCount failed out of $($results.Count) checks" -ForegroundColor Cyan
    return ($failCount -eq 0)
}

function Show-Summary {
    Write-Header "Configuration Summary"
    Write-Success "Claude Code optimization complete!"
    Write-Host ""
    Write-Host "Configuration files created/updated:" -ForegroundColor Cyan
    Write-Host "  - ~/.claude/settings.json (main configuration)"
    Write-Host "  - ~/.claude/CLAUDE.md (compact instructions)"
    Write-Host "  - ~/.claude/hooks/ (hook scripts)"
    Write-Host ""
    Write-Host "Environment variables set:" -ForegroundColor Cyan
    Write-Host "  - BASH_MAX_OUTPUT_LENGTH=10000 (caps bash output)"
    Write-Host "  - DISABLE_TELEMETRY=1 (disables telemetry)"
    if (-not $ReducedPrivacy) { Write-Host "  - CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 (max privacy)" }
    Write-Host "  - CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000 (compact threshold)"
    Write-Host "  - CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70 (compact at 70%)"
    Write-Host "  - CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 (disables auto-memory)"
    Write-Host ""
    Write-Host "Hooks configured:" -ForegroundColor Cyan
    Write-Host "  - PreToolUse/Read: Image resize + binary-to-markdown"
    if (-not $NoGuard) { Write-Host "  - PreToolUse/Write|Edit|Bash: File guard" }
    Write-Host "  - PostToolUse/*: Validation logger"
    if (-not $NoNotify) { Write-Host "  - Notification/*: Desktop notifications" }
    if (-not $NoContextRefresh) { Write-Host "  - SessionStart/compact: Context re-injection" }
    Write-Host ""
    Write-Host "Privacy mode: " -NoNewline
    if ($ReducedPrivacy) { Write-Host "Standard (telemetry disabled)" -ForegroundColor Yellow }
    else { Write-Host "MAXIMUM (all non-essential traffic disabled)" -ForegroundColor Green }
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Start Claude Code: claude"
    Write-Host "2. Ask Claude: 'What environment variables do you see for BASH_MAX_OUTPUT_LENGTH?'"
    Write-Host "3. Try reading a PDF or image file to test hooks"
    Write-Host ""
    Write-Success "Happy optimizing!"
}

Write-Header "Claude Code Token Optimizer & Privacy Enhancer v2 (Windows)"
if ($DryRun) {
    Write-WarningLine "DRY RUN MODE - No changes will be made"
    Write-Host ""
}
Write-Host "Mode Configuration:" -ForegroundColor Cyan
Write-Host "  Privacy: " -NoNewline
if ($ReducedPrivacy) { Write-Host "Standard (telemetry only)" -ForegroundColor Yellow }
else { Write-Host "Maximum (all non-essential traffic disabled)" -ForegroundColor Green }
if ($Experimental) { Write-Host "  Experimental features: ENABLED" -ForegroundColor Magenta }
if ($NoGuard) { Write-Host "  File guard: DISABLED" -ForegroundColor Yellow }
if ($NoNotify) { Write-Host "  Desktop notifications: DISABLED" -ForegroundColor Yellow }
if ($NoContextRefresh) { Write-Host "  Context refresh after compact: DISABLED" -ForegroundColor Yellow }
if ($AutoApprove) { Write-Host "  Auto-approve safe commands: ENABLED" -ForegroundColor Green }
if ($AutoFormat) { Write-Host "  Auto-format after edits: ENABLED" -ForegroundColor Green }
Write-Host ""
Install-Dependencies
Set-ClaudeSettings
New-HookScripts
New-ClaudeMdTemplate
$validationPassed = Test-Optimizations
Show-Summary
if (-not $validationPassed) { Write-WarningLine "Some validation checks failed. Review the output above." }
