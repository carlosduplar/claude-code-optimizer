# claude-code-optimizer

Scripts, CLAUDE.md template, and env vars to cut Claude Code token usage and cost. Backed by reverse-engineered internals docs.

## Quickstart

**Prerequisites:** PowerShell 7 (Windows) or Bash (Linux/macOS/WSL2)

**Clone and run (default: tuned profile + max privacy):**
```powershell
# Windows
git clone https://github.com/carlosduplar/claude-code-optimizer.git
.\claude-code-optimizer\scripts\windows\optimize-claude.ps1

# Linux/macOS
git clone https://github.com/carlosduplar/claude-code-optimizer.git
./claude-code-optimizer/scripts/linux/optimize-claude.sh
```

**Copy the CLAUDE.md template** to your project root:
```bash
cp claude-code-optimizer/CLAUDE.md ./CLAUDE.md
```

**Tested:** Windows PowerShell 7.6, Ubuntu WSL2

## Profiles

| Profile | Purpose |
|---------|---------|
| `official` | Official-docs-aligned baseline defaults |
| `tuned` | Adds BASH_MAX_OUTPUT_LENGTH, SM_COMPACT, AUTOCOMPACT_PCT_OVERRIDE=80; disables auto-memory, advisor, git instructions, policy skills |

`tuned` is the default profile.

## What It Optimizes

| Technique | Mechanism | Measured Impact |
|-----------|-----------|-----------------|
| CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 | Proactive context compaction before 13K-token buffer | Reduces reactive compactions |
| Binary preprocessing | markitdown conversion before API call | 50-80% token reduction on binary files |
| Compact CLAUDE.md | Compressed behavioral anchors | ~45% reduction on session-start input |
| experimentalSystemReminder | Per-turn style injection | ⚠️ unverified |
| Telemetry blocking | Disables Datadog/BigQuery/OTLP endpoints | Reduces non-essential outbound traffic |

*Cache savings only realized on hit; binary savings depend on file type.*

## Configuration Reference

All optimizer-managed runtime configuration is written to `~/.claude/settings.json`.

### Optimizer CLI

| Flag | Values | Default |
|------|--------|---------|
| `--profile` | `official` or `tuned` | `tuned` |
| `--privacy` | `standard` or `max` | `max` |
| `--unsafe-auto-approve` | ⚠️ enable broad Bash allowlist | off |
| `--auto-format` | enable post-edit format hook | off |
| `--dry-run` | preview without writes | off |
| `--skip-deps` | skip dependency checks | off |
| `--verify` | validate current settings only | off |

### Environment Variables

