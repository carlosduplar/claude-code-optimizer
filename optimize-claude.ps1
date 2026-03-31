#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Claude Code Token Optimizer & Privacy Enhancer for Windows

.DESCRIPTION
    This PowerShell script:
    1. Installs missing dependencies (markitdown, poppler, imagemagick) via winget/chocolatey
    2. Configures MAXIMUM privacy environment variables by default
    3. Enables auto-compact in Claude settings
    4. Creates optimization guidance and helper scripts

.PARAMETER ReducedPrivacy
    Use reduced privacy (telemetry disabled only, keeps auto-updates)

.PARAMETER DryRun
    Show what would be done without making changes

.PARAMETER SkipDeps
    Skip dependency installation

.EXAMPLE
    .\optimize-claude.ps1
    Full privacy mode (default) with dependency installation

.EXAMPLE
    .\optimize-claude.ps1 -ReducedPrivacy
    Reduced privacy mode (standard telemetry disabled only)

.EXAMPLE
    .\optimize-claude.ps1 -DryRun
    Preview changes without applying them
#>

[CmdletBinding()]
param(
    [switch]$ReducedPrivacy,
    [switch]$DryRun,
    [switch]$SkipDeps
)

# Colors for output
$Colors = @{
    Info = 'Cyan'
    Success = 'Green'
    Warning = 'Yellow'
    Error = 'Red'
    Header = 'Blue'
}

# Dependency tracking
$script:MissingDeps = @()
$script:InstallFailed = @()

# Functions for colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Info
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor $Colors.Success
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[⚠] $Message" -ForegroundColor $Colors.Warning
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor $Colors.Error
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Header
    Write-Host " $Message" -ForegroundColor $Colors.Header -Bold
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Header
    Write-Host ""
}

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check for Python
tunction Test-Python {
    Write-Status "Checking Python installation..."

    $python = Get-Command python -ErrorAction SilentlyContinue
    $python3 = Get-Command python3 -ErrorAction SilentlyContinue

    if ($python3) {
        $script:PythonCmd = "python3"
        $version = & python3 --version 2>&1
        Write-Success "Python found: $version"
        return $true
    } elseif ($python) {
        $script:PythonCmd = "python"
        $version = & python --version 2>&1
        Write-Success "Python found: $version"
        return $true
    } else {
        Write-Error "Python is not installed. Please install Python 3 from python.org"
        return $false
    }
}

# Check for pip
tunction Test-Pip {
    $pip = Get-Command pip -ErrorAction SilentlyContinue
    $pip3 = Get-Command pip3 -ErrorAction SilentlyContinue

    if ($pip3 -or $pip) {
        return $true
    } else {
        Write-Warning "pip not found. You may need to install pip."
        return $false
    }
}

# Check for markitdown
tunction Test-Markitdown {
    Write-Status "Checking markitdown..."

    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        Write-Success "markitdown is already installed"
        return $true
    }

    # Try importing as Python module
    try {
        & $script:PythonCmd -c "import markitdown" 2>$null
        Write-Success "markitdown is already installed"
        return $true
    } catch {
        Write-Warning "markitdown is not installed"
        $script:MissingDeps += "markitdown"
        return $false
    }
}

# Check for ImageMagick
tunction Test-ImageMagick {
    Write-Status "Checking ImageMagick..."

    $magick = Get-Command magick -ErrorAction SilentlyContinue
    $convert = Get-Command convert -ErrorAction SilentlyContinue

    if ($magick -or $convert) {
        Write-Success "ImageMagick is already installed"
        return $true
    } else {
        Write-Warning "ImageMagick is not installed"
        $script:MissingDeps += "imagemagick"
        return $false
    }
}

# Check for poppler
tunction Test-Poppler {
    Write-Status "Checking poppler (pdftotext)..."

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue

    if ($pdftotext) {
        Write-Success "poppler (pdftotext) is already installed"
        return $true
    } else {
        Write-Warning "poppler (pdftotext) is not installed"
        $script:MissingDeps += "poppler"
        return $false
    }
}

