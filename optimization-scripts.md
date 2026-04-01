# Claude Code Optimization Scripts

Automated setup scripts for maximizing Claude Code token efficiency and privacy.

---

## Overview

These scripts automate the installation of dependencies and configuration of privacy settings to help you:

1. **Reduce token consumption** by 50-80%
2. **Maximize privacy** by disabling telemetry and non-essential traffic
3. **Install pre-processing tools** for document/image optimization
4. **Enable auto-compact** to prevent rate limit blocks

---

## Scripts

| Script | Platform | Requirements |
|--------|----------|--------------|
| `optimize-claude.sh` | Linux, macOS, WSL | Bash, sudo access |
| `optimize-claude.ps1` | Windows 10/11 | PowerShell 5.1+, Administrator |

---

## Quick Start

### Linux / macOS / WSL

```bash
cd docs
./optimize-claude.sh
```

### Windows (Run as Administrator)

```powershell
cd docs
.\optimize-claude.ps1
```

---

## What the Scripts Do

### 1. Dependency Installation

Both scripts check for and install:

| Dependency | Purpose | Linux/macOS | Windows |
|------------|---------|-------------|---------|
| **markitdown** | Convert Office/PDF → Markdown | pip | pip |
| **ImageMagick** | Resize/optimize images | apt/yum/brew | winget/choco |
| **poppler** | PDF text extraction | apt/yum/brew | choco |

**Why these matter:**
- Converting documents to text before Claude sees them reduces tokens by 10x
- Resizing images before upload saves ~33% on base64 encoding overhead
- PDF text extraction avoids the 10-page inline threshold

### 2. Privacy Configuration (Default: Maximum)

By default, both scripts configure **maximum privacy mode**:

```bash
# Set in shell profile (Linux/macOS) or Registry (Windows)
DISABLE_TELEMETRY=1
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
OTEL_LOG_USER_PROMPTS=0
OTEL_LOG_TOOL_DETAILS=0
```

**What gets disabled:**
- All Datadog logging
- First-party event logging to BigQuery
- OpenTelemetry tracing
- Auto-updates
- Release notes fetching
- Changelog fetching
- Model capabilities prefetch
- Plugin marketplace sync
- MCP registry sync

**What still works:**
- Anthropic API calls (required for functionality)
- OAuth token refresh (if using OAuth)
- All core Claude Code features

#### Reduced Privacy Mode

If you want to keep auto-updates and release notes:

```bash
# Linux/macOS
./optimize-claude.sh --reduced-privacy

# Windows
.\optimize-claude.ps1 -ReducedPrivacy
```

This only sets `DISABLE_TELEMETRY=1`, keeping other features enabled.

### 3. Auto-Compact Configuration

Both scripts enable `autoCompactEnabled` in Claude's settings:

**Location:**
- Linux/macOS: `~/.claude/.claude.json`
- Windows: `%USERPROFILE%\.claude\.claude.json`

**What it does:**
- Monitors token usage every turn
- Automatically triggers `/compact` at ~150K tokens
- Prevents expensive blocking rate limits
- Preserves recent context (unlike `/clear`)

### 4. CLAUDE.md Template

Creates a project-level `CLAUDE.md` with:

- Cost-first defaults (model selection, pagination rules)
- Token budget syntax (`+500k`, `+1m`)
- File reading guidelines (offset/limit)
- Binary file handling (pre-conversion commands)
- Context management rules
- Emergency controls

### 5. Windows Helper Scripts (PowerShell only)

The PowerShell script additionally creates:

- `preprocess-for-claude.ps1` - Document conversion helper
- `preprocess-for-claude.bat` - Batch wrapper for easy use

---

## Command Line Options

### Bash Script (`optimize-claude.sh`)

| Option | Description |
|--------|-------------|
| `--reduced-privacy` | Standard privacy only (keeps auto-updates) |
| `--dry-run` | Preview changes without applying |
| `--skip-deps` | Skip dependency installation |
| `--help` | Show help message |

**Examples:**

```bash
# Default: maximum privacy + dependency install
./optimize-claude.sh

# Reduced privacy (standard telemetry only)
./optimize-claude.sh --reduced-privacy

# Preview what would be done
./optimize-claude.sh --dry-run

# Skip dependencies, just configure privacy
./optimize-claude.sh --skip-deps
```

### PowerShell Script (`optimize-claude.ps1`)

| Parameter | Description |
|-----------|-------------|
| `-ReducedPrivacy` | Standard privacy only (keeps auto-updates) |
| `-DryRun` | Preview changes without applying |
| `-SkipDeps` | Skip dependency installation |

