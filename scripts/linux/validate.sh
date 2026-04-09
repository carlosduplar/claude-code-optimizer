#!/usr/bin/env bash
# Validate optimizer state from ~/.claude/settings.json only.

set -euo pipefail

PROFILE=""
PRIVACY=""
EXPECT_UNSAFE=false
EXPECT_UNSAFE_SET=false

SETTINGS_FILE="${HOME}/.claude/settings.json"
FAILED=0

info() { echo "[INFO] $1"; }
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAILED=$((FAILED+1)); }

usage() {
  cat <<'EOF'
Usage: validate.sh [options]

Options:
  --profile official|tuned   Validate expected profile behavior
  --privacy standard|max     Validate expected privacy behavior
  --expect-unsafe            Assert unsafe high-risk Bash patterns are present
  --help                     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --privacy) PRIVACY="$2"; shift 2 ;;
    --expect-unsafe) EXPECT_UNSAFE=true; EXPECT_UNSAFE_SET=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -f "$SETTINGS_FILE" ]] || { echo "Missing $SETTINGS_FILE" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

TMP_REPORT="/tmp/claude-optimizer-validate-$$.json"
python3 - <<PY > "$TMP_REPORT"
import json
from pathlib import Path
s = json.loads(Path(r"$SETTINGS_FILE").read_text(encoding="utf-8"))
out = {
  "schema": "\$schema" in s,
  "env_is_object": isinstance(s.get("env"), dict),
  "hooks_pretooluse": isinstance(s.get("hooks", {}).get("PreToolUse"), list),
  "hooks_sessionstart": isinstance(s.get("hooks", {}).get("SessionStart"), list),
  "permissions_deny": isinstance(s.get("permissions", {}).get("deny"), list),
  "allow_present": isinstance(s.get("permissions", {}).get("allow"), list) and len(s.get("permissions", {}).get("allow")) > 0,
  "has_disable_telemetry": str(s.get("env", {}).get("DISABLE_TELEMETRY", "")) == "1",
  "has_max_privacy_flag": str(s.get("env", {}).get("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "")) == "1",
  "has_tuned_key": "CLAUDE_CODE_DISABLE_AUTO_MEMORY" in s.get("env", {}),
  "pretooluse_command": json.dumps(s.get("hooks", {}).get("PreToolUse", [])),
}
allow = s.get("permissions", {}).get("allow", []) if isinstance(s.get("permissions", {}).get("allow", []), list) else []
unsafe_markers = ["Bash(cat *)", "Bash(head *)", "Bash(tail *)", "Bash(find *)", "Bash(grep *)", "Bash(rg *)", "Bash(git show*)", "Bash(git remote*)", "Bash(git config*)", "Bash(npm run*)"]
out["unsafe_patterns_present"] = any(m in allow for m in unsafe_markers)
print(json.dumps(out))
PY

check_json_bool() {
  local key="$1"
  local expected="${2:-true}"
  local val
  val="$(python3 - <<PY
import json
d=json.load(open(r"$TMP_REPORT","r",encoding="utf-8"))
print(str(d.get("$key")).lower())
PY
)"
  if [[ "$val" == "$expected" ]]; then pass "$key"; else fail "$key (expected $expected got $val)"; fi
}

check_json_bool "schema"
check_json_bool "env_is_object"
check_json_bool "hooks_pretooluse"
check_json_bool "hooks_sessionstart"
check_json_bool "permissions_deny"
check_json_bool "has_disable_telemetry"

if [[ -n "$PRIVACY" ]]; then
  if [[ "$PRIVACY" == "max" ]]; then
    check_json_bool "has_max_privacy_flag"
  else
    check_json_bool "has_max_privacy_flag" "false"
  fi
fi

if [[ -n "$PROFILE" ]]; then
  if [[ "$PROFILE" == "tuned" ]]; then
    check_json_bool "has_tuned_key"
  else
    check_json_bool "has_tuned_key" "false"
  fi
fi

check_json_bool "allow_present"

if $EXPECT_UNSAFE_SET; then
  if $EXPECT_UNSAFE; then
    check_json_bool "unsafe_patterns_present"
  else
    check_json_bool "unsafe_patterns_present" "false"
  fi
else
  info "unsafe_patterns_present=$(python3 - <<PY
import json
d=json.load(open(r\"$TMP_REPORT\",\"r\",encoding=\"utf-8\"))
print(str(d.get(\"unsafe_patterns_present\")).lower())
PY
) (not enforced; pass --expect-unsafe to enforce)"
fi

# Ensure non-mutating read hook path is configured (updatedInput behavior exists in hook script command target).
HOOKS_JSON="$(python3 - <<PY
import json
d=json.load(open(r"$TMP_REPORT","r",encoding="utf-8"))
print(d["pretooluse_command"])
PY
)"
if echo "$HOOKS_JSON" | grep -qi "pretooluse"; then
  pass "pretooluse hook configured"
else
  fail "pretooluse hook configured"
fi

rm -f "$TMP_REPORT"

if [[ $FAILED -gt 0 ]]; then
  echo "Validation failed: $FAILED checks failed."
  exit 1
fi

echo "Validation passed."
