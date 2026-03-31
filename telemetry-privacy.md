# Telemetry & Privacy Guide

## Overview

Claude Code has three privacy levels that control telemetry and network traffic:

| Level | Trigger | Effect |
|-------|---------|--------|
| `default` | None | Everything enabled |
| `no-telemetry` | `DISABLE_TELEMETRY=1` | Analytics/telemetry disabled |
| `essential-traffic` | `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | ALL nonessential network traffic disabled |

The resolved level is the **most restrictive** signal from all sources.

---

## Telemetry Systems

### 1. First-Party Event Logging (1P)

**Purpose**: Internal analytics and debugging

**Endpoint**: `/api/event_logging/batch`

**Data collected**:
- Session ID, model, user type, betas enabled
- Environment context:
  - Platform, architecture, terminal type
  - Package managers detected (npm, yarn, pnpm)
  - Runtimes detected (bun, deno, node)
  - WSL version, Linux distro info
  - VCS detected (git, svn, etc.)
- Process metrics:
  - Memory usage (rss, heap, external)
  - CPU usage percentage
  - Uptime
- Tool usage (sanitized):
  - Built-in tool names: logged as-is
  - MCP tool names: redacted to `mcp_tool` unless from official registry
- Git repo hash (first 16 chars of SHA256)
- OAuth account UUID, organization UUID
- Subscription tier (max, pro, enterprise, team)

**Opt-out**:
```bash
export DISABLE_TELEMETRY=1
```

---

### 2. Datadog Logging

**Purpose**: Operational monitoring and debugging

**Endpoint**: `https://http-intake.logs.us5.datadoghq.com/api/v2/logs`

**Client token**: `pubbbf48e6d78dae54bceaa4acf463299bf`

**Flush interval**: 15 seconds (batching)

**Allowed events** (selective logging - not all events):
- API errors/success
- OAuth events (token refresh, errors)
- Tool usage (granted, rejected, success, error)
- Compaction events
- Terminal flicker
- Voice recording
- Bridge connections
- Team memory sync
- Exit/crash events

**Opt-out**:
```bash
export DISABLE_TELEMETRY=1
```

---

### 3. OpenTelemetry (OTel)

**Purpose**: Distributed tracing and metrics

**Logger**: Exports to OTLP endpoint

**Attributes collected**:
- `user.id` - Anonymous user ID (always)
- `session.id` - Session identifier (configurable)
- `organization.id` - OAuth org ID (if available)
- `user.email` - OAuth email (if available)
- `user.account_uuid` - OAuth account UUID (configurable)
- `terminal.type` - Detected terminal
- `app.version` - Claude Code version (configurable)
- `prompt.id` - Current prompt ID
- `workspace.host_paths` - Host paths (desktop app only)

**Configuration**:
```bash
# Disable all OTel
export DISABLE_TELEMETRY=1

# Configure metrics cardinality
export OTEL_METRICS_INCLUDE_SESSION_ID=false
export OTEL_METRICS_INCLUDE_VERSION=false
export OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false

# Enable detailed logging (disabled by default)
export OTEL_LOG_USER_PROMPTS=1        # Log full prompts
export OTEL_LOG_TOOL_DETAILS=1      # Log MCP server/tool names
```

---

## Data Sanitization

### Tool Input Truncation

For telemetry purposes, tool inputs are automatically truncated:
- **Strings**: >512 chars truncated to 128 chars
- **Arrays**: Max 20 items
- **Objects**: Max 20 keys, depth 2
- **JSON output**: Max 4KB

**Example**:
```typescript
// Original input
{
  "command": "git log --oneline --all --graph --decorate --source --remotes --... (500+ chars)"
}

// Logged as
{
  "command": "git log --oneline --all --graph --dec…[567 chars]"
}
```

### MCP Tool Name Sanitization

MCP tool names are redacted unless they meet specific criteria:

**Logged as-is**:
- Built-in MCP servers (computer-use)
- claude.ai-proxied connectors
- Servers matching official MCP registry URLs

**Redacted to `mcp_tool`**:
- Custom/user-configured MCP servers
- Non-official URLs
- Local/stdio MCP servers

**Why**: MCP server names can reveal user-specific configurations (PII-medium per taxonomy).

---

## PII Handling

### Marked Types (Compile-time Protection)

The codebase uses TypeScript types to prevent accidental logging:

