# Claude Code Hook Validation

This document describes how to validate that the Claude Code optimization hooks are correctly configured and working.

## Overview

The validation script:
1. **Checks configuration** - Verifies hooks are properly set up in settings.json
2. **Tests dependencies** - Ensures ImageMagick, pdftotext, and markitdown are installed (markitdown is skipped in Termux)
3. **Validates privacy settings** - Confirms environment variables are set correctly
4. **Optional headless testing** - Can run Claude Code in headless mode to verify hooks actually fire

## The Problem

Manual testing requires:
- User to manually run Claude Code
- User to type commands
- User to check if hooks fired
- User to interpret results

This is error-prone and doesn't provide automated validation.

## The Solution

The validation script provides two modes:

### Config-Only Mode (Default)
Checks that all configurations are in place without running Claude Code:
- Hooks configured in settings.json
- Dependencies installed
- Environment variables set

### Headless Mode (`--test-hooks`)
Actually runs Claude Code programmatically to verify hooks fire:
1. **Creates test files** automatically
2. **Runs Claude Code** using `claude -p` (non-interactive mode)
3. **Sends commands** like `Read test-image.png` via stdin
4. **Captures all output** to files
5. **Checks for evidence**:
   - Resized images in `/tmp/` (PreToolUse proof)
   - Hook events in output (PostToolUse proof)
6. **Generates report** with pass/fail and evidence

## Requirements

- Claude Code installed and in PATH
- Hooks already configured (run `optimize-claude.ps1/sh` first)
- ImageMagick installed (for image tests)
- `jq` installed (for `--test-hooks` mode)

## Quick Start

### Linux / macOS / WSL

```bash
# 1. First, ensure hooks are installed
./scripts/linux/optimize-claude.sh

# 2. Restart Claude Code completely

# 3. Run headless validation
./scripts/linux/validate.sh

# 4. View detailed output
./scripts/linux/validate.sh --verbose
```

### Windows

```powershell
# 1. First, ensure hooks are installed
.\scripts\windows\optimize-claude.ps1

# 2. Restart Claude Code completely

# 3. Run headless validation
.\scripts\windows\validate.ps1

# 4. View detailed output
.\scripts\windows\validate.ps1 -VerboseOutput
```

## How It Works

### Test 1: PreToolUse Hook (Image Processing)

**What it does:**
1. Creates `test-image.png` (3000x3000 pixels)
2. Runs: `echo "Read test-image.png" | claude -p`
3. Waits for hook to execute
4. Checks: `ls /tmp/resized_*.png`

**Pass Criteria:**
- Resized image exists in `/tmp/`
- File is smaller than original

**Evidence:**
```
[PROOF] Resized file: /tmp/resized_test-image.png
[PROOF] Original size: 115275 bytes
[PROOF] Resized size: 48122 bytes
[PROOF] Size reduction: 59%
```

### Test 2: PostToolUse Hook (Cache Keepalive)

**What it does:**
1. Runs: `echo "ls" | claude -p`
2. Captures all output
3. Searches for `cache_keepalive` in output

**Pass Criteria:**
- `cache_keepalive` string found in Claude's output
- JSON format confirmed

**Evidence:**
```
[PROOF] Evidence in output file: tests/claude-output-ls.txt
[PROOF] Cache keepalive output:
  {"cache_keepalive": "1705312202"}
```

### Test 3: Combined Workflow

**What it does:**
1. Runs multiple commands:
   - `Read test-doc.txt`
   - `pwd`
   - `echo 'test'`
2. Checks each output for `cache_keepalive`
3. Verifies consistency

**Pass Criteria:**
- PostToolUse fires on multiple operations
- Consistent behavior

## Sample Output

