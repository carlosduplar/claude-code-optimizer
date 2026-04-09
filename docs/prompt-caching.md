# Prompt Caching Internals & Keepalive Strategies

> **Note:** The 5-minute cache invalidation claim comes from community reports (Reddit, Discord) and has not been officially confirmed by Anthropic. However, the strategies below are sound regardless of exact TTL.

---

## How Prompt Caching Works in Claude Code

### Cache Hit Requirements

From source analysis (`src/services/api/claude.ts`, `src/utils/betas.ts`), prompt cache hits require **identical**:

1. **System prompt** (including auto-memory, MCP tool listings)
2. **Tools** (definitions and schemas)
3. **Model** (any change invalidates cache)
4. **Messages prefix** (the conversation history up to the cache point)
5. **Thinking config** (`thinking: { type, budget_tokens }` - changing this breaks cache!)
6. **Beta headers** (some beta features alter the request signature)

### What Invalidates Cache

| Action | Cache Effect |
|--------|--------------|
| Switching models (`/model`) | **Full invalidation** |
| Changing thinking settings | **Full invalidation** |
| Adding/removing MCP servers | **System prompt change** |
| Large tool result compaction | **Prefix change** (CACHED_MICROCOMPACT mitigates) |
| 5+ minutes inactivity | **Possible TTL expiration** (community report) |

### Cache-Preserving Features

#### CACHED_MICROCOMPACT (ant-only)

**File:** `src/services/compact/microCompact.ts:52-128`

Uses `cache_edits` API to remove tool results **without** invalidating the cached prefix:

```typescript
async function cachedMicrocompactPath(messages: Message[]): Promise<MicrocompactResult> {
  const toolsToDelete = mod.getToolResultsToDelete(state)
  if (toolsToDelete.length > 0) {
    const cacheEdits = mod.createCacheEditsBlock(state, toolsToDelete)
    pendingCacheEdits = cacheEdits  // Queued for API layer
    return {
      messages,  // Unchanged locally
      compactionInfo: { pendingCacheEdits: { trigger: 'auto', deletedToolIds: toolsToDelete } }
    }
  }
}
```

This allows removing large tool outputs while preserving the cache prefix.

---

## The 5-Minute Inactivity Claim

### Source

Multiple community reports (Reddit r/ClaudeAI, Anthropic Discord) suggest the Anthropic API has a **~5 minute TTL** on prompt cache entries. After this period of inactivity:
- The cache entry may be evicted
- Subsequent requests require re-processing the full context
- Token costs increase significantly (no cache discount)

### Anthropic's Official Position

The [official API documentation](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) states:
> "Cached content remains active for **5 minutes** of inactivity"

This confirms the 5-minute claim for the **API-level cache**, not specifically Claude Code's behavior.

### Impact on Claude Code

| Scenario | Cost Impact |
|----------|-------------|
| Cache hit | ~90% reduction on cached prefix |
| Cache miss (after 5min idle) | Full price for all tokens |
| Long-running session (active) | Cache preserved while active |

For a 200K context window, this is the difference between:
- **With cache:** ~$0.60 (200K × $0.30/million cached input)
- **Without cache:** ~$6.00 (200K × $3.00/million standard input)

---

## Keepalive Strategies

### Why PostToolUse Is the Wrong Hook for Keepalive