```typescript
// This type forces developers to explicitly verify strings don't contain code/filepaths
type AnalyticsMetadata_I_VERIFIED_THIS_IS_NOT_CODE_OR_FILEPATHS = never

// This type allows PII-tagged proto columns (privileged access)
type AnalyticsMetadata_I_VERIFIED_THIS_IS_PII_TAGGED = never
```

### Proto Column Routing

Data prefixed with `_PROTO_` is:
1. **Stripped** before Datadog fanout
2. **Hoisted** to proto fields in 1P logging
3. **Kept redacted** in general-access backends

Example:
```typescript
// In code
logEvent('event', {
  toolName: 'safe_name',
  _PROTO_userEmail: user.email  // Only reaches 1P privileged column
})
```

---

## Feature Flags (GrowthBook/Statsig)

Dynamic configuration controlled server-side:

| Flag | Purpose |
|------|---------|
| `tengu_event_sampling_config` | Per-event sampling rates (0-1) |
| `tengu_log_datadog_events` | Datadog logging toggle |
| `tengu_1p_event_batch_config` | 1P logging batch/queue config |
| `tengu_satin_quoll` | Per-tool persistence thresholds |
| `tengu_hawthorn_window` | Per-message budget limit |
| `tengu_hawthorn_steeple` | Enable message-level budget |
| `tengu_penguins_off` | Fast mode kill switch |

**Note**: These are server-controlled and cannot be overridden locally.

---

## Network Traffic Categories

### Essential Traffic (Always Enabled)

- Anthropic API calls (messages, token counting)
- OAuth token refresh
- Bootstrap data fetching (if OAuth)

### Non-Essential Traffic (Can Be Disabled)

- Analytics/telemetry
- Auto-updates
- Release notes fetching
- Changelog fetching
- Model capabilities prefetch
- Grove integration
- Plugin marketplace sync
- MCP registry sync

**Disable with**:
```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
```

---

## Recommended Configurations

### Maximum Privacy

```bash
# In ~/.bashrc, ~/.zshrc, or before running claude
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export OTEL_LOG_USER_PROMPTS=0
export OTEL_LOG_TOOL_DETAILS=0
```

**Effects**:
- No analytics sent to Datadog
- No 1P event logging
- No auto-updates
- No release notes/changelog fetching
- No plugin marketplace sync

### Moderate Privacy (Keep Functionality)

```bash
export DISABLE_TELEMETRY=1
```

**Effects**:
- No analytics
- Keeps auto-updates, release notes
- Keeps plugin functionality

### Corporate/Restricted Environment

```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export HTTPS_PROXY=http://proxy.company.com:8080
export CLAUDE_CODE_SIMPLE=1  # Minimal mode
```

---

## Verification

### Check Current Privacy Level

```bash
# Start claude and run:
/debug
```

Look for:
- `telemetry: disabled` or `enabled`
- `analytics: disabled` or `enabled`
- `nonessential_traffic: blocked` or `allowed`

### Check Environment Variables

```bash
echo "Telemetry: $DISABLE_TELEMETRY"
echo "Nonessential: $CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
```

---

## Legal & Compliance Notes

### HIPAA

For HIPAA compliance, disable 1M context:
```bash
export CLAUDE_CODE_DISABLE_1M_CONTEXT=1
```

### GDPR/CCPA

Users can request data deletion by:
1. Setting `DISABLE_TELEMETRY=1` to stop future collection
2. Contacting Anthropic support for historical data deletion

### Audit Logging

For compliance environments, enable all logging:
```bash
export OTEL_LOG_USER_PROMPTS=1
export OTEL_LOG_TOOL_DETAILS=1
export OTEL_METRICS_INCLUDE_SESSION_ID=true
export OTEL_METRICS_INCLUDE_ACCOUNT_UUID=true
```

---

## Troubleshooting

### Telemetry Still Sending?

1. Verify env vars are exported:
   ```bash
   export -p | grep -E '(DISABLE_TELEMETRY|NONENTIAL)'
   ```

2. Check for config file overrides in `~/.claude.json`

3. Restart claude completely (env vars set at startup)

### Missing Analytics?

If you're an admin expecting analytics but seeing nothing:
1. Check `DISABLE_TELEMETRY` isn't set globally
2. Verify network connectivity to Datadog/1P endpoints
3. Check GrowthBook feature flags aren't sampling events
