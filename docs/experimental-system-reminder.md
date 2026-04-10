# experimentalSystemReminder

**Status:** Unverified in public builds — may be dead-code eliminated.

---

## What It Is

`experimentalSystemReminder` is a per-turn system prompt injection mechanism for Claude Code agents. Unlike `CLAUDE.md` (injected once at session start), this field re-injects content at **every user turn**, helping maintain behavioral consistency across long conversations.

**Source:** `src/Tool.ts:275`

```typescript
experimentalSystemReminder?: string  // Re-injected every turn
```

---

## Agent Definition

Location: `.claude/agents/default.json`

```json
{
  "name": "default",
  "experimentalSystemReminder": "No articles, filler, pleasantries..."
}
```

### Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Agent identifier |
| `experimentalSystemReminder` | string | No | Content re-injected every turn |

---

## CLAUDE.md vs experimentalSystemReminder

| Aspect | CLAUDE.md | experimentalSystemReminder |
|--------|-----------|---------------------------|
| **Timing** | Session start | Every user turn |
| **Persistence** | Loaded once | Re-injected repeatedly |
| **Use case** | Static conventions | Dynamic behavior reinforcement |
| **Context pressure** | Single injection | Accumulates with turns |

---

## Silent Failure Risk

**Critical:** This field may be dead-code eliminated in public builds.

If `experimentalSystemReminder` is removed during build optimization:
- Agent JSON loads without error
- Field is silently ignored
- No behavioral change occurs

**Detection:**
1. Start session with verbose logging (if available)
2. Let context grow past 20 turns
3. Compare style drift vs session without the agent
4. Check if reminder content appears in API request debug output

---

## Verification Method

Test for style drift across long conversations:

1. **Control session:** No agent, or agent without `experimentalSystemReminder`
2. **Test session:** Agent with strict style rules in `experimentalSystemReminder`
3. **Procedure:**
   - Run 20+ turn conversation
   - Measure style adherence at turns 5, 10, 15, 20
4. **Pass criteria:** Test session shows significantly less style drift

---

## When to Use

**Appropriate:**
- Maintaining strict output formats across long sessions
- Preserving behavioral constraints that tend to drift
- Reinforcing critical safety or style rules

**Not appropriate:**
- Static conventions (use `CLAUDE.md` instead)
- One-time setup instructions
- Large content (re-injected every turn = token cost)

---

## Experimental Agent Teams

**Variable:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
**Status:** Unverified in public builds — may be dead-code eliminated.

Enables multi-instance parallel collaboration with direct agent-to-agent communication. When set to `1`, multiple Agent tool invocations can run concurrently with message passing between them.

**Use cases:**
- Parallel brainstorming across domain experts (security, performance, testing)
- Concurrent file analysis across multiple directories
- Multi-agent consensus building

**Set by optimizer:** `tuned` profile automatically enables this flag.

**Environment configuration:**
```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

**Limitations:**
- Requires explicit Agent tool use with parallel invocation
- No guarantee of availability in public builds
- Agent-to-agent message format undocumented

---

## Related

- [CLAUDE.md communication rules](https://code.claude.com/docs/en/) — session-start conventions
- [Undocumented Features](undocumented-features.md) — other hidden capabilities
