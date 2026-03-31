# Undocumented Features in Claude Code

A comprehensive inventory of features, flags, and internal systems found in the Claude Code source that are not covered in official documentation.

## Build-Time Feature Flags

Claude Code uses compile-time feature flags via `feature()` (imported from `bun:bundle`) for dead code elimination. There are **88 unique flags**. Most are undocumented and gated behind Anthropic's internal build configuration.

### Agent Orchestration

| Flag | File References | Description |
|---|---|---|
| `KAIROS` | Multiple | Full "assistant" agent mode with multi-agent capabilities |
| `KAIROS_BRIEF` | commands/brief.tsx | KAIROS brief sub-feature |
| `KAIROS_CHANNELS` | services/ | Channel-based notifications for KAIROS |
| `KAIROS_DREAM` | services/ | KAIROS dream feature (purpose unclear) |
| `KAIROS_GITHUB_WEBHOOKS` | commands/subscribe-pr.tsx | GitHub webhook subscriptions |
| `KAIROS_PUSH_NOTIFICATION` | services/ | Push notification support |
| `PROACTIVE` | components/, hooks/ | Agent acts without user prompts |
| `COORDINATOR_MODE` | coordinator/ | Multi-agent orchestrator |
| `AGENT_TRIGGERS` | services/ | Cron-based agent scheduling |
| `AGENT_TRIGGERS_REMOTE` | tools/ | Remote trigger tool |
| `AGENT_MEMORY_SNAPSHOT` | memdir/ | Persistent memory snapshots |
| `VERIFICATION_AGENT` | tools/ | Separate verification agent |
| `BUILTIN_EXPLORE_PLAN_AGENTS` | tools/ | Built-in explore/plan agent pair |
| `FORK_SUBAGENT` | commands/fork.ts | Fork a sub-agent from current session |
| `TRANSCRIPT_CLASSIFIER` | hooks/ | Auto permission mode from conversation analysis |

### Remote & Daemon

| Flag | Description |
|---|---|
| `BRIDGE_MODE` | Remote control over WebSocket |
| `DAEMON` | Long-running daemon supervisor |
| `BG_SESSIONS` | Background session management (`ps`, `logs`, `attach`, `kill`) |
| `DIRECT_CONNECT` | `cc://` and `cc+unix://` URL scheme support |
| `LODESTONE` | Deep link URI handling |
| `SSH_REMOTE` | `claude ssh <host>` sessions |
| `CCR_REMOTE_SETUP` | CCR remote setup web command |
| `CCR_AUTO_CONNECT` | CCR auto-connect |
| `CCR_MIRROR` | CCR session mirroring |
| `SELF_HOSTED_RUNNER` | CI self-hosted runner |
| `BYOC_ENVIRONMENT_RUNNER` | Bring-your-own-cloud runner |
| `UDS_INBOX` | Unix domain socket inbox/peers |

### Model & API

| Flag | Description |
|---|---|
| `ANTI_DISTILLATION_CC` | Content filtering against distillation |
| `CACHED_MICROCOMPACT` | Cached micro-compaction |
| `PROMPT_CACHE_BREAK_DETECTION` | Detect prompt cache breaks |
| `CONTEXT_COLLAPSE` | Context compaction |
| `REACTIVE_COMPACT` | Reactive compaction |
| `TOKEN_BUDGET` | API-side token budgets |
| `UNATTENDED_RETRY` | Unattended retry logic |
| `BASH_CLASSIFIER` | Bash command classification |
| `CONNECTOR_TEXT` | Connector text summarization |
| `EFFORT_BETA_HEADER` | Effort level beta |

### Tools & Integrations

| Flag | Description |
|---|---|
| `CHICAGO_MCP` | Computer-use MCP (screen/keyboard control) |
| `MCP_SKILLS` | MCP server skill fetching |
| `MCP_RICH_OUTPUT` | Rich MCP output rendering |
| `EXPERIMENTAL_SKILL_SEARCH` | Skill search/discovery |
| `SKILL_IMPROVEMENT` | Skill improvement surveys |
| `RUN_SKILL_GENERATOR` | Skill generator |
| `WORKFLOW_SCRIPTS` | Workflow tool/scripts |
| `WEB_BROWSER_TOOL` | Web browser tool |
| `TOOL_SEARCH` | Tool search capability |
| `TREE_SITTER_BASH` | Tree-sitter bash parsing |
| `POWERSHELL_AUTO_MODE` | PowerShell auto-mode detection |

