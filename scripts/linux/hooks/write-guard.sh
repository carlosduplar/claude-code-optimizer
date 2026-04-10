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

# For Edit tool, we'd need to read the old file and apply patches
# This is a simplified check that only validates the patch content
if [[ "$tool_name" == "Edit" || "$tool_name" == "MultiEdit" ]]; then
  # Check edit-related fields for potential secrets
  content="$(echo "$input" | jq -r '.tool_input.oldString // .tool_input.newString // empty')"
fi

[[ -z "$content" ]] && exit 0

# Secret detection patterns
secret_patterns=(
  '(?i)password\s*=\s*["'\'''][^"'\''"\n]{4,}["'\''']'
  '(?i)passwd\s*=\s*["'\'''][^"'\''"\n]{4,}["'\''']'
  '(?i)api[_-]?key\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)apikey\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)secret[_-]?key\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)secret\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)auth[_-]?token\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)access[_-]?token\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)token\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)private[_-]?key\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'
  '(?i)aws[_-]?access[_-]?key[_-]?id\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)aws[_-]?secret[_-]?access[_-]?key\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  'AKIA[0-9A-Z]{16}'
  '(?i)github[_-]?token\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)slack[_-]?token\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  'xox[baprs]-[0-9a-zA-Z]{10,48}'
  '(?i)database[_-]?url\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
  '(?i)connection[_-]?string\s*=\s*["'\'''][^"'\''"\n]{8,}["'\''']'
)

block() {
  local reason="$1"
  echo "BLOCKED: $reason" >&2
  echo "If this is intentional, write to .env.example or use placeholder values" >&2
  exit 2
}

for pattern in "${secret_patterns[@]}"; do
  if echo "$content" | grep -qiP "$pattern" 2>/dev/null; then
    block "suspected secret detected in write content (pattern: credential)"
  fi
done

exit 0
