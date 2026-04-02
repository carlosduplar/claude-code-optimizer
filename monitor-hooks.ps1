#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Hook Execution Monitor for Windows
    Verifies that Claude Code ACTUALLY triggers existing hooks during operation

.DESCRIPTION
    This script:
    1. Creates test files that should trigger existing hooks
    2. Provides instructions for testing
    3. Verifies hook execution by checking for output files/clues

.PARAMETER Test
    Create test files and show test instructions

.PARAMETER Verify
    Check if hooks are configured and provide verification steps

.PARAMETER Reset
    Clean up test files

.EXAMPLE
    .\monitor-hooks.ps1 -Test
    Create test files and show instructions

.EXAMPLE
    .\monitor-hooks.ps1 -Verify
    Check hook configuration and verification methods

.EXAMPLE
    .\monitor-hooks.ps1 -Reset
    Clean up test files
#>

[CmdletBinding()]
param(
    [switch]$Test,
    [switch]$Verify,
    [switch]$Reset
)

# Colors
$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Error = 'Red'
    Warning = 'Yellow'
    Header = 'Blue'
}

# Paths
$ScriptDir = $PSScriptRoot
$TestFilesDir = Join-Path $ScriptDir ".hook-test-files"
$SettingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
$TempDir = $env:TEMP

# Output functions
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Header
    Write-Host " $Message" -ForegroundColor $Colors.Header
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Header
    Write-Host ""
}

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Info
}

function Write-Success {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor $Colors.Success
}

function Write-Error {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor $Colors.Error
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor $Colors.Warning
}

# Create test files
function Create-TestFiles {
    Write-Header "Creating Test Files"

    New-Item -ItemType Directory -Path $TestFilesDir -Force | Out-Null
    Write-Status "Test files directory: $TestFilesDir"

    # Create a test image
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue

    if ($magick -or $convert) {
        $cmd = if ($magick) { "magick" } else { "convert" }
        $testImage = Join-Path $TestFilesDir "test-image.png"
        & $cmd -size 3000x3000 xc:blue $testImage 2>$null
        if (Test-Path $testImage) {
            Write-Success "Created test-image.png (3000x3000 pixels)"
        }
    } else {
        Write-Warning "ImageMagick not available - cannot create test image"
    }

    # Create a test PDF
    $python = Get-Command python -ErrorAction SilentlyContinue
    $python3 = Get-Command python3 -ErrorAction SilentlyContinue
    $pyCmd = if ($python3) { "python3" } elseif ($python) { "python" } else { $null }

    if ($pyCmd) {
        $pdfPath = Join-Path $TestFilesDir "test-document.pdf"
        $pyScript = "from reportlab.pdfgen import canvas; c = canvas.Canvas('$pdfPath'); c.drawString(100, 700, 'Test PDF document for hook monitoring'); c.drawString(100, 680, 'This file is used to test if Claude Code triggers hooks'); c.save()"
        & $pyCmd -c $pyScript 2>$null
        if (Test-Path $pdfPath) {
            Write-Success "Created test-document.pdf"
        }
    }

    # Create a test text file
    $testText = Join-Path $TestFilesDir "test-document.txt"
    "This is a test text file." | Set-Content $testText
    Write-Success "Created test-document.txt"

    Write-Host ""
    Write-Host "Test files created:" -Bold
    Get-ChildItem $TestFilesDir | ForEach-Object {
        Write-Host "  $($_.Name) - $([math]::Round($_.Length / 1KB, 2)) KB"
    }
}

# Check if hooks are configured
function Check-HooksConfigured {
    Write-Header "Checking Hook Configuration"

    if (-not (Test-Path $SettingsFile)) {
        Write-Error "No settings.json found at ~/.claude/settings.json"
        Write-Status "Run optimize-claude.ps1 first to install hooks"
        return $false
    }

    Write-Success "Found settings.json at ~/.claude/settings.json"

    $content = Get-Content $SettingsFile -Raw

    # Check for PreToolUse hook
    if ($content -match '"PreToolUse"') {
        Write-Success "PreToolUse hook is configured"
        if ($content -match 'magick.*resize|convert.*resize') {
            Write-Success "Image resize command found in PreToolUse hook"
        }
    } else {
        Write-Error "PreToolUse hook not found in settings.json"
        Write-Status "Run optimize-claude.ps1 to install hooks"
        return $false
    }

    # Check for PostToolUse hook
    if ($content -match '"PostToolUse"') {
        Write-Success "PostToolUse hook is configured"
        if ($content -match 'cache_keepalive|keepalive') {
            Write-Success "Cache keepalive command found in PostToolUse hook"
        }
    } else {
        Write-Error "PostToolUse hook not found in settings.json"
        Write-Status "Run optimize-claude.ps1 to install hooks"
        return $false
    }

    Write-Host ""
    Write-Success "Hooks are configured!"
    return $true
}

