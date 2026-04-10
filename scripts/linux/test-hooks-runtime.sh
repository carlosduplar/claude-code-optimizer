#!/usr/bin/env bash
# Runtime hook verification (actual hook firing), not just config checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_IMAGE="$REPO_DIR/tests/test-image.png"
SETTINGS_FILE="$HOME/.claude/settings.json"

FAILED=0

info() { echo "[INFO] $1"; }
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAILED=$((FAILED+1)); }
warn() { echo "[WARN] $1"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd claude
require_cmd jq
require_cmd sha256sum

[[ -f "$TEST_IMAGE" ]] || { echo "Missing test image: $TEST_IMAGE" >&2; exit 1; }
[[ -f "$SETTINGS_FILE" ]] || { echo "Missing settings file: $SETTINGS_FILE" >&2; exit 1; }

TMP1="/tmp/claude-hooks-read-$$.jsonl"
TMP2="/tmp/claude-hooks-bash-$$.jsonl"

EXPECT_SESSIONSTART="$(jq -r '.hooks | has("SessionStart")' "$SETTINGS_FILE" 2>/dev/null || echo false)"
EXPECT_POSTTOOLUSE="$(jq -r '.hooks | has("PostToolUse")' "$SETTINGS_FILE" 2>/dev/null || echo false)"

cleanup() {
  rm -f "$TMP1" "$TMP2" /tmp/sha-before-$$ /tmp/sha-after-$$
}
trap cleanup EXIT

info "Test 1/3: SessionStart + PreToolUse events on Read"
echo "Read $TEST_IMAGE" | claude -p \
  --verbose \
  --include-hook-events \
  --output-format stream-json \
  --allowedTools "Read" > "$TMP1" 2>&1 || true

HOOK_NAMES="$(
  {
    jq -r 'select(.type=="system" and (.subtype|startswith("hook_"))) | .hook_name // empty' "$TMP1" 2>/dev/null || true
    grep -Eo '\b(SessionStart|PreToolUse|PostToolUse)\b' "$TMP1" 2>/dev/null || true
  } | sort -u
)"
echo "$HOOK_NAMES" | grep -q "PreToolUse" && pass "PreToolUse hook fired" || fail "PreToolUse hook did not fire"
if [[ "$EXPECT_SESSIONSTART" == "true" ]]; then
  if echo "$HOOK_NAMES" | grep -q "SessionStart" || grep -q "Keepalive reminder:" "$TMP1"; then
    pass "SessionStart hook observed"
  else
    warn "SessionStart not observed in non-interactive run (startup/resume matcher may not trigger with -p)"
  fi
else
  warn "SessionStart hook not configured; skipped"
fi
if [[ "$EXPECT_POSTTOOLUSE" == "true" ]]; then
  warn "PostToolUse configured but not actively exercised by this script (requires write/edit flow)"
else
  warn "PostToolUse hook not configured; skipped"
fi

info "Test 2/3: Read hook is non-mutating for original image"
sha256sum "$TEST_IMAGE" > /tmp/sha-before-$$
echo "Read $TEST_IMAGE" | claude -p --allowedTools "Read" >/dev/null 2>&1 || true
sha256sum "$TEST_IMAGE" > /tmp/sha-after-$$
if diff -q /tmp/sha-before-$$ /tmp/sha-after-$$ >/dev/null 2>&1; then
  pass "Original file hash unchanged"
else
  fail "Original file hash changed (Read hook appears mutating)"
fi

info "Test 3/3: file-guard blocks high-risk traversal path"
echo "Run this exact command: cat ../.env" | claude -p \
  --verbose \
  --include-hook-events \
  --output-format stream-json \
  --allowedTools "Bash" > "$TMP2" 2>&1 || true

if grep -qi "BLOCKED:" "$TMP2"; then
  pass "file-guard blocked traversal command"
else
  fail "file-guard did not block traversal command"
fi

if [[ $FAILED -gt 0 ]]; then
  echo "Runtime hook tests failed: $FAILED check(s) failed."
  exit 1
fi

echo "Runtime hook tests passed."
