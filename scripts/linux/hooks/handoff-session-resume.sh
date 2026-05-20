#!/usr/bin/env bash
# handoff-session-resume: Auto-inlines handoff-context.md on compact/resume
# Emits hookSpecificOutput with handoff content as additionalContext
# No Read-tool round trip needed

set -uo pipefail

input="$(cat)"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
[[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null || true

handoff_file="${cwd}/docs/handoff-context.md"

if [[ -f "$handoff_file" ]]; then
  content="$(cat "$handoff_file" 2>/dev/null || true)"
  if [[ -n "$content" ]]; then
    jq -n --arg ctx "Previous session handoff context:

$content" '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $ctx
      }
    }'
  fi
fi

exit 0
