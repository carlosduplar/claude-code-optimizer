# Adversarial Code Review Report: validate.sh

**Review Date:** 2026-04-07  
**Scope:** scripts/linux/validate.sh  
**Focus Areas:** WSL Path Conversion, Race Conditions, Error Handling, Concurrent Execution  
**Classification:** MEDIUM-HIGH RISK - Multiple stability and security issues identified

---

## 1. WSL Path Conversion Edge Cases

### 1.1 Hardcoded /tmp Paths (Lines 363, 381-382, 423, 459, 467, 474, 476)
**Severity: MEDIUM**

The script makes extensive assumptions about `/tmp` availability:

```bash
# Line 381-382
test_image="/tmp/validate-test.png"
local output_file="/tmp/claude-hook-test-$$.jsonl"
local hook_events_file="/tmp/claude-hooks-$$.txt"
```

**Issues:**
- WSL2 may not have `/tmp` mounted or it may be a bind mount with different permissions
- Windows Defender or enterprise policies may block execution from `/tmp`
- WSL path translation (`wslpath`) is not used when passing paths to Windows binaries
- If `claude` is a Windows executable (claude.exe), paths like `/tmp/file.txt` won't resolve

**Reproduction Scenario:**
```bash
# In WSL2 with Windows Claude installed
./validate.sh --test-hooks
# Claude.exe receives /tmp/claude-hook-test-12345.jsonl but cannot resolve Linux path
```

**Recommended Fix:**
```bash
# Use TMPDIR if set, fall back to temp directory with wslpath conversion
get_temp_dir() {
    local temp_dir="${TMPDIR:-/tmp}"
    # Validate temp_dir exists and is writable
    if [[ ! -d "$temp_dir" ]] || [[ ! -w "$temp_dir" ]]; then
        temp_dir="$REPO_DIR/.temp"
        mkdir -p "$temp_dir"
    fi
    echo "$temp_dir"
}

# When passing to potentially Windows binaries:
if [[ -n "$WSL_DISTRO_NAME" ]] && [[ "$CLAUDE_CMD" == *.exe ]]; then
    output_file=$(wslpath -w "$temp_dir/hook-test-$$.jsonl")
fi
```

---

## 2. Temporary File Race Conditions

### 2.1 PID-Based Filename Collisions (Lines 381-382)
**Severity: HIGH**

```bash
local output_file="/tmp/claude-hook-test-$$.jsonl"
local hook_events_file="/tmp/claude-hooks-$$.txt"
```

**Attack/Failure Scenarios:**

1. **Nested Execution Attack:**
   ```bash
   # Process $$ = 1234
   # Spawns subprocess that also runs validate.sh
   # Both use /tmp/claude-hook-test-1234.jsonl
   # Data corruption or information disclosure
   ```

2. **PID Reuse Race:**
   ```bash
   # Process A (PID 1234) creates /tmp/claude-hook-test-1234.jsonl
   # Process A exits, PID 1234 released
   # Process B gets PID 1234, runs validate.sh
   # Process A's cleanup (deferred) deletes Process B's file
   ```

3. **Symlink Attack (if run as root or via sudo):**
   ```bash
   # Attacker creates symlink: /tmp/claude-hook-test-1234.jsonl -> /etc/passwd
   # Script follows symlink, overwrites system file
   ```

**Evidence:**
- No `set -o noclobber` protection
- No `O_EXCL` flag equivalent in bash redirection
- Cleanup at line 440 is unconditional and could delete wrong files

**Recommended Fix:**
```bash
# Use mktemp for atomic file creation with unique names
output_file=$(mktemp "${temp_dir}/claude-hook-test.XXXXXX.jsonl")
hook_events_file=$(mktemp "${temp_dir}/claude-hooks.XXXXXX.txt")

# Set trap for guaranteed cleanup
cleanup() {
    rm -f "$output_file" "$hook_events_file" 2>/dev/null
}
trap cleanup EXIT INT TERM
```

### 2.2 Glob Pattern Collision (Line 424)
**Severity: MEDIUM**

```bash
if [[ "$resize_happened" -gt 0 ]] || ls /tmp/claude-resize-*.png 2>/dev/null | grep -q .; then
```

**Issue:**
- Matches files from OTHER Claude processes or previous runs
- If another user's process created `/tmp/claude-resize-99999.png`, this script may falsely report success
- TOCTOU (Time-of-Check-Time-of-Use) vulnerability between `ls` and `grep`

**Recommended Fix:**
```bash
# Check specific file instead of glob pattern
# Or use process-specific markers
resize_marker="${temp_dir}/.resize-done-$$"
touch "$resize_marker"
# Then check for marker instead of glob
```

---

## 3. Missing Error Handling

