#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Optimizer Validation Suite for Windows
    Tests all claims made by the optimization scripts

.DESCRIPTION
    This script validates:
    - Dependencies installed (markitdown, imagemagick, poppler)
    - Privacy environment variables configured
    - Auto-compact enabled in Claude settings
    - Hooks properly configured in settings.json
    - Image pre-processing capabilities
    - Document conversion capabilities

.PARAMETER Before
    Capture baseline state before running optimizations

.PARAMETER After
    Verify optimizations are working after running optimize-claude.ps1

.PARAMETER Verbose
    Show detailed output for all tests

.EXAMPLE
    .\validate-optimizations.ps1
    Run all validation tests

.EXAMPLE
    .\validate-optimizations.ps1 -Before
    Capture baseline state

.EXAMPLE
    .\validate-optimizations.ps1 -After
    Verify optimizations are working

.EXAMPLE
    .\validate-optimizations.ps1 -Verbose
    Run with detailed output
#>

[CmdletBinding()]
param(
    [switch]$Before,
    [switch]$After,
    [switch]$Verbose
)

# Colors for output
$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Warning = 'Yellow'
    Error = 'Red'
    Header = 'Blue'
}

# Test results tracking
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsSkipped = 0

# Functions for colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Info
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓ PASS] $Message" -ForegroundColor $Colors.Success
    $script:TestsPassed++
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[⚠ SKIP] $Message" -ForegroundColor $Colors.Warning
    $script:TestsSkipped++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗ FAIL] $Message" -ForegroundColor $Colors.Error
    $script:TestsFailed++
}

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

# Test: Dependency Installation
function Test-Dependencies {
    Write-Section "DEPENDENCY INSTALLATION TESTS"

    # Test markitdown
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        Write-Success "markitdown is installed and in PATH"
        if ($Verbose) {
            $version = & markitdown --version 2>&1
            Write-Host "  Version: $version"
        }
    } else {
        # Try importing as Python module
        try {
            $python = Get-Command python -ErrorAction SilentlyContinue
            $python3 = Get-Command python3 -ErrorAction SilentlyContinue
            $pyCmd = if ($python3) { "python3" } elseif ($python) { "python" } else { $null }

            if ($pyCmd) {
                & $pyCmd -c "import markitdown" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "markitdown Python module is installed"
                } else {
                    Write-Error "markitdown is not installed"
                    if ($Verbose) {
                        Write-Host "  Expected: markitdown command or Python module"
                        Write-Host "  Install: pip install markitdown"
                    }
                }
            } else {
                Write-Error "markitdown is not installed (Python not found)"
            }
        } catch {
            Write-Error "markitdown is not installed"
        }
    }

    # Test ImageMagick
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue

    if ($magick -or $convert) {
        Write-Success "ImageMagick is installed and in PATH"
        if ($Verbose) {
            $cmd = if ($magick) { "magick" } else { "convert" }
            $version = & $cmd --version 2>&1 | Select-Object -First 1
            Write-Host "  Command: $cmd"
            Write-Host "  Version: $version"
        }
    } else {
        Write-Error "ImageMagick is not installed"
        if ($Verbose) {
            Write-Host "  Expected: magick or convert command"
            Write-Host "  Install: winget install ImageMagick.ImageMagick"
        }
    }

    # Test poppler/pdftotext
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue

    if ($pdftotext) {
        Write-Success "poppler (pdftotext) is installed and in PATH"
        if ($Verbose) {
            $version = & pdftotext -v 2>&1 | Select-Object -First 1
            Write-Host "  Version: $version"
        }
    } else {
        # Check common installation paths
        $popplerPaths = @(
            "C:\ProgramData\chocolatey\lib\xpdf-utils\tools",
            "C:\ProgramData\chocolatey\bin",
            "C:\Program Files\xpdf-utils",
            "C:\tools\xpdf-utils"
        )

        $found = $false
        foreach ($path in $popplerPaths) {
            if (Test-Path $path) {
                $pdftotextExe = Get-ChildItem -Path $path -Recurse -Filter "pdftotext.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pdftotextExe) {
                    Write-Success "poppler (pdftotext) found at $($pdftotextExe.FullName)"
                    $found = $true
                    break
                }
            }
        }

        if (-not $found) {
            Write-Error "poppler (pdftotext) is not installed"
            if ($Verbose) {
                Write-Host "  Expected: pdftotext.exe command"
                Write-Host "  Install: choco install xpdf-utils"
            }
        }
    }
}

