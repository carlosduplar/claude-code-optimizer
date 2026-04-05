#!/bin/bash
#
# Claude Code Prompt Cache Keepalive Script
# Prevents 5-minute cache TTL expiration by sending periodic no-op messages
#
# Usage: ./claude-keepalive.sh [session-name] &
#   Run in background while Claude Code is active
#
# The Anthropic API has a 5-minute TTL on prompt cache entries.
# After 5 minutes of inactivity, cache is evicted and costs increase 10x.
# For 200K context: $0.60 → $6.00 per request
#
# Note: This script is optional. The PostToolUse hook in .claude/settings.json
# already handles cache keepalive automatically.
#

SESSION_NAME="${1:-claude}"
INTERVAL=240  # 4 minutes (safely under 5min TTL)
KEEPALIVE_MSG="# keepalive $(date +%s)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[Keepalive]${NC} Starting keepalive for session: $SESSION_NAME"
echo -e "${GREEN}[Keepalive]${NC} Interval: ${INTERVAL}s (4 minutes)"
echo -e "${YELLOW}[Keepalive]${NC} Press Ctrl+C to stop"

# Function to send keepalive via tmux
send_tmux_keepalive() {
    local session="$1"
    if tmux has-session -t "$session" 2>/dev/null; then
        # Send a comment (no-op) to keep session warm
        tmux send-keys -t "$session" "$KEEPALIVE_MSG" Enter
        sleep 0.5
        # Clear it with Ctrl+C so it doesn't accumulate
        tmux send-keys -t "$session" C-c
        echo -e "${GREEN}[Keepalive]${NC} $(date '+%H:%M:%S') - Sent keepalive to tmux session: $session"
        return 0
    fi
    return 1
}

# Function to send keepalive via AppleScript (macOS GUI)
send_macos_keepalive() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Try to find iTerm2 or Terminal with Claude
        local term_app=""
        if osascript -e 'tell application "iTerm2" to return name of front window' 2>/dev/null | grep -q "claude\|Claude"; then
            term_app="iTerm2"
        elif osascript -e 'tell application "Terminal" to return name of front window' 2>/dev/null | grep -q "claude\|Claude"; then
            term_app="Terminal"
        fi

        if [[ -n "$term_app" ]]; then
            osascript << APPLESCRIPT 2>/dev/null
tell application "$term_app"
    activate
    tell application "System Events" to keystroke "# keepalive"
    tell application "System Events" to key code 36
    delay 0.5
    tell application "System Events" to key code 53
end tell
APPLESCRIPT
            echo -e "${GREEN}[Keepalive]${NC} $(date '+%H:%M:%S') - Sent keepalive to $term_app"
            return 0
        fi
    fi
    return 1
}

# Main keepalive loop
cleanup() {
    echo -e "\n${YELLOW}[Keepalive]${NC} Stopping keepalive script"
    exit 0
}

trap cleanup INT TERM

while true; do
    # Try tmux first, then fall back to macOS GUI methods
    if ! send_tmux_keepalive "$SESSION_NAME"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            send_macos_keepalive
        fi
    fi

    sleep $INTERVAL
done
