#!/usr/bin/env bash
# bash-guard: Zero-trust security hook for Bash tool
# Blocks dangerous commands with fail-closed pattern

set -euo pipefail

trap 'echo "BLOCKED: bash-guard validation error (fail-closed)" >&2; exit 1' ERR

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
command_str="$(echo "$input" | jq -r '.tool_input.command // empty')"

[[ "$tool_name" != "Bash" || -z "$command_str" ]] && exit 0

# Dangerous command patterns
deny_patterns=(
  '^[[:space:]]*sudo\b'
  '\brm[[:space:]]+-rf[[:space:]]+/[[:space:]]*$'
  '\brm[[:space:]]+-rf[[:space:]]+/\*[[:space:]]*$'
  '\beval[[:space:]]+'
  '\bcurl[[:space:]]+.*\|.*\b(bash|sh)\b'
  '\bwget[[:space:]]+.*\|.*\b(bash|sh)\b'
  '\bcurl[[:space:]]+.*\|.*\b(bash|sh)[[:space:]]*-[[:space:]]*c\b'
  '[[:space:]]*>[[:space:]]*/dev/sda[[:space:]]*$'
  ':\(\)[[:space:]]*\{[[:space:]]*:\|:&[[:space:]]*\};[[:space:]]*:'
  '\bdd[[:space:]]+if=.*of=/dev/sd[a-z]'
  '\bmkfs\.[a-z]+[[:space:]]+/dev/sd[a-z][0-9]*'
  '\b>:\(\)\{[[:space:]]*:|:&[[:space:]]*\};[[:space:]]*:'
)

block() {
  local reason="$1"
  echo "BLOCKED: $reason" >&2
  exit 2
}

for pattern in "${deny_patterns[@]}"; do
  if echo "$command_str" | grep -qiE "$pattern"; then
    block "command matches dangerous pattern: $pattern"
  fi
done

exit 0
