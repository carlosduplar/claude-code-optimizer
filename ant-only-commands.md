# Anthropic-Internal Commands

## Overview

Claude Code defines 24 commands restricted to Anthropic employees. They are gated by a single environment variable check in `src/commands.ts:343-345`:

```typescript
...(process.env.USER_TYPE === 'ant' && !process.env.IS_DEMO
    ? INTERNAL_ONLY_COMMANDS
    : []),
```

Two additional commands (`tag`, `files`) have their own `isEnabled: () => process.env.USER_TYPE === 'ant'` guards but are not in the `INTERNAL_ONLY_COMMANDS` array.

## Can `USER_TYPE=ant` Activate Them?

**Partially.** There is no client-side anti-tampering. The check is a plain `process.env` read with no validation against any auth system. Setting `USER_TYPE=ant` in your environment will cause Claude Code to register the internal commands.

However, 17 of the 24 commands are **stubs** — their implementations have been stripped from the open-source build. Setting the env var makes them "available" but they do nothing.

### What Actually Works

| Command | Fully Functional? | Notes |
|---|---|---|
| `commit` | Yes | Pure prompt command, no internal infra needed |
| `commit-push-pr` | Yes | Requires `gh` CLI for GitHub PR creation |
| `init-verifiers` | Yes | Pure prompt command, generates verifier skills |
| `version` | Yes | Prints `MACRO.VERSION` / `MACRO.BUILD_TIME` |
| `bridge-kick` | Partial | Requires an active Remote Control bridge connection |
| `tag` | Yes | Local session tagging, uses session storage |
| `files` | Yes | Lists files in context, purely in-memory |

### What Remains Stubbed

All 17 remaining commands export:

```javascript
export default { isEnabled: () => false, isHidden: true, name: 'stub' };
```

Even with `USER_TYPE=ant`, `isEnabled()` returns `false`, so they are never shown or executed. The stub also means `getCommands()` at `src/commands.ts:225-254` imports a dead object.

`agents-platform` is worse — its directory does not exist in this build at all. The conditional `require('./commands/agents-platform/index.js')` at `src/commands.ts:48-51` would throw `MODULE_NOT_FOUND`.

---

## Commands With Real Implementations

### `/commit`

**File:** `src/commands/commit.ts` (92 lines)

Creates a git commit. It is a **prompt command** — it generates a prompt for the model rather than performing actions directly.

**What it does:**
1. Runs `git status`, `git diff HEAD`, `git branch --show-current`, `git log --oneline -10` via shell command injection
2. Generates a prompt instructing the model to stage files and create a commit
3. Limits tool access to `Bash(git add:*)`, `Bash(git status:*)`, `Bash(git commit:*)`
4. Uses HEREDOC syntax for commit messages with optional attribution text
5. If `USER_TYPE=ant` and `isUndercover()` returns true (public repo), prepends undercover instructions that strip attribution

**Dependencies:** Git. No external APIs.

**Activation:** `USER_TYPE=ant` is required because the command is in `INTERNAL_ONLY_COMMANDS`. It would work fully with just that env var.

---

### `/commit-push-pr`

**File:** `src/commands/commit-push-pr.ts` (158 lines)

Creates a commit, pushes to origin, and opens/updates a GitHub PR. Also a prompt command.

**What it does:**
1. Runs `git diff`, `git status`, checks for existing PR via `gh pr view`
2. Generates a prompt instructing the model to create a branch, commit, push, and create a PR via `gh pr create` / `gh pr edit`
3. Supports undercover mode (strips reviewer assignment, changelog, Slack posting in public repos)
4. Supports optional Slack notification via `mcp__slack__send_message` tool
5. Allows user to pass additional instructions as arguments

**Dependencies:** Git, GitHub CLI (`gh`). Optionally Slack MCP server.

**Activation:** `USER_TYPE=ant` is required. Would work fully with `gh` CLI installed.

---

### `/init-verifiers`