### 3.1 Silent Failures in Subshells (Lines 103, 273, 281-282, 400-403, 431)
**Severity: MEDIUM**

**Pattern:** Extensive use of `2>/dev/null` masks critical errors:

```bash
# Line 103 - Claude failure masked
local version=$($CLAUDE_CMD --version 2>&1 | head -1 || echo "unknown")

# Line 273 - grep failure masked
if grep -q '"autoCompactEnabled": true' "$claude_config" 2>/dev/null; then

# Line 400 - jq parse errors masked
jq -r 'select(.type == "system"...)' "$output_file" 2>/dev/null > "$hook_events_file"

# Line 402-403 - grep count failures masked
local pre_count=$(grep -c "PreToolUse" "$hook_events_file" 2>/dev/null || echo "0")
```

**Impact:**
- User sees "0 hooks fired" without knowing if it's because:
  - Hooks actually didn't fire, OR
  - jq failed to parse invalid JSON, OR
  - File was not created due to permissions

**Recommended Fix:**
```bash
# Use a pattern that captures and reports errors
safe_jq() {
    local result
    local jq_error
    result=$(jq "$@" 2>&1) || {
        jq_error="$?"
        print_error "jq failed with code $jq_error: ${result:0:100}"
        return $jq_error
    }
    echo "$result"
}
```

### 3.2 Directory Traversal Without Validation (Lines 11-12)
**Severity: LOW-MEDIUM**

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
```

**Issues:**
- If script is sourced (not executed), `${BASH_SOURCE[0]}` may not exist
- `cd` failure is not checked before `pwd`
- Directory may exist but not have read/execute permissions
- Symbolic link traversal may result in unexpected paths

**Reproduction:**
```bash
# From /nonexistent directory
source /some/path/validate.sh --test-hooks
# cd fails silently, pwd returns current (invalid) directory
```

**Recommended Fix:**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "ERROR: Cannot determine script directory" >&2
    exit 1
}
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)" || {
    echo "ERROR: Cannot determine repository directory" >&2
    exit 1
}
```

### 3.3 No Timeout on Headless Claude Execution (Lines 388-393)
**Severity: MEDIUM**

```bash
echo "Read $test_image" | "$CLAUDE_CMD" -p \
    --output-format stream-json \
    --verbose \
    --include-hook-events \
    --allowedTools "Read" \
    > "$output_file" 2>&1
```

**Issues:**
- No timeout - process could hang indefinitely on:
  - Network issues (API unreachable)
  - Interactive authentication prompts (browser required)
  - Rate limiting with exponential backoff
- Ctrl+C may leave temp files behind (no SIGINT trap until later)
- Zombie processes if Claude spawns children

**Recommended Fix:**
```bash
# Use timeout command (coreutils)
timeout_duration=60  # 60 seconds max
if ! command -v timeout >/dev/null 2>&1; then
    print_warning "timeout command not available, no timeout protection"
fi

echo "Read $test_image" | timeout "$timeout_duration" "$CLAUDE_CMD" -p ...
exit_code=$?

if [[ $exit_code -eq 124 ]]; then
    print_error "Claude test timed out after ${timeout_duration}s"
fi
```

### 3.4 Unvalidated wc Output (Line 42)
**Severity: LOW**

```bash
local chars=$(wc -c < "$file" 2>/dev/null || echo "0")
```

**Issue:**
- `wc -c` output may have leading spaces on some systems
- Arithmetic expansion `$((chars / 4))` could fail with non-numeric input

**Evidence:**
```bash
$ chars=$(wc -c < /etc/passwd); echo "[$chars]"
[  2643]  # leading spaces!
```

**Recommended Fix:**
```bash
local chars=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
```

### 3.5 Unsafe Array Parsing with IFS (Lines 171, 214, 237)
**Severity: MEDIUM**

```bash
IFS=':' read -r var_name expected description <<< "$var_info"
```

**Issues:**
- `description` field containing colons will be truncated
- No validation that all 3 fields were actually read
- `<<<` creates temp file which may fail on read-only filesystems

**Evidence of Bug:**
```bash
# If description contains a colon:
"CLAUDE_VAR:1:Some:Description"  
# description will be "Some", not "Some:Description"
```

**Recommended Fix:**
```bash
# Use only 2 delimiters, preserve rest as description
IFS=':' read -r var_name expected rest <<< "$var_info"
description="$rest"  # Everything after second colon preserved

# Or use different delimiter unlikely to appear
IFS=$'\x1F' read -r var_name expected description <<< "$var_info"
```

---

## 4. Concurrent Execution Issues

### 4.1 Non-Atomic Test Counter Operations (Lines 18, 33-35)
**Severity: HIGH**

