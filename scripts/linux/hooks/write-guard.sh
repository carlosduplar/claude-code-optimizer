#!/usr/bin/env bash
# write-guard: Secret detection for Write/Edit tools
# Blocks writes containing suspected secrets with fail-closed pattern

set -euo pipefail

trap 'echo "BLOCKED: write-guard validation error (fail-closed)" >&2; exit 1' ERR

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"

[[ "$tool_name" != "Write" && "$tool_name" != "Edit" && "$tool_name" != "MultiEdit" ]] && exit 0
[[ -z "$file_path" ]] && exit 0

# Allow safe files (examples, tests, fixtures)
allowed_patterns=(
  '\.env\.example$'
  '\.env\.sample$'
  '\.env\.template$'
  '\.env\.local\.example$'
  '\.test\.[a-z]+$'
  '\.spec\.[a-z]+$'
  '_test\.[a-z]+$'
  '_spec\.[a-z]+$'
  'test/'
  'tests/'
  '__tests__/'
  'fixtures/'
  'examples/'
  '\.md$'
)

for pattern in "${allowed_patterns[@]}"; do
  if echo "$file_path" | grep -qiE "$pattern"; then
    exit 0
  fi
done

# Get content for Write tool
content=""
if [[ "$tool_name" == "Write" ]]; then
  content="$(echo "$input" | jq -r '.tool_input.content // empty')"
fi

# For Edit tool, check the patch content
if [[ "$tool_name" == "Edit" || "$tool_name" == "MultiEdit" ]]; then
  content="$(echo "$input" | jq -r '.tool_input.oldString // .tool_input.newString // empty')"
fi

[[ -z "$content" ]] && exit 0

block() {
  local reason="$1"
  echo "BLOCKED: $reason" >&2
  echo "If this is intentional, write to .env.example or use placeholder values" >&2
  exit 2
}

# Check for secrets using simple grep (no complex regex)
check_patterns=(
  'api[_-]?key[[:space:]]*='
  'apikey[[:space:]]*='
  'secret[_-]?key[[:space:]]*='
  'secret[[:space:]]*='
  'password[[:space:]]*='
  'passwd[[:space:]]*='
  'auth[_-]?token[[:space:]]*='
  'access[_-]?token[[:space:]]*='
  'private[_-]?key[[:space:]]*='
  'database[_-]?url[[:space:]]*='
  'connection[_-]?string[[:space:]]*='
  'github[_-]?token[[:space:]]='
  'slack[_-]?token[[:space:]]='
  'AKIA[0-9A-Z]'
  'xox[baprs]-'
  'BEGIN.*PRIVATE KEY'
)

for pattern in "${check_patterns[@]}"; do
  if echo "$content" | grep -qiE "$pattern" 2>/dev/null; then
    block "suspected secret detected in write content (pattern: $pattern)"
  fi
done

# Check for values that look like secrets (high entropy after = sign)
if echo "$content" | grep -qiE '=[[:space:]]*["'"'"']?[a-zA-Z0-9_]{20,}["'"'"']?' 2>/dev/null; then
  # Verify it's not a common safe value
  safe_value='(true|false|null|undefined|example|placeholder|test|demo)'
  if ! echo "$content" | grep -qiE "=$safe_value" 2>/dev/null; then
    block "suspected secret value detected (high-entropy string after =)"
  fi
fi

exit 0
