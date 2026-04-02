# Claude Code Optimizer Validation Suite

Comprehensive testing framework to verify all claims made by the optimization scripts.

---

## Overview

The validation suite tests every optimization claim:

| Claim | Test | How Verified |
|-------|------|--------------|
| Dependencies installed | ✓ | Command availability + functional tests |
| Privacy variables set | ✓ | Environment variable inspection |
| Auto-compact enabled | ✓ | Config file parsing |
| Hooks configured | ✓ | settings.json validation |
| Image pre-processing works | ✓ | Create + resize test image |
| Document conversion works | ✓ | PDF text extraction test |
| Cache keepalive active | ✓ | Hook presence verification |
| 50-80% token reduction | ⚠ | Indirect (via dependency verification) |

---

## Quick Start

### Linux / macOS / WSL

```bash
# Run all validation tests
./validate-optimizations.sh

# Before/After comparison
./validate-optimizations.sh --before
./optimize-claude.sh
./validate-optimizations.sh --after

# Detailed output
./validate-optimizations.sh --verbose
```

### Windows

```powershell
# Run all validation tests
.\validate-optimizations.ps1

# Before/After comparison
.\validate-optimizations.ps1 -Before
.\optimize-claude.ps1
.\validate-optimizations.ps1 -After

# Detailed output
.\validate-optimizations.ps1 -Verbose
```

---

## What Gets Tested

### 1. Dependency Installation Tests

Verifies all three dependencies are installed and functional:

| Dependency | Test | Success Criteria |
|------------|------|------------------|
| **markitdown** | Command or Python module check | `markitdown --version` or `import markitdown` succeeds |
| **ImageMagick** | Command check | `magick` or `convert` in PATH |
| **poppler** | Command check | `pdftotext` in PATH |

**Functional Tests:**
- ImageMagick: Creates 2000x2000 test image, resizes to verify operation
- Document tools: Verifies commands are available (creates test PDF if Python/reportlab available)

### 2. Privacy Environment Variables Tests

Checks all 5 privacy variables:

```bash
DISABLE_TELEMETRY=1
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
OTEL_LOG_USER_PROMPTS=0
OTEL_LOG_TOOL_DETAILS=0
CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000
```

**Verification:**
- Current shell environment variables
- Shell profile persistence (block markers)
- Windows Registry (Windows only)

**Scoring:**
- 5/5 = Maximum privacy mode ✓
- 3-4/5 = Standard privacy mode ⚠
- 0-2/5 = Limited protection ✗

### 3. Claude Settings Tests

Verifies `~/.claude/.claude.json` (or `%USERPROFILE%\.claude\.claude.json` on Windows):

```json
{
  "autoCompactEnabled": true
}
```

**Checks:**
- Config file exists
- `autoCompactEnabled: true` is set
- JSON is valid

### 4. Hooks Configuration Tests

Validates `.claude/settings.json`:

**PreToolUse Hook:**
- Resizes PNG/JPG/JPEG images before Claude reads them
- Uses ImageMagick `magick` command
- Saves ~33% on base64 encoding overhead

**PostToolUse Hook:**
- Fires after every tool use
- Keeps prompt cache warm (prevents 5-minute TTL expiration)
- Outputs `cache_keepalive` timestamp

### 5. Image Pre-processing Capability Tests

**Functional Test:**
1. Creates 2000x2000 pixel test image
2. Resizes using ImageMagick (`-resize 2000x2000> -quality 85`)
3. Verifies output file exists and is smaller

**Validates:**
- ImageMagick is working correctly
- Resize operation produces smaller files
- Quality settings are applied

### 6. Document Conversion Capability Tests

**PDF Test:**
- Creates test PDF (if Python/reportlab available)
- Extracts text using `pdftotext -layout`
- Verifies output is produced

**markitdown Test:**
- Verifies command availability
- (Full conversion tests require sample files)

### 7. Cache Keepalive Mechanism Tests

**Hook Verification:**
- Checks for `PostToolUse` hook in settings.json
- Looks for `cache_keepalive` or `keepalive` in hook command
- Verifies hook fires on all tool use (`"matcher": "*"`)

**Optional Script:**
- Checks for `claude-keepalive.sh` / `claude-keepalive.ps1`
- (Hooks handle this automatically, script is optional)

### 8. Privacy Level Verification

**Scoring System:**

| Variable | Points | Purpose |
|----------|--------|---------|
| `DISABLE_TELEMETRY=1` | 1 | Disables Datadog telemetry |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | 1 | Blocks updates, release notes |
| `OTEL_LOG_USER_PROMPTS=0` | 1 | Disables prompt logging |
| `OTEL_LOG_TOOL_DETAILS=0` | 1 | Disables tool logging |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000` | 1 | Auto-compact threshold |

**Results:**
- **5/5 (100%)**: Maximum privacy mode - all non-essential traffic disabled
- **3-4/5 (60-80%)**: Standard privacy mode - core telemetry disabled
- **1-2/5 (20-40%)**: Partial protection - some logging may occur
- **0/5 (0%)**: No privacy protection - full telemetry active

---

## Before/After Comparison

Capture baseline state before running optimizations, then compare after:

### Linux/macOS

```bash
# 1. Capture baseline
./validate-optimizations.sh --before