# Verify hook execution
function Verify-HookExecution {
    Write-Header "Verifying Hook Execution"

    # First check if hooks are configured
    if (-not (Check-HooksConfigured)) {
        return
    }

    Write-Host ""
    Write-Host "Verification Methods:" -Bold
    Write-Host ""

    # Method 1: Check for resized image
    Write-Host "Method 1: Check for Resized Image" -ForegroundColor Cyan
    Write-Host "The PreToolUse hook should create resized images in $TempDir"
    Write-Host ""
    Write-Host "Check for resized files:"
    Write-Host "  Get-ChildItem $TempDir\resized_*.png" -ForegroundColor Cyan
    Write-Host ""

    $resizedFiles = Get-ChildItem -Path "$TempDir\resized_*" -ErrorAction SilentlyContinue
    if ($resizedFiles) {
        Write-Success "Found $($resizedFiles.Count) resized file(s) in $TempDir"
        $resizedFiles | Select-Object -First 5 | ForEach-Object {
            Write-Host "  $($_.Name) - $([math]::Round($_.Length / 1KB, 2)) KB"
        }
    } else {
        Write-Warning "No resized files found in $TempDir"
        Write-Host "  The PreToolUse hook may not have fired yet"
    }

    Write-Host ""

    # Method 2: Check temp directory activity
    Write-Host "Method 2: Check Temp Directory" -ForegroundColor Cyan
    Write-Host "Look for files created by Claude Code hooks:"
    Write-Host ""
    Write-Host "Recent files in $TempDir :"
    Get-ChildItem -Path $TempDir | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $($_.LastWriteTime.ToString('HH:mm:ss')) | $($_.Name)"
    }

    Write-Host ""

    # Method 3: Check settings.json content
    Write-Host "Method 3: Hook Configuration Details" -ForegroundColor Cyan
    Write-Host "Current hook configuration:"
    Write-Host ""

    try {
        $config = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        $hooks = $config.hooks

        Write-Host "PreToolUse hooks:"
        foreach ($hook in $hooks.PreToolUse) {
            Write-Host "  Matcher: $($hook.matcher)"
            foreach ($h in $hook.hooks) {
                Write-Host "    Type: $($h.type)"
                Write-Host "    Condition: $($h.if)"
                if ($h.command -match 'resize') {
                    Write-Host "    Action: Image resize ✓" -ForegroundColor Green
                }
            }
        }

        Write-Host ""
        Write-Host "PostToolUse hooks:"
        foreach ($hook in $hooks.PostToolUse) {
            Write-Host "  Matcher: $($hook.matcher)"
            foreach ($h in $hook.hooks) {
                Write-Host "    Type: $($h.type)"
                if ($h.command -match 'cache_keepalive|keepalive') {
                    Write-Host "    Action: Cache keepalive ✓" -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "  (Could not parse settings.json for detailed output)"
    }

    Write-Host ""
    Write-Host "How to Test:" -Bold
    Write-Host ""
    Write-Host "1. Ensure test files exist:"
    Write-Host "   .\monitor-hooks.ps1 -Test" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. In Claude Code, run:"
    Write-Host "   Read $TestFilesDir\test-image.png" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. Immediately check for resized image:"
    Write-Host "   Get-ChildItem $TempDir\resized_*.png" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "4. If the file exists, the PreToolUse hook fired and resized the image!"
    Write-Host ""
    Write-Host "5. Run any command in Claude Code (like 'ls') and watch for"
    Write-Host "   cache_keepalive output - that means PostToolUse fired."
}

# Show test instructions
function Show-TestInstructions {
    Write-Header "Hook Testing Instructions"

    # Create test files if needed
    if (-not (Test-Path $TestFilesDir)) {
        Write-Status "Creating test files first..."
        Create-TestFiles
    }

    # Check if hooks are configured
    Check-HooksConfigured

    Write-Host ""
    Write-Host "To verify hooks are triggered by Claude Code:" -Bold
    Write-Host ""
    Write-Host "1. Ensure hooks are installed:" -Bold
    Write-Host "   Run optimize-claude.ps1 first (if you haven't already)"
    Write-Host ""
    Write-Host "2. Restart Claude Code completely (close and reopen the application)" -Bold
    Write-Host ""
    Write-Host "3. Test PreToolUse hook (image processing):" -Bold
    Write-Host "   In Claude Code, run:"
    Write-Host "   Read $TestFilesDir\test-image.png" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   This should trigger the PreToolUse hook which will:"
    Write-Host "   • Resize the image to max 2000x2000"
    Write-Host "   • Save it to $TempDir\resized_test-image.png"
    Write-Host ""
    Write-Host "4. Verify PreToolUse hook fired:" -Bold
    Write-Host "   In PowerShell, run:"
    Write-Host "   Get-ChildItem $TempDir\resized_*.png" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   If you see resized_test-image.png, the hook worked!"
    Write-Host ""
    Write-Host "5. Test PostToolUse hook (cache keepalive):" -Bold
    Write-Host "   Run any command in Claude Code, such as:"
    Write-Host "   ls" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Look for JSON output with cache_keepalive in Claude's response."
    Write-Host "   This confirms PostToolUse is firing after every tool use."
    Write-Host ""
    Write-Host "6. Check hook configuration:" -Bold
    Write-Host "   .\monitor-hooks.ps1 -Verify"
    Write-Host ""
    Write-Host "Test files available:" -Bold
    Get-ChildItem $TestFilesDir -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.Name)"
    }
}

