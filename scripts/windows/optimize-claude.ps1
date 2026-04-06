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

.PARAMETER Caveman
    Enable CAVEMAN mode (concise system prompt for token savings)

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
    .\optimize-claude.ps1 -Caveman
    Enable CAVEMAN concise prompt mode for maximum token savings
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
    [switch]$AutoFormat,
    [switch]$Caveman
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

function Test-Formatter {
    Write-Header "Checking Code Formatters"

    # Check for Prettier
    $prettier = Get-Command prettier -ErrorAction SilentlyContinue
    if ($prettier) {
        Write-Success "Prettier is already installed"
    } else {
        Write-WarningLine "Prettier is not installed (needed for JS/TS/CSS/HTML/JSON/YAML formatting)"
        $script:MissingDeps += "prettier"
    }

    # Check for black (Python)
    $black = Get-Command black -ErrorAction SilentlyContinue
    if ($black) {
        Write-Success "black is already installed"
    } else {
        Write-WarningLine "black is not installed (needed for Python formatting)"
        $script:MissingDeps += "black"
    }

    # Check for autopep8 (Python fallback)
    $autopep8 = Get-Command autopep8 -ErrorAction SilentlyContinue
    if ($autopep8) {
        Write-Success "autopep8 is already installed"
    } else {
        Write-WarningLine "autopep8 is not installed (fallback for Python formatting)"
        $script:MissingDeps += "autopep8"
    }
}

function Install-Prettier {
    Write-Status "Installing Prettier..."
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: npm install -g prettier"
        return
    }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-ErrorLine "npm not found. Please install Node.js and npm first."
        $script:InstallFailed += "prettier"
        return
    }

    try {
        & npm install -g prettier 2>$null
        $newPrettier = Get-Command prettier -ErrorAction SilentlyContinue
        if ($newPrettier) {
            Write-Success "Prettier installed successfully"
        } else {
            throw "Installation verification failed"
        }
    } catch {
        Write-ErrorLine "Failed to install Prettier: $_"
        $script:InstallFailed += "prettier"
    }
}

function Install-Black {
    Write-Status "Installing black..."
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: pip install black"
        return
    }

    try {
        & $script:PythonCmd -m pip install black 2>$null
        $newBlack = Get-Command black -ErrorAction SilentlyContinue
        if ($newBlack) {
            Write-Success "black installed successfully"
        } else {
            throw "Installation verification failed"
        }
    } catch {
        Write-ErrorLine "Failed to install black: $_"
        $script:InstallFailed += "black"
    }
}

