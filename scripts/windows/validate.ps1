#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Optimizer Comprehensive Validation Suite (Windows)
    Tests ALL optimization claims with quantitative token measurements

.DESCRIPTION
    This script validates:
    1. PreToolUse hook (image resizing) with token savings
    2. PostToolUse hook (cache keepalive)
    3. PDF text extraction with token savings
    4. Privacy environment variables
    5. Auto-compact configuration
    6. Dependency installation

.PARAMETER Detailed
    Show detailed output

.PARAMETER Keep
    Keep test files and results

.EXAMPLE
    .\validate.ps1
    Run full validation with token measurements
#>

[CmdletBinding()]
param(
    [switch]$Detailed,
    [switch]$Keep
)

# Colors
$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Error = 'Red'
    Warning = 'Yellow'
    Header = 'Blue'
    Proof = 'Magenta'
    Metric = 'Magenta'
}

# Configuration
$ScriptDir = $PSScriptRoot
$RepoDir = Join-Path $ScriptDir "..\.."
$TestDir = Join-Path $ScriptDir ".validation-test"
$ResultsDir = Join-Path $ScriptDir ".validation-results"
$TestImage = Join-Path $RepoDir "tests\test-image.png"
$PdfFile = Join-Path $RepoDir "tests\test-document.pdf"
$HookLog = "/tmp/hook-validation.log"
$ClaudeCmd = "claude"
$Timeout = 60

# Token tracking
$script:OriginalImageTokens = 0
$script:OptimizedImageTokens = 0
$script:OriginalPdfTokens = 0
$script:OptimizedPdfTokens = 0

# Test results
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0
$script:PreToolUseFired = $false
$script:PostToolUseFired = $false
$script:AutoCompactEnabled = $false
$script:PrivacyVarsSet = $false

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

function Write-Proof {
    param([string]$Message)
    Write-Host "[PROOF] $Message" -ForegroundColor $Colors.Proof
}

function Write-Metric {
    param([string]$Message)
    Write-Host "[METRIC] $Message" -ForegroundColor $Colors.Metric
}

# Token counting function
function Count-FileTokens {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return 0 }
    $chars = (Get-Item $FilePath).Length
    return [math]::Floor($chars / 4)
}

# Cleanup
function Cleanup {
    if (-not $Keep) {
        if (Test-Path $TestDir) { Remove-Item $TestDir -Recurse -Force }
        if (Test-Path $ResultsDir) { Remove-Item $ResultsDir -Recurse -Force }
    }
}
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

# Check prerequisites
function Check-Prerequisites {
    Write-Section "CHECKING PREREQUISITES"

    # Check Claude Code
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        $possiblePaths = @(
            "$env:USERPROFILE\.local\bin\claude.exe",
            "$env:LOCALAPPDATA\Programs\Claude\Claude.exe",
            "C:\Program Files\Claude\Claude.exe"
        )
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) { $script:ClaudeCmd = $path; break }
        }
    } else {
        $script:ClaudeCmd = $claude.Source
    }

    if (-not $script:ClaudeCmd) {
        Write-Error "Claude Code not found"
        exit 1
    }
    Write-Success "Claude Code found: $script:ClaudeCmd"

    # Check settings.json
    $userSettings = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (-not (Test-Path $userSettings)) {
        Write-Error "No settings.json found at ~/.claude/settings.json"
        Write-Status "Run optimize-claude.ps1 first"
        exit 1
    }
    Write-Success "Found settings.json"

    # Check hooks
    $settingsContent = Get-Content $userSettings -Raw
    if ($settingsContent -match '"PreToolUse"') { Write-Success "PreToolUse hook configured" }
    else { Write-Error "PreToolUse hook not configured" }

    if ($settingsContent -match '"PostToolUse"') { Write-Success "PostToolUse hook configured" }
    else { Write-Error "PostToolUse hook not configured" }

    # Check dependencies
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue
    if ($magick -or $convert) { Write-Success "ImageMagick found" }
    else { Write-Warning "ImageMagick not found" }

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) { Write-Success "pdftotext found" }
    else { Write-Warning "pdftotext not found" }
}

