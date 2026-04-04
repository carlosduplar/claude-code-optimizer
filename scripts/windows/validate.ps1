#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Optimizer - Configuration Validation Suite (Windows)
    Validates setup with optional headless hook testing

.DESCRIPTION
    Validates:
    1. Claude Code installation
    2. Dependencies (ImageMagick, pdftotext, markitdown, jq)
    3. Privacy environment variables
    4. Auto-compact configuration
    5. Hook configuration (PreToolUse, PostToolUse)
    6. Headless hook execution (optional with -TestHooks)

.PARAMETER VerboseOutput
    Show detailed output including full config file contents

.PARAMETER TestHooks
    Run headless hook tests (requires jq, API credits)

.PARAMETER Help
    Show help message

.EXAMPLE
    .\validate.ps1
    Run configuration validation only

.EXAMPLE
    .\validate.ps1 -TestHooks
    Run validation including headless hook tests

.EXAMPLE
    .\validate.ps1 -VerboseOutput
    Run with detailed output
#>

[CmdletBinding()]
param(
    [switch]$VerboseOutput,
    [switch]$TestHooks
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
$ClaudeCmd = $null

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

# Find Claude binary
function Find-Claude {
    $paths = @(
        (Get-Command claude -ErrorAction SilentlyContinue),
        "$env:USERPROFILE\.local\bin\claude.exe",
        "$env:LOCALAPPDATA\Programs\Claude\Claude.exe",
        "$env:LOCALAPPDATA\claude\claude.exe",
        "C:\Program Files\Claude\Claude.exe",
        "C:\Program Files (x86)\Claude\Claude.exe"
    )

    foreach ($path in $paths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }
    return $null
}

# Test 1: Check Claude Code installation
function Test-ClaudeInstallation {
    Write-Section "🔍 CLAUDE CODE INSTALLATION"

    $script:ClaudeCmd = Find-Claude

    if ($script:ClaudeCmd) {
        $version = & $script:ClaudeCmd --version 2>&1 | Select-Object -First 1
        Write-Success "Claude Code found: $version"
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

    # jq (for headless hook testing)
    $jq = Get-Command jq -ErrorAction SilentlyContinue
    if ($jq) {
        Write-Success "jq installed (required for -TestHooks)"
    } else {
        if ($TestHooks) {
            Write-Error "jq not found (required for -TestHooks)"
            Write-Status "Install: winget install jqlang.jq"
            Write-Status "        choco install jq"
            $TestHooks = $false
        } else {
            Write-Warning "jq not found (install for -TestHooks capability)"
        }
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

    # Check attribution settings (saves ~50-100 tokens per commit/PR)
    if ($configContent -match '"attribution"') {
        if ($configContent -match '"commit":\s*""' -and $configContent -match '"pr":\s*""') {
            Write-Success "attribution: commit and pr set to empty (saves ~50-100 tokens)"
        } else {
            Write-Warning "attribution found but may not be empty strings"
        }
    } else {
        Write-Warning "attribution not configured (optional, saves ~50-100 tokens per commit/PR)"
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

# Test 6: Headless hook execution
function Test-HooksHeadless {
    Write-Section "🧪 HEADLESS HOOK TESTING"

    if (-not $TestHooks) {
        Write-Warning "Skipped (use -TestHooks to enable)"
        return
    }

    if (-not $script:ClaudeCmd) {
        Write-Error "Claude not found, cannot run headless tests"
        return
    }

    Write-Status "Running headless hook test (costs ~`$0.01-0.02 in API credits)..."
    Write-Status "Command: claude -p --output-format stream-json --include-hook-events --allowedTools 'Read'"

    # Create test image if needed
    $testImage = $TestImage
    if (-not (Test-Path $testImage)) {
        Write-Warning "Test image not found at $testImage"
        Write-Status "Creating a simple test image..."
        $testImage = "$env:TEMP\validate-test.png"

        $magick = Get-Command magick -ErrorAction SilentlyContinue
        $convert = Get-Command convert -ErrorAction SilentlyContinue

        if ($magick) {
            & $magick -size 100x100 xc:blue $testImage 2>$null
        } elseif ($convert) {
            & $convert -size 100x100 xc:blue $testImage 2>$null
        }

        if (-not (Test-Path $testImage)) {
            Write-Warning "Could not create test image, skipping headless test"
            return
        }
    }

    # Convert to WSL path if needed
    $wslImage = $testImage
    if ($testImage -match '^[A-Z]:') {
        $drive = $testImage[0].ToString().ToLower()
        $path = $testImage.Substring(2).Replace('\', '/')
        $wslImage = "/mnt/$drive$path"
    }

    $outputFile = "$env:TEMP\claude-hook-test-$PID.jsonl"

    Write-Status "Executing: Read $wslImage"

    # Run Claude in headless mode with hook events
    # Note: --include-hook-events requires --verbose flag
    & $script:ClaudeCmd -p `
        --output-format stream-json `
        --verbose `
        --include-hook-events `
        --allowedTools "Read" `
        "Read $wslImage" 2>&1 | Out-File -FilePath $outputFile -Encoding UTF8

    $exitCode = $LASTEXITCODE

    # Parse results
    if (Test-Path $outputFile) {
        $content = Get-Content $outputFile -Raw
        $lines = $content -split "`n" | Where-Object { $_.Trim() }

        $preCount = 0
        $postCount = 0
        $hookEvents = @()

        foreach ($line in $lines) {
            try {
                $json = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                # Hook events have type="system" with subtype="hook_started" or "hook_response"
                if ($json.type -eq "system" -and $json.subtype -match "^hook_") {
                    $hookEvents += "$($json.hook_name):$($json.hook_event)"
                    if ($json.hook_name -eq "PreToolUse:Read") { $preCount++ }
                    if ($json.hook_name -eq "PostToolUse:Read") { $postCount++ }
                }
            } catch {}
        }

        if ($preCount -gt 0) {
            Write-Success "PreToolUse hook fired ($preCount times)"
        } else {
            Write-Error "PreToolUse hook did not fire"
            if ($VerboseOutput) {
                Write-Status "Hook events found:"
                $hookEvents | ForEach-Object { Write-Status "  $_" }
            }
        }

        if ($postCount -gt 0) {
            Write-Success "PostToolUse hook fired ($postCount times)"
        } else {
            Write-Error "PostToolUse hook did not fire"
        }

        # Check for resized image (in WSL /tmp)
        $wslCheck = wsl ls /tmp/resized_*.png 2>$null
        if ($wslCheck) {
            Write-Success "Image resizing hook executed (resized file found)"
        } else {
            Write-Warning "Resized image not found in WSL /tmp (hook may have run but output path differs)"
        }

        # Show usage if available
        foreach ($line in $lines) {
            try {
                $json = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($json.type -eq "result" -and $json.usage) {
                    $u = $json.usage
                    $usage = "Input: $($u.input_tokens), Output: $($u.output_tokens), Cache: $($u.cache_creation_tokens)/$($u.cache_read_tokens)"
                    Write-Metric "API Usage: $usage"
                    break
                }
            } catch {}
        }
    } else {
        Write-Error "No output captured from headless test"
    }

    # Cleanup
    Remove-Item $outputFile -ErrorAction SilentlyContinue

    if ($exitCode -ne 0) {
        Write-Warning "Claude exited with code $exitCode (may indicate API error or rate limit)"
    }
}

# Print manual test instructions
function Write-ManualTests {
    Write-Header "🧪 MANUAL HOOK VERIFICATION (Fallback)"

    $wslRepoDir = wsl wslpath -a "$RepoDir" 2>$null
    if (-not $wslRepoDir) {
        $wslRepoDir = "/mnt/c" + ($RepoDir -replace '^C:', '').Replace('\', '/')
    }

    Write-Host "If headless testing failed or was skipped, verify hooks manually:"
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
        if ($TestHooks) {
            Write-Host "  • Hooks tested in headless mode"
        }
        Write-Host ""
        if (-not $TestHooks) {
            Write-Host "Next step: Run with -TestHooks to verify hook execution" -ForegroundColor $Colors.Warning
        }
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
    Write-Host "  Test hooks:     .\scripts\windows\validate.ps1 -TestHooks"

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
Test-HooksHeadless
Write-ManualTests
Write-Report