function Install-Autopep8 {
    Write-Status "Installing autopep8..."
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: pip install autopep8"
        return
    }

    try {
        & $script:PythonCmd -m pip install autopep8 2>$null
        $newAutopep8 = Get-Command autopep8 -ErrorAction SilentlyContinue
        if ($newAutopep8) {
            Write-Success "autopep8 installed successfully"
        } else {
            throw "Installation verification failed"
        }
    } catch {
        Write-ErrorLine "Failed to install autopep8: $_"
        $script:InstallFailed += "autopep8"
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
    Test-Formatter
    if ($script:MissingDeps.Count -eq 0) {
        Write-Success "All dependencies are already installed!"
        return
    }
    Write-WarningLine "Missing dependencies: $($script:MissingDeps -join ', ')"

    $install = Read-Host "Install missing dependencies? (y/N)"
    if ($install -notmatch '^[Yy]$') {
        Write-WarningLine "Skipping dependency installation"
        return
    }

    foreach ($dep in $script:MissingDeps) {
        switch ($dep) {
            "markitdown" { pip install markitdown }
            "imagemagick" { Write-WarningLine "Please install ImageMagick manually from https://imagemagick.org" }
            "poppler" { Write-WarningLine "Please install poppler from https://github.com/oschwartz10612/poppler-windows/releases" }
            "prettier" { Install-Prettier }
            "black" { Install-Black }
            "autopep8" { Install-Autopep8 }
        }
    }
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
        $autoapproveCmd = "bash ~/.claude/hooks/auto-approve.sh"
        $autoformatCmd = "bash ~/.claude/hooks/post-edit-format.sh"
    } else {
        $pretooluseCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\pretooluse.ps1`""
        $posttooluseCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\posttooluse.ps1`""
        $fileguardCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\file-guard.ps1`""
        $notifyCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\notify.ps1`""
        $postcompactCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\post-compact.ps1`""
        $autoapproveCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\auto-approve.ps1`""
        $autoformatCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hooksDir\post-edit-format.ps1`""
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
    if ($AutoApprove) {
        $hooks.PreToolUse += @{
            matcher = "Bash"
            hooks = @(@{ type = "command"; command = $autoapproveCmd; timeout = 5 })
        }
    }
    if ($AutoFormat) {
        $hooks.PostToolUse += @{
            matcher = "Write|Edit|MultiEdit"
            hooks = @(@{ type = "command"; command = $autoformatCmd; timeout = 30 })
        }
    }

    $settings = @{
        '$schema' = "https://json.schemastore.org/claude-code-settings.json"
        autoCompactEnabled = $true
        attribution = @{
            commit = ""
            pr = ""
        }
        env = $envVars
        hooks = $hooks
    }

    if ($Caveman) {
        $settings['appendSystemPrompt'] = "CAVEMAN: Strip articles, helping verbs, filler. Keep nouns, main verbs, adjectives, numbers. Raw content only."
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

    # Debug output
    Write-Status "Bash available: $script:BashAvailable"

    if ($script:BashAvailable) {
        Write-Status "Creating bash hook scripts..."
        $pretooluseSh = '#!/usr/bin/env bash
# pretooluse.sh - PreToolUse hook for Read tool
# Receives JSON on stdin. Exit codes: 0=proceed, 2=intercept (stderr shown to Claude)

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r ''.tool_name // empty'')"
FILE_PATH="$(echo "$INPUT" | jq -r ''.tool_input.file_path // .tool_input.filePath // empty'')"

LOG_FILE="/tmp/claude-hook-validation.log"
MAX_DIMENSION="${CLAUDE_IMAGE_MAX_DIMENSION:-2000}"
MAX_FILE_SIZE_MB="${CLAUDE_IMAGE_MAX_SIZE_MB:-5}"
QUALITY="${CLAUDE_IMAGE_QUALITY:-85}"

log() { echo "$(date -Iseconds) | PreToolUse | $1" >> "$LOG_FILE"; }

# Only handle Read tool
if [[ "$TOOL_NAME" != "Read" ]]; then exit 0; fi
if [[ -z "$FILE_PATH" ]]; then log "NO_FILE_PATH"; exit 0; fi
log "FILE | $FILE_PATH"
if [[ ! -f "$FILE_PATH" ]]; then log "FILE_NOT_FOUND | $FILE_PATH"; exit 0; fi

EXTENSION="${FILE_PATH##*.}"
LOWER_EXT="$(echo "$EXTENSION" | tr ''[:upper:]'' ''[:lower:]'')"

# Image handling - resize in-place, exit 0
image_extensions="png jpg jpeg gif webp bmp tiff tif"
if [[ " $image_extensions " =~ " $LOWER_EXT " ]]; then
    log "IMAGE_DETECTED | $FILE_PATH"
    if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
        log "NO_IMAGEMAGICK | Skipping resize"; exit 0
    fi
    # Get dimensions
    if command -v magick >/dev/null 2>&1; then
        identify_output=$(magick identify -format "%wx%h" "$FILE_PATH" 2>/dev/null)
    else
        identify_output=$(convert "$FILE_PATH" -format "%wx%h" info: 2>/dev/null)
    fi
    if [[ "$identify_output" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        width="${BASH_REMATCH[1]}"; height="${BASH_REMATCH[2]}"
        file_size=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
        max_bytes=$((MAX_FILE_SIZE_MB * 1024 * 1024))
        if [[ $width -gt $MAX_DIMENSION || $height -gt $MAX_DIMENSION || $file_size -gt $max_bytes ]]; then
            log "RESIZING | ${width}x${height} | $file_size bytes"
            temp_file="/tmp/claude-resize-$(basename "$FILE_PATH")"
            if command -v magick >/dev/null 2>&1; then
                magick "$FILE_PATH" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" -quality "$QUALITY" "$temp_file" 2>/dev/null
            else
                convert "$FILE_PATH" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" -quality "$QUALITY" "$temp_file" 2>/dev/null
            fi
            if [[ -f "$temp_file" ]]; then
                cp "$temp_file" "$FILE_PATH"; rm -f "$temp_file"
                new_size=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
                log "RESIZED | $file_size -> $new_size bytes"
            fi
        else
            log "WITHIN_LIMITS | ${width}x${height} | $file_size bytes"
        fi
    fi
    exit 0
fi

# PDF handling - convert to text, exit 2
if [[ "$LOWER_EXT" == "pdf" ]]; then
    if command -v pdftotext >/dev/null 2>&1; then
        temp_txt="/tmp/claude-pdf-$(date +%s).txt"
        if pdftotext -layout "$FILE_PATH" "$temp_txt" 2>/dev/null; then
            content=$(cat "$temp_txt" 2>/dev/null); rm -f "$temp_txt"
            if [[ -n "$content" ]]; then
                if [[ ${#content} -gt 9500 ]]; then
                    content="${content:0:9500}

[... TRUNCATED - file too large for hook output]"
                fi
                log "PDF_CONVERTED | $FILE_PATH | ${#content} chars"
                echo "Converted PDF content from ${FILE_PATH}:

$content" >&2
                exit 2
            fi
        fi
    fi
    if command -v markitdown >/dev/null 2>&1; then
        content=$(markitdown "$FILE_PATH" 2>/dev/null)
        if [[ -n "$content" ]]; then
            if [[ ${#content} -gt 9500 ]]; then
                content="${content:0:9500}

[... TRUNCATED]"
            fi
            log "PDF_MARKITDOWN | $FILE_PATH | ${#content} chars"
            echo "Converted PDF content from ${FILE_PATH}:

$content" >&2
            exit 2
        fi
    fi
    log "NO_PDF_CONVERTER | $FILE_PATH"; exit 0
fi

# Office documents - convert to markdown, exit 2
doc_extensions="docx xlsx pptx doc xls ppt"
if [[ " $doc_extensions " =~ " $LOWER_EXT " ]]; then
    if command -v markitdown >/dev/null 2>&1; then
        content=$(markitdown "$FILE_PATH" 2>/dev/null)
        if [[ -n "$content" ]]; then
            if [[ ${#content} -gt 9500 ]]; then
                content="${content:0:9500}

[... TRUNCATED]"
            fi
            log "DOC_CONVERTED | $FILE_PATH | ${#content} chars"
            echo "Converted document content from ${FILE_PATH}:

$content" >&2
            exit 2
        fi
    fi
    log "NO_DOC_CONVERTER | $FILE_PATH"; exit 0
fi

exit 0'
        $posttooluseSh = '#!/usr/bin/env bash
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r ''.tool_name // empty'')"
LOG_FILE="/tmp/claude-hook-validation.log"
echo "$(date -Iseconds) | PostToolUse | FIRED | Tool: ${TOOL_NAME:-unknown}" >> "$LOG_FILE"
exit 0'
        $fileguardSh = '#!/usr/bin/env bash
# file-guard.sh - blocks writes to sensitive files and paths
# Event: PreToolUse
# Matcher: Write|Edit|MultiEdit|Bash
# Exit 0 = allow | Exit 2 = block (stderr message shown to Claude)

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r ''.tool_name // empty'')"
FILE_PATH="$(echo "$INPUT" | jq -r ''.tool_input.file_path // .tool_input.filePath // empty'')"
COMMAND="$(echo "$INPUT" | jq -r ''.tool_input.command // empty'')"

LOG_FILE="/tmp/claude-file-guard.log"

# Sensitive path patterns (POSIX extended regex)
BLOCKED_PATTERNS=(
    ''\.env$''
    ''\.env\.''
    ''\.git/''
    ''package-lock\.json$''
    ''yarn\.lock$''
    ''pnpm-lock\.yaml$''
    ''\.ssh/''
    ''id_rsa''
    ''id_ed25519''
    ''credentials\.json$''
    ''\.aws/credentials''
    ''\.gnupg/''
    ''secrets\.''
    ''\.pem$''
    ''\.key$''
)

block_with_reason() {
    local path="$1" pattern="$2"
    echo "[file-guard] $(date -Iseconds) BLOCKED tool=$TOOL_NAME path=$path pattern=$pattern" >> "$LOG_FILE"
    echo "BLOCKED: ''$path'' matches protected pattern ''$pattern''. If you genuinely need to edit this file, the user must do it manually." >&2
    exit 2
}

check_path() {
    local path="$1"
    if [[ -z "$path" ]]; then return; fi
    for pattern in "${BLOCKED_PATTERNS[@]}"; do
        if echo "$path" | grep -qE "$pattern"; then
            block_with_reason "$path" "$pattern"
        fi
    done
}

# Write / Edit / MultiEdit: check tool_input.file_path
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then
    check_path "$FILE_PATH"
fi

# Bash: scan the command string for suspicious path patterns
if [[ "$TOOL_NAME" == "Bash" && -n "$COMMAND" ]]; then
    for pattern in "${BLOCKED_PATTERNS[@]}"; do
        if echo "$COMMAND" | grep -qE "$pattern"; then
            echo "[file-guard] $(date -Iseconds) BLOCKED bash command matching pattern=$pattern" >> "$LOG_FILE"
            echo "BLOCKED: Bash command appears to touch a protected path (pattern: $pattern). If intentional, the user must run this command manually." >&2
            exit 2
        fi
    done
fi

echo "[file-guard] $(date -Iseconds) ALLOWED tool=$TOOL_NAME path=$FILE_PATH" >> "$LOG_FILE"
exit 0'
        $notifySh = '#!/usr/bin/env bash
# notify.sh - cross-platform desktop notifications for Claude Code events
# Event: Notification
# Exit 2 = we handled it, suppress default notification

INPUT="$(cat)"
MESSAGE="$(echo "$INPUT" | jq -r ''.message // .title // "Claude Code notification"'')"
TITLE="$(echo "$INPUT" | jq -r ''.title // "Claude Code"'')"

LOG_FILE="/tmp/claude-notify.log"
echo "[notify] $(date -Iseconds) title=$TITLE msg=$MESSAGE" >> "$LOG_FILE"

# Sanitize: remove single quotes
SAFE_TITLE="${TITLE//''\''/}"
SAFE_MESSAGE="${MESSAGE//''\''/}"

# Windows: balloon tip via Windows Forms
if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "
        Add-Type -AssemblyName System.Windows.Forms
        \$icon = New-Object System.Windows.Forms.NotifyIcon
        \$icon.Icon = [System.Drawing.SystemIcons]::Information
        \$icon.BalloonTipTitle = ''$SAFE_TITLE''
        \$icon.BalloonTipText = ''$SAFE_MESSAGE''
        \$icon.Visible = \$true
        \$icon.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 5500
        \$icon.Dispose()
    " 2>/dev/null
    exit 2
fi

# Linux: notify-send
if command -v notify-send >/dev/null 2>&1; then
    notify-send "$TITLE" "$MESSAGE" --expire-time=5000 2>/dev/null
    exit 2
fi

# macOS: osascript
if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$SAFE_MESSAGE\" with title \"$SAFE_TITLE\"" 2>/dev/null
    exit 2
fi

# Last resort: terminal bell
printf ''\a'' >/dev/tty 2>/dev/null || true
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
        $autoapproveSh = '#!/usr/bin/env bash
# auto-approve.sh - auto-approves safe read-only bash commands
# Event: PreToolUse
# Matcher: Bash
# Opt-in: only installed with -AutoApprove
# Exit 0 + JSON stdout = auto-approve | Exit 0 (no JSON) = defer to normal permission prompt

INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | jq -r ''.tool_input.command // empty'')"
LOG_FILE="/tmp/claude-auto-approve.log"

# Whitelisted command prefixes (read-only, safe)
SAFE_PREFIXES=(
    "ls"
    "cat "
    "echo "
    "pwd"
    "which "
    "where "
    "git status"
    "git log"
    "git diff"
    "git branch"
    "git show"
    "git remote"
    "git stash list"
    "npm list"
    "npm run"
    "pip list"
    "pip show"
    "python --version"
    "python3 --version"
    "node --version"
    "node -v"
    "npm --version"
    "npm -v"
    "Get-Content "
    "Get-ChildItem"
    "Write-Host"
    "Select-String"
    "type "
    "dir "
)

for prefix in "${SAFE_PREFIXES[@]}"; do
    if [[ "$COMMAND" == "$prefix" || "$COMMAND" == "$prefix"* ]]; then
        echo "[auto-approve] $(date -Iseconds) APPROVED: $COMMAND" >> "$LOG_FILE"
        printf ''{"hookSpecificOutput":{"permissionDecision":"allow"}}''
        exit 0
    fi
done

echo "[auto-approve] $(date -Iseconds) DEFERRED (not whitelisted): $COMMAND" >> "$LOG_FILE"
exit 0'
        $autoformatSh = '#!/usr/bin/env bash
# post-edit-format.sh - auto-formats files after Write/Edit/MultiEdit
# Event: PostToolUse
# Matcher: Write|Edit|MultiEdit
# Opt-in: only installed with -AutoFormat
# Exit 0 always (formatting failures are non-fatal)

INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | jq -r ''.tool_input.file_path // .tool_input.filePath // empty'')"
LOG_FILE="/tmp/claude-auto-format.log"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then exit 0; fi

EXT="${FILE_PATH##*.}"
EXT="$(echo "$EXT" | tr ''[:upper:]'' ''[:lower:]'')"

FORMAT_RESULT=""

case "$EXT" in
    js|jsx|ts|tsx|json|css|scss|less|html|htm|md|markdown|yaml|yml)
        if command -v prettier >/dev/null 2>&1; then
            prettier --write "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="prettier"
        fi
        ;;
    py)
        if command -v black >/dev/null 2>&1; then
            black --quiet "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="black"
        elif command -v autopep8 >/dev/null 2>&1; then
            autopep8 --in-place "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="autopep8"
        fi
        ;;
    go)
        if command -v gofmt >/dev/null 2>&1; then
            gofmt -w "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="gofmt"
        fi
        ;;
    rs)
        if command -v rustfmt >/dev/null 2>&1; then
            rustfmt "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="rustfmt"
        fi
        ;;
    rb)
        if command -v rubocop >/dev/null 2>&1; then
            rubocop --autocorrect --format quiet "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="rubocop"
        fi
        ;;
esac

if [[ -n "$FORMAT_RESULT" ]]; then
    echo "[auto-format] $(date -Iseconds) Formatted $FILE_PATH with $FORMAT_RESULT" >> "$LOG_FILE"
else
    echo "[auto-format] $(date -Iseconds) No formatter for $FILE_PATH (.$EXT)" >> "$LOG_FILE"
fi

exit 0'

        $scripts = @{
            "pretooluse.sh" = $pretooluseSh
            "posttooluse.sh" = $posttooluseSh
            "file-guard.sh" = $fileguardSh
            "notify.sh" = $notifySh
            "post-compact.sh" = $postcompactSh
        }
        if ($AutoApprove) { $scripts["auto-approve.sh"] = $autoapproveSh }
        if ($AutoFormat) { $scripts["post-edit-format.sh"] = $autoformatSh }
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
        $pretoolusePs1 = '# pretooluse.ps1 - PreToolUse hook for Read tool
# Receives JSON on stdin. Exit codes: 0=proceed, 2=intercept (stderr shown to Claude)

param()
$ErrorActionPreference = ''Stop''

$MAX_DIMENSION = if ($env:CLAUDE_IMAGE_MAX_DIMENSION) { [int]$env:CLAUDE_IMAGE_MAX_DIMENSION } else { 2000 }
$MAX_FILE_SIZE_MB = if ($env:CLAUDE_IMAGE_MAX_SIZE_MB) { [int]$env:CLAUDE_IMAGE_MAX_SIZE_MB } else { 5 }
$QUALITY = if ($env:CLAUDE_IMAGE_QUALITY) { [int]$env:CLAUDE_IMAGE_QUALITY } else { 85 }
$LOG_FILE = Join-Path $env:TEMP "claude-hook-validation.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    Add-Content -Path $LOG_FILE -Value "$timestamp | PreToolUse | $Message" -ErrorAction SilentlyContinue
}

# Read JSON from stdin
$inputJson = $null
try {
    $inputJson = [Console]::In.ReadToEnd()
    if (-not $inputJson) { Write-Log "EMPTY_INPUT"; exit 0 }
} catch { Write-Log "STDIN_READ_ERROR | $_"; exit 0 }

# Parse JSON
$payload = $null
try { $payload = $inputJson | ConvertFrom-Json }
catch { Write-Log "JSON_PARSE_ERROR | $_"; exit 0 }

# Only handle Read tool
if ($payload.tool_name -ne ''Read'') { exit 0 }

# Extract file path
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }
if (-not $filePath) { Write-Log "NO_FILE_PATH"; exit 0 }

Write-Log "FILE | $filePath"
if (-not (Test-Path $filePath -PathType Leaf)) { Write-Log "FILE_NOT_FOUND | $filePath"; exit 0 }

$extension = [System.IO.Path]::GetExtension($filePath).ToLower()

# Image handling
$imageExtensions = @(''.png'', ''.jpg'', ''.jpeg'', ''.gif'', ''.webp'', ''.bmp'', ''.tiff'', ''.tif'')
if ($extension -in $imageExtensions) {
    Write-Log "IMAGE_DETECTED | $filePath"
    $magick = Get-Command magick.exe -ErrorAction SilentlyContinue
    if (-not $magick) { Write-Log "NO_IMAGEMAGICK | Skipping resize"; exit 0 }
    try {
        $identify = & magick.exe identify -format "%wx%h" "$filePath" 2>$null
        if ($identify -match ''(\d+)x(\d+)'') {
            $width = [int]$Matches[1]; $height = [int]$Matches[2]
            $fileSize = (Get-Item $filePath).Length
            $maxBytes = $MAX_FILE_SIZE_MB * 1024 * 1024
            if ($width -gt $MAX_DIMENSION -or $height -gt $MAX_DIMENSION -or $fileSize -gt $maxBytes) {
                Write-Log "RESIZING | ${width}x${height} | $fileSize bytes"
                $tempFile = Join-Path $env:TEMP "claude-resize-$([System.IO.Path]::GetFileName($filePath))"
                & magick.exe "$filePath" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" -quality $QUALITY "$tempFile" 2>$null
                if (Test-Path $tempFile) {
                    Copy-Item $tempFile $filePath -Force
                    Remove-Item $tempFile -ErrorAction SilentlyContinue
                    $newSize = (Get-Item $filePath).Length
                    Write-Log "RESIZED | $fileSize -> $newSize bytes"
                }
            } else {
                Write-Log "WITHIN_LIMITS | ${width}x${height} | $fileSize bytes"
            }
        }
    } catch { Write-Log "RESIZE_ERROR | $_" }
    exit 0
}

# PDF handling
$pdfExtensions = @(''.pdf'')
if ($extension -in $pdfExtensions) {
    $pdftotext = Get-Command pdftotext.exe -ErrorAction SilentlyContinue
    if ($pdftotext) {
        try {
            $tempTxt = Join-Path $env:TEMP "claude-pdf-$([guid]::NewGuid().ToString(''N'')).txt"
            & pdftotext.exe -layout "$filePath" "$tempTxt" 2>$null
            if (Test-Path $tempTxt) {
                $content = Get-Content $tempTxt -Raw -ErrorAction SilentlyContinue
                Remove-Item $tempTxt -ErrorAction SilentlyContinue
                if ($content) {
                    if ($content.Length -gt 9500) {
                        $content = $content.Substring(0, 9500) + "`n`n[... TRUNCATED - file too large for hook output]"
                    }
                    Write-Log "PDF_CONVERTED | $filePath | $($content.Length) chars"
                    [Console]::Error.Write("Converted PDF content from ${filePath}:`n`n$content")
                    exit 2
                }
            }
        } catch { Write-Log "PDFTOTEXT_ERROR | $_" }
    }
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        try {
            $content = & markitdown "$filePath" 2>$null
            if ($content) {
                $contentStr = $content -join "`n"
                if ($contentStr.Length -gt 9500) {
                    $contentStr = $contentStr.Substring(0, 9500) + "`n`n[... TRUNCATED]"
                }
                Write-Log "PDF_MARKITDOWN | $filePath | $($contentStr.Length) chars"
                [Console]::Error.Write("Converted PDF content from ${filePath}:`n`n$contentStr")
                exit 2
            }
        } catch { Write-Log "MARKITDOWN_ERROR | $_" }
    }
    Write-Log "NO_PDF_CONVERTER | $filePath"; exit 0
}