# Install markitdown
tunction Install-Markitdown {
    Write-Status "Installing markitdown..."

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: pip install markitdown"
        return $true
    }

    try {
        & pip install markitdown 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "markitdown installed successfully"
            return $true
        }
    } catch {
        # Try pip3
        try {
            & pip3 install markitdown 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "markitdown installed successfully"
                return $true
            }
        } catch {
            Write-Error "Failed to install markitdown"
            $script:InstallFailed += "markitdown"
            return $false
        }
    }

    Write-Error "Failed to install markitdown"
    $script:InstallFailed += "markitdown"
    return $false
}

# Install ImageMagick via winget
tunction Install-ImageMagick {
    Write-Status "Installing ImageMagick via winget..."

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: winget install ImageMagick.ImageMagick"
        return $true
    }

    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Warning "winget not found. Trying Chocolatey..."
            return Install-ImageMagick-Choco
        }

        winget install ImageMagick.ImageMagick --silent --accept-package-agreements --accept-source-agreements

        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        # Verify installation
        $magick = Get-Command magick -ErrorAction SilentlyContinue
        if ($magick) {
            Write-Success "ImageMagick installed successfully"
            return $true
        } else {
            Write-Warning "ImageMagick installation may require a restart. Trying Chocolatey..."
            return Install-ImageMagick-Choco
        }
    } catch {
        Write-Warning "winget installation failed. Trying Chocolatey..."
        return Install-ImageMagick-Choco
    }
}

# Install ImageMagick via Chocolatey
tunction Install-ImageMagick-Choco {
    $choco = Get-Command choco -ErrorAction SilentlyContinue

    if (-not $choco) {
        Write-Error "Neither winget nor Chocolatey found. Please install ImageMagick manually from https://imagemagick.org"
        $script:InstallFailed += "imagemagick"
        return $false
    }

    Write-Status "Installing ImageMagick via Chocolatey..."

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: choco install imagemagick -y"
        return $true
    }

    try {
        choco install imagemagick -y

        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        $magick = Get-Command magick -ErrorAction SilentlyContinue
        if ($magick) {
            Write-Success "ImageMagick installed successfully"
            return $true
        } else {
            Write-Error "ImageMagick installation may have failed or requires restart"
            $script:InstallFailed += "imagemagick"
            return $false
        }
    } catch {
        Write-Error "Failed to install ImageMagick: $_"
        $script:InstallFailed += "imagemagick"
        return $false
    }
}

# Install poppler via Chocolatey
tunction Install-Poppler {
    Write-Status "Installing poppler via Chocolatey..."

    $choco = Get-Command choco -ErrorAction SilentlyContinue

    if (-not $choco) {
        Write-Error "Chocolatey not found. Please install poppler manually."
        Write-Host "Download from: https://github.com/oschwartz10612/poppler-windows/releases/"
        $script:InstallFailed += "poppler"
        return $false
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would run: choco install poppler -y"
        return $true
    }

    try {
        choco install poppler -y

        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
        if ($pdftotext) {
            Write-Success "poppler installed successfully"
            return $true
        } else {
            Write-Error "poppler installation may have failed or requires restart"
            $script:InstallFailed += "poppler"
            return $false
        }
    } catch {
        Write-Error "Failed to install poppler: $_"
        $script:InstallFailed += "poppler"
        return $false
    }
}

