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
| `scripts/linux/optimize-claude.sh` | Linux, macOS, WSL | Bash, sudo access |
| `scripts/windows/optimize-claude.ps1` | Windows 10/11 | PowerShell 5.1+, Administrator |

### Validation

After running the optimizer, validate that hooks are working:

```bash
# Linux/macOS/WSL
./scripts/linux/validate.sh

# Windows
.\scripts\windows\validate.ps1
```

---

## Quick Start

### Linux / macOS / WSL

```bash
# 1. Run optimizer
./scripts/linux/optimize-claude.sh

# 2. Restart shell to apply env vars
source ~/.bashrc  # or ~/.zshrc

# 3. Verify optimizations are working
./scripts/linux/validate.sh --verbose
```

### Windows (Run as Administrator)

```powershell
# 1. Run optimizer
.\scripts\windows\optimize-claude.ps1

# 2. Restart PowerShell to apply env vars
# Close and reopen PowerShell window

# 3. Verify optimizations are working
.\scripts\windows\validate.ps1 -VerboseOutput
```

---

## Validation & Testing

After running the optimization scripts, verify that all optimizations are working correctly using the **Validation Suite**.

### Validation Scripts

| Script | Platform | Purpose |
|--------|----------|---------|
| `scripts/linux/validate.sh` | Linux, macOS, WSL | Functional validation that hooks actually work |
| `scripts/windows/validate.ps1` | Windows | Functional validation that hooks actually work |

### What Gets Validated

The validation suite tests every claim made by the optimization scripts:

1. **Dependencies** - markitdown (optional, skipped in Termux), ImageMagick, poppler installed and functional
2. **Privacy Variables** - All 5 environment variables set correctly
3. **Auto-Compact** - Enabled in Claude config
4. **Hooks** - PreToolUse and PostToolUse hooks configured
5. **Image Pre-processing** - Can resize images (functional test)
6. **Document Conversion** - Can extract text from PDFs
7. **Cache Keepalive** - Hook mechanism in place

### Validation Output

**Sample Output:**

```
📊 DEPENDENCY CHANGES:
  ✓ markitdown: NOT INSTALLED → INSTALLED (or skipped in Termux)
  ✓ imagemagick: NOT INSTALLED → INSTALLED
  ✓ poppler: NOT INSTALLED → INSTALLED

🔒 PRIVACY CHANGES:
  ✓ DISABLE_TELEMETRY: NOT SET → 1
  ✓ CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: NOT SET → 1

⚙️  AUTO-COMPACT:
  ✓ Auto-compact: DISABLED → ENABLED

🪝 HOOKS:
  ✓ PreToolUse hook: NOT CONFIGURED → CONFIGURED
  ✓ PostToolUse hook: NOT CONFIGURED → CONFIGURED
```

See [validation.md](validation.md) for complete documentation.

---

## What the Scripts Do

### 1. Dependency Installation

Both scripts check for and install:

| Dependency | Purpose | Linux/macOS | Windows | Notes |
|------------|---------|-------------|---------|-------|
| **markitdown** | Convert Office/PDF → Markdown | pip | pip | _Skipped in Termux_ |
| **ImageMagick** | Resize/optimize images | apt/yum/brew | winget/choco | |
| **poppler** | PDF text extraction | apt/yum/brew | choco | |

**Platform Notes:**
- **Termux (Android):** markitdown is automatically skipped due to heavy dependencies (libxml, libxslt) not being readily available. Office document conversion is disabled, but image resizing and other features work normally.

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
./scripts/linux/optimize-claude.sh --reduced-privacy

# Windows
.\scripts\windows\optimize-claude.ps1 -ReducedPrivacy
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

### 4. Remove Attribution Text

Configure empty attribution strings in `settings.json` to hide the "Co-authored by" attribution on commits and PRs:

```json
{
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

**Savings:** ~50–100 tokens per commit/PR operation
**Complexity:** Edit `settings.json`

This removes the default Claude Code attribution signature from git commits and pull request descriptions, reducing token usage on every commit or PR created through Claude Code.

### 5. CAVEMAN Mode (Optional)

Enable CAVEMAN mode by adding `--caveman` (Bash) or `-Caveman` (PowerShell) to configure a concise system prompt extension:

```bash
./scripts/linux/optimize-claude.sh --caveman
```

```powershell
.\scripts\windows\optimize-claude.ps1 -Caveman
```

**What it does:**

Adds an `appendSystemPrompt` field to `settings.json` that targets common verbosity patterns:

```json
{
  "appendSystemPrompt": "NO PREAMBLE. No 'Sure!', 'Great question!', 'Happy to help!'. Start with answer. NO SIGN-OFFS. No 'Let me know...', 'Hope this helps!', 'Feel free to ask...'. End when done. NO PROCESS NARRATION. Don't explain what you're about to do. Do it. Show result. NO FILLER. Drop 'just', 'basically', 'actually', 'simply', 'really', 'very'. SHORT SENTENCES. Break long sentences. 10 words max."
}
```

**Effect:**
- Eliminates conversational padding ("Sure!", "Great question!")
- Removes sign-offs ("Let me know if...", "Hope this helps!")
- Stops process narration ("I'm going to...", "First I'll...")
- Cuts filler words while keeping technical precision
- Technical content stays complete and accurate

**When to use:**
- Technical tasks where brevity is preferred
- Environments with strict token budgets
- Users who prefer direct, no-fluff responses

## Command Line Options

### Bash Script (`optimize-claude.sh`)

| Option | Description |
|--------|-------------|
| `--reduced-privacy` | Standard privacy only (keeps auto-updates) |
| `--auto-approve` | Enable auto-approval whitelist for safe commands (opt-in) |
| `--auto-format` | Enable auto-formatting after file edits (opt-in) |
| `--caveman` | Enable CAVEMAN mode (concise system prompt for token savings) |
| `--dry-run` | Preview changes without applying |
| `--skip-deps` | Skip dependency installation |
| `--help` | Show help message |

**Examples:**

```bash
# Default: maximum privacy + dependency install
./scripts/linux/optimize-claude.sh

