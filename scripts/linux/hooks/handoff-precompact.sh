#!/usr/bin/env bash
# handoff-precompact: Synthesizes structured handoff context before compaction
# Uses claude -p --bare to avoid nested hook cascade
# Always exits 0 so compact proceeds regardless of outcome

set -uo pipefail

input="$(cat)"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
transcript_path="$(echo "$input" | jq -r '.transcript_path // empty')"

[[ -z "$cwd" ]] && cwd="$PWD"
handoff_file="${cwd}/docs/handoff-context.md"

timeout_seconds=60
fallback_max_bytes=50000

write_handoff() {
  mkdir -p "${cwd}/docs"
  echo "$1" > "$handoff_file"
}

write_fallback() {
  local tail=""
  if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    tail="$(tail -c "$fallback_max_bytes" "$transcript_path" 2>/dev/null || true)"
  fi
  write_handoff "# HANDOFF_AUTO_PARTIAL

Handoff synthesis failed. Raw transcript tail:

\`\`\`
${tail}
\`\`\`"
}

if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
  exit 0
fi

tail_text="$(tail -c "$fallback_maxBytes" "$transcript_path" 2>/dev/null || tail -c 50000 "$transcript_path" 2>/dev/null || true)"

prompt="You are synthesizing a handoff context summary from a Claude Code session transcript.
Extract the following information as a structured Markdown document.
If a field cannot be determined, write \"Unknown\".

Format the output as Markdown with these sections:

## Session Started
ISO 8601 timestamp from transcript.

## Task
One sentence overall goal.

## Completed Tasks
Bullet list of concrete thing finished.

## Current State
In-flight work, files modified, what works/broken.

## Constraints
Bullet list of user rules, ruled-out approaches and why.

## Files Touched
Table: path | status (created/modified/deleted) | summary

## Issues Discovered
Bullet list of bugs/gotchas and workarounds.

## Open Questions
Bullet list of unresolved decisions.

## Next Steps
Numbered ordered list of specific actions. next_steps[0] = literally first action.

## Resume Prompt
One paragraph a user can paste into a fresh session to continue.

Transcript tail (last 50KB):
${tail_text}"

export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1
export CLAUDE_CODE_DISABLE_POLICY_SKILLS=1

result="$(timeout "$timeout_seconds" claude -p --bare --model claude-sonnet-4-6 "$prompt" 2>/dev/null || true)"

if [[ -n "$result" && "${#result}" -gt 10 ]]; then
  write_handoff "$result"
else
  write_fallback
fi

exit 0
