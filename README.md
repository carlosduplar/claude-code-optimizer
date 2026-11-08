# claude-code-optimizer v1.0.0

Scripts, CLAUDE.md template, and env vars to cut Claude Code token usage and cost. Official-docs-aligned baseline + tuned overlay. Reverse-engineered internals are marked unverified.

> Version: see `VERSION`. Source of truth for voice: https://github.com/carlosduplar/caveman-output-style-claude-code (synced v1.2.0).

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
| `tuned` | Adds BASH_MAX_OUTPUT_LENGTH, promptCacheTtl=1h, AUTOCOMPACT_PCT_OVERRIDE=80; disables auto-memory; sets legacy compat flags (SM_COMPACT, advisor, git instructions, policy skills — unverified in public builds, see below) |

`tuned` is the default profile.

## What It Optimizes

| Technique | Mechanism | Measured Impact |
|-----------|-----------|-----------------|
| CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 | Compact at 80% of auto-compact window (cannot raise threshold; lower values only) | Reduces reactive compactions |
| promptCacheTtl=1h (+ ENABLE_PROMPT_CACHING_1H for older CLI) | Extend prompt cache TTL from 5min to 1hr. Subscription default is already 1h for main conversation; explicit 1h helps API-key/Bedrock | Fewer cache misses after idle |
| Binary preprocessing | markitdown conversion before API call | Token reduction varies by file type (unmeasured) |
| Compact CLAUDE.md | Compressed behavioral anchors | Smaller session-start input (unmeasured; ~45% claim removed — not benchmarked) |
| Caveman output style | Always-on voice via output style (system-prompt level). Source: caveman-output-style v1.2.0 | Fewer output tokens; prose-only savings, payload verbatim |
| Telemetry blocking | Disables Datadog/BigQuery/OTLP endpoints | Reduces non-essential outbound traffic |
| Auto-handoff hooks | PreCompact synthesizes session state; SessionStart auto-inlines | Survives compaction without losing context |

*Cache savings only realized on hit. Output-style savings are voice-only; code/tool calls unchanged. Percentages in older docs were illustrative, not benchmarks.*

## Configuration Reference

All optimizer-managed runtime configuration is written to `~/.claude/settings.json`.

### Optimizer CLI

| Flag | Values | Default |
|------|--------|---------|
| `--profile` | `official` or `tuned` | `tuned` |
| `--privacy` | `standard` or `max` | `max` |
| `--output-style` | `caveman`, `caveman-ultra`, or `none` | `caveman` |
| `--unsafe-auto-approve` | ⚠️ enable broad Bash allowlist | off |
| `--auto-format` | enable post-edit format hook (opt-in, off by default) | off |
| `--dry-run` | preview without writes | off |
| `--skip-deps` | skip dependency checks | off |
| `--verify` | validate current settings only | off |

### Environment Variables

Canonical cache control is now `promptCacheTtl: 1h` in settings.json (v2.1.242+). `ENABLE_PROMPT_CACHING_1H=1` is kept for older CLI compatibility. `BASH_MAX_OUTPUT_LENGTH` is overridden by `bashOutputMaxChars` setting if set — optimizer sets env only.