# Check and install all dependencies
tunction Install-Dependencies {
    if ($SkipDeps) {
        Write-Status "Skipping dependency check (-SkipDeps specified)"
        return
    }

    Write-Header "Checking Dependencies"

    # Check Python first (required for markitdown)
    $pythonOK = Test-Python
    if (-not $pythonOK) {
        Write-Error "Python is required. Please install it first."
        return
    }

    Test-Pip
    Test-Markitdown
    Test-ImageMagick
    Test-Poppler

    if ($script:MissingDeps.Count -eq 0) {
        Write-Success "All dependencies are already installed!"
        return
    }

    Write-Warning "Missing dependencies: $($script:MissingDeps -join ', ')"

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would attempt to install: $($script:MissingDeps -join ', ')"
        return
    }

    $confirm = Read-Host "Install missing dependencies? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Warning "Skipping dependency installation"
        return
    }

    # Install each missing dependency
    foreach ($dep in $script:MissingDeps) {
        switch ($dep) {
            "markitdown" { Install-Markitdown }
            "imagemagick" { Install-ImageMagick }
            "poppler" { Install-Poppler }
        }
    }

    # Report results
    Write-Host ""
    if ($script:InstallFailed.Count -eq 0) {
        Write-Success "All dependencies installed successfully!"
    } else {
        Write-Error "Failed to install: $($script:InstallFailed -join ', ')"
        Write-Warning "You can still use Claude Code, but some optimizations won't work"
    }
}

# Configure privacy environment variables
tunction Set-PrivacyConfiguration {
    Write-Header "Configuring Privacy Settings"

    # Determine target profile script
    $profilePaths = @(
        $PROFILE.CurrentUserAllHosts,
        $PROFILE.CurrentUserCurrentHost,
        [Environment]::GetFolderPath("MyDocuments") + "\PowerShell\Microsoft.PowerShell_profile.ps1",
        [Environment]::GetFolderPath("MyDocuments") + "\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    )

    $targetProfile = $null
    foreach ($path in $profilePaths) {
        if ($path -and (Test-Path (Split-Path $path -Parent))) {
            $targetProfile = $path
            break
        }
    }

    if (-not $targetProfile) {
        $targetProfile = $PROFILE.CurrentUserAllHosts
        $profileDir = Split-Path $targetProfile -Parent
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
    }

    Write-Status "PowerShell profile: $targetProfile"

    # Build environment variable block
    $envBlock = @"
# Claude Code Token Optimization & Privacy Settings
"@

    if ($ReducedPrivacy) {
        $envBlock += @"

# Standard Privacy Mode
`$env:DISABLE_TELEMETRY = "1"
"@
        Write-Status "Configuring standard privacy mode (reduced)"
    } else {
        $envBlock += @"

# Maximum Privacy Mode (DEFAULT)
`$env:DISABLE_TELEMETRY = "1"
`$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
`$env:OTEL_LOG_USER_PROMPTS = "0"
`$env:OTEL_LOG_TOOL_DETAILS = "0"
"@
        Write-Status "Configuring MAXIMUM privacy mode (default)"
    }

    # Add token optimization variables
    $envBlock += @"

# Token Optimization
`$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW = "180000"
"@

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would add to $targetProfile:"
        Write-Host $envBlock
        return
    }

    # Check if already configured
    if (Test-Path $targetProfile) {
        $content = Get-Content $targetProfile -Raw
        if ($content -match "DISABLE_TELEMISTRY=1") {
            Write-Warning "Privacy settings already appear to be configured in profile"
            $update = Read-Host "Update anyway? (y/N)"
            if ($update -notmatch '^[Yy]$') {
                return
            }
        }
    }

    # Append to profile
    Add-Content -Path $targetProfile -Value "`n$envBlock" -Encoding UTF8

    Write-Success "Privacy settings added to PowerShell profile"
    Write-Status "Restart PowerShell or run the profile to apply changes to current session"
}

# Also set in Windows environment for GUI applications
tunction Set-WindowsEnvironment {
    Write-Header "Configuring Windows Environment Variables"

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would set system environment variables"
        return
    }

    # User-level environment variables (applies to all applications)
    [Environment]::SetEnvironmentVariable("DISABLE_TELEMETRY", "1", "User")

    if (-not $ReducedPrivacy) {
        [Environment]::SetEnvironmentVariable("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1", "User")
        [Environment]::SetEnvironmentVariable("OTEL_LOG_USER_PROMPTS", "0", "User")
        [Environment]::SetEnvironmentVariable("OTEL_LOG_TOOL_DETAILS", "0", "User")
    }

    [Environment]::SetEnvironmentVariable("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "180000", "User")

    Write-Success "Windows environment variables configured"
    Write-Status "These apply to all applications, including Claude Code Desktop"
}

# Configure Claude settings (auto-compact)
tunction Set-ClaudeConfiguration {
    Write-Header "Configuring Claude Code Settings"

    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    $claudeConfig = Join-Path $claudeDir ".claude.json"

    # Check if config exists
    if (Test-Path $claudeConfig) {
        Write-Status "Found existing Claude config: $claudeConfig"

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would update $claudeConfig to enable autoCompactEnabled"
            return
        }

        try {
            $config = Get-Content $claudeConfig -Raw | ConvertFrom-Json

            if ($config.autoCompactEnabled -eq $true) {
                Write-Success "autoCompactEnabled is already enabled"
            } else {
                # Create backup
                $backupName = ".claude.json.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item $claudeConfig (Join-Path $claudeDir $backupName)

                # Update config
                $config | Add-Member -NotePropertyName "autoCompactEnabled" -NotePropertyValue $true -Force
                $config | ConvertTo-Json -Depth 10 | Set-Content $claudeConfig -Encoding UTF8

                Write-Success "Enabled autoCompactEnabled in Claude config"
            }
        } catch {
            Write-Error "Failed to parse existing config. Creating new one..."
            # Backup corrupted config
            Move-Item $claudeConfig "$claudeConfig.corrupted.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Create-NewClaudeConfig $claudeConfig
        }
    } else {
        Create-NewClaudeConfig $claudeConfig
    }
}