### UI & UX

| Flag | Description |
|---|---|
| `BUDDY` | Buddy companion sprite with notifications |
| `AUTO_THEME` | Auto theme detection |
| `HISTORY_PICKER` | History picker dialog |
| `HISTORY_SNIP` | Force-snip history command |
| `MESSAGE_ACTIONS` | Message action menus |
| `QUICK_SEARCH` | Quick search feature |
| `TERMINAL_PANEL` | Terminal panel |
| `STREAMLINED_OUTPUT` | Streamlined output mode |
| `VOICE_MODE` | Voice interaction |

### Telemetry & Internal

| Flag | Description |
|---|---|
| `PERFETTO_TRACING` | Perfetto-compatible trace export |
| `ENHANCED_TELEMETRY_BETA` | Enhanced telemetry |
| `SHOT_STATS` | Shot statistics (ant-only) |
| `SLOW_OPERATION_LOGGING` | Slow operation logging |
| `ABLATION_BASELINE` | Harness-science experiments (disables thinking, compaction, memory, tasks) |
| `ULTRAPLAN` | Extended planning mode |
| `ULTRATHINK` | Extended thinking mode |
| `TORCH` | Torch feature |

## Hidden CLI Flags

Undocumented top-level flags from `src/main.tsx`:

| Flag | Description |
|---|---|
| `--bare` | Stripped-down hermetic auth mode |
| `--json-schema <schema>` | Enforce JSON output schema |
| `--include-hook-events` | Emit hook events in output |
| `--input-format <format>` | Structured input parsing |
| `--replay-user-messages` | Replay mode |
| `--prefill <text>` | Prefill the assistant response |
| `--agents <json>` | Pass agent definitions as JSON |
| `--setting-sources <sources>` | Custom setting sources |
| `--disable-slash-commands` | Disable all slash commands |
| `--fork-session` | Fork current session |
| `--from-pr <pr>` | Start from a PR |
| `--agent <agent>` | Launch a specific agent |
| `--betas <betas>` | Pass API beta flags |
| `--effort <level>` | Set reasoning effort level |
| `--session-id <uuid>` | Force a specific session UUID |
| `--name <name>` | Name the session |
| `--file <specs>` | Pre-load file specs |
| `--fallback-model <model>` | Fallback model on primary failure |
| `--strict-mcp-config` | Strict MCP config mode |
| `--plugin-dir <path>` | Plugin directory path |
| `--chrome/--no-chrome` | Chrome integration toggle |
| `--debug-file <path>` | Debug log to file |

## Fast-Path Subcommands

Handled before Commander argument parsing in `src/entrypoints/cli.tsx`:

| Subcommand | Aliases | Description |
|---|---|---|
| `remote-control` | `rc`, `remote`, `sync` | Remote session control |
| `daemon` | — | Long-running daemon mode |
| `ps` | — | List background sessions |
| `logs` | — | View session logs |
| `attach` | — | Attach to running session |
| `kill` | — | Kill a session |
| `new` | — | New session |
| `list` | — | List sessions |
| `reply` | — | Reply to a session |
| `environment-runner` | — | CI environment runner |
| `self-hosted-runner` | — | CI self-hosted runner |
| `ssh` | — | SSH remote sessions |
| `open` | — | Internal `cc://` deep link handler |

## Anthropic-Only Commands

Commands gated behind `USER_TYPE === 'ant'` (Anthropic employees):

`backfill-sessions`, `break-cache`, `bughunter`, `commit`, `commit-push-pr`, `ctx_viz`, `good-claude`, `issue`, `init-verifiers`, `mock-limits`, `bridge-kick`, `version`, `reset-limits`, `onboarding`, `share`, `summary`, `teleport`, `ant-trace`, `perf-issue`, `env`, `oauth-refresh`, `debug-tool-call`, `agents-platform`, `autofix-pr`

