#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Hook Validation - Headless Mode (Windows)
    Automatically runs Claude Code, triggers hooks, and validates they fire

.DESCRIPTION
    This script:
    1. Creates test files (images, PDFs, documents)
    2. Runs Claude Code in headless/non-interactive mode (-p flag)
    3. Sends Read commands to trigger PreToolUse hooks
    4. Verifies hooks fired by checking side effects and log files
    5. Generates validation report with proof

.PARAMETER Detailed
    Show detailed output

.PARAMETER Keep
    Keep test files and results

.EXAMPLE
    .\validate-hooks-headless.ps1
    Run full validation

.EXAMPLE
    .\validate-hooks-headless.ps1 -Detailed
    Run with detailed output

.EXAMPLE
    .\validate-hooks-headless.ps1 -Keep
    Preserve test files for inspection
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
}

# Configuration
$ScriptDir = $PSScriptRoot
$TestDir = Join-Path $ScriptDir ".validation-test"
$ResultsDir = Join-Path $ScriptDir ".validation-results"
$HookLog = "/tmp/hook-validation.log"
$ClaudeCmd = "claude"
$Timeout = 60

# Test results
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0
$script:PreToolUseFired = $false
$script:PostToolUseFired = $false
$script:ResizedImageCreated = $false
$script:PdfConverted = $false

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
    Write-Host "[PASS] $Message" -ForegroundColor $Colors.Success
    $script:TestsPassed++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor $Colors.Error
    $script:TestsFailed++
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor $Colors.Warning
    $script:TestsSkipped++
}

function Write-Proof {
    param([string]$Message)
    Write-Host "[PROOF] $Message" -ForegroundColor $Colors.Proof
}

# Cleanup
function Cleanup {
    if (-not $Keep) {
        if (Test-Path $TestDir) {
            Remove-Item $TestDir -Recurse -Force
        }
        if (Test-Path $ResultsDir) {
            Remove-Item $ResultsDir -Recurse -Force
        }
        # Don't remove hook log on Windows (WSL path)
    }
}

# Register cleanup
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Cleanup }

# Check prerequisites
function Check-Prerequisites {
    Write-Section "CHECKING PREREQUISITES"

    # Check Claude Code
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        # Try common locations
        $possiblePaths = @(
            "$env:USERPROFILE\.local\bin\claude.exe",
            "$env:LOCALAPPDATA\Programs\Claude\Claude.exe",
            "C:\Program Files\Claude\Claude.exe"
        )
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $script:ClaudeCmd = $path
                break
            }
        }
    } else {
        $script:ClaudeCmd = $claude.Source
    }

    if (-not $script:ClaudeCmd) {
        Write-Error "Claude Code not found"
        exit 1
    }
    Write-Success "Claude Code found: $script:ClaudeCmd"

    # Check version
    try {
        $version = & $script:ClaudeCmd --version 2>&1
        Write-Status "Claude Code version: $version"
    } catch {
        Write-Status "Could not determine version"
    }

    # Check settings.json (user-level only - project-level is just an example)
    $userSettings = Join-Path $env:USERPROFILE ".claude\settings.json"

    if (-not (Test-Path $userSettings)) {
        Write-Error "No settings.json found at ~/.claude/settings.json"
        Write-Status "Run optimize-claude.ps1 first"
        exit 1
    }
    Write-Success "Found settings.json at ~/.claude/settings.json"

    # Check hooks configured
    $settingsContent = Get-Content $userSettings -Raw

    if ($settingsContent -notmatch '"PreToolUse"') {
        Write-Error "PreToolUse hook not configured"
        exit 1
    }
    Write-Success "PreToolUse hook configured"

    if ($settingsContent -notmatch '"PostToolUse"') {
        Write-Error "PostToolUse hook not configured"
        exit 1
    }
    Write-Success "PostToolUse hook configured"

    # Check ImageMagick
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue
    if (-not $magick -and -not $convert) {
        Write-Warning "ImageMagick not found"
    } else {
        Write-Success "ImageMagick found"
    }

    # Check pdftotext
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if (-not $pdftotext) {
        Write-Warning "pdftotext not found - PDF tests may be limited"
    } else {
        Write-Success "pdftotext found"
    }
}