# Create new Claude config
tunction Create-NewClaudeConfig {
    param([string]$Path)

    Write-Status "Creating new Claude config: $Path"

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create $Path with autoCompactEnabled"
        return
    }

    $claudeDir = Split-Path $Path -Parent
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    $config = @{
        autoCompactEnabled = $true
        theme = "dark"
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8

    Write-Success "Created Claude config with autoCompactEnabled"
}

# Create CLAUDE.md template
tunction New-ClaudeMdTemplate {
    Write-Header "Creating CLAUDE.md Template"

    $claudeMd = Join-Path $PWD "CLAUDE.md"

    if (Test-Path $claudeMd) {
        Write-Warning "CLAUDE.md already exists in current directory"
        $overwrite = Read-Host "Overwrite? (y/N)"
        if ($overwrite -notmatch '^[Yy]$') {
            return
        }
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create CLAUDE.md in current directory"
        return
    }

    $content = @'
# Claude Code Optimization Guide

## Cost-First Defaults
- **Default model**: sonnet 4.6 (or haiku for quick tasks)
- **Always use offset/limit** for reads >500 lines
- **Pre-convert**: PDF→text, Office→Markdown, images→2000x2000 max
- **Compact at**: 150K tokens
- **Turn limits**: +500k default, +1m for complex tasks

## Token Budgets
Set token budgets by starting messages with:
- `+500k` - Limit to 500,000 tokens this turn
- `+1m` - Limit to 1,000,000 tokens this turn

## File Reading Guidelines
### Always Use Pagination
For files >500 lines, always specify offset and limit:
```
Read file.ts {"offset": 1, "limit": 100}
```

### Search Before Reading
```
# Good - targeted search
Grep "function handleRequest" *.ts

# Bad - reading everything
Read all files then search
```

### Binary File Handling
Pre-convert binary files before reading:
- PDFs: Use pdftotext.exe or markitdown
- DOCX/XLSX/PPTX: markitdown
- Images: magick.exe -resize 2000x2000

## Context Management
- **Enable auto-compact** in settings (already configured)
- **Run `/compact` at 150K tokens**
- **Never use `/clear`** (destroys cached context)

## Model Selection Strategy
| Model | Input | Output | Use For |
|-------|-------|--------|---------|
| Haiku 3.5 | $0.80 | $4 | Quick tasks, searches |
| Sonnet 4.x | $3 | $15 | General development |
| Opus 4.5 | $5 | $25 | Complex architecture |
| Opus 4.6 Fast | $30 | $150 | Emergency only |

## PowerShell Pre-Processing Commands

### Convert Documents
```powershell
# PDF to text
pdftotext.exe -layout document.pdf document.txt

# Office to Markdown
markitdown document.docx > document.md
markitdown spreadsheet.xlsx > spreadsheet.md
```

### Resize Images
```powershell
magick.exe input.png -resize 2000x2000 -quality 85 output.png
magick.exe input.jpg -resize 2000x2000 -quality 85 output.jpg
```

## Daily Checklist
- [ ] Set appropriate model for the task
- [ ] Use offset/limit for file reads
- [ ] Set token budgets (+500k) for large tasks
- [ ] Run `/compact` at 150K tokens
- [ ] Pre-convert binary documents

## Windows-Specific Tips
- Use PowerShell or WSL for markitdown
- ImageMagick command is `magick.exe` on Windows
- pdftotext comes with poppler (choco install poppler)
'@

    $content | Set-Content $claudeMd -Encoding UTF8

    Write-Success "Created CLAUDE.md in current directory"
}