## Feature-Gated Commands

Commands available only when their corresponding feature flag is enabled:

| Command | Feature Flag |
|---|---|
| `remote-setup` | `CCR_REMOTE_SETUP` |
| `fork` | `FORK_SUBAGENT` |
| `buddy` | `BUDDY` |
| `proactive` | `PROACTIVE` or `KAIROS` |
| `brief` | `KAIROS` or `KAIROS_BRIEF` |
| `assistant` | `KAIROS` |
| `bridge` | `BRIDGE_MODE` |
| `remote-control-server` | `DAEMON` + `BRIDGE_MODE` |
| `voice` | `VOICE_MODE` |
| `peers` | `UDS_INBOX` |
| `workflows` | `WORKFLOW_SCRIPTS` |
| `torch` | `TORCH` |
| `subscribe-pr` | `KAIROS_GITHUB_WEBHOOKS` |
| `ultraplan` | `ULTRAPLAN` |
| `force-snip` | `HISTORY_SNIP` |

## Undocumented Environment Variables

### Feature Enable

| Variable | Description |
|---|---|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Multi-agent swarm spawning |
| `CLAUDE_CODE_ENABLE_CFC` | Claude-in-Chrome integration |
| `CLAUDE_CODE_ENABLE_XAA` | Extended Authorization Architecture (MCP OAuth) |
| `ENABLE_AGENT_SWARMS` | Agent swarm support |
| `ENABLE_TOOL_SEARCH` | Tool search/discovery |
| `ENABLE_SESSION_PERSISTENCE` | Session persistence |
| `ENABLE_BETA_TRACING_DETAILED` | Detailed beta tracing |
| `ENABLE_PROMPT_CACHING_1H_BEDROCK` | 1-hour prompt caching (Bedrock) |
| `ENABLE_ENHANCED_TELEMETRY_BETA` | Enhanced telemetry beta |
| `ENABLE_PID_BASED_VERSION_LOCKING` | PID-based version locking |
| `ENABLE_LOCKLESS_UPDATES` | Lockless update mechanism |
| `ENABLE_LSP_TOOL` | LSP tool |
| `ENABLE_CLAUDEAI_MCP_SERVERS` | claude.ai MCP servers |
| `ENABLE_MCP_LARGE_OUTPUT_FILES` | Large MCP output files |
| `ENABLE_CLAUDE_CODE_SM_COMPACT` | Session-memory compaction |

### Feature Disable

| Variable | Description |
|---|---|
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | Kill switch for all experimental beta headers |
| `CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING` | File checkpoint/rollback |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Automatic memory extraction |
| `CLAUDE_CODE_DISABLE_MESSAGE_ACTIONS` | Message action menus |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | Background task execution |
| `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL` | Virtual scrolling |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | Advisor tool |
| `CLAUDE_CODE_DISABLE_POLICY_SKILLS` | Policy-based skills |
| `CLAUDE_CODE_DISABLE_SM_COMPACT` | Session-memory compaction |
| `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | Terminal title setting |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | Feedback surveys |
| `CLAUDE_CODE_DISABLE_LEGACY_MODEL_REMAP` | Legacy model remapping |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Non-essential network traffic |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | Non-streaming fallback |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | Git instructions |
| `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL` | Marketplace auto-install |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS` | Claude MDS |
| `CLAUDE_CODE_DISABLE_PRECOMPACT_SKIP` | Pre-compact skip |
| `DISABLE_PROMPT_CACHING` | All prompt caching |
| `DISABLE_PROMPT_CACHING_HAIKU` | Prompt caching for Haiku |
| `DISABLE_PROMPT_CACHING_SONNET` | Prompt caching for Sonnet |
| `DISABLE_PROMPT_CACHING_OPUS` | Prompt caching for Opus |
| `DISABLE_COMPACT` | Compaction entirely |
| `DISABLE_AUTO_COMPACT` | Auto-compaction |
| `DISABLE_INTERLEAVED_THINKING` | Interleaved thinking |
| `DISABLE_AUTOUPDATER` | Auto-updater |
| `DISABLE_LOGIN_COMMAND` | `/login` command |
| `DISABLE_LOGOUT_COMMAND` | `/logout` command |
| `DISABLE_FEEDBACK_COMMAND` | Feedback command |
| `DISABLE_DOCTOR_COMMAND` | `/doctor` command |
| `DISABLE_INSTALL_GITHUB_APP_COMMAND` | GitHub app install |
| `DISABLE_UPGRADE_COMMAND` | `/upgrade` command |
| `DISABLE_EXTRA_USAGE_COMMAND` | Extra-usage command |
| `DISABLE_COST_WARNINGS` | Cost warnings |
| `DISABLE_ERROR_REPORTING` | Error reporting |
| `DISABLE_TELEMETRY` | Telemetry |
| `DISABLE_INSTALLATION_CHECKS` | Installation checks |