# Create test files
function Create-TestFiles {
    Write-Section "CREATING TEST FILES"

    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
    Write-Status "Test directory: $TestDir"

    # Create test image
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue

    if ($magick -or $convert) {
        $cmd = if ($magick) { "magick" } else { "convert" }
        $testImage = Join-Path $TestDir "test-image.png"
        & $cmd -size 3000x3000 xc:blue $testImage 2>$null
        Write-Success "Created test-image.png (3000x3000 pixels)"
    } else {
        Write-Error "Cannot create test image"
    }

    # Create test text file
    $testDoc = Join-Path $TestDir "test-doc.txt"
    "This is a test document for Claude Code hook validation." | Set-Content $testDoc
    Write-Success "Created test-doc.txt"

    # Check for existing test PDF
    $existingPdf = Join-Path $ScriptDir "test-document.pdf"
    if (Test-Path $existingPdf) {
        Write-Success "Found existing test-document.pdf"
    }

    Get-ChildItem $TestDir | ForEach-Object {
        Write-Host "  $($_.Name) - $([math]::Round($_.Length / 1KB, 2)) KB"
    }
}

# Run Claude Code headlessly
function Run-ClaudeHeadless {
    param(
        [string]$InputCmd,
        [string]$OutputFile,
        [string]$Description
    )

    Write-Status "Running: $Description"

    if ($Detailed) {
        Write-Host "--- Claude Code Input ---"
        Write-Host $InputCmd
        Write-Host "-------------------------"
    }

    # Clear hook log via WSL
    wsl rm -f $HookLog 2>$null

    # Run with timeout
    $job = Start-Job -ScriptBlock {
        param($cmd, $inputCmd)
        $output = $inputCmd | & $cmd -p 2>&1
        $output
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

    if ($Detailed) {
        Write-Host "--- Claude Code Output ---"
        $output | ForEach-Object { Write-Host $_ }
        Write-Host "--------------------------"
    }

    return (Test-Path $OutputFile)
}

# Test PreToolUse Hook
function Test-PreToolUseHook {
    Write-Section "TEST 1: PreToolUse Hook (Image Processing)"

    Write-Status "Testing if PreToolUse hook fires when reading an image..."

    # Clean up
    wsl rm -f /tmp/resized_*.png 2>$null
    wsl rm -f $HookLog 2>$null

    # Run Claude
    $outputFile = Join-Path $ResultsDir "claude-output-image.txt"
    $testImage = Join-Path $TestDir "test-image.png"

    Write-Status "Reading image: $testImage"

    if (-not (Run-ClaudeHeadless "Read $testImage" $outputFile "Read image file")) {
        Write-Error "Failed to run Claude Code"
        return
    }

    if (Test-Path $outputFile) {
        Write-Success "Claude Code produced output"
    } else {
        Write-Error "No output captured"
        return
    }

    # Wait for hook
    Start-Sleep -Seconds 2

    # Check for resized image
    Write-Status "Checking for resized image in /tmp (via WSL)..."

    $resizedFiles = wsl ls /tmp/resized_*.png 2>$null
    if ($resizedFiles) {
        $resizedFile = $resizedFiles | Select-Object -First 1
        $originalFile = Get-Item (Join-Path $TestDir "test-image.png")

        # Get sizes via WSL
        $originalSize = $originalFile.Length
        $resizedSize = wsl stat -c%s $resizedFile 2>$null

        Write-Success "PreToolUse hook FIRED and resized the image!"
        Write-Proof "Resized file: $resizedFile"
        Write-Proof "Original: $originalSize bytes"
        if ($resizedSize) {
            Write-Proof "Resized: $resizedSize bytes"
            if ([int]$resizedSize -lt $originalSize) {
                $reduction = [math]::Round(100 - ([int]$resizedSize * 100 / $originalSize))
                Write-Proof "Size reduction: $reduction%"
            }
        }

        $script:PreToolUseFired = $true
        $script:ResizedImageCreated = $true
    } else {
        Write-Error "PreToolUse hook did NOT fire - no resized image found"
        Write-Status "Expected: /tmp/resized_*.png"
        $script:PreToolUseFired = $false
    }
}

# Test PostToolUse Hook
function Test-PostToolUseHook {
    Write-Section "TEST 2: PostToolUse Hook (Cache Keepalive)"

    Write-Status "Testing if PostToolUse hook fires after tool use..."

    # Clear log
    wsl rm -f $HookLog 2>$null

    # Run Claude
    $outputFile = Join-Path $ResultsDir "claude-output-ls.txt"

    Write-Status "Running: ls"

    if (-not (Run-ClaudeHeadless "ls" $outputFile "List directory")) {
        Write-Error "Failed to run Claude Code"
        return
    }

    if (Test-Path $outputFile) {
        Write-Success "Claude Code produced output"
    } else {
        Write-Error "No output captured"
        return
    }

    # Check hook log via WSL
    Write-Status "Checking hook log file (via WSL)..."

    $logContent = wsl cat $HookLog 2>$null
    if ($logContent) {
        $entries = $logContent -split "`n" | Where-Object { $_ -ne "" }
        $entryCount = $entries.Count

        if ($entryCount -gt 0) {
            Write-Success "PostToolUse hook FIRED - $entryCount entries in log!"
            Write-Proof "Hook log entries:"
            $entries | Select-Object -First 5 | ForEach-Object {
                Write-Host "  $_"
            }
            $script:PostToolUseFired = $true
        } else {
            Write-Error "Hook log is empty"
            $script:PostToolUseFired = $false
        }
    } else {
        Write-Error "PostToolUse hook did NOT fire - no hook log found"
        $script:PostToolUseFired = $false
    }
}

# Test PDF Processing
function Test-PdfProcessing {
    Write-Section "TEST 3: PDF Processing (Binary File Optimization)"

    # Use existing test PDF from project root
    $pdfFile = Join-Path $ScriptDir "test-document.pdf"
    if (-not (Test-Path $pdfFile)) {
        Write-Warning "No test-document.pdf found in project root - skipping PDF test"
        return
    }

    Write-Status "Testing PDF text extraction with existing test-document.pdf..."

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if (-not $pdftotext) {
        Write-Warning "pdftotext not available - skipping PDF test"
        return
    }

    $extractedText = Join-Path $TestDir "extracted-text.txt"

    Write-Status "Using pdftotext to extract PDF content..."

    if (& pdftotext.exe -layout $pdfFile $extractedText 2>$null) {
        if (Test-Path $extractedText) {
            $pdfSize = (Get-Item $pdfFile).Length
            $txtSize = (Get-Item $extractedText).Length

            Write-Success "PDF text extraction worked!"
            Write-Proof "PDF size: $pdfSize bytes"
            Write-Proof "Text size: $txtSize bytes"

            if ($txtSize -lt $pdfSize) {
                $reduction = [math]::Round(100 - ($txtSize * 100 / $pdfSize))
                Write-Proof "Size reduction: $reduction%"
            }

            if ($Detailed) {
                Write-Host "  Extracted text preview:"
                Get-Content $extractedText -TotalCount 5 | ForEach-Object {
                    Write-Host "    $_"
                }
            }

            $script:PdfConverted = $true
        } else {
            Write-Warning "PDF extraction produced empty file"
        }
    } else {
        Write-Error "PDF text extraction failed"
    }
}

# Test Combined Workflow
function Test-CombinedWorkflow {
    Write-Section "TEST 4: Combined Workflow"

    Write-Status "Testing multiple operations..."

    wsl rm -f $HookLog 2>$null

    $operations = @(
        @{ Cmd = "Read $(Join-Path $TestDir 'test-doc.txt')"; Desc = "Read text file" },
        @{ Cmd = "pwd"; Desc = "Print working directory" },
        @{ Cmd = "echo 'test'"; Desc = "Echo test" }
    )

    $totalRuns = 0

    for ($i = 0; $i -lt $operations.Count; $i++) {
        $op = $operations[$i]
        $outputFile = Join-Path $ResultsDir "claude-output-$i.txt"

        Write-Status "Operation $($i + 1): $($op.Desc)"

        if (Run-ClaudeHeadless $op.Cmd $outputFile $op.Desc) {
            $totalRuns++
        }

        Start-Sleep -Seconds 1
    }

    # Count hook entries
    $logContent = wsl cat $HookLog 2>$null
    $hookEntries = if ($logContent) { ($logContent -split "`n").Count } else { 0 }

    Write-Status "Completed $totalRuns operations"
    Write-Status "Hook log has $hookEntries entries"

    if ($hookEntries -gt 0) {
        Write-Success "Hooks fire consistently across multiple operations"
    } else {
        Write-Warning "Hooks may not be firing consistently"
    }
}

# Generate report
function Generate-Report {
    Write-Header "HOOK VALIDATION REPORT"

    Write-Host "Test Results:" -Bold
    Write-Host "  Passed: $($script:TestsPassed)"
    Write-Host "  Failed: $($script:TestsFailed)"
    Write-Host "  Skipped: $($script:TestsSkipped)"
    Write-Host ""

    Write-Host "Hook Execution Summary:" -Bold
    Write-Host ""

    # PreToolUse
    Write-Host "PreToolUse Hook (Image Processing):" -ForegroundColor Cyan
    if ($script:PreToolUseFired) {
        Write-Host "  FIRED - Image was resized" -ForegroundColor Green
        if ($script:ResizedImageCreated) {
            Write-Host "  Evidence: /tmp/resized_*.png exists"
        }
    } else {
        Write-Host "  DID NOT FIRE" -ForegroundColor Red
        Write-Host "  No resized image found in /tmp/"
    }
    Write-Host ""

    # PostToolUse
    Write-Host "PostToolUse Hook (Cache Keepalive):" -ForegroundColor Cyan
    if ($script:PostToolUseFired) {
        Write-Host "  FIRED - Hook log has entries" -ForegroundColor Green
        Write-Host "  Evidence: $HookLog contains entries"
    } else {
        Write-Host "  DID NOT FIRE" -ForegroundColor Red
        Write-Host "  No hook log entries found"
    }
    Write-Host ""

    # PDF
    Write-Host "PDF Processing:" -ForegroundColor Cyan
    if ($script:PdfConverted) {
        Write-Host "  WORKING - PDF text extraction succeeded" -ForegroundColor Green
    } else {
        Write-Host "  NOT TESTED - PDF tools not available or test skipped" -ForegroundColor Yellow
    }
    Write-Host ""

    # Overall
    Write-Host "Overall Verdict:" -Bold
    if ($script:PreToolUseFired -and $script:PostToolUseFired) {
        Write-Host "ALL HOOKS ARE WORKING" -ForegroundColor Green -Bold
        Write-Host ""
        Write-Host "Both PreToolUse and PostToolUse hooks are firing automatically."
        Write-Host "The optimizations are active and functional!"
    } elseif ($script:PreToolUseFired -or $script:PostToolUseFired) {
        Write-Host "PARTIALLY WORKING" -ForegroundColor Yellow -Bold
        Write-Host ""
        Write-Host "Some hooks are firing but not all."
    } else {
        Write-Host "HOOKS NOT FIRING" -ForegroundColor Red -Bold
        Write-Host ""
        Write-Host "The hooks are not triggering. Check:"
        Write-Host "  - Claude Code was restarted after installing hooks"
        Write-Host "  - Hook scripts exist in .claude/hooks/"
        Write-Host "  - Hook scripts are executable"
    }

    Write-Host ""
    Write-Host "Artifacts:" -Bold
    if ($Keep) {
        Write-Host "  Test files: $TestDir"
        Write-Host "  Results: $ResultsDir"
    } else {
        Write-Host "  (Use -Keep to preserve test files and results)"
    }

    # Exit code
    if ($script:PreToolUseFired -and $script:PostToolUseFired) {
        exit 0
    } else {
        exit 1
    }
}

# Main
Write-Header "Claude Code Hook Validation - Headless Mode"

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null

Write-Status "This script will:"
Write-Status "1. Create test files (image, PDF, text)"
Write-Status "2. Run Claude Code in headless mode"
Write-Status "3. Send Read commands to trigger hooks"
Write-Status "4. Verify hooks fired by checking side effects"
Write-Host ""

Check-Prerequisites
Create-TestFiles
Test-PreToolUseHook
Test-PostToolUseHook
Test-PdfProcessing
Test-CombinedWorkflow

Generate-Report
