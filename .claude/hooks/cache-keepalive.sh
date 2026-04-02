#!/usr/bin/env bash
#===============================================================================
# Claude Code Cache Keepalive Hook - PostToolUse
#===============================================================================
# Logs all tool usage for validation and debugging purposes.
# Non-blocking: always exits 0 to let Claude continue normally.
#
# Place in: ~/.claude/hooks/cache-keepalive.sh
# Make executable: chmod +x ~/.claude/hooks/cache-keepalive.sh
#===============================================================================

set -euo pipefail

# Configuration
DEBUG=${CLAUDE_HOOK_DEBUG:-1}              # Enable debug logging (default: 1 for validation)
VALIDATION_LOG="/tmp/hook-validation.log"
DEBUG_LOG="/tmp/claude-cache-keepalive.log"

# Logging function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [cache-keepalive] $*"
    if [[ "$DEBUG" == "1" ]]; then
        echo "$msg" >> "$DEBUG_LOG"
    fi
    # Always log to validation log for hook verification
    echo "$(date -Iseconds) | PostToolUse | $*" >> "$VALIDATION_LOG"
}

# Main execution
INPUT=$(cat)

# Gracefully handle invalid JSON
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}' 2>/dev/null) || TOOL_INPUT="{}"
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // {}' 2>/dev/null) || TOOL_RESPONSE="{}"

# Exit gracefully if we couldn't parse the input
if [[ -z "$TOOL_NAME" ]]; then
    log "PARSE_ERROR | Could not parse tool_name from input"
    exit 0
fi

# Extract additional details based on tool type
FILE_PATH=""
if [[ "$TOOL_NAME" == "Read" ]]; then
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.filePath // .file_path // empty' 2>/dev/null) || FILE_PATH=""
fi

# Log the tool execution
if [[ -n "$FILE_PATH" ]]; then
    log "FIRED | Tool: $TOOL_NAME | File: $FILE_PATH"
else
    log "FIRED | Tool: $TOOL_NAME"
fi

# Log raw input for detailed debugging (optional, can be noisy)
# log "RAW_INPUT | $INPUT"

# Always exit 0 - do not block the response
exit 0