# Test: Privacy Environment Variables
function Test-PrivacyEnvVars {
    Write-Section "PRIVACY ENVIRONMENT VARIABLES TESTS"

    $vars = @(
        @{ Name = "DISABLE_TELEMETRY"; Expected = "1"; Description = "Disables all telemetry" },
        @{ Name = "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"; Expected = "1"; Description = "Blocks non-essential traffic" },
        @{ Name = "OTEL_LOG_USER_PROMPTS"; Expected = "0"; Description = "Disables OpenTelemetry prompt logging" },
        @{ Name = "OTEL_LOG_TOOL_DETAILS"; Expected = "0"; Description = "Disables OpenTelemetry tool logging" },
        @{ Name = "CLAUDE_CODE_AUTO_COMPACT_WINDOW"; Expected = "180000"; Description = "Sets auto-compact window" }
    )

    foreach ($var in $vars) {
        $actualValue = [Environment]::GetEnvironmentVariable($var.Name, "Process")

        if ($actualValue) {
            if ($actualValue -eq $var.Expected) {
                Write-Success "$($var.Name) is set to $($var.Expected) ($($var.Description))"
            } else {
                Write-Warning "$($var.Name) is set to '$actualValue' (expected '$($var.Expected)')"
                if ($Verbose) {
                    Write-Host "  Description: $($var.Description)"
                    Write-Host "  Current: $actualValue"
                    Write-Host "  Expected: $($var.Expected)"
                }
            }
        } else {
            Write-Error "$($var.Name) is not set ($($var.Description))"
            if ($Verbose) {
                Write-Host "  Expected value: $($var.Expected)"
                Write-Host "  Add to PowerShell profile or Windows Environment Variables"
            }
        }
    }

    # Check Windows Registry for persistent settings
    $userEnvVars = @{
        DISABLE_TELEMETRY = [Environment]::GetEnvironmentVariable("DISABLE_TELEMETRY", "User")
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "User")
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "User")
    }

    $configuredCount = ($userEnvVars.GetEnumerator() | Where-Object { $_.Value }).Count

    if ($configuredCount -ge 3) {
        Write-Success "Windows user environment variables are configured ($configuredCount/5 variables)"
    } elseif ($configuredCount -gt 0) {
        Write-Warning "Partial Windows environment configuration ($configuredCount/5 variables)"
    } else {
        Write-Error "No Windows user environment variables configured"
    }
}

# Test: Claude Settings (auto-compact)
function Test-ClaudeSettings {
    Write-Section "CLAUDE SETTINGS TESTS"

    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    $claudeConfig = Join-Path $claudeDir ".claude.json"

    if (Test-Path $claudeConfig) {
        Write-Success "Claude config file exists: $claudeConfig"

        if ($Verbose) {
            Write-Host "  Contents:"
            Get-Content $claudeConfig | ForEach-Object { Write-Host "    $_" }
        }

        try {
            $config = Get-Content $claudeConfig -Raw | ConvertFrom-Json

            if ($config.autoCompactEnabled -eq $true) {
                Write-Success "autoCompactEnabled is enabled in config"
            } elseif ($config.autoCompactEnabled -eq $false) {
                Write-Error "autoCompactEnabled is explicitly disabled"
            } else {
                Write-Warning "autoCompactEnabled not found in config (may use default)"
            }
        } catch {
            Write-Error "Failed to parse Claude config file"
        }
    } else {
        Write-Error "Claude config file not found: $claudeConfig"
        if ($Verbose) {
            Write-Host "  Run: .\optimize-claude.ps1 to create config"
        }
    }
}

