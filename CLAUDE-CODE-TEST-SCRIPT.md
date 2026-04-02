# Claude Code Optimizer Test Script

> **Usage**: Copy/paste these commands into Claude Code (Opencode) to test the optimizer installation.

---

## Quick Validation Tests

### Test 1: Check Environment Variables

Ask Claude:
```
What environment variables do you see for BASH_MAX_OUTPUT_LENGTH, DISABLE_TELEMETRY, and CLAUDE_CODE_AUTO_COMPACT_WINDOW?
```

**Expected**: Claude should report:
- `BASH_MAX_OUTPUT_LENGTH=10000`
- `DISABLE_TELEMETRY=1`
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000`
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70`
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`

---

### Test 2: Test Hook Logging (PreToolUse)

Ask Claude to read a simple text file:
```
Read the file at ~/.claude/CLAUDE.md
```

Then check the hook log:
```bash
Get-Content /tmp/claude-hook-validation.log -Tail 5
```

**Expected**: Log should show "PreToolUse | FILE | ~/.claude/CLAUDE.md"

---

### Test 3: Test File Guard (Sensitive File Protection)

Ask Claude to write to a protected file:
```
Write "test" to ~/.env
```

**Expected**: Claude should be blocked with message: "BLOCKED: '~/.env' matches protected pattern '\.env$'"

---

### Test 4: Test Image Processing (if ImageMagick installed)

If you have a test image:
```
Read the image at ~/test-image.png
```

**Expected**: 
- If image > 2000px or > 5MB: Image should be resized in-place
- Log should show "RESIZED" or "WITHIN_LIMITS"

---

### Test 5: Test PDF Conversion (if pdftotext/markitdown installed)

If you have a test PDF:
```
Read the PDF at ~/test-document.pdf
```

**Expected**: 
- Hook should intercept with exit code 2
- Claude should receive converted text content instead of binary

---

### Test 6: Test Post-Compaction Context Refresh

1. Start a conversation with Claude
2. Let context grow large (or manually trigger compaction)
3. After compaction, check if CLAUDE.md content is re-injected:
```
What are your compact instructions?
```

**Expected**: Claude should reference the compact instructions from ~/.claude/CLAUDE.md

---

### Test 7: Test Notification Hook

Trigger a notification (this happens automatically when Claude sends a notification message).

**Expected**: Windows balloon tip should appear with Claude Code notification.

---

## Settings.json Verification

Check the generated settings:

```bash
cat ~/.claude/settings.json | jq .
```

**Verify**:
- `$schema` is present
- `autoCompactEnabled: true`
- All 8 env vars are set
- Hooks are registered for PreToolUse, PostToolUse, Notification, SessionStart
- Hook commands use `bash ~/.claude/hooks/...` format (not PowerShell)

---

## Hook Files Verification

List hook files:

```bash
ls -la ~/.claude/hooks/
```

**Expected files**:
- `pretooluse.sh` (image resize + binary conversion)
- `posttooluse.sh` (validation logger)
- `file-guard.sh` (sensitive file protection)
- `notify.sh` (desktop notifications)
- `post-compact.sh` (context re-injection)

---

## CLAUDE.md Verification

Check the generated CLAUDE.md:

```bash
cat ~/.claude/CLAUDE.md
```

**Expected sections**:
- Cost-First Defaults
- File Reading Guidelines
- Compact Instructions

---

## Manual Hook Test (Bash)

Test the pretooluse hook manually:

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}' | bash ~/.claude/hooks/pretooluse.sh
echo "Exit code: $?"
```

**Expected**: Exit code 0, log entry created

---

## Troubleshooting

### Issue: Hooks not firing

1. Check if bash is available:
```bash
which bash
```

2. Check hook syntax:
```bash
bash -n ~/.claude/hooks/pretooluse.sh
```

3. Check settings.json path format:
```bash
cat ~/.claude/settings.json | grep -o 'bash ~/.claude/hooks/[a-z-]*\.sh'
```

### Issue: Environment variables not set

Check if Claude Code was restarted after running optimizer:
```bash
# Exit and restart Claude Code
exit
claude
```

### Issue: File guard not blocking

Test the file-guard hook manually:
```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/home/user/.env"}}' | bash ~/.claude/hooks/file-guard.sh 2>&1
echo "Exit code: $?"
```

**Expected**: "BLOCKED" message and exit code 2

---

## Full Test Suite (Automated)

Run all validation checks:

```powershell
# In PowerShell
& ~/.claude/optimizer/validate-optimizations.ps1
```

Or manually verify all items from the checklist above.

---

## Success Criteria

✅ All 15 validation checks pass  
✅ Environment variables visible to Claude  
✅ Hooks fire on Read/Write/Edit operations  
✅ File guard blocks sensitive paths  
✅ Images are resized when too large  
✅ PDFs/docs are converted to text  
✅ Notifications appear on Windows  
✅ Context re-injection works after compaction  

---

## Notes for Opencode Users

Since you're running on Opencode (not Claude Code directly):

1. **Environment variables** may not be visible in Opencode - they're set for Claude Code sessions
2. **Hooks** are configured for Claude Code's tool system, not Opencode
3. **Test by**: Starting a separate Claude Code session and running these tests there
4. **Settings location**: `~/.claude/settings.json` applies to all Claude Code sessions

To properly test, start Claude Code in a separate terminal:
```bash
claude
```

Then run the tests above within that session.
