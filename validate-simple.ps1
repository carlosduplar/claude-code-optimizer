# Simple test to verify PowerShell script syntax
$ErrorActionPreference = "Stop"

function Write-Success { param([string]$Message) Write-Host "[PASS] $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[SKIP] $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[FAIL] $Message" -ForegroundColor Red }

Write-Host "Claude Code Optimizer Validation Suite (Windows)" -ForegroundColor Cyan
Write-Host ""

# Test 1: Dependencies
Write-Host "DEPENDENCY INSTALLATION TESTS" -Bold
$markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
$magick = Get-Command magick -ErrorAction SilentlyContinue
$convert = Get-Command convert -ErrorAction SilentlyContinue
$pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue

if ($markitdown) {
    Write-Success "markitdown is installed"
} else {
    Write-Error "markitdown is not installed"
}

if ($magick -or $convert) {
    Write-Success "ImageMagick is installed"
} else {
    Write-Error "ImageMagick is not installed"
}

if ($pdftotext) {
    Write-Success "poppler (pdftotext) is installed"
} else {
    Write-Error "poppler is not installed"
}

# Test 2: Privacy Variables
Write-Host ""
Write-Host "PRIVACY ENVIRONMENT VARIABLES TESTS" -Bold
$vars = @(
    @{ Name = "DISABLE_TELEMETRY"; Expected = "1" },
    @{ Name = "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"; Expected = "1" },
    @{ Name = "OTEL_LOG_USER_PROMPTS"; Expected = "0" },
    @{ Name = "OTEL_LOG_TOOL_DETAILS"; Expected = "0" },
    @{ Name = "CLAUDE_CODE_AUTO_COMPACT_WINDOW"; Expected = "180000" }
)

$privacyScore = 0
foreach ($var in $vars) {
    $actual = [Environment]::GetEnvironmentVariable($var.Name, "Process")
    if ($actual -eq $var.Expected) {
        $privacyScore++
        Write-Success ($var.Name + " is set to " + $var.Expected)
    } else {
        Write-Error ($var.Name + " is not set (expected: " + $var.Expected + ")")
    }
}

Write-Host ""
Write-Host ("Privacy Score: " + $privacyScore + "/5")
if ($privacyScore -eq 5) {
    Write-Success "Maximum privacy mode configured"
} elseif ($privacyScore -ge 3) {
    Write-Warning "Standard privacy mode"
} else {
    Write-Error "Limited privacy protection"
}

# Test 3: Claude Config
Write-Host ""
Write-Host "CLAUDE SETTINGS TESTS" -Bold
$claudeConfig = Join-Path $env:USERPROFILE ".claude\.claude.json"
if (Test-Path $claudeConfig) {
    Write-Success "Claude config file exists"
    $config = Get-Content $claudeConfig -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($config.autoCompactEnabled -eq $true) {
        Write-Success "autoCompactEnabled is enabled"
    } else {
        Write-Error "autoCompactEnabled is not enabled"
    }
} else {
    Write-Error "Claude config file not found"
}

# Test 4: Hooks
Write-Host ""
Write-Host "HOOKS CONFIGURATION TESTS" -Bold
$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $settingsFile) {
    Write-Success "User settings.json exists at ~/.claude/settings.json"
    $content = Get-Content $settingsFile -Raw
    if ($content -match '"PreToolUse"') {
        Write-Success "PreToolUse hook is configured"
    } else {
        Write-Warning "PreToolUse hook not found"
    }
    if ($content -match '"PostToolUse"') {
        Write-Success "PostToolUse hook is configured"
    } else {
        Write-Warning "PostToolUse hook not found"
    }
} else {
    Write-Error "User settings.json not found at ~/.claude/settings.json"
}

# Summary
Write-Host ""
Write-Host "VALIDATION SUMMARY" -ForegroundColor Cyan -Bold
$totalTests = 12
$passedTests = $script:TestsPassed
Write-Host ("Tests Passed: " + $privacyScore + "/5 privacy variables")
Write-Host ("Dependencies: " + $(if ($markitdown -and ($magick -or $convert) -and $pdftotext) { "OK" } else { "Missing" }))
Write-Host ("Auto-compact: " + $(if ($config.autoCompactEnabled -eq $true) { "Enabled" } else { "Disabled" }))
Write-Host ("Hooks: " + $(if ($content -match '"PreToolUse"' -and $content -match '"PostToolUse"') { "Configured" } else { "Not configured" }))
