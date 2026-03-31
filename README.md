# Claude Code Documentation

This repository contains comprehensive technical documentation for Claude Code, Anthropic's official CLI for Claude. This documentation was reverse-engineered from the source code to provide deep insights into the system's architecture.

## 📚 Documentation Index

### Getting Started

| Document | Description |
|----------|-------------|
| [Custom API Providers](docs/custom-api-providers.md) | Using Claude Code with third-party API endpoints (Fireworks AI, etc.) |

### Core Architecture

| Document | Description |
|----------|-------------|
| [Query Flow & Message Streaming](docs/query-flow.md) | How messages flow from user input through API streaming, retry logic, fallbacks, and response processing |
| [Session Memory & Context Management](docs/session-memory.md) | How Claude Code manages long conversations: compaction, memory extraction, checkpoints, and token budget management |
| [Tool System Architecture](docs/tool-system.md) | The tool framework: registration, permissions, execution, MCP/LSP integration, and bash providers |
| [Permission System & YOLO/Auto Mode](docs/permission-system.md) | Multi-layered permission system with AI-powered auto-mode classifier |
| [Skill & Plugin System](docs/skill-plugin-system.md) | Skills (markdown workflows), plugins (full extensions), bundled skills, and MCP integration |

### Internal Features

| Document | Description |
|----------|-------------|
| [Undocumented Features](docs/undocumented-features.md) | 88+ feature flags, hidden CLI commands, 60+ environment variables |
| [Anthropic-Only Commands](docs/ant-only-commands.md) | Commands gated behind `USER_TYPE=ant` and their implementations |

---

## 🏗️ Architecture Overview

### Repository Structure

```
claude-code/
├── docs/                          # This documentation
│   ├── custom-api-providers.md
│   ├── query-flow.md
│   ├── session-memory.md
│   ├── tool-system.md
│   ├── permission-system.md
│   ├── skill-plugin-system.md
│   ├── undocumented-features.md
│   └── ant-only-commands.md
└── src/                           # Source code (not included in this repo)
```

### Key Subsystems

1. **Query Engine** (`src/QueryEngine.ts`, `src/services/api/claude.ts`)
   - Message streaming with fallback to non-streaming
   - Retry logic with exponential backoff + jitter
   - Rate limit and error handling
   - 10 default max retries, 3 consecutive 529 errors before fallback

2. **Permission System** (`src/utils/permissions/`)
   - Multiple modes: default, acceptEdits, plan, bypassPermissions, dontAsk, auto
   - AI-powered auto-mode with two-stage XML classifier
   - Safe tool allowlist, dangerous pattern detection
   - Denial tracking with circuit breakers

3. **Tool Framework** (`src/tools/`, `src/Tool.ts`)
   - 40+ built-in tools (Bash, FileEdit, WebSearch, etc.)
   - MCP (Model Context Protocol) integration
   - LSP (Language Server Protocol) support
   - Tool permission contexts and validation

4. **Context Management** (`src/services/compact/`, `src/memdir/`)
   - Proactive compaction (token thresholds)
   - Reactive compaction (API 413 handling)
   - Session memory extraction (background summarization)
   - Micro-compaction (tool result management)
   - File checkpoints for rollback

5. **Skill System** (`src/skills/`, `src/tools/SkillTool/`)
   - SKILL.md format with YAML frontmatter
   - Inline and forked execution modes
   - Bundled skills (verify, debug, skillify, etc.)
   - Dynamic skill discovery from `.claude/skills/`

6. **Plugin System** (`src/plugins/`, `src/utils/plugins/`)
   - Full-featured extensions with hooks, MCP/LSP servers
   - Plugin manifest (plugin.json) schema
   - Namespaced commands: `plugin-name:command-name`

---

## 🔧 Environment Variables

### Critical for Custom Providers

