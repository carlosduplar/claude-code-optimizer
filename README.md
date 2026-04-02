# Claude Code: Undocumented Internals

This repository documents **obscure, undocumented, and internal** aspects of Claude Code that are not covered in the [official documentation](https://code.claude.com/docs/en/). Everything here was reverse-engineered from the source code.

> **Note:** For standard usage (CLI flags, environment variables, skills, MCP, etc.), see the [official docs](https://code.claude.com/docs/en/cli-reference). This repo focuses on internals not documented there.

---

## 📚 Documentation Index

### Core Internals (Architecture Deep-Dives)

| Document | Description | Why Not in Official Docs |
|----------|-------------|--------------------------|
| [Query Flow & Message Streaming](query-flow.md) | Streaming fallback layers, retry logic with exponential backoff + jitter, 529 error handling, side query architecture | Internal implementation details |
| [Session Memory & Context Management](session-memory.md) | Proactive/reactive compaction, memdir taxonomy, CACHED_MICROCOMPACT, REACTIVE_COMPACT feature flags | Internal memory system |
| [Tool System Architecture](tool-system.md) | Tool registration pipeline, MCP/LSP integration internals, permission context flow | Implementation details |
| [Permission System & Auto-Mode Classifier](permission-system.md) | Two-stage XML classifier, iron gate fail-closed logic, denial tracking circuit breakers | Internal security mechanisms |
| [Skill & Plugin System](skill-plugin-system.md) | Bundled skills registry, dynamic skill discovery, workflow scripts, MCP skill builders | Internal extension architecture |
| [Prompt Caching & Keepalive](prompt-caching.md) | 5-minute TTL behavior, cache invalidation triggers, CACHED_MICROCOMPACT, keepalive strategies | API-level cache internals |

### Hidden/Internal Features

| Document | Description |
|----------|-------------|
| [Undocumented Features](undocumented-features.md) | 88+ compile-time feature flags, hidden CLI flags, fast-path subcommands, 60+ internal environment variables |
| [Anthropic-Only Commands](ant-only-commands.md) | 24 commands gated behind `USER_TYPE=ant`—which work, which are stubs, side effects |
| [Telemetry & Privacy Internals](telemetry-privacy.md) | Datadog endpoints, 1P event logging schema, PII sanitization rules, proto column routing |

### Practical Tools

| Document | Description |
|----------|-------------|
| [Optimization Scripts](optimization-scripts.md) | Automated setup scripts for token efficiency and privacy configuration |
| [Validation Suite](validation-suite.md) | Test framework to verify all optimization claims with before/after comparison |

**Tested Environments:**
- Windows: PowerShell 7.6.0
- Linux/WSL: Ubuntu (WSL2)

---

## 🏗️ Repository Structure

```
claude-code/
├── docs/                          # This documentation
│   ├── query-flow.md              # API streaming internals
│   ├── session-memory.md          # Memory & compaction
│   ├── tool-system.md             # Tool framework internals
│   ├── permission-system.md       # Auto-mode classifier
│   ├── skill-plugin-system.md     # Skills & plugins
│   ├── prompt-caching.md          # Cache TTL & keepalive strategies
│   ├── undocumented-features.md   # Feature flags & hidden commands
│   ├── ant-only-commands.md       # Internal commands
│   ├── telemetry-privacy.md       # Telemetry internals
│   ├── optimization-scripts.md    # Setup automation
│   └── validation-suite.md        # Verification testing framework
├── validate-optimizations.sh      # Validation script (Linux/macOS/WSL)
├── validate-optimizations.ps1     # Validation script (Windows)
├── optimize-claude.sh             # Optimizer script (Linux/macOS/WSL)
├── optimize-claude.ps1            # Optimizer script (Windows)
└── src/                           # Source code (not included)
```

---

## 🔍 Key Undocumented Patterns

### Feature Flags (Compile-Time)

Claude Code uses 88+ build-time flags via `feature()` from `bun:bundle`:

| Flag | Purpose | File Ref |
|------|---------|----------|
| `TRANSCRIPT_CLASSIFIER` | Auto-mode permission classification | `src/utils/permissions/yoloClassifier.ts` |
| `KAIROS` | Multi-agent assistant system | `src/services/kairos/` |
| `PROACTIVE` | Agent acts without user prompts | `src/hooks/proactive.ts` |
| `BRIDGE_MODE` | Remote control over WebSocket | `src/services/bridge/` |
| `CACHED_MICROCOMPACT` | API cache editing for compaction | `src/services/compact/microCompact.ts` |
| `REACTIVE_COMPACT` | 413-triggered compaction | `src/services/compact/autoCompact.ts` |
| `CHICAGO_MCP` | Computer-use MCP (screen/keyboard) | `src/services/mcp/` |
| `WORKFLOW_SCRIPTS` | Workflow-backed skills | `src/tools/WorkflowTool/` |
| `PROMPT_CACHE_BREAK_DETECTION` | Detect prompt cache breaks | `src/services/api/promptCacheBreakDetection.ts` |

### Prompt Cache TTL & Keepalive

Anthropic's API has a **5-minute TTL** on prompt cache entries. After 5 minutes of inactivity:
- Cache is evicted
- Subsequent requests pay full price (no ~90% discount)
- For 200K context: **$6.00 vs $0.60 per request**

**Keepalive strategies:**
1. **Hook-based:** PostToolUse hook that fires every 4 minutes
2. **Background ping:** tmux script sending no-op messages
3. **`/loop` command:** Built-in for active tasks
4. **Pre-flight warmup:** Small request after breaks

See [prompt-caching.md](prompt-caching.md) for implementation details.

### Hidden CLI Subcommands

Fast-path commands handled before Commander parsing:

| Subcommand | Aliases | Purpose |
|------------|---------|---------|
| `remote-control` | `rc`, `remote`, `sync` | Remote session control |
| `daemon` | — | Long-running daemon mode |
| `ps` | — | List background sessions |
| `logs` | — | View session logs |
| `attach` | — | Attach to running session |
| `kill` | — | Kill a session |
| `environment-runner` | — | CI environment runner |
| `self-hosted-runner` | — | CI self-hosted runner |
| `ssh` | — | SSH remote sessions |

### Internal Environment Variables

Notable undocumented variables:

| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_DUMP_AUTO_MODE` | Log classifier I/O to console |
| `CLAUDE_CODE_TWO_STAGE_CLASSIFIER` | Enable XML classifier (fast/thinking modes) |
| `CLAUDE_CODE_JSONL_TRANSCRIPT` | Use JSONL format for classifier |
| `CLAUDE_INTERNAL_FC_OVERRIDES` | GrowthBook feature flag overrides (ant-only) |
| `CLAUDE_CODE_ABLATION_BASELINE` | Disable thinking, compaction, memory for experiments |
| `ENABLE_PID_BASED_VERSION_LOCKING` | PID-based update locking |
| `CLAUDE_CODE_COWORKER_TYPE` | Coworker type for telemetry |

See [undocumented-features.md](undocumented-features.md) for the full list.

---

## 🛡️ Security Internals

### Permission Decision Pipeline

From `src/utils/permissions/permissions.ts:1158-1319`:

1. **Deny rules** - Tool entirely denied
2. **Ask rules** - Tool requires explicit permission
3. **Tool.checkPermissions()** - Tool-specific validation
4. **User interaction required** - Tool needs interactive input
5. **Content-specific ask rules** - Pattern-based rules
6. **Safety checks** - Sensitive path checks (.git/, .claude/)
7. **Bypass permissions mode** - Skip remaining checks
8. **Always allow rules** - Tool pre-approved
9. **Auto mode classifier** - AI evaluation (two-stage XML)
10. **Passthrough → Ask** - Default to prompting

### Two-Stage XML Classifier

From `src/utils/permissions/yoloClassifier.ts`:

| Stage | Max Tokens | Output |
|-------|------------|--------|
| Stage 1 (Fast) | 64 | `<block>yes/no</block>` |
| Stage 2 (Thinking) | 4096 | `<thinking>...</thinking><block>yes/no</block><reason>...</reason>` |

### Iron Gate (Fail-Closed)

When classifier is unavailable:
- Check `tengu_iron_gate_closed` GrowthBook flag (default: true)
- If true: deny with retry guidance
- If false: fall through to prompting

---

## 📊 Telemetry Internals

### Data Collection Streams

| Stream | Endpoint | Data |
|----------|----------|------|
| 1P Event Logging | `/api/event_logging/batch` | Session, model, tool usage (sanitized), process metrics |
| Datadog | `http-intake.logs.us5.datadoghq.com` | API errors, tool usage, compaction events |
| OpenTelemetry | OTLP endpoint | Traces with user/session/org IDs |

### MCP Tool Name Sanitization

MCP tool names are redacted to `mcp_tool` unless:
- Built-in MCP servers (computer-use)
- claude.ai-proxied connectors
- Official MCP registry URLs

Custom/user-configured servers are redacted (PII-medium per taxonomy).

---

## 📝 Contributing

This documentation is derived from source code analysis. To contribute:

1. Focus on **undocumented** internals not in [official docs](https://code.claude.com/docs/en/)
2. Include specific file paths and line numbers
3. Cite source code references
4. Submit PRs to `carlosduplar/claude-code-fork`

---

## 📄 License

This documentation is provided as-is for educational and research purposes. The underlying Claude Code software is proprietary to Anthropic.
