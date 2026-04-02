#!/usr/bin/env bash
# PostToolUse Hook - Tool usage logger
# Claude Code pipes a JSON payload to stdin, e.g.:
#   {"session_id":"...","tool_name":"Bash","tool_input":{...},"tool_response":{...}}

# Read JSON from stdin
INPUT=$(cat)

# Extract tool name using jq (tool_name is at top level, not nested)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL=""

echo "$(date -Iseconds) | PostToolUse | FIRED | Tool: ${TOOL:-unknown}" >> /tmp/hook-validation.log

# Exit 0 - do not block the response
exit 0