```bash
# Line 18 - Global counters
TESTS_PASSED=0; TESTS_FAILED=0; TESTS_SKIPPED=0

# Lines 33-35 - Non-atomic increments
print_success() { ((TESTS_PASSED++)); }
print_error() { ((TESTS_FAILED++)); }
print_warning() { ((TESTS_SKIPPED++)); }
```

**Issues:**
- If `validate.sh` is run in parallel (e.g., in subshells or background jobs), counters will be corrupted
- Bash arithmetic `((var++))` is not atomic across processes
- Race condition between read-modify-write operations

**Reproduction:**
```bash
# Terminal 1
./validate.sh &
# Terminal 2
./validate.sh &
# Wait - counters will be wrong in final report
```

**Recommended Fix:**
```bash
# For parallel safety, use file-based counters or flock
# Or simply warn that script is not parallel-safe:
validate_single_instance() {
    local lock_file="${temp_dir}/.validate-lock"
    if ! mkdir "$lock_file" 2>/dev/null; then
        echo "ERROR: Another instance is already running" >&2
        exit 1
    fi
    trap 'rmdir "$lock_file" 2>/dev/null; exit' EXIT
}
```

### 4.2 Shared Log File Conflicts (Line 423)
**Severity: MEDIUM**

```bash
local resize_happened=$(grep -c "RESIZED" /tmp/claude-hook-validation.log 2>/dev/null || echo "0")
```

**Issues:**
- All instances write to same `/tmp/claude-hook-validation.log`
- One instance reads another instance's "RESIZED" entries
- Log file may be rotated or deleted mid-execution

---

## 5. Additional Security and Stability Issues

### 5.1 Command Injection via Unquoted Variables (Lines 171, 214, 237)
**Severity: LOW (context-dependent)**

```bash
IFS=':' read -r var_name expected description <<< "$var_info"
local actual="${!var_name}"
```

**Issue:**
- If `var_name` contains special characters from environment, `${!var_name}` may evaluate unexpectedly
- While `var_name` is controlled by script author, this pattern is risky if arrays ever come from user input

### 5.2 Incomplete Cleanup (Line 440)
**Severity: LOW**

```bash
rm -f "$output_file" "$hook_events_file"
```

**Issues:**
- No verification that files were actually deleted
- If files were created as symlinks to other locations, this could delete unintended files
- Created test image at line 363 is NOT cleaned up: `test_image="/tmp/validate-test.png"`

### 5.3 No Validation of Test Image Creation (Lines 365, 370)
**Severity: LOW**

```bash
magick -size 2500x2500 xc:blue "$test_image" 2>/dev/null || { ... }
```

**Issues:**
- Success is assumed if command returns 0
- No validation that file actually exists and is non-empty
- Image could be corrupted but still "exist"

---

## 6. Summary and Recommendations

### Critical Fixes Required:

1. **Replace all PID-based temp files with `mktemp`**
2. **Add trap-based cleanup** for guaranteed resource release
3. **Add timeout protection** to headless Claude execution
4. **Implement single-instance locking** to prevent parallel execution corruption

### High Priority Fixes:

5. **Validate all `cd` operations** before using `pwd`
6. **Add WSL path conversion** when interacting with Windows binaries
7. **Remove or qualify `2>/dev/null` masks** - at minimum log errors in verbose mode
8. **Fix IFS parsing** to handle colons in description fields

### Medium Priority Fixes:

9. **Add file existence and readability checks** before operations
10. **Implement proper error propagation** from subshells
11. **Add wc output sanitization**
12. **Clean up all created temp files** including test images

### Estimated Risk Score: 6.5/10

The script will generally work in controlled environments but has multiple failure modes in:
- Enterprise/WSL environments
- Multi-user systems
- Parallel execution scenarios
- Resource-constrained environments

---

## Appendix: Specific Line References

| Line(s) | Issue | Severity |
|---------|-------|----------|
| 11-12 | Unvalidated directory traversal | MEDIUM |
| 18, 33-35 | Non-atomic global counters | HIGH |
| 42 | Unsanitized wc output | LOW |
| 103 | Silent failure on Claude version check | MEDIUM |
| 171, 214, 237 | Unsafe IFS parsing | MEDIUM |
| 273, 281-282 | Silent grep failures | LOW |
| 363 | Hardcoded /tmp path, no cleanup | MEDIUM |
| 365, 370 | Unvalidated image creation | LOW |
| 381-382 | PID-based temp files (race condition) | HIGH |
| 388-393 | No timeout on headless execution | MEDIUM |
| 400-403 | Silent jq/grep failures | MEDIUM |
| 423 | Shared log file access | MEDIUM |
| 424 | Glob pattern collision | MEDIUM |
| 440 | Incomplete cleanup | LOW |
| 459, 467, 474, 476 | Hardcoded /tmp assumptions | MEDIUM |

---

*Report generated by manual adversarial review without skill assistance.*