### Internal / Anthropic

| Variable | Description |
|---|---|
| `USER_TYPE` | Set to `'ant'` for internal Anthropic employees |
| `CLAUDE_INTERNAL_FC_OVERRIDES` | GrowthBook feature flag overrides |
| `CLAUDE_CODE_GB_BASE_URL` | GrowthBook base URL |
| `USE_LOCAL_OAUTH` | Local OAuth config |
| `USE_STAGING_OAUTH` | Staging OAuth config |
| `CLAUDE_CODE_CUSTOM_OAUTH_URL` | Custom OAuth URL |
| `CLAUDE_CODE_ABLATION_BASELINE` | Ablation baseline config |
| `CLAUDE_ENABLE_STREAM_WATCHDOG` | Stream health watchdog |
| `IS_DEMO` | Demo environment |
| `CLAUDE_CODE_COWORKER_TYPE` | Coworker type for telemetry |
| `CLAUDE_CODE_TAGS` | Session tags |
| `MCP_CLIENT_SECRET` | MCP OAuth client secret |
| `MCP_XAA_IDP_CLIENT_SECRET` | MCP XAA IdP client secret |
| `CLAUDE_CODE_SIMPLE` | Bare/simple mode flag |

### Operational

| Variable | Description |
|---|---|
| `CLAUDE_CODE_REMOTE` | Running in CCR environment |
| `CLAUDE_CODE_ENTRYPOINT` | Entrypoint identifier (cli, sdk-cli, mcp, local-agent, etc.) |
| `CLAUDE_CODE_ACTION` | Running as GitHub Action |
| `CLAUDE_CODE_SESSION_ACCESS_TOKEN` | Remote session access token |
| `CLAUDE_CODE_HOST_PLATFORM` | Host platform override |
| `CLAUDECODE` | Set to `'1'` for child processes |
| `ANTHROPIC_CUSTOM_HEADERS` | Custom HTTP headers (newline-separated `Name: Value` format) |
| `ANTHROPIC_CUSTOM_MODEL_OPTION` | Pre-validated model name (skips validation) |
| `ANTHROPIC_BETAS` | Comma-separated extra beta headers |
| `CLAUDE_CODE_EXTRA_BODY` | Extra JSON body params for API requests |
| `CLAUDE_CODE_EXTRA_METADATA` | Extra metadata for API requests |
| `API_TIMEOUT_MS` | API timeout in milliseconds (default: 600000) |

## Notable Hidden Systems

### Anti-Debug Protection

In non-ant builds, the process exits if a debugger is detected (`src/main.tsx:266-271`).

### Secret Scanner

`src/services/teamMemorySync/secretScanner.ts` implements client-side secret scanning before team memory uploads, with 23+ detection rules.

### Deep Link Handler

`cc://` and `cc+unix://` URL scheme support via the `LODESTONE` and `DIRECT_CONNECT` feature flags.

### Plugin System

Full plugin infrastructure with `/plugin`, `/reload-plugins` commands and `--plugin-dir` flag (`src/plugins/`).

### Vim Mode

Complete vim keybinding support with text objects, operators, motions (`src/vim/`).

### Memdir System

Persistent memory directory for cross-session memory (`src/memdir/`).

### Buddy Companion

A UI sprite/companion system with notifications (`src/buddy/`).

### experimentalSystemReminder

An experimental field on agent definitions (`src/Tool.ts:275`) that re-injects a system reminder every user turn.