# Office documents
$docExtensions = @(''.docx'', ''.xlsx'', ''.pptx'', ''.doc'', ''.xls'', ''.ppt'')
if ($extension -in $docExtensions) {
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        try {
            $content = & markitdown "$filePath" 2>$null
            if ($content) {
                $contentStr = $content -join "`n"
                if ($contentStr.Length -gt 9500) {
                    $contentStr = $contentStr.Substring(0, 9500) + "`n`n[... TRUNCATED]"
                }
                Write-Log "DOC_CONVERTED | $filePath | $($contentStr.Length) chars"
                [Console]::Error.Write("Converted document content from ${filePath}:`n`n$contentStr")
                exit 2
            }
        } catch { Write-Log "MARKITDOWN_DOC_ERROR | $_" }
    }
    Write-Log "NO_DOC_CONVERTER | $filePath"; exit 0
}

exit 0'
        $posttoolusePs1 = '# posttooluse.ps1
param()
$LOG_FILE = Join-Path $env:TEMP "claude-hook-validation.log"
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "$timestamp | PostToolUse | FIRED | Tool: $($payload.tool_name)" -ErrorAction SilentlyContinue
exit 0'
        $fileguardPs1 = '# file-guard.ps1 - blocks writes to sensitive files and paths
# Event: PreToolUse
# Matcher: Write|Edit|MultiEdit|Bash
# Exit 0 = allow | Exit 2 = block (stderr message shown to Claude)