```bash
# Authentication - use API_KEY not AUTH_TOKEN for custom endpoints
ANTHROPIC_API_KEY=fw_...                    # For x-api-key header
ANTHROPIC_BASE_URL=https://api.fireworks.ai/inference

# Model selection
ANTHROPIC_MODEL=accounts/fireworks/models/kimi-k2p5
ANTHROPIC_SMALL_FAST_MODEL=accounts/fireworks/models/kimi-k2p5
```

### Feature Control

```bash
CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1    # Strip beta headers
CLAUDE_CODE_DUMP_AUTO_MODE=1               # Log classifier I/O
CLAUDE_CODE_AUTO_MODE_MODEL=sonnet          # Override classifier model
```

### See Also

- [Full environment variable list](docs/undocumented-features.md#undocumented-environment-variables) (60+ variables)

---

## 🛡️ Security Features

### Permission System

- **Safe tool allowlist**: Read operations bypass classifier
- **Dangerous pattern detection**: Strips `Bash(*)`, `Agent(*)`, etc.
- **Iron gate (fail-closed)**: Classifier unavailable → deny with retry guidance
- **Denial limits**: 3 consecutive / 20 total denials before fallback to prompting

### Path Validation

- Symlink traversal protection for team memory
- Path normalization and escape detection
- `.git/` and `.claude/` safety checks

### Anti-Distillation

- Fake tool injection (`ANTI_DISTILLATION_CC`)
- Connector text summarization with signature verification

---

## 🎯 Feature Flags

Claude Code uses 88+ compile-time feature flags via `feature()` from `bun:bundle`:

### Notable Flags

| Flag | Description |
|------|-------------|
| `TRANSCRIPT_CLASSIFIER` | Auto-mode permission classification |
| `KAIROS` | Multi-agent assistant system |
| `PROACTIVE` | Agent acts without user prompts |
| `BRIDGE_MODE` | Remote control over WebSocket |
| `WORKFLOW_SCRIPTS` | Workflow-backed skills |
| `CHICAGO_MCP` | Computer-use MCP (screen/keyboard) |
| `MCP_SKILLS` | MCP server skill fetching |
| `CACHED_MICROCOMPACT` | API cache editing for compaction |
| `REACTIVE_COMPACT` | 413-triggered compaction |

---

## 📊 Configuration

### Skill Directories

```
~/.claude/skills/                  # Personal skills
.claude/skills/                    # Project skills (up tree to home)
managed/.claude/skills/            # Policy skills (unless disabled)
.claude/commands/                  # Legacy commands
```

### Session Storage

```
~/.claude/history.jsonl            # Command history (100 items)
~/.claude/projects/{cwd}/{sessionId}.jsonl   # Session transcript
~/.claude/projects/{cwd}/{sessionId}/session-memory/summary.md   # Session memory
~/.claude/projects/{cwd}/memory/   # Auto-memory / memdir
```

---

## 🔍 Key Implementation Details

### Retry Logic

```typescript
// Exponential backoff + jitter
const baseDelay = Math.min(500 * Math.pow(2, attempt - 1), 32000)
const jitter = Math.random() * 0.25 * baseDelay
return baseDelay + jitter
```

### Streaming Fallback

1. Streaming request → timeout/error
2. Fallback to non-streaming (64k token cap)
3. If still failing → model fallback (e.g., Opus → Sonnet)

### Permission Mode Cycling

Shift+Tab cycles: `default` → `acceptEdits` → `plan` → `bypassPermissions` → `auto`

---

## 📝 Contributing

This documentation is derived from source code analysis of Claude Code. To contribute:

1. Create a new branch from `main`
2. Add or edit documentation in `docs/`
3. Update this README with new entries
4. Submit a PR to `carlosduplar/claude-code-fork`

---

## 📄 License

This documentation is provided as-is for educational and research purposes. The underlying Claude Code software is proprietary to Anthropic.

---

## 🙏 Acknowledgments

Documentation compiled through reverse engineering of the Claude Code source tree. Special thanks to the Claude Code engineering team for building such a sophisticated system.