**Feature Enable** (runtime, public builds)

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_ENABLE_XAA` | Extended Authorization Architecture (MCP OAuth) | `false` |
| `ENABLE_TOOL_SEARCH` | Tool search/discovery | `auto` |
| `ENABLE_SESSION_PERSISTENCE` | Session persistence | `false` |
| `ENABLE_CLAUDE_CODE_SM_COMPACT` | Session-memory compaction | `false` (⚠️ legacy/unverified — set `true` by tuned for compat) |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Experimental multi-agent teams support | `false` (⚠️ unverified — set `1` by tuned) |
| `MAX_MCP_OUTPUT_TOKENS` | Maximum tokens per MCP tool response | unset (⚠️ unverified — set `25000` by tuned) |
| `ENABLE_PROMPT_CACHING_1H` | Extend prompt cache TTL to 1 hour (legacy; prefer `promptCacheTtl`) | `false` (set `1` by tuned) |

**Feature Disable** (runtime, public builds)

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Automatic memory extraction (`autoMemoryEnabled=false`) | `false` |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | Advisor tool | `false` (⚠️ legacy — set `true` by tuned for compat) |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | Git instructions (now `includeGitInstructions`) | `false` (⚠️ legacy — set `true` by tuned) |
| `CLAUDE_CODE_DISABLE_POLICY_SKILLS` | Policy-based skills | `false` (⚠️ legacy/unverified — set `true` by tuned) |
| `DISABLE_INTERLEAVED_THINKING` | Interleaved thinking | `false` (⚠️ legacy — set `true` by tuned) |
| `DISABLE_PROMPT_CACHING` | All prompt caching | `false` |
| `DISABLE_TELEMETRY` | Telemetry | `false` |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Compact threshold percentage (1-100, lower only) | `80` (set by tuned) |

Plus settings key `promptCacheTtl: 1h` (tuned, v2.1.242+).

**Internal / Anthropic-only** (⚠️ ant-only — requires `USER_TYPE=ant`)

| Variable | Description |
|----------|-------------|
| `USER_TYPE` | Set to `'ant'` for internal Anthropic employees |
| `CLAUDE_INTERNAL_FC_OVERRIDES` | GrowthBook feature flag overrides |
| `CLAUDE_CODE_ABLATION_BASELINE` | Ablation baseline config |

### CLAUDE.md Template

See [CLAUDE.md](CLAUDE.md). Contains compressed behavioral anchors for communication style, principles, workflow, and documentation. Copy to project root. For voice, prefer the caveman output style below — CLAUDE.md is a user message, output style is system-prompt level and persists without dilution.

### Implemented Hooks

| Hook | Event | What It Does | Script |
|------|-------|--------------|--------|
| `SessionStart` | Session startup | Displays keepalive reminder + project context (startup only; compact/resume handled by handoff) | `session-start-reminder.sh/ps1` |
| `PreToolUse` (Read) | Before Read tool | Sanity check for Read operations | `pretooluse.sh/ps1` |
| `PreToolUse` (Write/Edit/Bash) | Before write/bash | **bash-guard**: Blocks dangerous commands (sudo, rm -rf /, curl \| bash, etc.) | `bash-guard.sh/ps1` |
| `PreToolUse` (Write/Edit/Bash) | Before write/bash | **write-guard**: Blocks commits of secrets (API keys, tokens, private keys) to non-example files | `write-guard.sh/ps1` |
| `PreToolUse` (Write/Edit/Bash) | Before write/bash | **file-guard**: Additional file validation | `file-guard.ps1` (Windows only) |
| `PostToolUse` | After Write/Edit/MultiEdit | Auto-format files (prettier for JS/TS/CSS/HTML/JSON/YAML; black/autopep8 for Python) | `post-edit-format.sh/ps1` |
| `PostToolUseFailure` | After any tool fails | Logs errors to `~/.claude/logs/errors/` with 1MB rotation | `posttoolusefailure.sh/ps1` |
| `Notification` | When notification sent | Desktop toast (Windows) or `notify-send` (Linux); fallback to stderr | `notify.sh/ps1` |
| `PreCompact` | Before context compaction | Synthesizes structured handoff summary from session transcript; writes `docs/handoff-context.md` | `handoff-precompact.sh/ps1` |
| `SessionStart` (compact\|resume) | Session resume after compact | Auto-inlines previous handoff context into new session; no Read-tool round trip | `handoff-session-resume.sh/ps1` |

### Caveman Output Style

Installed from `assets/output-styles/` (synced from [caveman-output-style-claude-code](https://github.com/carlosduplar/caveman-output-style-claude-code) v1.2.0 — do not hand-edit; update assets instead) to `~/.claude/output-styles/`:

- `caveman.md` (`name: caveman`, lowercase — value is case-sensitive, `Caveman` falls back to `Default`)
- `caveman-ultra.md` (maximum terseness, symbols over words, prose-only abbreviations)

Both set `keep-coding-instructions: true` (full system prompt only; no effect on short prompt unless `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=0`). Applies to main conversation + forks, not subagents. Changing styles invalidates prompt cache on first message after switch.

Voice-only savings: prose shrinks, code/paths/errors/commands verbatim. No measured % claimed.

Set via `"outputStyle": "caveman"` in settings.json (optimizer default) or `--output-style caveman-ultra|none`. Switch mid-session with `/output-style <name>` (applies next message; v2.1.251+; CLI requires v2.1.269+). Takes effect on restart if files were created mid-session.

### Keepalive

Keepalive is reminder-based (`SessionStart`) and manual by design. Background `claude -p` pings create separate sessions with different prefixes and do not reliably keep the main conversation cache warm. Prefer active use; after >TTL idle expect one uncached turn. See `docs/prompt-caching.md`.

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
