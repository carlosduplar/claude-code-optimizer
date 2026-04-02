# IMPLEMENTATION PLAN

## What you've built vs. what the source reveals

**What's already solid in your optimizer:**

Image resizing (PreToolUse, ImageMagick), `autoCompactEnabled`, the privacy env vars cluster (`DISABLE_TELEMETRY`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `OTEL_LOG_*`), `CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000`, and the manual binary-to-markdown preprocessing scripts. The PostToolUse hook fires correctly but is currently just a logger — more on that below.

**What the fork reveals that you're missing:**

---

### 1. `BASH_MAX_OUTPUT_LENGTH` — biggest gap (source: `src/utils/shell/outputLimits.ts`)

```
BASH_MAX_OUTPUT_DEFAULT = 30_000
BASH_MAX_OUTPUT_UPPER_LIMIT = 150_000
```

Every bash tool invocation can return up to 30,000 characters by default. This is a massive per-turn token sink, especially on commands like `npm run build`, `git log`, or `find`. You can set it lower:

```bash
export BASH_MAX_OUTPUT_LENGTH=10000
```

This is completely absent from your optimizer and should be the first env var you add.

---

### 2. `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` — also missing (source: `src/tools/FileReadTool/limits.ts`)

```
DEFAULT_MAX_OUTPUT_TOKENS = 25000
```

The Read tool will return up to 25,000 tokens per file read. You can cap it:

```bash
export CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS=8000
```

Forces Claude to use line ranges (`startLine`/`endLine`) on large files instead of reading entire files blindly. Should be in your optimizer next to `BASH_MAX_OUTPUT_LENGTH`.

---

### 3. Binary-to-markdown is manual — it needs to be a PreToolUse `exit 2` hook

Your `preprocess-for-claude.ps1` is a manual wrapper. The PreToolUse `exit 2` pattern you already use for images (write bytes to stdout, exit 2, Claude gets that as the tool result) is exactly the right architecture for PDF/DOCX/XLSX too. The hook should intercept `Read` on those extensions, run `markitdown`, write the markdown to stdout, and exit 2 — so Claude receives clean markdown instead of triggering a binary read error.

Right now your `pretooluse.sh` only handles PNG/JPG. The binary-to-markdown pipeline you're building for `ai-environment-setup` belongs in this same hook, not as a standalone script users have to run manually.

---

### 4. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (source: `src/services/compact/autoCompact.ts`)

```typescript
const envPercent = process.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
if (!isNaN(parsed) && parsed > 0 && parsed <= 100) {
  const percentageThreshold = Math.floor(effectiveContextWindow * (parsed / 100))
  return Math.min(percentageThreshold, autocompactThreshold)
}
```

The default autocompact triggers at ~95% of effective context (effectiveWindow - 13,000 tokens buffer). You can make it fire earlier so compaction summaries are cheaper and less lossy:

```bash
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70
```

This means compaction fires at 70% of effective context rather than near the limit. You already set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to narrow the effective window — this gives you proportional control over when within that window compaction kicks in.

---

### 5. CLAUDE.md compact instructions — your template is empty

From `src/services/compact/prompt.ts`, the compaction prompt explicitly scans the conversation for:

```
## Compact Instructions
# Summary instructions
```

…and appends them to the summarization prompt. Your `CLAUDE.md-template` is a blank file. Adding a focused compact instruction block makes the compaction summary shorter and more task-relevant, which directly reduces the token cost of the next fresh context:

```markdown
## Compact Instructions
Focus on: current task state, file paths changed, pending errors, and last user instruction verbatim. Skip background theory. Keep code snippets only if they're the direct subject of the next task. Omit completed sub-tasks.
```

---

### 6. `CLAUDE_CODE_DISABLE_AUTO_MEMORY`

Auto-memory extraction (`src/services/extractMemories/`) fires as a background API call after sessions to extract persistent memories. If you're not using cross-session memory (which is not the default workflow for most users), this is a silent token burn. Add it to the optimizer:

```bash
export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
```

---

### 7. `ENABLE_CLAUDE_CODE_SM_COMPACT` (source: `src/services/compact/autoCompact.ts`)

From the autocompact source: `trySessionMemoryCompaction` is attempted first before full compaction. Session memory compaction only prunes oversized tool results rather than summarizing the entire conversation. It's an experiment flag:

```bash
export ENABLE_CLAUDE_CODE_SM_COMPACT=1
```

When it fires, it saves tokens on compaction by avoiding the full `getCompactPrompt()` API call. Worth enabling as it degrades gracefully to full compaction if SM compaction doesn't free enough headroom.

---

### 8. `DISABLE_INTERLEAVED_THINKING`

Extended thinking tokens are expensive. For tasks that don't need deep reasoning (file editing, search/replace, grep-based exploration), interleaved thinking is pure overhead. Adding this as an optional flag to your optimizer with a note that users should toggle it contextually:

```bash
export DISABLE_INTERLEAVED_THINKING=1
```

---

### 9. `CLAUDE_CODE_DISABLE_ADVISOR_TOOL`

The advisor tool (`src/commands/advisor.ts`) fires its own side queries. For users optimizing token consumption, it's a latent drain:

```bash
export CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1
```

---

### 10. Inline token budget notation (source: `src/utils/tokenBudget.ts`)

This is undocumented and worth surfacing in your README. Claude Code natively parses token budget syntax in prompts:

- `+500k` at the start/end of a message
- `use 2M tokens` anywhere in a message

This sets a per-turn budget (tracked via `checkTokenBudget` in `src/query/tokenBudget.ts`) and sends `getBudgetContinuationMessage` nudges when approaching the limit. Users can use this to self-impose turn-level token discipline without changing any settings.

---

### Summary priority order

| Gap | Type | Impact |
|---|---|---|
| `BASH_MAX_OUTPUT_LENGTH` | env var | High — 30K chars per bash call |
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | env var | High — 25K tokens per file read |
| Binary-to-markdown as exit 2 hook | hook architecture | High — eliminates manual step |
| CLAUDE.md compact instructions | configuration | Medium — cheaper compaction output |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | env var | Medium — compact before context is saturated |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | env var | Medium — stops silent background calls |
| `ENABLE_CLAUDE_CODE_SM_COMPACT` | env var | Medium — lighter compaction path |
| `DISABLE_INTERLEAVED_THINKING` | env var | Situational |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | env var | Low-medium |
| Token budget inline notation | docs/UX | Informational |

The three env vars (`BASH_MAX_OUTPUT_LENGTH`, `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) are the most straightforward wins — one-liners to add to `optimize-claude.sh` and `optimize-claude.ps1` with no dependencies. The binary-to-markdown hook is the biggest architectural gap: the exit 2 intercept pattern is already proven in your image hook, it just needs to be extended to cover the document types you're working on in `ai-environment-setup`.