# Reduced privacy (standard telemetry only)
./scripts/linux/optimize-claude.sh --reduced-privacy

# Enable auto-approval for safe commands
./scripts/linux/optimize-claude.sh --auto-approve

# Enable auto-formatting after edits
./scripts/linux/optimize-claude.sh --auto-format

# Enable CAVEMAN concise prompt mode
./scripts/linux/optimize-claude.sh --caveman

# Preview what would be done
./scripts/linux/optimize-claude.sh --dry-run

# Skip dependencies, just configure privacy
./scripts/linux/optimize-claude.sh --skip-deps
```

### PowerShell Script (`optimize-claude.ps1`)

| Parameter | Description |
|-----------|-------------|
| `-ReducedPrivacy` | Standard privacy only (keeps auto-updates) |
| `-AutoApprove` | Enable auto-approval whitelist for safe commands (opt-in) |
| `-AutoFormat` | Enable auto-formatting after file edits (opt-in) |
| `-Caveman` | Enable CAVEMAN mode (concise system prompt for token savings) |
| `-DryRun` | Preview changes without applying |
| `-SkipDeps` | Skip dependency installation |

**Examples:**

```powershell
# Default: maximum privacy + dependency install
.\scripts\windows\optimize-claude.ps1

# Reduced privacy
.\scripts\windows\optimize-claude.ps1 -ReducedPrivacy

# Enable auto-approval for safe commands
.\scripts\windows\optimize-claude.ps1 -AutoApprove

# Enable auto-formatting after edits
.\scripts\windows\optimize-claude.ps1 -AutoFormat

# Enable CAVEMAN concise prompt mode
.\scripts\windows\optimize-claude.ps1 -Caveman

# Preview only
.\scripts\windows\optimize-claude.ps1 -DryRun

# Skip dependency installation
.\scripts\windows\optimize-claude.ps1 -SkipDeps
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

The `settings.json` hooks automatically handle image resizing and cache keepalive. Manual pre-processing is only needed for edge cases or non-standard workflows.

### Documents (PDF, DOCX, XLSX, PPTX)

```bash
# Convert before reading in Claude (optional - hooks don't handle documents)
markitdown document.pdf > document.md
markitdown spreadsheet.xlsx > spreadsheet.md
markitdown presentation.pptx > presentation.md

# Then in Claude
Read document.md  # 10x cheaper than reading the binary
```

### Images (Automatic via Hooks)

Images are automatically resized by the PreToolUse hook when using the `Read` tool:
- PNG/JPG/JPEG files are resized to max 2000x2000
- Quality set to 85%
- Saves ~33% on base64 encoding overhead

```bash
# Manual resize (only if needed for edge cases)
magick screenshot.png -resize 2000x2000> -quality 85 optimized.png
```

### PDFs (Alternative)

```bash
# Text extraction (faster, no formatting)
pdftotext -layout document.pdf document.txt
```

---

## Expected Results

After running these scripts:

| Metric | Improvement | Verification |
|--------|-------------|--------------|
| **Token usage** | 50-80% reduction | Run validation suite |
| **Startup time** | Faster (no telemetry init) | Run validation suite |
| **Session length** | Longer before rate limits | Run validation suite |
| **Privacy** | Maximum (default) | Run validation suite |
| **Cost** | Significantly lower per task | Monitor `/cost` in Claude |
| **Attribution** | ~50-100 tokens saved per commit/PR | Check git logs for no "Co-authored by" |

**Verify the optimizations are working:**

```bash
# Linux/macOS
./scripts/linux/validate.sh

# Windows
.\scripts\windows\validate.ps1
```

The validation suite will test all claims and show you exactly what's working and what needs attention.

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
# The script auto-sources your profile, but if needed:
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
| `~/.claude/.claude.json` | Linux/macOS | Claude settings (auto-compact) |
| `%USERPROFILE%\.claude\.claude.json` | Windows | Claude settings (auto-compact) |
| `~/.claude/settings.json` | Linux/macOS | Hooks for auto-processing & keepalive |
| `.claude/settings.json` | Windows (project) | Hooks for auto-processing & keepalive |
| `~/.bashrc` / `~/.zshrc` modifications | Linux/macOS | Environment variables |
| Windows Registry | Windows | System environment variables |

---

## Security Notes

- Both scripts require elevated privileges (sudo on Linux, Administrator on Windows) only for dependency installation
- No network connections are made to third parties except package managers (apt, brew, winget, choco, pip)
- All environment variables are set at user-level (not system-wide)
- Scripts are idempotent—running multiple times is safe

---

## Related Documentation

- [`prompt-caching.md`](./prompt-caching.md) - 5-minute TTL behavior, keepalive strategies, cache optimization
- [`telemetry-privacy.md`](./telemetry-privacy.md) - Detailed telemetry and privacy internals
- [`undocumented-features.md`](./undocumented-features.md) - Environment variables and feature flags

---

*These scripts are based on analysis of the Claude Code source code.*