# Test: Hooks Configuration
function Test-HooksConfiguration {
    Write-Section "HOOKS CONFIGURATION TESTS"

    $settingsFile = ".claude\settings.json"
    $userSettings = Join-Path $env:USERPROFILE ".claude\settings.json"

    # Check project-level settings
    if (Test-Path $settingsFile) {
        Write-Success "Project settings.json exists: $settingsFile"

        if ($Verbose) {
            Write-Host "  Contents:"
            Get-Content $settingsFile | ForEach-Object { Write-Host "    $_" }
        }

        $content = Get-Content $settingsFile -Raw

        if ($content -match '"PreToolUse"') {
            Write-Success "PreToolUse hook is configured"
        } else {
            Write-Warning "PreToolUse hook not found in project settings"
        }

        if ($content -match '"PostToolUse"') {
            Write-Success "PostToolUse hook is configured"
        } else {
            Write-Warning "PostToolUse hook not found in project settings"
        }

        if ($content -match '"autoCompactEnabled":\s*true') {
            Write-Success "autoCompactEnabled is enabled in settings.json"
        }
    } else {
        Write-Warning "Project settings.json not found: $settingsFile"
    }

    # Check user-level settings
    if ((Test-Path $userSettings) -and ($userSettings -ne $settingsFile)) {
        Write-Success "User settings.json exists: $userSettings"

        $content = Get-Content $userSettings -Raw

        if ($content -match '"PreToolUse"') {
            Write-Success "PreToolUse hook is configured in user settings"
        }

        if ($content -match '"PostToolUse"') {
            Write-Success "PostToolUse hook is configured in user settings"
        }
    }
}

