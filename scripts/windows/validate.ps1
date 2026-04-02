#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Optimizer - Configuration Validation Suite (Windows)
    Validates setup without requiring headless Claude execution
    NOTE: Hooks must be tested manually in an interactive Claude session

.DESCRIPTION
    Validates:
    1. Claude Code installation
    2. Dependencies (ImageMagick, pdftotext, markitdown)
    3. Privacy environment variables
    4. Auto-compact configuration
    5. Hook configuration (PreToolUse, PostToolUse)

    Hook execution must be verified manually in an interactive Claude session.

.PARAMETER Verbose
    Show detailed output including full config file contents

.PARAMETER Help
    Show help message

.EXAMPLE
    .\validate.ps1
    Run full configuration validation

.EXAMPLE
    .\validate.ps1 -Verbose
    Run with detailed output
#>

[CmdletBinding()]
param(
    [switch]$VerboseOutput
)

# Colors
$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Error = 'Red'
    Warning = 'Yellow'
    Header = 'Blue'
    Metric = 'Magenta'
}

# Configuration
$ScriptDir = $PSScriptRoot
$RepoDir = Join-Path $ScriptDir "..\.."
$TestImage = Join-Path $RepoDir "tests\test-image.png"
$TestPdf = Join-Path $RepoDir "tests\test-document.pdf"

# Test counters
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0

# Output functions
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Header
    Write-Host " $Message" -ForegroundColor $Colors.Header
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Header
    Write-Host ""
}

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -Bold
    Write-Host ('=' * $Message.Length) -ForegroundColor Blue
}

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Info
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓ PASS] $Message" -ForegroundColor $Colors.Success
    $script:TestsPassed++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗ FAIL] $Message" -ForegroundColor $Colors.Error
    $script:TestsFailed++
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[⚠ SKIP] $Message" -ForegroundColor $Colors.Warning
    $script:TestsSkipped++
}

function Write-Metric {
    param([string]$Message)
    Write-Host "[METRIC] $Message" -ForegroundColor $Colors.Metric
}

# Count tokens (rough approximation: chars / 4)
function Count-Tokens {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return 0 }
    $chars = (Get-Item $FilePath).Length
    return [math]::Floor($chars / 4)
}

# Test 1: Check Claude Code installation
function Test-ClaudeInstallation {
    Write-Section "🔍 CLAUDE CODE INSTALLATION"

    $claudePaths = @(
        (Get-Command claude -ErrorAction SilentlyContinue),
        "$env:USERPROFILE\.local\bin\claude.exe",
        "$env:LOCALAPPDATA\Programs\Claude\Claude.exe",
        "$env:LOCALAPPDATA\claude\claude.exe",
        "C:\Program Files\Claude\Claude.exe",
        "C:\Program Files (x86)\Claude\Claude.exe"
    )

    $foundClaude = $null
    foreach ($path in $claudePaths) {
        if ($path -and (Test-Path $path)) {
            $foundClaude = $path
            break
        }
    }

    if ($foundClaude) {
        Write-Success "Claude Code found: $foundClaude"
        return $true
    } else {
        Write-Error "Claude Code not found"
        Write-Status "Install from: https://claude.ai/code"
        return $false
    }
}

# Test 2: Check dependencies
function Test-Dependencies {
    Write-Section "📦 DEPENDENCIES"

    # ImageMagick
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue
    if ($magick -or $convert) {
        $imgCmd = if ($magick) { "magick" } else { "convert" }
        Write-Success "ImageMagick installed ($imgCmd)"
    } else {
        Write-Error "ImageMagick not found (required for image optimization)"
        Write-Status "Install: winget install ImageMagick.ImageMagick"
        Write-Status "        choco install imagemagick"
    }

    # pdftotext
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) {
        Write-Success "pdftotext (poppler) installed"
    } else {
        Write-Error "pdftotext not found (required for PDF text extraction)"
        Write-Status "Install: choco install poppler"
        Write-Status "Download from: https://github.com/oschwartz10612/poppler-windows/releases"
    }

    # markitdown
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        Write-Success "markitdown installed"
    } else {
        Write-Warning "markitdown not found (optional, for Office document conversion)"
        Write-Status "Install: pip install markitdown"
    }
}