**Feature Enable** (runtime, public builds)

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_ENABLE_XAA` | Extended Authorization Architecture (MCP OAuth) | `false` |
| `ENABLE_TOOL_SEARCH` | Tool search/discovery | `auto` |
| `ENABLE_SESSION_PERSISTENCE` | Session persistence | `false` |
| `ENABLE_CLAUDE_CODE_SM_COMPACT` | Session-memory compaction | `false` |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Experimental multi-agent teams support | `false` (set `1` by tuned profile) |
| `MAX_MCP_OUTPUT_TOKENS` | Maximum tokens per MCP tool response | unset (set `25000` by tuned profile) |

**Feature Disable** (runtime, public builds)

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Automatic memory extraction | `false` |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | Advisor tool | `false` |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | Git instructions | `false` |
| `CLAUDE_CODE_DISABLE_POLICY_SKILLS` | Policy-based skills | `false` |
| `DISABLE_INTERLEAVED_THINKING` | Interleaved thinking | `false` |
| `DISABLE_PROMPT_CACHING` | All prompt caching | `false` |
| `DISABLE_TELEMETRY` | Telemetry | `false` |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Compact threshold (percentage) | `80` (set) |

**Internal / Anthropic-only** (⚠️ ant-only — requires `USER_TYPE=ant`)

| Variable | Description |
|----------|-------------|
| `USER_TYPE` | Set to `'ant'` for internal Anthropic employees |
| `CLAUDE_INTERNAL_FC_OVERRIDES` | GrowthBook feature flag overrides |
| `CLAUDE_CODE_ABLATION_BASELINE` | Ablation baseline config |

### CLAUDE.md Template

See [CLAUDE.md](CLAUDE.md). Contains compressed behavioral anchors for communication style, principles, workflow, and documentation. Copy to project root for ~45% session-start reduction.

### Keepalive

The project no longer claims PostToolUse-hook keepalive behavior. Keepalive is reminder-based (`SessionStart`) and manual (`/loop`) by design.

Default optimizer runs do not add `PostToolUse`; that hook is only added when auto-format is enabled.

### Hook Runtime Verification

Use runtime checks (not only config checks) to confirm hook events are firing:

- Linux/macOS/WSL: `./scripts/linux/test-hooks-runtime.sh`
- Windows: `.\scripts\windows\test-hooks-runtime.ps1`

### Bash Auto-Approve Defaults

Default install includes a conservative read-only metadata allowlist (listing/location/git metadata/version/help/package metadata). Higher-risk content-read patterns are added only with `--unsafe-auto-approve`.

## How It Works

These optimizations target the three largest cost drivers: prompt cache misses, verbose output, and large input files.

| Document | What It Covers |
|----------|----------------|
| [Prompt Caching & Keepalive](docs/prompt-caching.md) | 5-minute TTL behavior, invalidation triggers, realistic keepalive strategies |
| [Session Memory & Compaction](docs/session-memory.md) | Proactive/reactive compaction, memdir taxonomy, CACHED_MICROCOMPACT |
| [Binary Preprocessing](docs/optimization-scripts.md) | Automated setup for token efficiency and privacy |
| [Undocumented Features](docs/undocumented-features.md) | 88+ compile-time feature flags, 60+ environment variables |
| [Telemetry Internals](docs/telemetry-privacy.md) | Datadog endpoints, 1P event logging, PII sanitization |
| [experimentalSystemReminder](docs/experimental-system-reminder.md) | Per-turn system prompt injection |

## Internals Reference

Reverse-engineered from alleged source analysis. Not official Anthropic documentation. Build-time feature flags cannot be enabled in public binaries.

| Document | Description | Status |
|----------|-------------|--------|
| [Query Flow & Message Streaming](docs/query-flow.md) | Streaming fallback layers, retry logic, side query architecture | reference only |
| [Session Memory & Context Management](docs/session-memory.md) | Memory taxonomy, compaction triggers | actionable |
| [Tool System Architecture](docs/tool-system.md) | MCP/LSP integration internals, permission context flow | reference only |
| [Permission System & Auto-Mode Classifier](docs/permission-system.md) | Two-stage XML classifier, iron gate logic | reference only |
| [Skill & Plugin System](docs/skill-plugin-system.md) | Bundled skills registry, dynamic discovery | reference only |
| [Prompt Caching & Keepalive](docs/prompt-caching.md) | Cache TTL, keepalive strategy caveats | actionable |
| [Undocumented Features](docs/undocumented-features.md) | 88+ feature flags, hidden CLI flags, env vars | actionable |
| [Anthropic-Only Commands](docs/ant-only-commands.md) | 24 commands gated behind `USER_TYPE=ant` | ⚠️ ant-only |
| [Telemetry & Privacy Internals](docs/telemetry-privacy.md) | Datadog, BigQuery, OTLP endpoints | actionable |
| [Optimization Scripts](docs/optimization-scripts.md) | Automated setup for token efficiency | actionable |
| [Validation](docs/validation.md) | Functional testing to verify hooks | actionable |
| [Token Benchmark](tests/benchmark/README.md) | Token measurement test suite | actionable |
| [experimentalSystemReminder](docs/experimental-system-reminder.md) | Per-turn system prompt injection | actionable |
| [Legal Notice](docs/LEGAL.md) | Legal disclaimer and copyright notice | reference only |

## Contributing

This documentation is derived from source code analysis. To contribute:

1. Focus on **undocumented** internals not in [official docs](https://code.claude.com/docs/en/)
2. Include specific file paths and line numbers
3. Cite source code references
4. Submit PRs to `carlosduplar/claude-code-optimizer`

## Legal

See [docs/LEGAL.md](docs/LEGAL.md) for legal disclaimer and copyright notice.