# Create test files
function Create-TestFiles {
    Write-Section "CREATING TEST FILES"
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

    # Use test image
    if (Test-Path $TestImage) {
        Copy-Item $TestImage (Join-Path $TestDir "test-image.png")
        $script:OriginalImageTokens = Count-FileTokens $TestImage
        $size = (Get-Item $TestImage).Length
        Write-Success "Using test-image.png ($(($size/1MB).ToString('F1')) MB, ~$($script:OriginalImageTokens) tokens)"
    }

    # Create test text
    $testDoc = Join-Path $TestDir "test-doc.txt"
    "This is a test document for Claude Code hook validation." | Set-Content $testDoc
    Write-Success "Created test-doc.txt"

    # Use test PDF
    if (Test-Path $PdfFile) {
        Copy-Item $PdfFile (Join-Path $TestDir "test-document.pdf")
        $script:OriginalPdfTokens = Count-FileTokens $PdfFile
        $size = (Get-Item $PdfFile).Length
        Write-Success "Using test-document.pdf ($(($size/1MB).ToString('F1')) MB, ~$($script:OriginalPdfTokens) tokens)"
    }
}

# Run Claude headlessly
function Run-ClaudeHeadless {
    param([string]$InputCmd, [string]$OutputFile, [string]$Description)
    Write-Status "Running: $Description"

    wsl rm -f $HookLog 2>$null

    $job = Start-Job -ScriptBlock {
        param($cmd, $inputCmd)
        $inputCmd | & $cmd -p 2>&1
    } -ArgumentList $script:ClaudeCmd, $InputCmd

    $completed = $job | Wait-Job -Timeout $Timeout
    if (-not $completed) {
        Write-Warning "Claude command timed out"
        Stop-Job $job
        Remove-Job $job
        return $false
    }

    $output = Receive-Job $job
    Remove-Job $job
    $output | Set-Content $OutputFile -Encoding UTF8
    return (Test-Path $OutputFile)
}

# Test PreToolUse
function Test-PreToolUseHook {
    Write-Section "TEST 1: PreToolUse Hook (Image Processing)"
    Write-Status "Testing if PreToolUse hook fires..."

    wsl rm -f /tmp/resized_*.png 2>$null
    $outputFile = Join-Path $ResultsDir "claude-output-image.txt"
    $testImage = Join-Path $TestDir "test-image.png"

    if (-not (Run-ClaudeHeadless "Read $testImage" $outputFile "Read image file")) {
        Write-Error "Failed to run Claude Code"
        return
    }

    if (Test-Path $outputFile) { Write-Success "Claude Code produced output" }
    else { Write-Error "No output captured"; return }

    Start-Sleep -Seconds 2

    Write-Status "Checking for resized image in /tmp (via WSL)..."
    $resizedFiles = wsl ls /tmp/resized_*.png 2>$null

    if ($resizedFiles) {
        $resizedFile = $resizedFiles | Select-Object -First 1
        $origSize = (Get-Item (Join-Path $TestDir "test-image.png")).Length
        $resizedSize = [int](wsl stat -c%s $resizedFile 2>$null)
        $script:OptimizedImageTokens = Count-FileTokens (wsl wslpath -w $resizedFile 2>$null)
        $tokensSaved = $script:OriginalImageTokens - $script:OptimizedImageTokens

        Write-Success "PreToolUse hook FIRED and resized the image!"
        Write-Proof "Resized file: $resizedFile"
        Write-Metric "Original: $origSize bytes (~$($script:OriginalImageTokens) tokens)"
        Write-Metric "Resized: $resizedSize bytes (~$($script:OptimizedImageTokens) tokens)"

        if ($resizedSize -lt $origSize) {
            $reduction = [math]::Round(100 - ($resizedSize * 100 / $origSize))
            Write-Metric "Size reduction: $reduction%"
        }
        Write-Metric "Token savings: ~$tokensSaved tokens"

        $script:PreToolUseFired = $true
    } else {
        Write-Error "PreToolUse hook did NOT fire - no resized image found"
    }
}

# Test PostToolUse
function Test-PostToolUseHook {
    Write-Section "TEST 2: PostToolUse Hook (Cache Keepalive)"
    Write-Status "Testing if PostToolUse hook fires..."

    wsl rm -f $HookLog 2>$null
    $outputFile = Join-Path $ResultsDir "claude-output-ls.txt"

    if (-not (Run-ClaudeHeadless "ls" $outputFile "List directory")) {
        Write-Error "Failed to run Claude Code"
        return
    }

    if (Test-Path $outputFile) { Write-Success "Claude Code produced output" }
    else { Write-Error "No output captured"; return }

    Write-Status "Checking hook log..."
    $logContent = wsl cat $HookLog 2>$null

    if ($logContent) {
        $entries = $logContent -split "`n" | Where-Object { $_ -ne "" }
        if ($entries.Count -gt 0) {
            Write-Success "PostToolUse hook FIRED - $($entries.Count) entries!"
            Write-Proof "Hook log entries:"
            $entries | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" }
            $script:PostToolUseFired = $true
        } else {
            Write-Error "Hook log is empty"
        }
    } else {
        Write-Error "PostToolUse hook did NOT fire"
    }
}

