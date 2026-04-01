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

### Strategy 1: Hook-Based Keepalive (Recommended)

Add to your `settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "echo '{\"keepalive\": \"'$(date +%s)'\"}'",
        "if": "*"
      }]
    }]
  }
}
```

**Limitation:** Only fires when tools are used. If you're thinking/reading for >5 minutes, cache may still expire.

### Strategy 2: Background Ping Script

**File:** `claude-keepalive.sh`

```bash
#!/bin/bash
# Keepalive script for Claude Code prompt cache
# Run in background: ./claude-keepalive.sh &

SESSION_NAME="${1:-claude}"
INTERVAL=240  # 4 minutes (safely under 5min TTL)

while true; do
    # Check if Claude session is active
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        # Send a no-op comment to keep session warm
        # This creates minimal API traffic but keeps cache alive
        tmux send-keys -t "$SESSION_NAME" "# keepalive $(date +%s)" Enter
        sleep 5
        # Clear the no-op from history
        tmux send-keys -t "$SESSION_NAME" C-c
    fi
    sleep $INTERVAL
done
```

**Usage:**
```bash
# Start Claude in a named tmux session
tmux new -s claude

# In another terminal, start keepalive
./claude-keepalive.sh claude &
```

### Strategy 3: Claude Code `/loop` Command

Use the built-in `/loop` command for active tasks:

```
/loop --interval 240s echo "Cache keepalive"
```

This sends periodic messages without manual intervention.

### Strategy 4: Pre-Flight Cache Warmup

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

## Hook: Auto-Keepalive on Idle

**For settings.json:**

```json
{
  "hooks": {
    "PreSampling": [{
      "type": "command",
      "command": "if [ $(($(date +%s) - ${CLAUDE_LAST_ACTIVITY:-0})) -gt 240 ]; then echo '{\"warning\": \"Cache may expire soon - 5min idle approaching\"}'; fi",
      "if": "*"
    }]
  }
}
```

This warns you when approaching the 5-minute idle threshold.

---

## Summary: Cache Optimization Checklist

| Strategy | Implementation | Impact |
|----------|----------------|--------|
| **Batch by model** | Do all Haiku work first, then switch | High |
| **Stable thinking config** | Set once at session start | High |
| **Keepalive ping** | Background script every 4min | Medium |
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
