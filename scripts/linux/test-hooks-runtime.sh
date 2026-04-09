#!/usr/bin/env bash
# Runtime hook verification (actual hook firing), not just config checks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_IMAGE="$REPO_DIR/tests/test-image.png"

FAILED=0

info() { echo "[INFO] $1"; }
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAILED=$((FAILED+1)); }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd claude
require_cmd jq
require_cmd sha256sum

[[ -f "$TEST_IMAGE" ]] || { echo "Missing test image: $TEST_IMAGE" >&2; exit 1; }

TMP1="/tmp/claude-hooks-read-$$.jsonl"
TMP2="/tmp/claude-hooks-bash-$$.jsonl"

cleanup() {
  rm -f "$TMP1" "$TMP2" /tmp/sha-before-$$ /tmp/sha-after-$$
}
trap cleanup EXIT

info "Test 1/3: SessionStart + PreToolUse + PostToolUse events on Read"
echo "Read $TEST_IMAGE" | claude -p \
  --verbose \
  --include-hook-events \
  --output-format stream-json \
  --allowedTools "Read" > "$TMP1" 2>&1 || true

HOOK_NAMES="$(jq -r 'select(.type=="system" and (.subtype|startswith("hook_"))) | .hook_name // empty' "$TMP1" 2>/dev/null || true)"
echo "$HOOK_NAMES" | grep -q "SessionStart" && pass "SessionStart hook fired" || fail "SessionStart hook did not fire"
echo "$HOOK_NAMES" | grep -q "PreToolUse" && pass "PreToolUse hook fired" || fail "PreToolUse hook did not fire"
echo "$HOOK_NAMES" | grep -q "PostToolUse" && pass "PostToolUse hook fired" || fail "PostToolUse hook did not fire"

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
