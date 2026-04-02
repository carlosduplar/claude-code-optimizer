# Claude Code Hook Execution Monitor

This tool verifies that **Claude Code itself** is actually triggering the optimization hooks automatically during normal operation.

## The Problem

The configuration validation scripts check:
- ✓ Hooks are defined in `settings.json`
- ✓ Commands are valid
- ✓ Dependencies are installed

But they **don't verify**:
- ✗ Whether Claude Code actually fires the hooks
- ✗ Whether the hooks trigger without user prompting
- ✗ Whether the automation is actually working

## The Solution

The Hook Execution Monitor:
1. **Creates test files** (images, PDFs) that should trigger hooks
2. **You use Claude Code normally** (read a test file)
3. **Verifies execution** by checking for output files/clues

## Prerequisites

**You must run `optimize-claude.ps1` (Windows) or `optimize-claude.sh` (Linux/macOS) first!**

The monitor does NOT install hooks - it only verifies that existing hooks are firing.

## Quick Start

### Linux / macOS / WSL

```bash
# 1. First, ensure hooks are installed (run this if you haven't already)
./optimize-claude.sh

# 2. Restart Claude Code completely (close and reopen)

# 3. Create test files
./monitor-hooks.sh --test

# 4. In Claude Code, read a test file:
Read .hook-test-files/test-image.png

# 5. Check if the hook fired (look for resized image)
ls -la /tmp/resized_*.png

# 6. Clean up when done
./monitor-hooks.sh --reset
```

### Windows

```powershell
# 1. First, ensure hooks are installed (run this if you haven't already)
.\optimize-claude.ps1

# 2. Restart Claude Code completely (close and reopen)

# 3. Create test files
.\monitor-hooks.ps1 -Test

# 4. In Claude Code, read a test file:
Read .hook-test-files\test-image.png

# 5. Check if the hook fired (look for resized image)
Get-ChildItem $env:TEMP\resized_*.png

# 6. Clean up when done
.\monitor-hooks.ps1 -Reset
```

## How It Works

### The Hooks (Already Installed by optimize-claude.ps1)

**PreToolUse Hook (Image Processing):**
```json
{
  "type": "command",
  "command": "magick ... -resize 2000x2000 ... /tmp/resized_...",
  "if": "Read(*.{png,jpg,jpeg})"
}
```

**PostToolUse Hook (Cache Keepalive):**
```json
{
  "type": "command",
  "command": "echo '{\"cache_keepalive\": ...}'",
  "if": "*"
}
```

### Verification Methods

#### Method 1: Check for Resized Image (PreToolUse)

When you read an image in Claude Code, the PreToolUse hook should automatically resize it and save to temp:

**Linux/macOS:**
```bash
ls -la /tmp/resized_*.png
```

**Windows:**
```powershell
Get-ChildItem $env:TEMP\resized_*.png
```

**If you see a file like `/tmp/resized_test-image.png`, the hook fired!**

#### Method 2: Check Claude Code Output (PostToolUse)

The PostToolUse hook outputs JSON after every tool use. In Claude Code, run any command:

```
ls
```

Look for output like:
```json
{"cache_keepalive": "1705312202"}
```

**If you see this JSON output, the PostToolUse hook fired!**

#### Method 3: Check Hook Configuration

Run the verify command to see hook details:

```bash
./monitor-hooks.sh --verify
```

This shows:
- Whether hooks are configured in settings.json
- What commands the hooks run
- How to test them

## Commands

### `--test` / `-Test`

Creates test files and shows detailed testing instructions.

**Creates:**
- `test-image.png` (3000x3000 pixels - triggers PreToolUse)
- `test-document.pdf` (for PDF testing)
- `test-document.txt` (text file)

**Output:**
```
[INFO] Test files directory: ./.hook-test-files
[PASS] Created test-image.png (3000x3000 pixels)
[PASS] Created test-document.pdf
[PASS] Created test-document.txt

To verify hooks are triggered by Claude Code:

1. Ensure hooks are installed:
   Run optimize-claude.sh first

2. Restart Claude Code completely

3. Test PreToolUse hook (image processing):
   In Claude Code, run:
   Read .hook-test-files/test-image.png

4. Verify PreToolUse hook fired:
   ls -la /tmp/resized_*.png

   If you see /tmp/resized_test-image.png, the hook worked!
```

### `--verify` / `-Verify`

Checks if hooks are configured and shows verification methods.

**Output:**
```
[PASS] Found settings.json
[PASS] PreToolUse hook is configured
[PASS] Image resize command found in PreToolUse hook
[PASS] PostToolUse hook is configured
[PASS] Cache keepalive command found in PostToolUse hook

Verification Methods:

Method 1: Check for Resized Image
The PreToolUse hook should create resized images in /tmp/

Check for resized files:
  ls -la /tmp/resized_*.png

[PASS] Found 2 resized file(s) in /tmp/
  /tmp/resized_test-image.png
  /tmp/resized_screenshot.png
```

