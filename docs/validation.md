# Claude Code Hook Validation - Headless Mode

This script **automatically runs Claude Code in headless mode**, sends commands to trigger hooks, and validates that the hooks actually fire by checking for evidence.

## The Problem

Manual testing requires:
- User to manually run Claude Code
- User to type commands
- User to check if hooks fired
- User to interpret results

This is error-prone and doesn't provide automated validation.

## The Solution

The headless validation script:
1. **Creates test files** automatically
2. **Runs Claude Code programmatically** using `claude -p` (non-interactive mode)
3. **Sends commands** like `Read test-image.png` via stdin
4. **Captures all output** to files
5. **Checks for evidence**:
   - Resized images in `/tmp/` (PreToolUse proof)
   - `cache_keepalive` in output (PostToolUse proof)
6. **Generates report** with pass/fail and evidence

## Requirements

- Claude Code installed and in PATH
- Hooks already configured (run `optimize-claude.ps1/sh` first)
- ImageMagick installed (for image tests)

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

# 5. Keep artifacts for inspection
./scripts/linux/validate.sh --keep
```

### Windows

```powershell
# 1. First, ensure hooks are installed
.\scripts\windows\optimize-claude.ps1

# 2. Restart Claude Code completely

# 3. Run headless validation
.\scripts\windows\validate.ps1

# 4. View detailed output
.\scripts\windows\validate.ps1 -Detailed

# 5. Keep artifacts for inspection
.\scripts\windows\validate.ps1 -Keep
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

### Success Case

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Claude Code Hook Validation - Headless Mode
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] This script will:
[INFO] 1. Create test files
[INFO] 2. Run Claude Code in headless mode (-p)
[INFO] 3. Send Read commands to trigger hooks
[INFO] 4. Verify hooks fired by checking evidence

CHECKING PREREQUISITES
======================
[PASS] Claude Code found: /usr/local/bin/claude
[INFO] Claude Code version: 0.2.45
[PASS] Found settings.json
[PASS] PreToolUse hook configured
[PASS] PostToolUse hook configured
[PASS] ImageMagick found

CREATING TEST FILES
===================
[INFO] Test directory: ./tests
[PASS] Created test-image.png (3000x3000 pixels)
[PASS] Created test-doc.txt

TEST 1: PreToolUse Hook (Image Processing)
=========================================
[INFO] Testing if PreToolUse hook fires when reading an image...
[INFO] This hook should resize the image to max 2000x2000
[INFO] Cleaned up previous resized images
[INFO] Reading image: /path/to/test-image.png
[INFO] Running: Read image file
[INFO] Command: echo 'Read /path/to/test-image.png' | claude -p
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

TEST 3: Combined Workflow
==========================
[INFO] Testing multiple operations to verify hooks fire consistently...
[INFO] Operation 1: Read text file
[INFO] Running: Read text file
[INFO] Command: echo 'Read /path/to/test-doc.txt' | claude -p
[PASS] PostToolUse fired for this operation
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 HOOK VALIDATION REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test Results:
  Tests Passed: 8
  Tests Failed: 0

Hook Execution Summary:

PreToolUse Hook (Image Processing):
  ✓ FIRED - Hook automatically resized image
  Evidence: /tmp/resized_test-image.png exists

PostToolUse Hook (Cache Keepalive):
  ✓ FIRED - Hook output cache_keepalive
  Evidence: cache_keepalive found in Claude output

Overall Verdict:
ALL HOOKS ARE WORKING

Both PreToolUse and PostToolUse hooks are firing automatically
when Claude Code processes files. The optimizations are active!
```

### Failure Case

```
TEST 1: PreToolUse Hook (Image Processing)
=========================================
...
[INFO] Checking for resized image in /tmp/...
[FAIL] PreToolUse hook did NOT fire - no resized image found
[INFO] Expected: /tmp/resized_*.png
[INFO] This means the hook didn't trigger when reading the image

TEST 2: PostToolUse Hook (Cache Keepalive)
===========================================
...
[INFO] Checking for cache_keepalive in Claude's output...
[FAIL] PostToolUse hook did NOT fire - no cache_keepalive in output
[INFO] Expected: JSON with cache_keepalive field

Overall Verdict:
HOOKS NOT FIRING

The hooks are not triggering automatically. Possible causes:
  • Claude Code wasn't restarted after installing hooks
  • Hooks aren't configured correctly in settings.json
  • Claude Code version doesn't support hooks
```

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
.\scripts\windows\validate.ps1 -Detailed
```

### `--keep` / `-Keep`

Preserves test files and results:
- `.validation-test/` → `tests/` - Test files
- `.validation-results/` → `tests/` - Claude output files

Allows manual inspection after the test.

## Artifacts

When using `--keep` / `-Keep`:

| Location | Contents |
|----------|----------|
| `tests/` | test-image.png, test-doc.txt |
| `tests/claude-output-image.txt` | Claude output from Read command |
| `tests/claude-output-ls.txt` | Claude output from ls command |
| `tests/claude-output-*.txt` | Other command outputs |

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

## Comparison with Other Validation Methods

| Method | Automation | Proof | Use Case |
|--------|-----------|-------|----------|
| `validate.sh` | ✓ Config only | Settings exist | Quick check |
| `validate.sh` | ✓ **Full** | **Actual proof** | **Automated validation** |

The headless validation is the only method that:
- Runs Claude Code automatically
- Triggers hooks without user interaction
- Provides concrete proof hooks fired
- Can be used in CI/CD pipelines
