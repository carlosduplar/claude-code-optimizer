# Claude Code Architecture Overview

## 1. COMPONENT ARCHITECTURE

### Core Entry Points
| Component | File | Purpose |
|-----------|------|---------|
| **CLI Bootstrap** | `src/entrypoints/cli.tsx` | Fast-path command handling, special flags, delegates to main |
| **Main Application** | `src/main.tsx` (~800KB) | Primary CLI logic, Commander setup, initializes all systems |
| **MCP Entry** | `src/entrypoints/mcp.ts` | Model Context Protocol entry point |
| **SDK Types** | `src/entrypoints/agentSdkTypes.ts` | Agent SDK type definitions |

### Key Systems

#### **Analytics & Telemetry** (`src/services/analytics/`)
| Component | Purpose |
|-----------|---------|
| `index.ts` | Main analytics API (`logEvent`, `logEventAsync`) |
| `sink.ts` | Routes events to Datadog and 1P logging |
| `metadata.ts` | Event metadata enrichment (platform, env, process metrics) |
| `datadog.ts` | Datadog integration with log batching |
| `firstPartyEventLogger.ts` | Internal event logging to BigQuery |
| `growthbook.ts` | Feature flagging via Statsig (~40KB) |
| `config.ts` | Analytics configuration, opt-out detection |

#### **Rate Limiting & Quotas** (`src/services/claudeAiLimits.ts`)
- **5-hour session limit** (`five_hour`): ~90% utilization triggers warning
- **7-day weekly limit** (`seven_day`): Tiered warnings at 25%, 50%, 75% utilization
- **Overage system**: Extra usage billing with separate quota tracking
- **Early warning thresholds**: Time-relative warnings based on consumption rate vs window elapsed

#### **Token Management** (`src/services/tokenEstimation.ts`)
- Uses Haiku for token counting (cheaper than main model)
- Special handling for Bedrock/Vertex providers
- Thinking blocks support with 1024 budget/2048 max tokens
- Tool search field stripping before counting

#### **Auto-Compaction** (`src/services/compact/autoCompact.ts`)
- **Threshold**: Context window minus 13,000 tokens (default)
- **Circuit breaker**: Stops after 3 consecutive failures
- **Session memory compaction**: Tries pruning before legacy compaction
- **Override env vars**:
  - `CLAUDE_CODE_AUTO_COMPACT_WINDOW` - custom window size
  - `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` - percentage-based threshold
  - `DISABLE_COMPACT` / `DISABLE_AUTO_COMPACT` - disable entirely

#### **Tool Result Storage** (`src/utils/toolResultStorage.ts`)
- **Per-tool limit**: 50,000 characters (default)
- **Per-message aggregate limit**: 200,000 characters (prevents N parallel tools from flooding context)
- **GrowthBook override**: `tengu_satin_quoll` flag for per-tool thresholds
- **Persistence**: Large results saved to `~/.claude/<project>/<session>/tool-results/`

---

## 2. HIDDEN TELEMETRY SYSTEMS

### Data Collection Streams

#### **First-Party Event Logging (1P)**
- **Endpoint**: `/api/event_logging/batch`
- **Data collected**:
  - Session ID, model, user type, betas enabled
  - Environment context (platform, arch, terminal, package managers, runtimes)
  - Process metrics (memory usage, CPU%, uptime)
  - Tool usage (sanitized names for MCP tools)
  - Git repo hash (first 16 chars of SHA256)
  - OAuth account UUID, organization UUID

#### **Datadog Logging**
- **Endpoint**: `http-intake.logs.us5.datadoghq.com`
- **Client token**: `pubbbf48e6d78dae54bceaa4acf463299bf`
- **Allowed events** (selective logging):
  - API errors/success, OAuth events, tool usage, compaction events
  - Terminal flicker, voice recording, bridge connections
  - Team memory sync events

#### **OpenTelemetry (OTel) Events**
- **Event logger**: Logs to OTLP endpoint
- **Attributes**:
  - `user.id`, `session.id`, `organization.id`, `user.email`, `user.account_uuid`
  - `terminal.type`, `app.version`, `prompt.id`
  - Workspace host paths (for desktop app)
- **Sampling**: Events may be sampled based on `tengu_event_sampling_config`

### Privacy Levels (`src/utils/privacyLevel.ts`)

| Level | Trigger | Effect |
|-------|---------|--------|
| `default` | None | Everything enabled |
| `no-telemetry` | `DISABLE_TELEMETRY=1` | Analytics/telemetry disabled |
| `essential-traffic` | `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | ALL nonessential network traffic disabled |

### Sensitive Data Handling

**Sanitization rules**:
- **MCP tool names**: Redacted to `mcp_tool` unless official registry URL or claude.ai-proxied
- **Tool inputs**: Truncated at 512 chars, max 4KB JSON, 20 collection items, depth 2
- **File extensions**: Logged but truncated if >10 chars (avoids hash-based filenames)
- **User prompts**: Redacted unless `OTEL_LOG_USER_PROMPTS=1`
- **PII-tagged proto columns**: `_PROTO_*` keys stripped before Datadog, only sent to 1P

---

## 3. API LIMITS & CONSTANTS

| Limit | Value | Location |
|-------|-------|----------|
| Max image base64 | 5MB | `apiLimits.ts` |
| Image target raw | 3.75MB | `apiLimits.ts` |
| Max image dimensions | 2000x2000 | `apiLimits.ts` |
| PDF target raw size | 20MB | `apiLimits.ts` |
| PDF max pages | 100 | `apiLimits.ts` |
| PDF inline threshold | 10 pages | `apiLimits.ts` |
| PDF max pages per read | 20 | `apiLimits.ts` |
| Max media per request | 100 items | `apiLimits.ts` |
| Default max result chars | 50,000 | `toolLimits.ts` |
| Max tool result tokens | 100,000 | `toolLimits.ts` |
| Bytes per token | 4 | `toolLimits.ts` |
| Max tool results per message | 200,000 chars | `toolLimits.ts` |

---

## 4. ARCHITECTURE PATTERNS

### Feature Flagging
- Heavy use of `feature('FLAG_NAME')` from `bun:bundle` for dead code elimination
- Flags are build-time evaluated, enabling tree-shaking

### Sink Pattern
Analytics uses a sink pattern for routing events to multiple backends (Datadog, 1P logging)

### Tool/Command Registry
Tools and commands are registered in central registries (`src/tools.ts`, `src/commands.ts`)

### React/Ink UI
Terminal UI built with React and a custom Ink implementation (`src/ink/`)

### Service Layer
Business logic organized into domain services (`src/services/`)

### Cache Key Components
Prompt cache hits require identical:
1. System prompt
2. Tools
3. Model
4. Messages prefix
5. Thinking config (changing this breaks cache!)