param()
$ErrorActionPreference = ''Stop''

$LOG_FILE = Join-Path $env:TEMP "claude-file-guard.log"

$BLOCKED_PATTERNS = @(
    ''\.env$''
    ''\.env\.''
    ''\.git/''
    ''package-lock\.json$''
    ''yarn\.lock$''
    ''pnpm-lock\.yaml$''
    ''\.ssh/''
    ''id_rsa''
    ''id_ed25519''
    ''credentials\.json$''
    ''\.aws/credentials''
    ''\.gnupg/''
    ''secrets\.''
    ''\.pem$''
    ''\.key$''
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    Add-Content -Path $LOG_FILE -Value "[file-guard] $timestamp $Message" -ErrorAction SilentlyContinue
}

# Extract file path from shell redirection (e.g., "echo x > ~/.env" or "echo x >~/.env")
function Get-RedirectTarget {
    param([string]$Command)
    # Match redirection operators: >, >>, 1>, 2>, etc. followed by optional space and a path
    $redirectPattern = ''[0-9]*[>]+\s*([~\./][^\s|;"''&]+)''
    if ($Command -match $redirectPattern) {
        $target = $Matches[1]
        # Remove trailing punctuation
        $target = $target -replace ''[;|&"''''`]+$''
        # Expand ~ to user profile
        if ($target.StartsWith(''~'')) {
            $target = $target -replace ''^~'', $env:USERPROFILE
        }
        return $target
    }
    return $null
}

# Read JSON from stdin
$inputJson = $null
try {
    $inputJson = [Console]::In.ReadToEnd()
    if (-not $inputJson) { exit 0 }
} catch { exit 0 }

# Parse JSON
$payload = $null
try { $payload = $inputJson | ConvertFrom-Json }
catch { exit 0 }

$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }
$command = $payload.tool_input.command

function Block-WithReason {
    param([string]$Path, [string]$Pattern)
    Write-Log "BLOCKED tool=$toolName path=$Path pattern=$Pattern"
    [Console]::Error.WriteLine("BLOCKED: ''''$Path'''' matches protected pattern ''''$Pattern''''. If you genuinely need to edit this file, the user must do it manually.")
    exit 2
}

function Test-BlockedPath {
    param([string]$Path)
    if (-not $Path) { return }
    foreach ($pattern in $BLOCKED_PATTERNS) {
        if ($Path -match $pattern) { Block-WithReason -Path $Path -Pattern $pattern }
    }
}

# Write / Edit / MultiEdit: check tool_input.file_path
if ($toolName -in @(''Write'', ''Edit'', ''MultiEdit'')) { Test-BlockedPath -Path $filePath }

# Bash: scan the command string for suspicious patterns
if ($toolName -eq ''Bash'' -and $command) {
    # First check for shell redirections to sensitive files
    $redirectTarget = Get-RedirectTarget -Command $command
    if ($redirectTarget) {
        foreach ($pattern in $BLOCKED_PATTERNS) {
            if ($redirectTarget -match $pattern) {
                Write-Log "BLOCKED bash redirection to protected path: $redirectTarget"
                [Console]::Error.WriteLine("BLOCKED: Bash command redirects to protected path ''''$redirectTarget''''. If intentional, the user must run this command manually.")
                exit 2
            }
        }
    }

    # Also check for direct path patterns in write-related commands
    $writeCommands = @(''tee'', ''cp'', ''mv'', ''copy'', ''move'', ''type.*>'', ''echo.*>'', ''out-file'')
    $isWriteCommand = $false
    foreach ($wc in $writeCommands) {
        if ($command -match $wc) { $isWriteCommand = $true; break }
    }

    foreach ($pattern in $BLOCKED_PATTERNS) {
        if ($command -match $pattern) {
            # Only block if it''s a write command or has redirection
            if ($isWriteCommand -or $redirectTarget -or $command -match ''[>]'') {
                Write-Log "BLOCKED bash command matching pattern=$pattern"
                [Console]::Error.WriteLine("BLOCKED: Bash command appears to touch a protected path (pattern: $pattern). If intentional, the user must run this command manually.")
                exit 2
            }
        }
    }
}

Write-Log "ALLOWED tool=$toolName path=$filePath"
exit 0'
        $notifyPs1 = '# notify.ps1 - Windows desktop notifications for Claude Code events
# Event: Notification
# Exit 2 = we handled it, suppress default notification

param()
$ErrorActionPreference = ''SilentlyContinue''

$LOG_FILE = Join-Path $env:TEMP "claude-notify.log"

# Read JSON from stdin
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json

$message = if ($payload.message) { $payload.message } elseif ($payload.title) { $payload.title } else { "Claude Code notification" }
$title = if ($payload.title) { $payload.title } else { "Claude Code" }

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
Add-Content -Path $LOG_FILE -Value "[notify] $timestamp title=$title msg=$message" -ErrorAction SilentlyContinue

# Windows balloon tip via Windows Forms
Add-Type -AssemblyName System.Windows.Forms
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.BalloonTipTitle = $title
$icon.BalloonTipText = $message
$icon.Visible = $true
$icon.ShowBalloonTip(5000)
Start-Sleep -Milliseconds 5500
$icon.Dispose()

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
        $autoapprovePs1 = '# auto-approve.ps1 - auto-approves safe read-only bash commands
# Event: PreToolUse
# Matcher: Bash
# Opt-in: only installed with -AutoApprove
# Exit 0 + JSON stdout = auto-approve | Exit 0 (no JSON) = defer to normal permission prompt

param()
$ErrorActionPreference = ''Stop''

$LOG_FILE = Join-Path $env:TEMP "claude-auto-approve.log"

# Read JSON from stdin
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json

$command = $payload.tool_input.command

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

# Whitelisted command prefixes (read-only, safe)
$SAFE_PREFIXES = @(
    "ls",
    "cat ",
    "echo ",
    "pwd",
    "which ",
    "where ",
    "git status",
    "git log",
    "git diff",
    "git branch",
    "git show",
    "git remote",
    "git stash list",
    "npm list",
    "npm run",
    "pip list",
    "pip show",
    "python --version",
    "python3 --version",
    "node --version",
    "node -v",
    "npm --version",
    "npm -v",
    "Get-Content ",
    "Get-ChildItem",
    "Write-Host",
    "Select-String",
    "type ",
    "dir "
)

foreach ($prefix in $SAFE_PREFIXES) {
    if ($command -eq $prefix -or $command.StartsWith($prefix)) {
        Add-Content -Path $LOG_FILE -Value "[auto-approve] $timestamp APPROVED: $command" -ErrorAction SilentlyContinue
        [Console]::Out.Write(''{"hookSpecificOutput":{"permissionDecision":"allow"}}'')
        exit 0
    }
}

Add-Content -Path $LOG_FILE -Value "[auto-approve] $timestamp DEFERRED (not whitelisted): $command" -ErrorAction SilentlyContinue
exit 0'
        $autoformatPs1 = '# post-edit-format.ps1 - auto-formats files after Write/Edit/MultiEdit
# Event: PostToolUse
# Matcher: Write|Edit|MultiEdit
# Opt-in: only installed with -AutoFormat
# Exit 0 always (formatting failures are non-fatal)

param()
$ErrorActionPreference = ''SilentlyContinue''

$LOG_FILE = Join-Path $env:TEMP "claude-auto-format.log"

# Read JSON from stdin
$inputJson = [Console]::In.ReadToEnd()
$payload = $inputJson | ConvertFrom-Json

$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }

if (-not $filePath -or -not (Test-Path $filePath)) { exit 0 }

$extension = [System.IO.Path]::GetExtension($filePath).ToLower().TrimStart(''.'')
$FORMAT_RESULT = ""

switch ($extension) {
    { $_ -in @(''js'', ''jsx'', ''ts'', ''tsx'', ''json'', ''css'', ''scss'', ''less'', ''html'', ''htm'', ''md'', ''markdown'', ''yaml'', ''yml'') } {
        $prettier = Get-Command prettier -ErrorAction SilentlyContinue
        if ($prettier) {
            & prettier --write "$filePath" 2>$null
            if ($LASTEXITCODE -eq 0) { $FORMAT_RESULT = "prettier" }
        }
    }
    ''py'' {
        $black = Get-Command black -ErrorAction SilentlyContinue
        if ($black) {
            & black --quiet "$filePath" 2>$null
            if ($LASTEXITCODE -eq 0) { $FORMAT_RESULT = "black" }
        } else {
            $autopep8 = Get-Command autopep8 -ErrorAction SilentlyContinue
            if ($autopep8) {
                & autopep8 --in-place "$filePath" 2>$null
                if ($LASTEXITCODE -eq 0) { $FORMAT_RESULT = "autopep8" }
            }
        }
    }
    ''go'' {
        $gofmt = Get-Command gofmt -ErrorAction SilentlyContinue
        if ($gofmt) {
            & gofmt -w "$filePath" 2>$null
            if ($LASTEXITCODE -eq 0) { $FORMAT_RESULT = "gofmt" }
        }
    }
    ''rs'' {
        $rustfmt = Get-Command rustfmt -ErrorAction SilentlyContinue
        if ($rustfmt) {
            & rustfmt "$filePath" 2>$null
            if ($LASTEXITCODE -eq 0) { $FORMAT_RESULT = "rustfmt" }
        }
    }
    ''rb'' {
        $rubocop = Get-Command rubocop -ErrorAction SilentlyContinue
        if ($rubocop) {
            & rubocop --autocorrect --format quiet "$filePath" 2>$null
            if ($LASTEXITCODE -eq 0) { $FORMAT_RESULT = "rubocop" }
        }
    }
}

$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
if ($FORMAT_RESULT) {
    Add-Content -Path $LOG_FILE -Value "[auto-format] $timestamp Formatted $filePath with $FORMAT_RESULT"
} else {
    Add-Content -Path $LOG_FILE -Value "[auto-format] $timestamp No formatter for $filePath (.$extension)"
}

exit 0'

        $scripts = @{
            "pretooluse.ps1" = $pretoolusePs1
            "posttooluse.ps1" = $posttoolusePs1
            "file-guard.ps1" = $fileguardPs1
            "notify.ps1" = $notifyPs1
            "post-compact.ps1" = $postcompactPs1
        }
        if ($AutoApprove) { $scripts["auto-approve.ps1"] = $autoapprovePs1 }
        if ($AutoFormat) { $scripts["post-edit-format.ps1"] = $autoformatPs1 }
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
        $results += @{ Check = "attribution.commit is empty"; Pass = ($settings.attribution.commit -eq "") }
        $results += @{ Check = "attribution.pr is empty"; Pass = ($settings.attribution.pr -eq "") }
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
    if ($AutoApprove) { $requiredHooks += "auto-approve$hookExt" }
    if ($AutoFormat) { $requiredHooks += "post-edit-format$hookExt" }
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
    Write-Host "Settings configured:" -ForegroundColor Cyan
    Write-Host "  - autoCompactEnabled: true"
    Write-Host "  - attribution.commit: '' (empty, saves ~50-100 tokens per commit)"
    Write-Host "  - attribution.pr: '' (empty, saves ~50-100 tokens per PR)"
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
    if ($AutoApprove) { Write-Host "  - PreToolUse/Bash: Auto-approve safe commands" }
    if ($AutoFormat) { Write-Host "  - PostToolUse/Write|Edit: Auto-format after edits" }
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

# Always check bash availability (needed for hook generation)
Test-Bash
Install-Dependencies
Set-ClaudeSettings
New-HookScripts
New-ClaudeMdTemplate
$validationPassed = Test-Optimizations
Show-Summary
if (-not $validationPassed) { Write-WarningLine "Some validation checks failed. Review the output above." }