# Test 3: Check privacy configuration
function Test-PrivacyConfiguration {
    Write-Section "🔒 PRIVACY CONFIGURATION"

    $privacyScore = 0
    $vars = @(
        @{ Name = "DISABLE_TELEMETRY"; Expected = "1"; Description = "Disable all telemetry" },
        @{ Name = "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"; Expected = "1"; Description = "Block non-essential network traffic" },
        @{ Name = "OTEL_LOG_USER_PROMPTS"; Expected = "0"; Description = "Don't log user prompts" },
        @{ Name = "OTEL_LOG_TOOL_DETAILS"; Expected = "0"; Description = "Don't log tool details" }
    )

    foreach ($var in $vars) {
        $actual = [Environment]::GetEnvironmentVariable($var.Name, "User")
        if ($actual -eq $var.Expected) {
            Write-Success "$($var.Name)=$actual ($($var.Description))"
            $privacyScore++
        } else {
            Write-Error "$($var.Name) not set (expected: $($var.Expected), got: $actual)"
            Write-Status "Set in PowerShell: [Environment]::SetEnvironmentVariable('$($var.Name)', '$($var.Expected)', 'User')"
        }
    }

    # Auto-compact window
    $autoCompactWindow = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "User")
    if ($autoCompactWindow -eq "180000") {
        Write-Success "CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000 (3 minute compact window)"
        $privacyScore++
    } else {
        Write-Error "CLAUDE_CODE_AUTO_COMPACT_WINDOW not set to 180000"
        Write-Status "Set in PowerShell: [Environment]::SetEnvironmentVariable('CLAUDE_CODE_AUTO_COMPACT_WINDOW', '180000', 'User')"
    }

    Write-Host ""
    Write-Metric "Privacy Score: $privacyScore/5"

    if ($privacyScore -eq 5) {
        Write-Success "Maximum privacy configured ✓"
    } elseif ($privacyScore -ge 3) {
        Write-Warning "Partial privacy ($privacyScore/5) - some protections active"
    } else {
        Write-Error "Privacy not configured - follow suggestions above"
    }
}

# Test 4: Check auto-compact configuration
function Test-AutoCompact {
    Write-Section "⚙️  AUTO-COMPACT CONFIGURATION"

    $claudeConfig = Join-Path $env:USERPROFILE ".claude\.claude.json"

    if (-not (Test-Path $claudeConfig)) {
        Write-Error "Claude config not found: $claudeConfig"
        Write-Status "Run optimize-claude.ps1 to create this file"
        return
    }

    $configContent = Get-Content $claudeConfig -Raw -ErrorAction SilentlyContinue
    if ($configContent -match '"autoCompactEnabled":\s*true') {
        Write-Success "autoCompactEnabled: true"
    } else {
        Write-Error "autoCompactEnabled not set to true"
        Write-Status "Run optimize-claude.ps1 or manually edit $claudeConfig"
    }

    if ($VerboseOutput) {
        Write-Host ""
        Write-Status "Current config contents:"
        $configContent
    }
}

# Test 5: Check hook configuration
function Test-HookConfiguration {
    Write-Section "🪝 HOOK CONFIGURATION"

    $userSettings = Join-Path $env:USERPROFILE ".claude\settings.json"
    $projectSettings = Join-Path $RepoDir ".claude\settings.json"

    $settingsFile = $null
    if (Test-Path $userSettings) {
        $settingsFile = $userSettings
    } elseif (Test-Path $projectSettings) {
        $settingsFile = $projectSettings
    }

    if (-not $settingsFile) {
        Write-Error "settings.json not found"
        Write-Status "Checked locations:"
        Write-Status "  - $userSettings"
        Write-Status "  - $projectSettings"
        Write-Status "Run optimize-claude.ps1 to configure hooks"
        return
    }

    $settingsContent = Get-Content $settingsFile -Raw

    $preConfigured = $false
    $postConfigured = $false

    if ($settingsContent -match '"PreToolUse"') {
        Write-Success "PreToolUse hook configured"
        $preConfigured = $true
    } else {
        Write-Error "PreToolUse hook not configured"
        Write-Status "This hook auto-resizes images before Claude processes them"
    }

    if ($settingsContent -match '"PostToolUse"') {
        Write-Success "PostToolUse hook configured"
        $postConfigured = $true
    } else {
        Write-Error "PostToolUse hook not configured"
        Write-Status "This hook keeps the prompt cache warm (saves 90% on cache misses)"
    }

    if ($VerboseOutput) {
        Write-Host ""
        Write-Status "Current hooks configuration:"
        $settingsContent
    }
}