# Test PDF Processing
function Test-PdfProcessing {
    Write-Section "TEST 3: PDF Processing (Binary File Optimization)"

    $pdfFile = Join-Path $TestDir "test-document.pdf"
    if (-not (Test-Path $pdfFile)) {
        Write-Warning "No test-document.pdf found - skipping PDF test"
        return
    }

    Write-Status "Testing PDF text extraction..."
    $extractedText = Join-Path $TestDir "extracted-text.txt"
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue

    if (-not $pdftotext) {
        Write-Warning "pdftotext not available - skipping PDF test"
        return
    }

    if (& pdftotext.exe -layout $pdfFile $extractedText 2>$null) {
        if (Test-Path $extractedText) {
            $pdfSize = (Get-Item $pdfFile).Length
            $txtSize = (Get-Item $extractedText).Length
            $script:OptimizedPdfTokens = Count-FileTokens $extractedText
            $tokensSaved = $script:OriginalPdfTokens - $script:OptimizedPdfTokens

            Write-Success "PDF text extraction worked!"
            Write-Metric "PDF: $pdfSize bytes (~$($script:OriginalPdfTokens) tokens)"
            Write-Metric "Text: $txtSize bytes (~$($script:OptimizedPdfTokens) tokens)"

            if ($txtSize -lt $pdfSize) {
                $reduction = [math]::Round(100 - ($txtSize * 100 / $pdfSize))
                Write-Metric "Size reduction: $reduction%"
            }
            Write-Metric "Token savings: ~$tokensSaved tokens"
        } else {
            Write-Warning "PDF extraction produced empty file"
        }
    } else {
        Write-Error "PDF text extraction failed"
    }
}

# Test Privacy Configuration
function Test-PrivacyConfiguration {
    Write-Section "TEST 4: Privacy Configuration"

    $vars = @(
        @{ Name = "DISABLE_TELEMETRY"; Expected = "1" },
        @{ Name = "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"; Expected = "1" },
        @{ Name = "OTEL_LOG_USER_PROMPTS"; Expected = "0" },
        @{ Name = "OTEL_LOG_TOOL_DETAILS"; Expected = "0" },
        @{ Name = "CLAUDE_CODE_AUTO_COMPACT_WINDOW"; Expected = "180000" }
    )

    $privacyScore = 0
    foreach ($var in $vars) {
        $actual = [Environment]::GetEnvironmentVariable($var.Name, "User")
        if ($actual -eq $var.Expected) {
            Write-Success "$($var.Name)=$actual"
            $privacyScore++
        } else {
            Write-Error "$($var.Name) not set (expected: $($var.Expected), got: $actual)"
        }
    }

    Write-Metric "Privacy Score: $privacyScore/5"
    if ($privacyScore -eq 5) { $script:PrivacyVarsSet = $true }
}

# Test Auto-Compact
function Test-AutoCompact {
    Write-Section "TEST 5: Auto-Compact Configuration"

    $claudeConfig = Join-Path $env:USERPROFILE ".claude\.claude.json"
    if (Test-Path $claudeConfig) {
        $config = Get-Content $claudeConfig -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($config.autoCompactEnabled -eq $true) {
            Write-Success "Auto-compact enabled"
            $script:AutoCompactEnabled = $true
        } else {
            Write-Error "Auto-compact not enabled"
        }
    } else {
        Write-Error "Claude config file not found: $claudeConfig"
    }
}

# Run all tests
function Run-AllTests {
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
    Test-PreToolUseHook
    Test-PostToolUseHook
    Test-PdfProcessing
    Test-PrivacyConfiguration
    Test-AutoCompact
}