**File:** `src/commands/init-verifiers.ts` (262 lines)

Generates verifier skills for automated verification of code changes.

**What it does:**
1. Analyzes the project to detect web apps (Playwright), CLI tools (Tmux), and API services (HTTP)
2. Interactive Q&A via the model to determine verification approach
3. Creates `SKILL.md` files in `.claude/skills/` with verification instructions
4. Multi-phase flow: auto-detection, user confirmation, verifier generation

**Dependencies:** None beyond filesystem access. Pure prompt command.

**Activation:** `USER_TYPE=ant` would fully enable this. No internal infrastructure needed.

---

### `/version`

**File:** `src/commands/version.ts` (22 lines)

Prints the build version and timestamp.

**What it does:**
- Returns `${MACRO.VERSION} (built ${MACRO.BUILD_TIME})` where `MACRO.VERSION` and `MACRO.BUILD_TIME` are compile-time constants injected by the Bun bundler.
- Different from `/status` which shows the auto-updated version. This shows what the binary was actually compiled as.

**Dependencies:** None. Purely local.

**Activation:** `USER_TYPE=ant` fully enables this.

---

### `/bridge-kick`

**File:** `src/commands/bridge-kick.ts` (200 lines)

Injects fault states into the Remote Control bridge to manually test recovery paths. This is a debugging/testing tool.

**Subcommands:**

| Subcommand | Description |
|---|---|
| `close <code>` | Fire WebSocket close with given code (e.g., 1002, 1006) |
| `poll <status> [type]` | Next poll throws `BridgeFatalError` with status |
| `poll transient` | Next poll throws 503/network rejection |
| `register fail [N]` | Next N register attempts transient-fail |
| `register fatal` | Next register returns 403 (terminal failure) |
| `reconnect-session fail` | POST to `/bridge/reconnect` fails |
| `heartbeat <status>` | Next heartbeat throws error |
| `reconnect` | Force reconnect directly |
| `status` | Print current bridge state |

**Dependencies:** Requires an active Remote Control bridge connection. Without one, returns: *"No bridge debug handle registered. Remote Control must be connected (USER_TYPE=ant)."*

**Activation:** `USER_TYPE=ant` registers the command, but it needs a connected bridge to be useful. The bridge infrastructure requires Anthropic's CCR (Claude Code Remote) service.

---

### `/tag` (additional, not in INTERNAL_ONLY_COMMANDS)

**File:** `src/commands/tag/tag.tsx` (215 lines)

Toggle a searchable tag on the current session. Tags appear after the branch name in `/resume`.

**What it does:**
- `/tag <name>` adds a tag, running it again removes it
- Saves to transcript storage via `saveTag()`
- Purely local file operations

**Activation:** Has its own `isEnabled: () => process.env.USER_TYPE === 'ant'` guard. Fully functional with that env var.

---

### `/files` (additional, not in INTERNAL_ONLY_COMMANDS)

**File:** `src/commands/files/files.ts` (19 lines)

Lists all files currently in context.

**What it does:**
- Returns relative paths of files tracked in the in-memory file state cache
- Purely local, reads from `context.readFileState`

**Activation:** Has its own `isEnabled: () => process.env.USER_TYPE === 'ant'` guard. Fully functional.

---

## Stubbed Commands

These 17 commands all export the same dead stub:

```javascript
export default { isEnabled: () => false, isHidden: true, name: 'stub' };
```

Even when `USER_TYPE=ant` is set, `isEnabled()` returns `false`, preventing the commands from appearing. The real implementations exist only in Anthropic's internal build system.

### Inferred Purposes

Descriptions are inferred from cross-references in the source, as the implementations are not present.

#### `backfill-sessions`

**Inferred purpose:** Backfill session data for analytics or data pipelines. No source references found beyond the import.

**Would work with USER_TYPE=ant:** No. Stub blocks activation.

---

#### `break-cache`