A common mistake is adding a `PostToolUse` hook that echoes a keepalive signal:

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{"type": "command", "command": "echo '{\"keepalive\": \"...\"}'"}]
    }]
  }
}
```

**This does nothing for cache TTL.** The problem: cache expires during **user idle time**, not between tool calls. If tools are firing, the session is already active—no keepalive is needed. If you're reading/thinking for 5+ minutes without tool use, the cache expires regardless of this hook.

### Strategy 1: Background Timer (Recommended)

The most reliable keepalive runs independently of Claude Code activity:

**Linux/macOS/WSL:**
```bash
# Run in background before starting your session
while sleep 240; do claude -p "." --no-stream 2>/dev/null; done &
```

**PowerShell:**
```powershell
# Start in background
Start-Job { while ($true) { Start-Sleep 240; claude -p "." 2>$null } }
```

This sends a minimal ping every 4 minutes regardless of what you're doing.

### Strategy 2: Claude Code `/loop` Command

Use the built-in `/loop` command for active tasks:

```
/loop --interval 240s echo "Cache keepalive"
```

This sends periodic messages without manual intervention.

### Strategy 3: Pre-Flight Cache Warmup

Before resuming work after a break:

```bash
# Send a minimal request to re-establish cache
claude -p "Acknowledge" --model sonnet
```

This warms the cache before your main work session.

---

## Maximizing Cache Efficiency

### 1. Batch Model Changes

**Bad:**
```
/model haiku
Grep pattern *.ts
/model sonnet  # Cache lost!
Edit file.ts
```

**Good:**
```
/model haiku
Grep pattern *.ts
Read file.ts {"limit": 50}
Read another.ts {"limit": 50}
# Now switch
/model sonnet
Edit file.ts  # Cache rebuilt once
```

### 2. Avoid Thinking Config Changes

**Critical:** Changing `thinking.budget_tokens` invalidates cache.

```typescript
// From src/services/api/claude.ts
// Cache key components include thinking config
const cacheKeyComponents = [
  systemPrompt,
  tools,
  model,
  messages,
  thinkingConfig  // <-- This matters!
]
```

Set thinking budget once at session start:
```
/model sonnet --thinking-budget 16000
```

### 3. Stable System Prompt

**Before starting work:**
1. Configure MCP servers
2. Load all skills
3. Then begin the conversation

Any system prompt change = cache invalidation.

### 4. Use `/compact` Strategically

**From** `src/services/compact/sessionMemoryCompact.ts`:

Session memory compaction preserves cache better than full compaction:

```
/compact  # Full compaction - may affect cache
```

vs.

```
# With CACHED_MICROCOMPACT (ant-only):
# Tool results removed via cache_edits, prefix preserved
```

### 5. Monitor Cache Effectiveness

Use `/cost` to check cache performance:

```
/cost
```

Look for:
- `cached_tokens` in the output (indicates cache hits)
- High input costs = potential cache misses

---

## Environment Variables for Cache Control

| Variable | Effect |
|----------|--------|
| `DISABLE_PROMPT_CACHING` | Disable all prompt caching |
| `DISABLE_PROMPT_CACHING_SONNET` | Disable for Sonnet |
| `DISABLE_PROMPT_CACHING_OPUS` | Disable for Opus |
| `DISABLE_PROMPT_CACHING_HAIKU` | Disable for Haiku |
| `ENABLE_PROMPT_CACHING_1H_BEDROCK` | 1-hour caching (Bedrock only) |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | May affect cache-related betas |

---

## Hook: Idle Warning with File-Based Timestamps

**Note:** `$CLAUDE_LAST_ACTIVITY` does not exist in Claude Code. Use a file-based approach instead.

Track last activity by writing timestamps on each tool use, then check in PreSampling:

**Linux/macOS/WSL:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "date +%s > /tmp/claude_last_activity",
        "if": "*"
      }]
    }],
    "PreSampling": [{
      "type": "command",
      "command": "[ $(($(date +%s) - $(cat /tmp/claude_last_activity 2>/dev/null || echo 0))) -gt 240 ] && echo '{\"warning\": \"Cache TTL risk - 4+ min idle\"}'",
      "if": "*"
    }]
  }
}
```

**PowerShell:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Out-File \"$env:TEMP/claude_last_activity.txt\" -NoNewline",
        "if": "*"
      }]
    }],
    "PreSampling": [{
      "type": "command",
      "command": "$ts = if (Test-Path \"$env:TEMP/claude_last_activity.txt\") { Get-Content \"$env:TEMP/claude_last_activity.txt\" } else { 0 }; if (([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ts) -gt 240) { Write-Host '{\"warning\": \"Cache TTL risk - 4+ min idle\"}' }",
      "if": "*"
    }]
  }
}
```

**Limitations:** This only tracks tool-based activity. Pure thinking/reading time without tool use will still cause cache expiry.

---

## Summary: Cache Optimization Checklist

| Strategy | Implementation | Impact |
|----------|----------------|--------|
| **Batch by model** | Do all Haiku work first, then switch | High |
| **Stable thinking config** | Set once at session start | High |
| **Keepalive ping** | Background timer or `/loop` every 4min | Medium |
| **Pre-warm cache** | Small request after breaks | Medium |
| **Minimize system changes** | Configure MCP servers before starting | High |
| **Use `/loop`** | For long-running monitoring tasks | Low |

---

## References

- **Anthropic API Docs:** [Prompt Caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- **Claude Code Source:** `src/services/api/claude.ts` (cache key construction)
- **Claude Code Source:** `src/services/compact/microCompact.ts` (CACHED_MICROCOMPACT)
- **Claude Code Source:** `src/utils/betas.ts` (cache-related beta headers)

---

*based on alleged Claude Code source analysis and Anthropic API documentation*
