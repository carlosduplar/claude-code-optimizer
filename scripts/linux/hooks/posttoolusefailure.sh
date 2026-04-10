#!/usr/bin/env bash
# PostToolUseFailure: Log errors with 1MB rotation
set -euo pipefail

LOG_DIR="${HOME}/.claude/logs/errors"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/${DATE}.log"

# Rotate if > 1MB
if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 1048576 ]]; then
  mv "$LOG_FILE" "${LOG_DIR}/${DATE}-1.log"
fi

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
error="$(echo "$input" | jq -r '.error // empty')"

TIMESTAMP=$(date -Iseconds)
echo "[${TIMESTAMP}] [${tool_name}] ${error}" >> "$LOG_FILE"

exit 0