**Inferred purpose:** Break or toggle prompt cache behavior. Referenced in `src/services/api/promptCacheBreakDetection.ts` which discusses cache-breaking headers.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `bughunter`

**Inferred purpose:** Code review via the "bughunter" system. The `/ultrareview` command is the public entry point to the remote bughunter path (`src/commands/review.ts:45`). Bughunter is gated behind GrowthBook flag `tengu_review_bughunter_config`.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `ctx_viz`

**Inferred purpose:** Context visualization — likely renders a view of current conversation context/tokens.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `good-claude`

**Inferred purpose:** Feedback/rating mechanism for Anthropic employees to flag good Claude responses. No source references found.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `issue`

**Inferred purpose:** Create or interact with GitHub issues. Referenced in `src/utils/git.ts:798` alongside `/share`.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `mock-limits`

**Inferred purpose:** Mock rate limit scenarios for testing. The **full infrastructure** exists at `src/services/mockRateLimits.ts` (882 lines) and `src/services/rateLimitMocking.ts` (144 lines). Supports scenarios:

- `normal`, `session-limit-reached`, `approaching-weekly-limit`, `weekly-limit-reached`
- `overage-active`, `overage-warning`, `overage-exhausted`
- `out-of-credits`, `org-zero-credit-limit`, `org-spend-cap-hit`
- `opus-limit`, `sonnet-limit`, `fast-mode-limit`

Modifies rate limit response headers in-memory via `applyMockHeaders()`.

**Would work with USER_TYPE=ant:** No. Stub blocks command registration, though the underlying mock infrastructure code is present and could theoretically be triggered via other paths.

---

#### `reset-limits`

**Inferred purpose:** Reset rate limits. Referenced in `src/services/rateLimitMessages.ts:340`: *"You can reset your limits with /reset-limits"*.

Exports three stubs:

```javascript
export default stub;              // command registration
export const resetLimits = stub;  // called by rateLimitMessages.ts
export const resetLimitsNonInteractive = stub; // non-interactive variant
```

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `onboarding`

**Inferred purpose:** User onboarding flow for Anthropic employees.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `share`

**Inferred purpose:** Share session data. Referenced in `src/services/api/errors.ts:688`: *"Run /share and post the JSON file to [FEEDBACK_CHANNEL]"*. Also referenced in `src/utils/sessionRestore.ts:447`. Likely serializes the session transcript for sharing/debugging.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `summary`

**Inferred purpose:** Summarize the conversation via session memory extraction. Referenced in `src/services/sessionMemory/sessionMemory.ts:385`. Listed in `BRIDGE_SAFE_COMMANDS` (safe for remote/mobile use). Calls `manuallyExtractSessionMemory()`.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `teleport`

**Inferred purpose:** Remote session teleportation. Full infrastructure exists at `src/utils/teleport/` (api.ts, environments.ts, environmentSelection.ts, gitBundle.ts). Used by `/ultrareview` for remote review sessions (`src/commands/review/reviewRemote.ts:31`). Communicates with Anthropic's sessions API at `BASE_API_URL/v1/code/sessions/{id}/teleport-events`.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `ant-trace`

**Inferred purpose:** Anthropic-internal tracing/debugging. No source references found.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `perf-issue`

**Inferred purpose:** Report or diagnose performance issues. No source references found.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `env`

**Inferred purpose:** Set session-scoped environment variables. The **full infrastructure** exists at `src/utils/sessionEnvVars.ts` (22 lines) with `setSessionEnvVar()`, `deleteSessionEnvVar()`, `getSessionEnvVars()`, `clearSessionEnvVars()`. These affect child processes spawned by the Bash tool (`src/utils/shell/powershellProvider.ts:105`, `src/utils/shell/bashProvider.ts:248`).

**Would work with USER_TYPE=ant:** No. Stub blocks the command, but the underlying `sessionEnvVars` module is fully implemented and imported elsewhere.

---

#### `oauth-refresh`

