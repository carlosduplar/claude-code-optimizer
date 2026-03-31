# Environment Variables Reference

## Authentication & API

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Direct API key auth | - |
| `ANTHROPIC_BASE_URL` | Custom API endpoint | - |
| `ANTHROPIC_AUTH_TOKEN` | Alternative auth token | - |
| `ANTHROPIC_UNIX_SOCKET` | Unix socket for API | - |
| `CLAUDE_CODE_USE_BEDROCK` | Use AWS Bedrock | false |
| `CLAUDE_CODE_USE_VERTEX` | Use Google Vertex AI | false |
| `CLAUDE_CODE_USE_FOUNDRY` | Use Anthropic Foundry | false |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | Bedrock region | `us-east-1` |
| `CLOUD_ML_REGION` | Vertex region | `us-east5` |

## Performance & Behavior

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_DISABLE_FAST_MODE` | Disable fast mode | false |
| `CLAUDE_CODE_SKIP_FAST_MODE_NETWORK_ERRORS` | Bypass fast mode org checks | false |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | Disable advisor tool | false |
| `CLAUDE_CODE_DISABLE_ATTACHMENTS` | Disable file attachments | false |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | Disable beta features | false |
| `CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING` | Enhanced tool streaming | false |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | Disable background agents | false |
| `CLAUDE_AUTO_BACKGROUND_TASKS` | Auto-background after 120s | false |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | Disable 1M context (HIPAA) | false |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | Override context window (ant-only) | - |

## Privacy & Telemetry

| Variable | Description | Default |
|----------|-------------|---------|
| `DISABLE_TELEMETRY` | Disable all telemetry | false |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Essential traffic only | false |
| `OTEL_LOG_USER_PROMPTS` | Log full prompts | false |
| `OTEL_LOG_TOOL_DETAILS` | Log MCP server/tool names | false |
| `OTEL_METRICS_INCLUDE_SESSION_ID` | Include session ID in metrics | true |
| `OTEL_METRICS_INCLUDE_VERSION` | Include version in metrics | false |
| `OTEL_METRICS_INCLUDE_ACCOUNT_UUID` | Include account UUID | true |

## Context & Compaction

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Custom context window size | 200000 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Compaction threshold % | - |
| `DISABLE_COMPACT` | Disable all compaction | false |
| `DISABLE_AUTO_COMPACT` | Disable only auto-compact | false |
| `CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE` | Hard token limit override | - |
| `CLAUDE_CONTEXT_COLLAPSE` | Enable context collapse (ant-only) | - |

## Development & Debugging

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_SIMPLE` / `--bare` | Minimal mode (no hooks, LSP, plugins) | false |
| `CLAUDE_CONFIG_DIR` | Custom config directory | `~/.claude` |
| `CLAUDE_CODE_TERMINAL_RECORDING` | Enable asciicast recording (ant-only) | false |
| `USER_TYPE=ant` | Internal employee mode | - |
| `CLAUDE_CODE_ENTRYPOINT` | Entry point identifier | - |

## Remote & Container

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_REMOTE` | Remote session mode | false |
| `CLAUDE_CODE_CONTAINER_ID` | Container identifier | - |
| `CLAUDE_CODE_REMOTE_SESSION_ID` | Remote session tracking | - |
| `CLAUDE_CODE_WORKSPACE_HOST_PATHS` | Host workspace paths | - |
| `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE` | Remote environment type | - |

## Hooks & Plugins

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` | Session end hook timeout | 1500ms |
| `CLAUDE_CODE_ENABLE_TOKEN_USAGE_ATTACHMENT` | Show token usage in context | false |
| `CLAUDE_CODE_VERIFY_PLAN` | Enable plan verification (ant-only) | false |

## Network & Proxy

| Variable | Description | Default |
|----------|-------------|---------|
| `HTTPS_PROXY` / `HTTP_PROXY` | Proxy settings | - |
| `CLAUDE_CODE_CLIENT_CERT` | Client certificate path | - |
| `CLAUDE_CODE_CLIENT_KEY` | Client key path | - |

## Model Overrides

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_SMALL_FAST_MODEL` | Small/fast model override | - |
| `CLAUDE_CODE_OPUS_4_6_FAST_MODE_REGION` | Fast mode region | - |

## Bash & Shell

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` | Reset WD after each command | false |
| `SHELL` | Shell override | `$SHELL` |

## Terminal Detection

| Variable | Description |
|----------|-------------|
| `TERM_PROGRAM` | Terminal program (iTerm, vscode, etc.) |
| `VSCODE_GIT_ASKPASS_MAIN` | VS Code / Cursor / Windsurf detection |
| `__CFBundleIdentifier` | macOS bundle ID detection |
| `TMUX` | Tmux detection |
| `TERM` | Terminal type |

## CI/CD Detection

| Variable | Description |
|----------|-------------|
| `CI` | Generic CI detection |
| `GITHUB_ACTIONS` | GitHub Actions |
| `CLAUDE_CODE_ACTION` | Claude Code Action |
| `RUNNER_OS` | GitHub Actions runner OS |
| `GITHUB_EVENT_NAME` | GitHub event type |

---

## Privacy Mode Combinations

### Maximum Privacy
```bash
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export OTEL_LOG_USER_PROMPTS=0
export OTEL_LOG_TOOL_DETAILS=0
```

### Essential Traffic Only
```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
```

### No Telemetry (Analytics Only)
```bash
export DISABLE_TELEMETRY=1
```

---

## Context Window Overrides

### Force 1M Context (if available)
```bash
# Model string suffix
CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000  # ant-only
```

### Cap Context Window
```bash
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000
```

### Disable 1M Context (HIPAA compliance)
```bash
export CLAUDE_CODE_DISABLE_1M_CONTEXT=1
```

---

## Rate Limit & Performance

### Skip Fast Mode Network Checks
```bash
export CLAUDE_CODE_SKIP_FAST_MODE_NETWORK_ERRORS=1
```

### Disable Fast Mode
```bash
export CLAUDE_CODE_DISABLE_FAST_MODE=1
```

### Enable Background Tasks
```bash
export CLAUDE_AUTO_BACKGROUND_TASKS=1
```

---

## Development Mode

### Bare Mode (Minimal)
```bash
claude --bare
# OR
export CLAUDE_CODE_SIMPLE=1
```

Effects:
- Skips hooks
- Skips LSP
- Skips plugin sync
- Skips skill dir-walk
- Skips attribution
- Skips background prefetches
- No keychain/credential reads