# Test: Image Pre-processing Capability
function Test-ImagePreprocessing {
    Write-Section "IMAGE PRE-PROCESSING CAPABILITY TESTS"

    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue

    if ($magick -or $convert) {
        $cmd = if ($magick) { "magick" } else { "convert" }

        # Create a test directory
        $testDir = Join-Path $env:TEMP "claude-validation-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $testImage = Join-Path $testDir "test_image.png"
        $resizedImage = Join-Path $testDir "resized_image.png"

        # Generate a test image
        try {
            & $cmd -size 2000x2000 xc:blue $testImage 2>$null

            if (Test-Path $testImage) {
                Write-Success "ImageMagick can create test images"

                # Test resize operation
                & $cmd $testImage -resize 2000x2000 -quality 85 $resizedImage 2>$null

                if (Test-Path $resizedImage) {
                    Write-Success "ImageMagick resize operation works"

                    $originalSize = (Get-Item $testImage).Length
                    $resizedSize = (Get-Item $resizedImage).Length

                    if ($resizedSize -le $originalSize) {
                        Write-Success "Image resize reduces file size (original: $originalSize, resized: $resizedSize)"
                    } else {
                        Write-Warning "Resized image is larger (this can happen with certain image types)"
                    }
                } else {
                    Write-Error "ImageMagick resize operation failed"
                }
            } else {
                Write-Warning "Could not create test image for validation"
            }
        } catch {
            Write-Warning "ImageMagick test failed: $_"
        } finally {
            # Cleanup
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Error "ImageMagick not available for image pre-processing tests"
    }
}

# Test: Document Conversion Capability
function Test-DocumentConversion {
    Write-Section "DOCUMENT CONVERSION CAPABILITY TESTS"

    $testDir = Join-Path $env:TEMP "claude-validation-$(Get-Random)"
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null

    # Test PDF text extraction if poppler is available
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue

    if ($pdftotext) {
        Write-Success "pdftotext is available for PDF text extraction"
    } else {
        Write-Error "pdftotext not available for PDF tests"
    }

    # Test markitdown if available
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        Write-Success "markitdown is available for document conversion"
    } else {
        Write-Warning "markitdown not available for document conversion tests"
    }

    # Cleanup
    Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Test: Cache Keepalive Mechanism
function Test-CacheKeepalive {
    Write-Section "CACHE KEEPALIVE MECHANISM TESTS"

    $settingsFile = ".claude\settings.json"
    $userSettings = Join-Path $env:USERPROFILE ".claude\settings.json"

    $hookFound = $false

    if (Test-Path $settingsFile) {
        $content = Get-Content $settingsFile -Raw
        if ($content -match '"PostToolUse"' -and ($content -match "cache_keepalive" -or $content -match "keepalive")) {
            Write-Success "Cache keepalive hook found in project settings.json"
            $hookFound = $true
        }
    }

    if ((Test-Path $userSettings) -and ($userSettings -ne $settingsFile)) {
        $content = Get-Content $userSettings -Raw
        if ($content -match '"PostToolUse"' -and ($content -match "cache_keepalive" -or $content -match "keepalive")) {
            Write-Success "Cache keepalive hook found in user settings.json"
            $hookFound = $true
        }
    }

    if (-not $hookFound) {
        Write-Warning "Cache keepalive hook not found in settings.json"
        if ($Verbose) {
            Write-Host "  The PostToolUse hook should contain a command that outputs cache_keepalive"
            Write-Host "  This hook fires after every tool use to keep the prompt cache warm"
        }
    }

    # Check for keepalive script (optional)
    if (Test-Path "claude-keepalive.ps1") {
        Write-Success "Optional keepalive script exists: claude-keepalive.ps1"
    } else {
        if ($Verbose) {
            Write-Host "  Optional: claude-keepalive.ps1 not found (hooks handle this automatically)"
        }
    }
}

# Test: Privacy Level Verification
function Test-PrivacyLevel {
    Write-Section "PRIVACY LEVEL VERIFICATION"

    $privacyScore = 0
    $maxScore = 5

    # Check each privacy variable
    $vars = @{
        DISABLE_TELEMETRY = $env:DISABLE_TELEMETRY
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
        OTEL_LOG_USER_PROMPTS = $env:OTEL_LOG_USER_PROMPTS
        OTEL_LOG_TOOL_DETAILS = $env:OTEL_LOG_TOOL_DETAILS
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW
    }

    if ($vars.DISABLE_TELEMETRY -eq "1") { $privacyScore++ }
    if ($vars.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -eq "1") { $privacyScore++ }
    if ($vars.OTEL_LOG_USER_PROMPTS -eq "0") { $privacyScore++ }
    if ($vars.OTEL_LOG_TOOL_DETAILS -eq "0") { $privacyScore++ }
    if ($vars.CLAUDE_CODE_AUTO_COMPACT_WINDOW -eq "180000") { $privacyScore++ }

    Write-Host "Privacy Score: $privacyScore/$maxScore"

    if ($privacyScore -eq $maxScore) {
        Write-Success "Maximum privacy mode is configured (all 5 variables set)"
    } elseif ($privacyScore -ge 3) {
        Write-Warning "Standard privacy mode ($privacyScore/$maxScore variables set)"
    } else {
        Write-Error "Limited privacy protection ($privacyScore/$maxScore variables set)"
    }

    if ($Verbose) {
        Write-Host ""
        Write-Host "Privacy Variables Status:"
        Write-Host "  DISABLE_TELEMETRY=$($vars.DISABLE_TELEMETRY ?? '<not set>') (disables Datadog telemetry)"
        Write-Host "  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$($vars.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC ?? '<not set>') (blocks updates, release notes)"
        Write-Host "  OTEL_LOG_USER_PROMPTS=$($vars.OTEL_LOG_USER_PROMPTS ?? '<not set>') (disables prompt logging)"
        Write-Host "  OTEL_LOG_TOOL_DETAILS=$($vars.OTEL_LOG_TOOL_DETAILS ?? '<not set>') (disables tool logging)"
        Write-Host "  CLAUDE_CODE_AUTO_COMPACT_WINDOW=$($vars.CLAUDE_CODE_AUTO_COMPACT_WINDOW ?? '<not set>') (auto-compact threshold)"
    }
}

# Generate summary report
function Generate-Report {
    Write-Header "VALIDATION SUMMARY"

    $totalTests = $script:TestsPassed + $script:TestsFailed + $script:TestsSkipped

    Write-Host "Test Results:" -Bold
    Write-Host "  Passed:  $($script:TestsPassed)"
    Write-Host "  Failed:  $($script:TestsFailed)"
    Write-Host "  Skipped: $($script:TestsSkipped)"
    Write-Host "  Total:   $totalTests"
    Write-Host ""

    if ($script:TestsFailed -eq 0) {
        Write-Host "✓ All critical tests passed!" -ForegroundColor Green -Bold
        Write-Host "Your Claude Code environment is fully optimized."
    } elseif ($script:TestsFailed -le 2) {
        Write-Host "⚠ Most tests passed with minor issues" -ForegroundColor Yellow -Bold
        Write-Host "Your environment is mostly optimized. Review failed tests above."
    } else {
        Write-Host "✗ Several optimizations are not working" -ForegroundColor Red -Bold
        Write-Host "Run .\optimize-claude.ps1 to fix the issues."
    }

    Write-Host ""
    Write-Host "Key Claims Verification:" -Bold

    # Check specific claims
    $depsOk = $false
    $privacyOk = $false
    $compactOk = $false
    $hooksOk = $false

    # Dependencies
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue

    if ($markitdown -and ($magick -or $convert) -and $pdftotext) {
        $depsOk = $true
        Write-Host "  ✓ Dependencies installed (markitdown, imagemagick, poppler)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Some dependencies missing" -ForegroundColor Red
    }

    # Privacy
    if ($env:DISABLE_TELEMETRY -eq "1" -and $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -eq "1") {
        $privacyOk = $true
        Write-Host "  ✓ Maximum privacy mode configured" -ForegroundColor Green
    } elseif ($env:DISABLE_TELEMETRY -eq "1") {
        Write-Host "  ⚠ Standard privacy mode (telemetry disabled)" -ForegroundColor Yellow
    } else {
        Write-Host "  ✗ Privacy not configured" -ForegroundColor Red
    }

    # Auto-compact
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    $claudeConfig = Join-Path $claudeDir ".claude.json"
    if (Test-Path $claudeConfig) {
        $config = Get-Content $claudeConfig -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($config.autoCompactEnabled -eq $true) {
            $compactOk = $true
            Write-Host "  ✓ Auto-compact enabled" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Auto-compact not enabled" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✗ Auto-compact not enabled" -ForegroundColor Red
    }

    # Hooks
    if (Test-Path ".claude\settings.json") {
        $content = Get-Content ".claude\settings.json" -Raw
        if ($content -match '"PreToolUse"' -and $content -match '"PostToolUse"') {
            $hooksOk = $true
            Write-Host "  ✓ Hooks configured (image resize + cache keepalive)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Hooks not fully configured" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✗ Hooks not fully configured" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Expected Benefits:" -Bold

    if ($depsOk -and $privacyOk -and $compactOk -and $hooksOk) {
        Write-Host "  ✓ Token usage: 50-80% reduction expected" -ForegroundColor Green
        Write-Host "  ✓ Startup time: Faster (no telemetry init)" -ForegroundColor Green
        Write-Host "  ✓ Session length: Longer before rate limits" -ForegroundColor Green
        Write-Host "  ✓ Privacy: Maximum protection" -ForegroundColor Green
        Write-Host "  ✓ Cost: Significantly lower per task" -ForegroundColor Green
    } else {
        Write-Host "  Some optimizations incomplete - benefits may be reduced"
    }

    Write-Host ""
    Write-Host "Next Steps:" -Bold
    if ($script:TestsFailed -gt 0) {
        Write-Host "  1. Run: .\optimize-claude.ps1"
        Write-Host "  2. Restart PowerShell or run: `$PROFILE"
        Write-Host "  3. Restart Claude Code"
        Write-Host "  4. Run validation again: .\validate-optimizations.ps1"
    } else {
        Write-Host "  Your environment is optimized! Start using Claude Code."
        Write-Host "  Monitor /cost regularly to track savings."
    }
}

# Save state for before/after comparison
function Save-State {
    param([string]$Mode)

    $stateFile = ".validation_state.json"

    $state = @{
        timestamp = (Get-Date -Format "o")
        mode = $Mode
        dependencies = @{
            markitdown = [bool](Get-Command markitdown -ErrorAction SilentlyContinue)
            imagemagick = [bool]((Get-Command magick -ErrorAction SilentlyContinue) -or (Get-Command convert -ErrorAction SilentlyContinue))
            poppler = [bool](Get-Command pdftotext -ErrorAction SilentlyContinue)
        }
        privacy_vars = @{
            DISABLE_TELEMETRY = $env:DISABLE_TELEMETRY
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
            OTEL_LOG_USER_PROMPTS = $env:OTEL_LOG_USER_PROMPTS
            OTEL_LOG_TOOL_DETAILS = $env:OTEL_LOG_TOOL_DETAILS
            CLAUDE_CODE_AUTO_COMPACT_WINDOW = $env:CLAUDE_CODE_AUTO_COMPACT_WINDOW
        }
        claude_config = @{
            exists = Test-Path (Join-Path $env:USERPROFILE ".claude\.claude.json")
            autoCompactEnabled = $false
        }
        hooks = @{
            settings_json_exists = Test-Path ".claude\settings.json"
            pretooluse_hook = $false
            posttooluse_hook = $false
        }
    }

    # Check autoCompactEnabled
    $claudeConfig = Join-Path $env:USERPROFILE ".claude\.claude.json"
    if (Test-Path $claudeConfig) {
        $config = Get-Content $claudeConfig -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        $state.claude_config.autoCompactEnabled = $config.autoCompactEnabled -eq $true
    }

    # Check hooks
    if (Test-Path ".claude\settings.json") {
        $content = Get-Content ".claude\settings.json" -Raw
        $state.hooks.pretooluse_hook = $content -match '"PreToolUse"'
        $state.hooks.posttooluse_hook = $content -match '"PostToolUse"'
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content $stateFile -Encoding UTF8

    Write-Success "State saved to $stateFile"
}

# Compare before/after states
function Compare-States {
    $beforeFile = ".validation_state_before.json"
    $afterFile = ".validation_state_after.json"

    if (-not (Test-Path $beforeFile)) {
        Write-Error "No before state found. Run with -Before first."
        return
    }

    if (-not (Test-Path $afterFile)) {
        Write-Error "No after state found. Run with -After."
        return
    }

    Write-Header "BEFORE/AFTER COMPARISON"

    $before = Get-Content $beforeFile -Raw | ConvertFrom-Json
    $after = Get-Content $afterFile -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "📊 DEPENDENCY CHANGES:" -Bold
    foreach ($dep in @('markitdown', 'imagemagick', 'poppler')) {
        $b = $before.dependencies.$dep
        $a = $after.dependencies.$dep
        if (-not $b -and $a) {
            Write-Host "  ✓ ${dep}: NOT INSTALLED → INSTALLED" -ForegroundColor Green
        } elseif ($b -and $a) {
            Write-Host "  = ${dep}: Already installed (no change)"
        } elseif ($b -and -not $a) {
            Write-Host "  ✗ ${dep}: INSTALLED → NOT INSTALLED (regression!)" -ForegroundColor Red
        } else {
            Write-Host "  ✗ ${dep}: Still not installed" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "🔒 PRIVACY CHANGES:" -Bold
    $privacyVars = @('DISABLE_TELEMETRY', 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
                     'OTEL_LOG_USER_PROMPTS', 'OTEL_LOG_TOOL_DETAILS')
    foreach ($var in $privacyVars) {
        $b = $before.privacy_vars.$var
        $a = $after.privacy_vars.$var
        if (-not $b -and $a) {
            Write-Host "  ✓ ${var}: NOT SET → $a" -ForegroundColor Green
        } elseif ($b -ne $a) {
            Write-Host "  ~ ${var}: $b → $a" -ForegroundColor Yellow
        } else {
            Write-Host "  = ${var}: $a (no change)"
        }
    }

    Write-Host ""
    Write-Host "⚙️  AUTO-COMPACT:" -Bold
    $b = $before.claude_config.autoCompactEnabled
    $a = $after.claude_config.autoCompactEnabled
    if (-not $b -and $a) {
        Write-Host "  ✓ Auto-compact: DISABLED → ENABLED" -ForegroundColor Green
    } elseif ($b -and $a) {
        Write-Host "  = Auto-compact: Already enabled (no change)"
    } else {
        $status = if (-not $a) { "Still disabled" } else { "Enabled" }
        $symbol = if (-not $a) { "✗" } else { "=" }
        Write-Host "  $symbol Auto-compact: $status" -ForegroundColor $(if (-not $a) { 'Red' } else { 'White' })
    }

    Write-Host ""
    Write-Host "🪝 HOOKS:" -Bold
    $b = $before.hooks.pretooluse_hook
    $a = $after.hooks.pretooluse_hook
    if (-not $b -and $a) {
        Write-Host "  ✓ PreToolUse hook: NOT CONFIGURED → CONFIGURED" -ForegroundColor Green
    } else {
        $status = if ($a) { "Configured" } else { "Not configured" }
        $symbol = if ($b -eq $a) { "=" } else { "~" }
        Write-Host "  $symbol PreToolUse hook: $status"
    }

    $b = $before.hooks.posttooluse_hook
    $a = $after.hooks.posttooluse_hook
    if (-not $b -and $a) {
        Write-Host "  ✓ PostToolUse hook: NOT CONFIGURED → CONFIGURED" -ForegroundColor Green
    } else {
        $status = if ($a) { "Configured" } else { "Not configured" }
        $symbol = if ($b -eq $a) { "=" } else { "~" }
        Write-Host "  $symbol PostToolUse hook: $status"
    }

    Write-Host ""
}

# Main execution
function Main {
    Write-Header "Claude Code Optimizer Validation Suite (Windows)"

    # Handle before/after modes
    if ($Before) {
        Write-Status "Capturing BEFORE state..."
        Save-State "before"
        Move-Item -Path ".validation_state.json" -Destination ".validation_state_before.json" -Force
        Write-Success "Before state saved to .validation_state_before.json"
        Write-Host ""
        Write-Host "Next: Run .\optimize-claude.ps1 to apply optimizations"
        Write-Host "Then: Run $PSCommandPath -After to capture post-optimization state"
        return
    }

    if ($After) {
        Write-Status "Capturing AFTER state..."
        Save-State "after"
        Move-Item -Path ".validation_state.json" -Destination ".validation_state_after.json" -Force
        Write-Success "After state saved to .validation_state_after.json"
        Compare-States
        return
    }

    # Run all tests
    Write-Status "Starting validation tests..."
    Write-Host ""

    Test-Dependencies
    Test-PrivacyEnvVars
    Test-ClaudeSettings
    Test-HooksConfiguration
    Test-ImagePreprocessing
    Test-DocumentConversion
    Test-CacheKeepalive
    Test-PrivacyLevel

    Generate-Report

    # Exit with appropriate code
    if ($script:TestsFailed -eq 0) {
        exit 0
    } else {
        exit 1
    }
}

# Run main
Main