# Reset - clean up test files
function Reset-TestFiles {
    Write-Header "Cleaning Up Test Files"

    if (Test-Path $TestFilesDir) {
        Remove-Item $TestFilesDir -Recurse -Force
        Write-Success "Removed test files directory"
    } else {
        Write-Warning "No test files to clean up"
    }

    # Also clean up any resized images in temp
    $resizedFiles = Get-ChildItem -Path "$TempDir\resized_*" -ErrorAction SilentlyContinue
    if ($resizedFiles) {
        $resizedFiles | Remove-Item -Force
        Write-Success "Cleaned up resized images in $TempDir"
    }

    Write-Host ""
    Write-Success "Cleanup complete!"
    Write-Host ""
    Write-Host "Note: This only removes test files, not the hooks." -Bold
    Write-Host "The hooks remain active in ~/.claude/settings.json"
}

# Show help
function Show-Help {
    Write-Header "Claude Code Hook Execution Monitor"

    @"
Usage: monitor-hooks.ps1 [COMMAND]

COMMANDS:
    -Test       Create test files and show test instructions
    -Verify     Check if hooks are configured and provide verification steps
    -Reset      Clean up test files

WORKFLOW:
    1. Run optimize-claude.ps1 first (installs hooks)
    2. Restart Claude Code completely
    3. Run: .\monitor-hooks.ps1 -Test (creates test files)
    4. In Claude Code, run: Read .hook-test-files\test-image.png
    5. Check if hooks fired (see verification methods below)
    6. Run: .\monitor-hooks.ps1 -Reset (cleanup)

VERIFICATION METHODS:

Method 1: Check for resized image
  The PreToolUse hook should create: $env:TEMP\resized_test-image.png
  Run: Get-ChildItem $env:TEMP\resized_*.png

Method 2: Check Claude Code output
  The PostToolUse hook outputs JSON. Look for cache_keepalive in Claude's output.

Method 3: Monitor temp files
  Watch $env:TEMP for files created by hooks during operation.

This tool verifies that Claude Code ACTUALLY triggers hooks automatically.
"@
}

# Main execution
if ($Test) {
    Show-TestInstructions
} elseif ($Verify) {
    Verify-HookExecution
} elseif ($Reset) {
    Reset-TestFiles
} else {
    Show-Help
}