# Create a batch file for easy pre-processing
tunction New-PreprocessScript {
    Write-Header "Creating Pre-Processing Helper Scripts"

    $batchFile = Join-Path $PWD "preprocess-for-claude.bat"
    $psFile = Join-Path $PWD "preprocess-for-claude.ps1"

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create helper scripts"
        return
    }

    # Batch file
    $batchContent = @'
@echo off
:: Pre-process files for Claude Code
:: Usage: preprocess-for-claude.bat <file>

if "%~1"=="" (
    echo Usage: preprocess-for-claude.bat ^<file^>
    exit /b 1
)

set "file=%~1"
set "ext=%~x1"

if /i "%ext%"==".pdf" (
    pdftotext.exe -layout "%file%" "%~n1.txt"
    echo Converted to: %~n1.txt
) else if /i "%ext%"==".docx" (
    markitdown "%file%" > "%~n1.md"
    echo Converted to: %~n1.md
) else if /i "%ext%"==".xlsx" (
    markitdown "%file%" > "%~n1.md"
    echo Converted to: %~n1.md
) else if /i "%ext%"==".pptx" (
    markitdown "%file%" > "%~n1.md"
    echo Converted to: %~n1.md
) else if /i "%ext%"==".png" (
    magick.exe "%file%" -resize 2000x2000 -quality 85 "%~n1-optimized.png"
    echo Resized to: %~n1-optimized.png
) else if /i "%ext%"==".jpg" (
    magick.exe "%file%" -resize 2000x2000 -quality 85 "%~n1-optimized.jpg"
    echo Resized to: %~n1-optimized.jpg
) else if /i "%ext%"==".jpeg" (
    magick.exe "%file%" -resize 2000x2000 -quality 85 "%~n1-optimized.jpg"
    echo Resized to: %~n1-optimized.jpg
) else (
    echo Unknown file type: %ext%
    exit /b 1
)
'@

    $batchContent | Set-Content $batchFile -Encoding ASCII

    # PowerShell version with more features
    $psContent = @'
# Pre-process files for Claude Code
# Usage: .\preprocess-for-claude.ps1 <file> [-OutputPath <path>]

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [string]$OutputPath,

    [switch]$Batch
)