### `--reset` / `-Reset`

Cleans up test files and resized images.

**Removes:**
- `.hook-test-files/` directory
- `/tmp/resized_*.png` files

**Does NOT remove:**
- The hooks in `.claude/settings.json`
- Your configuration

## Testing Workflow

### Test 1: PreToolUse Hook (Image Processing)

**What it tests:** Whether Claude Code automatically resizes images before processing them.

**Steps:**
1. Ensure hooks are installed (`optimize-claude.sh` or `optimize-claude.ps1`)
2. Restart Claude Code
3. Create test files: `./monitor-hooks.sh --test`
4. In Claude Code, run:
   ```
   Read .hook-test-files/test-image.png
   ```
5. Immediately check for resized image:
   ```bash
   ls -la /tmp/resized_*.png
   ```

**Expected Results:**
- File `/tmp/resized_test-image.png` exists
- File is smaller than original (resized to max 2000x2000)

### Test 2: PostToolUse Hook (Cache Keepalive)

**What it tests:** Whether Claude Code fires the keepalive hook after every tool use.

**Steps:**
1. Ensure hooks are installed
2. In Claude Code, run any command:
   ```
   ls
   pwd
   echo "test"
   ```
3. Watch Claude Code's output for JSON with `cache_keepalive`

**Expected Results:**
- You see output like: `{"cache_keepalive": "1705312202"}`
- This appears after every tool use

### Test 3: Combined Workflow

**What it tests:** Real-world usage with multiple files.

**Steps:**
1. Ensure hooks are installed
2. Restart Claude Code
3. Create test files: `./monitor-hooks.sh --test`
4. In Claude Code, run:
   ```
   Read .hook-test-files/test-image.png
   Read .hook-test-files/test-document.txt
   ls
   ```
5. Check for multiple resized files and cache_keepalive outputs

**Expected Results:**
- PreToolUse fires for image file
- PostToolUse fires after every Read and ls
- Multiple resized files in /tmp/

## Interpreting Results

### Success Indicators

✓ **Resized image exists** - PreToolUse hook fired and processed image
✓ **cache_keepalive JSON appears** - PostToolUse hook firing after tool use
✓ **Multiple files** - Hooks fire consistently, not just once

### Failure Indicators

✗ **No resized files** - PreToolUse hook didn't fire
✗ **No cache_keepalive output** - PostToolUse hook not firing
✗ **Original image processed** - Hook fired but resize failed

## Troubleshooting

### No Resized Files Created

**Cause:** PreToolUse hook isn't firing or image processing failed

**Solutions:**
1. Verify hooks are installed:
   ```bash
   cat .claude/settings.json | grep -A5 "PreToolUse"
   ```
2. Ensure you restarted Claude Code after installing hooks
3. Check ImageMagick is installed:
   ```bash
   which magick || which convert
   ```
4. Try reading the test file again

### No cache_keepalive Output

**Cause:** PostToolUse hook isn't firing

**Solutions:**
1. Run multiple commands in Claude Code
2. Check the hook is configured:
   ```bash
   cat .claude/settings.json | grep -A5 "PostToolUse"
   ```
3. Look carefully at Claude Code's output - it may be subtle

### Hooks Not Configured

**Cause:** optimize-claude.ps1/sh wasn't run

**Solution:**
```bash
# Run the optimizer first
./optimize-claude.sh

# Then restart Claude Code
# Then test with monitor-hooks.sh
```

## Files Created

| File/Directory | Purpose | Cleanup |
|----------------|---------|---------|
| `.hook-test-files/` | Test files (image, PDF, text) | `--reset` removes this |
| `/tmp/resized_*.png` | Resized images from hooks | `--reset` removes this |

## Safety

- **Non-destructive:** Only creates test files and checks outputs
- **Reversible:** `--reset` cleans up everything
- **Isolated:** Test files are in dedicated directory
- **Transparent:** All verification is visible

## Integration with Other Tests

Use this monitor **after** running the configuration validation:

```bash
# 1. Validate configuration
./validate-optimizations.sh

# 2. Ensure hooks are installed
./optimize-claude.sh

# 3. Restart Claude Code

# 4. Test that hooks actually fire
./monitor-hooks.sh --test
# (follow instructions to test in Claude Code)

# 5. Verify execution
./monitor-hooks.sh --verify

# 6. Cleanup
./monitor-hooks.sh --reset
```

This gives you:
- ✓ Configuration is correct
- ✓ Dependencies are installed
- ✓ **Hooks actually fire automatically when Claude Code runs**