**Inferred purpose:** Refresh OAuth tokens. Referenced in `src/services/mcp/auth.ts` with analytics events `tengu_mcp_oauth_refresh_success` and `tengu_mcp_oauth_refresh_failure`.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `debug-tool-call`

**Inferred purpose:** Debug tool call execution. No source references found.

**Would work with USER_TYPE=ant:** No. Stub.

---

#### `agents-platform`

**Not present at all.** The directory `src/commands/agents-platform/` does not exist in this build. The conditional `require()` at `src/commands.ts:48-51` would throw `MODULE_NOT_FOUND` if `USER_TYPE=ant` is set:

```typescript
const agentsPlatform =
  process.env.USER_TYPE === 'ant'
    ? require('./commands/agents-platform/index.js').default
    : null
```

Referenced in `src/utils/cron.ts:186` as a UI for scheduling/managing remote agent runs on Anthropic's platform.

**Would work with USER_TYPE=ant:** No. Would actually cause a startup crash.

---

#### `autofix-pr`

**Inferred purpose:** Automatically fix PR review comments. No source references found.

**Would work with USER_TYPE=ant:** No. Stub.

---

## Side Effects of Setting `USER_TYPE=ant`

Beyond enabling the 7 functional commands, setting `USER_TYPE=ant` activates approximately 100+ other code paths across the codebase:

### Client-Side Features That Activate

| Feature | File | Effect |
|---|---|---|
| Mock rate limits | `src/services/mockRateLimits.ts` | Enables rate limit scenario simulation |
| Dump prompts | `src/services/api/dumpPrompts.ts` | Dumps API requests/responses to `~/.claude/dump-prompts/` |
| GrowthBook overrides | `src/services/analytics/growthbook.ts` | Allows `CLAUDE_INTERNAL_FC_OVERRIDES` env var |
| Internal logging | `src/services/internalLogging.ts` | Kubernetes namespace / container ID logging |
| CLI internal beta header | `src/utils/betas.ts:243-248` | Adds `cli-internal` beta header to API requests |
| Connector text summarization | `src/utils/betas.ts:289-298` | Anti-distillation summarization |
| Effort override | `src/services/api/claude.ts:457-465` | Numeric effort override via `anthropic_internal` field |
| Anti-debug bypass | `src/main.tsx:266-271` | Skips the anti-debug process exit |
| Undercover mode | `src/commands/commit.ts:16-18` | Strips attribution in public repos |
| Research data capture | `src/services/api/claude.ts:1987+` | Captures `research` field from API responses |

### Risks

1. **`agents-platform` crash.** The `require('./commands/agents-platform/index.js')` at `src/commands.ts:48` will throw `MODULE_NOT_FOUND` at startup, likely preventing Claude Code from launching.

2. **API incompatibility.** Features like effort override send `anthropic_internal` fields that your API key may not be authorized for. The server may reject these requests.

3. **Analytics pollution.** Internal telemetry paths activate, sending data to Anthropic's internal analytics with your user ID.

4. **Beta header leakage.** The `cli-internal` beta header is added to all API requests, which may cause unexpected behavior with third-party providers.

### Practical Activation

To use the 7 functional commands without crashing on the missing `agents-platform`:

1. The `agents-platform` require at `src/commands.ts:48-51` needs to be wrapped in a try-catch, or a dummy module needs to be created at `src/commands/agents-platform/index.js`
2. The remaining stubs will register but do nothing (their `isEnabled` returns `false`)
3. `commit`, `commit-push-pr`, `init-verifiers`, `version`, `tag`, `files` will work
4. `bridge-kick` will register but needs a connected Remote Control bridge to function

Setting `USER_TYPE=ant` alone is insufficient for the stubbed commands because the stubs have hardcoded `isEnabled: () => false` — the USER_TYPE check in `commands.ts` only controls whether the command is **included in the command list**, but each command's own `isEnabled` determines whether it **appears to the user**.