# Generate report
function Generate-Report {
    Write-Header "COMPREHENSIVE VALIDATION REPORT"

    Write-Host "Test Results: Passed: $script:TestsPassed | Failed: $script:TestsFailed | Skipped: $script:TestsSkipped"
    Write-Host ""

    # Dependencies
    Write-Section "📦 Dependencies"
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($magick -or $convert) {
        if ($pdftotext) { Write-Success "All dependencies installed" }
        else { Write-Warning "ImageMagick OK, pdftotext missing" }
    } else { Write-Error "ImageMagick not installed" }

    # Privacy
    Write-Section "🔒 Privacy Configuration"
    $privacyScore = 0
    if ($env:DISABLE_TELEMETRY -eq "1") { $privacyScore++ }
    if ($env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -eq "1") { $privacyScore++ }
    if ($env:OTEL_LOG_USER_PROMPTS -eq "0") { $privacyScore++ }
    if ($env:OTEL_LOG_TOOL_DETAILS -eq "0") { $privacyScore++ }
    if ($env:CLAUDE_CODE_AUTO_COMPACT_WINDOW -eq "180000") { $privacyScore++ }

    Write-Metric "Privacy Score: $privacyScore/5"
    if ($privacyScore -eq 5) { Write-Success "Maximum privacy configured" }

    # Auto-compact
    Write-Section "⚙️  Auto-Compact"
    $claudeConfig = Join-Path $env:USERPROFILE ".claude\.claude.json"
    if ((Test-Path $claudeConfig) -and (Get-Content $claudeConfig -Raw) -match '"autoCompactEnabled": true') {
        Write-Success "Auto-compact enabled"
    } else { Write-Error "Auto-compact not enabled" }

    # Hooks
    Write-Section "🪝 Hook Execution"
    if ($script:PreToolUseFired) { Write-Success "PreToolUse (image processing)" }
    else { Write-Error "PreToolUse did not fire" }

    if ($script:PostToolUseFired) { Write-Success "PostToolUse (cache keepalive)" }
    else { Write-Error "PostToolUse did not fire" }

    # Token savings
    Write-Section "💰 Token Savings"
    $totalSaved = 0
    if ($script:OriginalImageTokens -gt 0 -and $script:OptimizedImageTokens -gt 0) {
        $imgSaved = $script:OriginalImageTokens - $script:OptimizedImageTokens
        $imgPct = [math]::Round(($imgSaved * 100 / $script:OriginalImageTokens), 1)
        Write-Metric "Images: $($script:OriginalImageTokens) → $($script:OptimizedImageTokens) tokens (${imgPct}% reduction)"
        $totalSaved += $imgSaved
    }
    if ($script:OriginalPdfTokens -gt 0 -and $script:OptimizedPdfTokens -gt 0) {
        $pdfSaved = $script:OriginalPdfTokens - $script:OptimizedPdfTokens
        $pdfPct = [math]::Round(($pdfSaved * 100 / $script:OriginalPdfTokens), 1)
        Write-Metric "PDFs: $($script:OriginalPdfTokens) → $($script:OptimizedPdfTokens) tokens (${pdfPct}% reduction)"
        $totalSaved += $pdfSaved
    }
    Write-Metric "Total token savings: ~$totalSaved tokens"

    # Overall verdict
    Write-Section "Overall Verdict"
    $allGood = $script:PreToolUseFired -and $script:PostToolUseFired -and
               $script:PrivacyVarsSet -and $script:AutoCompactEnabled

    if ($allGood) {
        Write-Success "ALL OPTIMIZATIONS WORKING"
        Write-Host ""
        Write-Host "Your Claude Code environment is fully optimized:"
        Write-Host "  • Hooks are firing automatically"
        Write-Host "  • Privacy settings configured"
        Write-Host "  • Token savings verified (~$totalSaved tokens)"
        Write-Host "  • Auto-compact enabled"
    } elseif ($script:PreToolUseFired -or $script:PostToolUseFired) {
        Write-Warning "PARTIALLY OPTIMIZED - Some optimizations working"
    } else {
        Write-Error "NOT OPTIMIZED - Run .\optimize-claude.ps1"
    }

    if ($allGood) { exit 0 } else { exit 1 }
}

# Main
Write-Header "Claude Code Optimizer - Comprehensive Validation Suite"
New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null

Write-Status "This comprehensive suite will:"
Write-Status "1. Check all dependencies and configuration"
Write-Status "2. Create test files and measure original token counts"
Write-Status "3. Run Claude Code to trigger hooks"
Write-Status "4. Measure actual token savings"
Write-Status "5. Generate detailed validation report"
Write-Host ""

Check-Prerequisites
Create-TestFiles
Run-AllTests
Generate-Report