**Examples:**

```powershell
# Default: maximum privacy + dependency install
.\optimize-claude.ps1

# Reduced privacy
.\optimize-claude.ps1 -ReducedPrivacy

# Preview only
.\optimize-claude.ps1 -DryRun

# Skip dependency installation
.\optimize-claude.ps1 -SkipDeps
```

---

## Privacy Levels Explained

### Maximum Privacy (Default)

```bash
DISABLE_TELEMETRY=1
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
OTEL_LOG_USER_PROMPTS=0
OTEL_LOG_TOOL_DETAILS=0
```

**Effect:** API calls only. All analytics, updates, and non-essential traffic disabled. Fastest startup.

### Standard Privacy (`--reduced-privacy` / `-ReducedPrivacy`)

```bash
DISABLE_TELEMETRY=1
```

**Effect:** No analytics, but keeps auto-updates, release notes, plugin marketplace. Good balance for most users.

### Verification

After running either script, verify with:

```bash
# In Claude Code
/debug
```

Look for:
- `telemetry: disabled` ✓
- `nonessential_traffic: blocked` ✓ (maximum privacy)
- `analytics: disabled` ✓

---

## Pre-Processing Tools Usage

After installation, use these workflows:

### Documents (PDF, DOCX, XLSX, PPTX)

```bash
# Convert before reading in Claude
markitdown document.pdf > document.md
markitdown spreadsheet.xlsx > spreadsheet.md
markitdown presentation.pptx > presentation.md

# Then in Claude
Read document.md  # 10x cheaper than reading the binary
```

### Images

```bash
# Resize before attaching
magick screenshot.png -resize 2000x2000> -quality 85 optimized.png

# Or use the Windows helper
.\preprocess-for-claude.ps1 -Path screenshot.png
```

### PDFs (Alternative)

```bash
# Text extraction (faster, no formatting)
pdftotext -layout document.pdf document.txt
```

---

## Expected Results

After running these scripts:

| Metric | Improvement |
|--------|-------------|
| **Token usage** | 50-80% reduction |
| **Startup time** | Faster (no telemetry init) |
| **Session length** | Longer before rate limits |
| **Privacy** | Maximum (default) |
| **Cost** | Significantly lower per task |

---

## Troubleshooting

### Dependencies fail to install

**Linux:**
```bash
# Update package lists first
sudo apt-get update  # Debian/Ubuntu
sudo yum update      # RHEL/CentOS
```

**macOS:**
```bash
# Update Homebrew
brew update
```

**Windows:**
```powershell
# Install Chocolatey first if needed
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
```

### Privacy settings not applying

**Linux/macOS:**
```bash
# Source your profile
source ~/.bashrc  # or ~/.zshrc

# Verify
export -p | grep TELEMETRY
```

**Windows:**
```powershell
# Restart PowerShell/Terminal completely
# Or run:
$env:DISABLE_TELEMETRY = "1"
```

### Claude Code doesn't see the settings

Claude Code reads environment variables at startup. **You must restart Claude Code** after running these scripts.

---

## Files Created

| File | Platform | Purpose |
|------|----------|---------|
| `CLAUDE.md` | All | Project-level optimization guide |
| `~/.claude/.claude.json` | Linux/macOS | Claude settings (auto-compact) |
| `%USERPROFILE%\.claude\.claude.json` | Windows | Claude settings (auto-compact) |
| `~/.bashrc` / `~/.zshrc` modifications | Linux/macOS | Environment variables |
| Windows Registry | Windows | System environment variables |
| `preprocess-for-claude.ps1` | Windows | Document conversion helper |
| `preprocess-for-claude.bat` | Windows | Batch wrapper |

---

## Security Notes

- Both scripts require elevated privileges (sudo on Linux, Administrator on Windows) only for dependency installation
- No network connections are made to third parties except package managers (apt, brew, winget, choco, pip)
- All environment variables are set at user-level (not system-wide)
- Scripts are idempotent—running multiple times is safe

---

## Related Documentation

- [`prompt-caching.md`](prompt-caching.md) - 5-minute TTL behavior, keepalive strategies, cache optimization
- [`telemetry-privacy.md`](telemetry-privacy.md) - Detailed telemetry and privacy internals
- [`undocumented-features.md`](undocumented-features.md) - Environment variables and feature flags
- [`CLAUDE.md-template`](CLAUDE.md-template) - Ready-to-use project template

---

*These scripts are based on analysis of the Claude Code source code.*