### Success Case (Config-Only)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Claude Code Optimizer - Configuration Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Claude Code found: 0.2.45
[✓ PASS] ImageMagick installed
[✓ PASS] pdftotext (poppler) installed
[✓ PASS] markitdown installed
[✓ PASS] DISABLE_TELEMETRY=1 (Disable all telemetry)
[✓ PASS] CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 (Block non-essential traffic)
[✓ PASS] OTEL_LOG_USER_PROMPTS=0 (Don't log user prompts)
[✓ PASS] OTEL_LOG_TOOL_DETAILS=0 (Don't log tool details)
[✓ PASS] CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000 (3 minute compact window)
[METRIC] Privacy Score: 5/5
[✓ PASS] Maximum privacy configured
[✓ PASS] autoCompactEnabled: true
[✓ PASS] PreToolUse hook configured
[✓ PASS] PostToolUse hook configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 📊 VALIDATION SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test Results: Passed: 12 | Failed: 0 | Skipped: 0

[✓ PASS] ALL CONFIGURATIONS VALID ✓

Your Claude Code environment is properly configured:
  • Dependencies installed
  • Privacy settings active
  • Auto-compact enabled
  • Hooks configured
```

### Success Case (With `--test-hooks`)

```
🧪 HEADLESS HOOK TESTING
=========================
[INFO] Running headless hook test (costs ~$0.01-0.02 in API credits)...
[INFO] Executing: Read /path/to/test-image.png
[✓ PASS] PreToolUse hook fired (1 times)
[✓ PASS] PostToolUse hook fired (1 times)
[✓ PASS] Image resizing hook executed (resized file found)
[METRIC] API Usage: Input: 1500, Output: 250, Cache: 0/0
```
[PASS] Claude Code produced output
[PROOF] Output saved to: ./tests/claude-output-image.txt
[INFO] Checking for resized image in /tmp/...
[PASS] PreToolUse hook FIRED and resized the image!
[PROOF] Resized file: /tmp/resized_test-image.png
[PROOF] Original size: 115275 bytes
[PROOF] Resized size: 48122 bytes
[PROOF] Size reduction: 59%

TEST 2: PostToolUse Hook (Cache Keepalive)
===========================================
[INFO] Testing if PostToolUse hook fires after tool use...
[INFO] This hook should output cache_keepalive JSON
[INFO] Running: List directory
[INFO] Command: echo 'ls' | claude -p
[PASS] Claude Code produced output
[INFO] Checking for cache_keepalive in Claude's output...
[PASS] PostToolUse hook FIRED - cache_keepalive found in output!
[PROOF] Evidence in output file: ./tests/claude-output-ls.txt
[PROOF] Cache keepalive output:
  {"cache_keepalive": "1705312202"}

### Failure Case (Config Issues)

```
🔒 PRIVACY CONFIGURATION
==========================
[✗ FAIL] DISABLE_TELEMETRY not set (expected: 1, got: )
[INFO] Add to ~/.bashrc or ~/.zshrc: export DISABLE_TELEMETRY=1
[✗ FAIL] CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC not set (expected: 1, got: )
[METRIC] Privacy Score: 0/5
[✗ FAIL] Privacy not configured - follow suggestions above

⚙️  AUTO-COMPACT CONFIGURATION
============================
[✗ FAIL] Claude config not found: ~/.claude/.claude.json
[INFO] Run optimize-claude.sh to create this file

🪝 HOOK CONFIGURATION
=====================
[✗ FAIL] PreToolUse hook not configured
[INFO] This hook auto-resizes images before Claude processes them
[✗ FAIL] PostToolUse hook not configured
[INFO] This hook keeps the prompt cache warm (saves 90% on cache misses)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 📊 VALIDATION SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test Results: Passed: 2 | Failed: 6 | Skipped: 1

[✗ FAIL] CONFIGURATION INCOMPLETE

Some optimizations are not configured.
Review the errors above and run optimize-claude.sh to fix.
```

### Failure Case (Headless Test)

```
🧪 HEADLESS HOOK TESTING
=========================
[INFO] Running headless hook test (costs ~$0.01-0.02 in API credits)...
[INFO] Executing: Read /path/to/test-image.png
[✗ FAIL] PreToolUse hook did NOT fire - no resized image found
[✗ FAIL] PostToolUse hook did NOT fire - no cache_keepalive in output
[⚠ SKIP] Resized image not found (hook may have run but output path differs)
```

**Possible causes:**
  • Claude Code wasn't restarted after installing hooks
  • Hooks aren't configured correctly in settings.json
  • Claude Code version doesn't support hooks

## Command Line Options

### `--verbose` / `-Detailed`

Shows detailed output including:
- Full Claude Code input commands
- Complete Claude Code output
- All file operations

Useful for debugging failures.

**Linux/macOS:**
```bash
./scripts/linux/validate.sh --verbose
```

**Windows:**
```powershell
.\scripts\windows\validate.ps1 -VerboseOutput
```

## Artifacts

When running validation, temporary files are created in:

| Location | Contents |
|----------|----------|
| `tests/` | test-image.png, test-doc.txt |
| `/tmp/` (Linux/macOS) or `$env:TEMP` (Windows) | Claude output files |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All hooks fired successfully |
| 1 | One or more hooks failed |

## Troubleshooting

### "Claude Code not found in PATH"

**Solution:**
```bash
# Check if Claude is installed
which claude

# If not found, install it:
# https://code.claude.com/docs/en/installation
```

### "No settings.json found"

**Solution:**
```bash
# Run the optimizer first
./scripts/linux/optimize-claude.sh

# Then restart Claude Code
# Then run validation
```

### "PreToolUse hook did NOT fire"

**Possible causes:**
1. Claude Code wasn't restarted after installing hooks
2. ImageMagick not installed or not in PATH
3. Hook command has syntax error

**Debug:**
```bash
# Check ImageMagick
which magick || which convert

# Check settings.json syntax
cat .claude/settings.json | python3 -m json.tool

# Try running hook manually
magick test-image.png -resize 2000x2000> -quality 85 /tmp/test.png
```

### "PostToolUse hook did NOT fire"

**Possible causes:**
1. Hook not configured correctly
2. Claude Code version issue
3. Output capture problem

**Debug:**
```bash
# Run Claude manually and check output
echo "ls" | claude -p | grep cache_keepalive

# Check settings.json has PostToolUse hook
grep -A5 "PostToolUse" .claude/settings.json
```

## Integration with CI/CD

This script can be used in automated testing:

```yaml
# GitHub Actions example
- name: Validate Claude Code Hooks
  run: |
    ./scripts/linux/optimize-claude.sh
    ./scripts/linux/validate.sh
  timeout-minutes: 5
```

The exit code indicates success/failure:
- Exit 0 = hooks working
- Exit 1 = hooks not firing

## Comparison of Validation Modes

| Mode | Flag | Description |
|------|------|-------------|
| Config-only | (default) | Checks that hooks are configured in settings.json |
| With headless tests | `--test-hooks` | Actually runs Claude Code to verify hooks fire |

The headless validation (`--test-hooks`) is the only method that:
- Runs Claude Code automatically
- Triggers hooks without user interaction
- Provides concrete proof hooks fired
- Can be used in CI/CD pipelines

Note: `--test-hooks` requires `jq` to be installed and uses API credits (~$0.01-0.02 per test).