function Process-File {
    param([string]$Path)

    $file = Get-Item $Path
    $ext = $file.Extension.ToLower()
    $base = $file.BaseName

    if (-not $OutputPath) {
        $OutputPath = $file.DirectoryName
    }

    switch ($ext) {
        ".pdf" {
            $output = Join-Path $OutputPath "$base.txt"
            Write-Host "Converting PDF to text: $output" -ForegroundColor Green
            & pdftotext.exe -layout $file.FullName $output
        }
        ".docx" {
            $output = Join-Path $OutputPath "$base.md"
            Write-Host "Converting DOCX to Markdown: $output" -ForegroundColor Green
            & markitdown $file.FullName > $output
        }
        ".xlsx" {
            $output = Join-Path $OutputPath "$base.md"
            Write-Host "Converting XLSX to Markdown: $output" -ForegroundColor Green
            & markitdown $file.FullName > $output
        }
        ".pptx" {
            $output = Join-Path $OutputPath "$base.md"
            Write-Host "Converting PPTX to Markdown: $output" -ForegroundColor Green
            & markitdown $file.FullName > $output
        }
        ".png" {
            $output = Join-Path $OutputPath "$base-optimized.png"
            Write-Host "Resizing PNG: $output" -ForegroundColor Green
            & magick.exe $file.FullName -resize 2000x2000 -quality 85 $output
        }
        ".jpg" {
            $output = Join-Path $OutputPath "$base-optimized.jpg"
            Write-Host "Resizing JPEG: $output" -ForegroundColor Green
            & magick.exe $file.FullName -resize 2000x2000 -quality 85 $output
        }
        ".jpeg" {
            $output = Join-Path $OutputPath "$base-optimized.jpg"
            Write-Host "Resizing JPEG: $output" -ForegroundColor Green
            & magick.exe $file.FullName -resize 2000x2000 -quality 85 $output
        }
        default {
            Write-Warning "Unknown file type: $ext"
        }
    }
}

if ($Batch) {
    # Process all supported files in directory
    $files = Get-ChildItem -File | Where-Object {
        $_.Extension -match '\.(pdf|docx|xlsx|pptx|png|jpg|jpeg)$'
    }
    foreach ($file in $files) {
        Process-File -Path $file.FullName
    }
} else {
    Process-File -Path $FilePath
}
'@

    $psContent | Set-Content $psFile -Encoding UTF8

    Write-Success "Created pre-processing scripts:"
    Write-Host "  - $batchFile (Command Prompt)"
    Write-Host "  - $psFile (PowerShell with more features)"
}

# Main execution
tunction Main {
    Write-Header "Claude Code Token Optimizer & Privacy Enhancer (Windows)"

    if (-not (Test-Administrator)) {
        Write-Warning "Script not running as Administrator. Some features may not work."
        Write-Host "For best results, run PowerShell as Administrator."
        Write-Host ""
    }

    if ($DryRun) {
        Write-Warning "DRY RUN MODE - No changes will be made"
    }

    # Execute functions
    Install-Dependencies
    Set-PrivacyConfiguration
    Set-WindowsEnvironment
    Set-ClaudeConfiguration
    New-ClaudeMdTemplate
    New-PreprocessScript

    # Summary
    Write-Header "Summary"

    Write-Success "Configuration complete!"
    Write-Host ""

    if ($script:InstallFailed.Count -gt 0) {
        Write-Warning "Some dependencies failed to install: $($script:InstallFailed -join ', ')"
        Write-Host "You can manually install them later."
        Write-Host ""
    }

    Write-Host "Next steps:" -Bold
    Write-Host "1. Review the environment variables in your PowerShell profile"
    Write-Host "2. Restart PowerShell or run: `$PROFILE"
    Write-Host "3. Start Claude Code with optimized settings"
    Write-Host "4. Check /cost regularly to monitor usage"
    Write-Host "5. Use the preprocess-for-claude.ps1 script for document conversion"
    Write-Host ""

    if ($ReducedPrivacy) {
        Write-Host "Privacy mode: Standard (telemetry disabled, auto-updates enabled)" -ForegroundColor Yellow
    } else {
        Write-Host "Privacy mode: MAXIMUM (all non-essential traffic disabled)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Success "Happy optimizing!"
}

# Run main
Main