# Print manual test instructions
function Write-ManualTests {
    Write-Header "🧪 MANUAL HOOK VERIFICATION"

    $wslRepoDir = wsl wslpath -a "$RepoDir" 2>$null
    if (-not $wslRepoDir) {
        $wslRepoDir = "/mnt/c" + ($RepoDir -replace '^C:', '').Replace('\', '/')
    }

    Write-Host "Since hooks require an interactive Claude session, verify them manually:"
    Write-Host ""

    Write-Host "Test 1: PreToolUse Hook (Image Processing)" -Bold
    Write-Host "1. Start an interactive Claude session: claude"
    Write-Host "2. Run this command inside Claude:"
    Write-Host "   Read $TestImage" -ForegroundColor $Colors.Info
    Write-Host "3. Check if the image was resized:"
    Write-Host "   wsl ls -la /tmp/resized_*.png" -ForegroundColor $Colors.Info
    Write-Host "4. Expected: A resized image file should exist (~33% smaller)"
    Write-Host ""

    Write-Host "Test 2: PostToolUse Hook (Cache Keepalive)" -Bold
    Write-Host "1. In the same Claude session, run:"
    Write-Host "   ls" -ForegroundColor $Colors.Info
    Write-Host "2. Check the hook log:"
    Write-Host "   wsl cat /tmp/cache-keepalive.log" -ForegroundColor $Colors.Info
    Write-Host "3. Expected: Log entries showing 'keepalive' timestamps"
    Write-Host "4. The hook fires every ~4 minutes to keep the 5-minute cache alive"
    Write-Host ""

    Write-Host "Test 3: PDF Text Extraction" -Bold
    Write-Host "1. Extract text from the test PDF:"
    Write-Host "   pdftotext -layout `"$TestPdf`" C:\temp\extracted.txt" -ForegroundColor $Colors.Info
    Write-Host "2. Compare sizes:"
    Write-Host "   dir `"$TestPdf`" C:\temp\extracted.txt" -ForegroundColor $Colors.Info
    Write-Host "3. Run inside Claude:"
    Write-Host "   Read C:\temp\extracted.txt" -ForegroundColor $Colors.Info
    Write-Host "4. Expected: Text file is ~10x smaller than binary PDF"
    Write-Host ""

    Write-Host "Note: If you don't have the test files, download them:" -ForegroundColor $Colors.Warning
    Write-Host "   wget -O tests/test-document.pdf https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf" -ForegroundColor $Colors.Info
}

# Generate final report
function Write-Report {
    Write-Header "📊 VALIDATION SUMMARY"

    Write-Host "Test Results: Passed: $script:TestsPassed | Failed: $script:TestsFailed | Skipped: $script:TestsSkipped"
    Write-Host ""

    $allConfigsOk = $script:TestsFailed -eq 0

    if ($allConfigsOk) {
        Write-Success "ALL CONFIGURATIONS VALID ✓"
        Write-Host ""
        Write-Host "Your Claude Code environment is properly configured:"
        Write-Host "  • Dependencies installed"
        Write-Host "  • Privacy settings active"
        Write-Host "  • Auto-compact enabled"
        Write-Host "  • Hooks configured"
        Write-Host ""
        Write-Host "Next step: Run the manual tests above to verify hook execution" -ForegroundColor $Colors.Warning
    } else {
        Write-Error "CONFIGURATION INCOMPLETE"
        Write-Host ""
        Write-Host "Some optimizations are not configured."
        Write-Host "Review the errors above and run optimize-claude.ps1 to fix."
    }

    Write-Host ""
    Write-Host "Quick Commands:" -Bold
    Write-Host "  Run optimizer:  .\scripts\windows\optimize-claude.ps1"
    Write-Host "  Debug mode:     .\scripts\windows\validate.ps1 -VerboseOutput"

    if ($allConfigsOk) {
        exit 0
    } else {
        exit 1
    }
}

# Main
Write-Header "Claude Code Optimizer - Configuration Validation"

Test-ClaudeInstallation
Test-Dependencies
Test-PrivacyConfiguration
Test-AutoCompact
Test-HookConfiguration

Write-ManualTests
Write-Report