# 2. Run optimizer
./optimize-claude.sh

# 3. Restart shell to apply env vars
source ~/.bashrc  # or ~/.zshrc

# 4. Capture post-optimization state
./validate-optimizations.sh --after
```

### Windows

```powershell
# 1. Capture baseline
.\validate-optimizations.ps1 -Before

# 2. Run optimizer
.\optimize-claude.ps1

# 3. Restart PowerShell to apply env vars
# Close and reopen PowerShell window

# 4. Capture post-optimization state
.\validate-optimizations.ps1 -After
```

**Comparison Output:**

```
📊 DEPENDENCY CHANGES:
  ✓ markitdown: NOT INSTALLED → INSTALLED
  ✓ imagemagick: NOT INSTALLED → INSTALLED
  ✓ poppler: NOT INSTALLED → INSTALLED

🔒 PRIVACY CHANGES:
  ✓ DISABLE_TELEMETRY: NOT SET → 1
  ✓ CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: NOT SET → 1
  ✓ OTEL_LOG_USER_PROMPTS: NOT SET → 0
  ✓ OTEL_LOG_TOOL_DETAILS: NOT SET → 0

⚙️  AUTO-COMPACT:
  ✓ Auto-compact: DISABLED → ENABLED

🪝 HOOKS:
  ✓ PreToolUse hook: NOT CONFIGURED → CONFIGURED
  ✓ PostToolUse hook: NOT CONFIGURED → CONFIGURED
```

---

## Understanding Test Results

### Pass (✓)

The optimization is working correctly. The claim is verified.

### Skip (⚠)

The test couldn't run or the feature is partially configured:
- May indicate optional features not installed
- Could be legacy configuration (without block markers)
- Some tests require Python/reportlab for full validation

### Fail (✗)

The optimization is not working. Action needed:
- Run the optimizer script again
- Check error messages for specific fixes
- Verify shell was restarted after optimization

---

## State Files

The validation suite creates JSON state files for comparison:

| File | Purpose |
|------|---------|
| `.validation_state_before.json` | Baseline state before optimization |
| `.validation_state_after.json` | State after optimization |
| `.validation_state.json` | Temporary file (moved to before/after) |

**State File Structure:**

```json
{
  "timestamp": "2025-01-15T10:30:00Z",
  "mode": "before",
  "dependencies": {
    "markitdown": false,
    "imagemagick": false,
    "poppler": false
  },
  "privacy_vars": {
    "DISABLE_TELEMETRY": null,
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": null
  },
  "claude_config": {
    "exists": false,
    "autoCompactEnabled": false
  },
  "hooks": {
    "settings_json_exists": false,
    "pretooluse_hook": false,
    "posttooluse_hook": false
  }
}
```

---

## Troubleshooting Failed Tests

### Dependencies Fail

**markitdown:**
```bash
pip install markitdown
```

**ImageMagick:**
```bash
# Linux
sudo apt-get install imagemagick

# macOS
brew install imagemagick

# Windows
winget install ImageMagick.ImageMagick
```

**poppler:**
```bash
# Linux
sudo apt-get install poppler-utils

# macOS
brew install poppler

# Windows
choco install xpdf-utils
```

### Privacy Variables Not Set

**Linux/macOS:**
```bash
# Check current shell
echo $DISABLE_TELEMETRY

# Source profile if not set
source ~/.bashrc  # or ~/.zshrc

# Verify again
echo $DISABLE_TELEMETRY
```

**Windows:**
```powershell
# Check current session
$env:DISABLE_TELEMETRY

# Check persistent setting
[Environment]::GetEnvironmentVariable("DISABLE_TELEMETRY", "User")

# Set if missing
[Environment]::SetEnvironmentVariable("DISABLE_TELEMETRY", "1", "User")
```

### Auto-Compact Not Enabled

```bash
# Check config exists
cat ~/.claude/.claude.json

# Manually enable if needed
# Edit the file to add: "autoCompactEnabled": true
```

### Hooks Not Configured

```bash
# Check if settings.json exists
cat .claude/settings.json

# Re-run optimizer to create
./optimize-claude.sh
```

---

## Expected Benefits Summary

When all tests pass:

| Metric | Expected Improvement | Verified By |
|--------|---------------------|-------------|
| **Token usage** | 50-80% reduction | Dependencies + hooks working |
| **Startup time** | Faster | Privacy variables (no telemetry init) |
| **Session length** | Longer before rate limits | Auto-compact enabled |
| **Privacy** | Maximum protection | 5/5 privacy score |
| **Cost** | Significantly lower | All optimizations combined |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All critical tests passed |
| 1 | Some tests failed - review output |

---

## Related Documentation

- [`optimization-scripts.md`](optimization-scripts.md) - Main optimization scripts
- [`prompt-caching.md`](prompt-caching.md) - Cache TTL and keepalive details
- [`telemetry-privacy.md`](telemetry-privacy.md) - Privacy internals
