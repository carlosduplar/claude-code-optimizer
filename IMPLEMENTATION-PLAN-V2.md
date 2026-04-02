# Implementation Plan v2 — `optimize-claude.ps1` Rewrite

> **Audience**: A fast, cheap model (Sonnet-class) that will implement this plan step-by-step.
> **Platform**: Windows-first (PowerShell 5.1+). Linux/macOS port follows after Windows validation.
> **Goal**: One-shot script that maximizes token savings and privacy for Claude Code without modifying Claude Code's source.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [How Claude Code Hooks Work (Detailed)](#2-how-claude-code-hooks-work-detailed)
3. [How settings.json Works](#3-how-settingsjson-works)
4. [Environment Variables Reference](#4-environment-variables-reference)
5. [What the Script Must Do](#5-what-the-script-must-do)
6. [Detailed Implementation: Each Function](#6-detailed-implementation-each-function)
7. [Hook Scripts to Generate](#7-hook-scripts-to-generate)
8. [CLAUDE.md Template to Generate](#8-claudemd-template-to-generate)
9. [Validation Strategy](#9-validation-strategy)
10. [Known Issues in Current Script](#10-known-issues-in-current-script)
11. [Appendix: Official vs Undocumented Features](#11-appendix-official-vs-undocumented-features)
12. [Additional Hooks: Security, Automation & UX](#12-additional-hooks-security-automation--ux)
13. [Test Cases for Implementation Validation](#13-test-cases-for-implementation-validation)

---

## 1. Architecture Overview

The optimizer touches **four surfaces** of Claude Code configuration:

```
┌─────────────────────────────────────────────────────────┐
│  Surface 1: Environment Variables                       │
│  Set via settings.json "env" key (preferred)            │
│  OR via PowerShell profile (fallback)                   │
│  Controls: token limits, privacy, compaction behavior   │
├─────────────────────────────────────────────────────────┤
│  Surface 2: settings.json (user-level)                  │
│  Located at: ~/.claude/settings.json                    │
│  Controls: hooks, autoCompact, env vars                 │
├─────────────────────────────────────────────────────────┤
│  Surface 3: Hook Scripts                                │
│  Located at: ~/.claude/hooks/                           │
│  Controls: pre/post tool interception                   │
├─────────────────────────────────────────────────────────┤
│  Surface 4: CLAUDE.md (user-level)                      │
│  Located at: ~/.claude/CLAUDE.md                        │
│  Controls: compact instructions, model behavior hints   │
├─────────────────────────────────────────────────────────┤
│  Surface 5: Dependencies (optional)                     │
│  ImageMagick, markitdown, pdftotext                     │
│  Controls: binary file preprocessing capability         │
└─────────────────────────────────────────────────────────┘
```

### File Locations (Windows)

| Item | Path | Written by optimizer? |
|------|------|-----------------------|
| User settings | `%USERPROFILE%\.claude\settings.json` | **Yes** |
| Hook scripts | `%USERPROFILE%\.claude\hooks\` | **Yes** |
| User CLAUDE.md | `%USERPROFILE%\.claude\CLAUDE.md` | **Yes** |
| Project settings | `<project>\.claude\settings.json` | No — left to the developer |
| Project CLAUDE.md | `<project>\CLAUDE.md` | No — left to the developer |
| PowerShell profile | `$PROFILE.CurrentUserAllHosts` | No — not touched |

### settings.json Scope Precedence (Highest to Lowest)

1. **Project-level**: `<project>/.claude/settings.json` — overrides user for this project
2. **User-level**: `~/.claude/settings.json` — applies globally
3. **Enterprise/managed**: system-level policies (we don't touch these)

**IMPORTANT**: The optimizer writes **only to user-level** (`~/.claude/settings.json`, `~/.claude/hooks/`, `~/.claude/CLAUDE.md`). It never touches project-level files. This makes the optimizations apply globally across all projects without needing to touch any repository.

---

## 2. How Claude Code Hooks Work (Detailed)

This section is the most important for implementation. Previous attempts failed because the model didn't understand hook mechanics. Read this carefully.

### 2.1 Hook Lifecycle

Hooks are shell commands that Claude Code executes at specific lifecycle events. There are 5 event types:

| Event | When it fires | Can block tool? | Use case |
|-------|---------------|-----------------|----------|
| `PreToolUse` | Before a tool executes | Yes (exit 2) | Intercept reads, resize images, convert binaries, block protected files |
| `PostToolUse` | After a tool succeeds | No (already ran) | Logging, auto-formatting, validation |
| `Notification` | When Claude sends a notification message | No | Desktop alerts, monitoring |
| `Stop` | When Claude finishes a turn | No | Post-turn actions |
| `SubagentStop` | When a subagent completes | No | Subagent monitoring |
| `SessionStart` | When a session begins; also fires after compaction when matcher is `"compact"` | No | Re-inject context after compaction |

### 2.2 Hook Configuration in settings.json

Hooks are defined in `settings.json` under the `hooks` key. Each event type contains an array of hook groups, each with a `matcher` and an array of `hooks`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -File C:/Users/me/.claude/hooks/pretooluse.ps1",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -File C:/Users/me/.claude/hooks/posttooluse.ps1",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### 2.3 Matcher Values

The `matcher` field determines which tool triggers the hook:

| Matcher | Matches |
|---------|---------|
| `"Read"` | The Read (file read) tool |
| `"Write"` | The Write (file write) tool |
| `"Edit"` | The Edit (file edit) tool |
| `"Bash"` | The Bash (shell command) tool |
| `"Glob"` | The Glob (file search) tool |
| `"Grep"` | The Grep (content search) tool |
| `"WebFetch"` | The WebFetch tool |
| `"TodoRead"` | The TodoRead tool |
| `"TodoWrite"` | The TodoWrite tool |
| `"*"` | ALL tools (wildcard) |
| `"compact"` | Special: fires on the `SessionStart` event after compaction |

### 2.4 Hook Input (stdin JSON)

When a hook command runs, Claude Code sends a JSON object to the command's **stdin**. The structure depends on the event type.

#### PreToolUse stdin:

```json
{
  "session_id": "abc123",
  "tool_name": "Read",
  "tool_input": {
    "filePath": "/path/to/file.png",
    "offset": 1,
    "limit": 100
  }
}
```

#### PostToolUse stdin:

```json
{
  "session_id": "abc123",
  "tool_name": "Read",
  "tool_input": {
    "filePath": "/path/to/file.txt"
  },
  "tool_response": {
    "filePath": "/path/to/file.txt",
    "content": "file contents here..."
  }
}
```

#### Notification stdin:

```json
{
  "session_id": "abc123",
  "message": "I've completed the task...",
  "title": "Task Complete"
}
```

### 2.5 Hook Exit Codes (CRITICAL)

The exit code determines what happens after the hook:

| Exit Code | Meaning | Effect |
|-----------|---------|--------|
| **0** | Success, proceed | Tool runs normally. If stdout contains valid JSON with specific keys, it can modify behavior (see 2.6). |
| **1** | Hard error | Hook is considered failed. Claude Code logs the error and proceeds with the tool as if the hook didn't exist. This is a hook failure, NOT a tool block. |
| **2** | Soft intercept / blocking error | **For PreToolUse**: The tool is SKIPPED. Content from **stderr** is shown to Claude as an error message. Content from **stdout** is parsed for JSON (see 2.6). **For PostToolUse**: stderr content is shown to Claude as a message. |
| **Any other** | Treated like exit 1 | Hook failure, tool proceeds normally. |

### 2.6 Hook stdout JSON Output (PreToolUse only, exit 0)

When a PreToolUse hook exits 0 and writes JSON to stdout, Claude Code looks for specific keys:

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow"
  }
}
```

Valid `permissionDecision` values:
- `"allow"` — Auto-approve the tool (skip user permission prompt)
- `"deny"` — Block the tool silently (Claude sees a denial message)
- `"ask"` — Show normal permission prompt (default behavior)

**stdout output is capped at 10,000 characters.** Anything beyond is truncated.

### 2.7 The `exit 2` Intercept Pattern for PreToolUse

This is the key pattern for binary-to-markdown conversion:

1. Hook receives stdin JSON with `tool_name: "Read"` and `tool_input.filePath`
2. Hook checks if the file is a binary type (.pdf, .docx, .xlsx, .pptx, image)
3. Hook converts the file to text/markdown
4. Hook writes the converted content to **stderr** (which is displayed to Claude as the error/result message)
5. Hook exits with code **2**
6. Claude Code **skips** the Read tool and shows the stderr content to Claude as if it were the tool result

**Wait — stderr or stdout?** Per official docs: when exit code is 2, **stderr** content is "fed to Claude" as the blocking message. stdout is parsed for JSON `hookSpecificOutput`. For the intercept pattern, write converted content to **stderr**.

**CORRECTION from official docs**: Actually, for exit 2 on PreToolUse:
- stderr → shown to Claude as the error/result
- stdout → parsed for JSON only

So for the binary-to-markdown pattern: write the markdown to **stderr**, exit 2.

### 2.8 Shell Selection for Windows — CORRECTED FINDING

**Previous assumption was wrong.** Claude Code on Windows does NOT use cmd.exe to execute hook commands. It resolves the command through the normal PATH — so whatever shell binary appears first in `PATH` is what gets called.

**Confirmed behavior (from live testing)**:
- `bash` is available at `/bin/bash.exe` (MSYS2/Git Bash via Chocolatey at `C:\ProgramData\chocolatey\`)
- `$SHELL` inside hooks = `/bin/bash.exe`
- `bash --version` = `5.2.37(1)-release (MSYS2)`
- `jq` is available via Chocolatey at `/c/ProgramData/chocolatey/bin/jq`
- `~/.claude/hooks/` tilde expansion works correctly (MSYS2 maps `~` → user home)
- `/tmp/` is a valid writable path (MSYS2 maps it to a temp directory)

**What this means for hook commands:**

| Command style | Works? | Requires |
|---------------|--------|----------|
| `bash ~/.claude/hooks/hook.sh` | ✅ Works | Git for Windows / MSYS2 / WSL bash in PATH |
| `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\...\hook.ps1"` | ✅ Works | PowerShell (always present on Windows) |
| `powershell -File $env:USERPROFILE\...` | ❌ Fails | `$env:` is PowerShell syntax, not safe in this context |
| `bash ~/.claude/hooks/hook.sh` (no bash in PATH) | ❌ Fails | Requires Git for Windows / MSYS2 installed |

**THE CORRECT PATTERN — bash preferred, PowerShell fallback:**

The optimizer must detect which shell is available and choose accordingly:

```powershell
# In optimizer script — detect shell availability:
$bashAvailable = (Get-Command bash -ErrorAction SilentlyContinue) -ne $null

if ($bashAvailable) {
    # Bash hooks — simpler, cross-platform compatible
    $command = "bash ~/.claude/hooks/pretooluse.sh"
    $hookExt = ".sh"
} else {
    # PowerShell fallback — hardcoded absolute path required
    $hooksDir = Join-Path $env:USERPROFILE ".claude\hooks"
    $hookPath = Join-Path $hooksDir "pretooluse.ps1"
    $command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$hookPath`""
    $hookExt = ".ps1"
}
```

**Why bash hooks are preferred when available:**
1. Tilde expansion (`~`) works — no need for hardcoded paths in the command string
2. Scripts are portable (same `.sh` files work on Linux/macOS)
3. `jq` is typically available alongside bash (Chocolatey, Homebrew, etc.)
4. `set -euo pipefail` gives reliable error handling

**Why PowerShell fallback requires hardcoded paths:**
When PowerShell is invoked as `powershell -File ...`, the path must be absolute because tilde expansion (`~`) is a PowerShell feature and does NOT work when the path is passed as an argument to `powershell.exe` from a non-PowerShell context. Use `Join-Path $env:USERPROFILE ".claude\hooks\hook.ps1"` to resolve the path at optimizer run time, then embed the resulting absolute path as a string literal in `settings.json`.

**JSON key casing — CRITICAL BUG to avoid:**

Claude Code sends `tool_input` keys in **snake_case** (`file_path`, not `filePath`). Using `grep/sed` to parse `"filePath"` will always yield an empty result. Always use `jq` with a fallback:

```bash
# CORRECT — jq with snake_case primary, camelCase fallback:
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)

# Or two-step (extract tool_input sub-object first):
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // {}' 2>/dev/null)
FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // .filePath // empty' 2>/dev/null)

# WRONG — grep/sed pattern that caused PARSED_PATH | <empty> in logs:
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"filePath"...' | sed '...')  # DO NOT USE
```

**Impact on `New-HookScripts` function**: Detect `bash` availability first. Generate `.sh` scripts when bash is available, `.ps1` scripts as fallback. Always use the jq two-step extraction pattern, never `grep/sed`.

### 2.9 Environment Variables Available in Hooks

These environment variables are available inside hook commands:
- `$env:CLAUDE_PROJECT_DIR` — the current project directory Claude is working in
- All user environment variables (PATH, USERPROFILE, etc.)
- Any variables set in `settings.json` `env` key

### 2.10 Hook Timeout

The `timeout` field is in **seconds**. If the hook doesn't exit within this time, it's killed and treated as exit 1 (hook failure, tool proceeds). Default timeout is not specified; always set it explicitly.

---

## 3. How settings.json Works

### 3.1 Structure

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "autoCompactEnabled": true,
  "env": {
    "BASH_MAX_OUTPUT_LENGTH": "10000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_TELEMETRY": "1",
    "OTEL_LOG_USER_PROMPTS": "0",
    "OTEL_LOG_TOOL_DETAILS": "0",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "180000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "70",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
  },
  "hooks": {
    "PreToolUse": [...],
    "PostToolUse": [...]
  }
}
```

### 3.2 The `env` Key (IMPORTANT DISCOVERY)

The `env` key in `settings.json` sets environment variables **for the Claude Code session**. This is the **preferred** way to set env vars because:

1. No modification to shell profiles (`.bashrc`, PowerShell `$PROFILE`)
2. Applies regardless of how Claude Code is launched (terminal, desktop app, etc.)
3. Scoped to Claude Code only — doesn't pollute the user's general environment
4. Set at **user-level only** — the optimizer never writes to project-level `settings.json`

**This eliminates the need for the `Set-PrivacyConfiguration` and `Set-WindowsEnvironment` functions in the current script.** All env vars should go into `settings.json` `env` instead.

### 3.3 The `autoCompactEnabled` Key

Boolean. When `true`, Claude Code automatically compacts the conversation when context gets too large. This is the most basic optimization and should always be enabled.

### 3.4 Merging Behavior (Informational — Claude Code's own resolution, not optimizer behavior)

When both user-level and project-level `settings.json` exist, Claude Code:
- **Merges** them (not replaces)
- Project-level values **override** user-level for conflicting keys
- For hooks: both user and project hooks run (they don't override each other)

The optimizer only writes user-level files. If a project already has its own `.claude/settings.json`, Claude Code will layer it on top — the optimizer's user-level settings remain as the base.

---

## 4. Environment Variables Reference

### 4.1 Officially Documented (safe to use)

| Variable | Value | Effect | Impact |
|----------|-------|--------|--------|
| `BASH_MAX_OUTPUT_LENGTH` | `"10000"` | Caps bash tool output to 10,000 chars (default: 30,000) | **HIGH** — saves ~20K chars per bash call |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `"1"` | Disables auto-updater, feedback, error reporting, telemetry | **HIGH** — privacy + reduced network |
| `DISABLE_TELEMETRY` | `"1"` | Disables telemetry specifically | Medium — subset of above |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `"180000"` | Effective context window for compaction math (tokens) | Medium — triggers compaction earlier |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"70"` | Compact at 70% of effective window (default: ~95%) | Medium — earlier, cheaper compaction |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | `"1"` | Disables background memory extraction API calls | Medium — stops silent token burn |
| `OTEL_LOG_USER_PROMPTS` | `"0"` | Disables logging user prompts in OTel traces | Low — privacy |
| `OTEL_LOG_TOOL_DETAILS` | `"0"` | Disables logging tool details in OTel traces | Low — privacy |

### 4.2 Undocumented (from reverse engineering — use at your own risk)

| Variable | Value | Effect | Risk |
|----------|-------|--------|------|
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | `"8000"` | Caps file read output to 8,000 tokens (default: 25,000) | May break if removed in future builds |
| `ENABLE_CLAUDE_CODE_SM_COMPACT` | `"1"` | Enables session memory compaction (lighter than full) | Experimental, may not exist in all builds |
| `CLAUDE_CODE_DISABLE_THINKING` | `"1"` | Disables extended thinking | Reduces quality on complex tasks |
| `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` | `"1"` | Disables adaptive thinking budget | May reduce quality |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | `"1"` | Disables advisor side-queries | May reduce suggestion quality |

### 4.3 Implementation Decision

**The script should set ONLY officially documented env vars by default.** Undocumented vars should be offered as optional flags (e.g., `-Experimental`) with clear warnings.

---

## 5. What the Script Must Do

### 5.1 Execution Flow (Step by Step)

```
1. Parse parameters (-DryRun, -ReducedPrivacy, -SkipDeps, -Experimental,
                     -AutoApprove, -AutoFormat, -NoGuard, -NoNotify, -NoContextRefresh)
2. Display banner and mode
3. Check/install dependencies (if not -SkipDeps)
   a. Check for ImageMagick (magick.exe)
   b. Check for markitdown (pip package)
   c. Check for pdftotext (poppler)
   d. Prompt to install missing ones
4. Backup existing settings.json (if exists)
5. Generate settings.json with:
   a. autoCompactEnabled: true
   b. env: { all optimization env vars }
   c. hooks: { all enabled hooks, see below }
6. Generate hook scripts in ~/.claude/hooks/
   a. pretooluse.sh/.ps1   — image resize + binary-to-markdown interceptor (Read tool) [always]
   b. posttooluse.sh/.ps1  — validation logger (all tools) [always]
   c. file-guard.sh/.ps1   — protect .env and sensitive files (Write|Edit|Bash) [default on, -NoGuard disables]
   d. notify.sh/.ps1       — desktop notification when Claude signals (Notification event) [default on, -NoNotify disables]
   e. post-compact.sh/.ps1 — re-inject CLAUDE.md after compaction (SessionStart/compact) [default on, -NoContextRefresh disables]
   f. auto-approve.sh/.ps1 — auto-approve safe bash commands (Bash) [opt-in with -AutoApprove]
   g. post-edit-format.sh/.ps1 — auto-format files after edits (Write|Edit) [opt-in with -AutoFormat]
   (.sh when bash in PATH, .ps1 fallback)
7. Generate CLAUDE.md template (compact instructions) at ~/.claude/CLAUDE.md
8. Run validation checks
9. Display summary with what was configured
```

### 5.2 What NOT to Do (Fixing Current Issues)

| Current behavior | Problem | Fix |
|-----------------|---------|-----|
| Modifies PowerShell profile with env vars | Pollutes user shell, fragile | Use `settings.json` `env` key instead |
| Sets Windows registry env vars | Same — persistent, hard to undo | Use `settings.json` `env` key instead |
| Uses bash hooks on Windows | ~~Incorrect — bash works via MSYS2/Git Bash when installed~~ | Generate `.sh` hooks when `bash` is in PATH; generate `.ps1` hooks with absolute paths as fallback |
| `cache-keepalive.sh` PostToolUse hook | Does nothing useful (just logs) | Replace with meaningful validation logger |
| Creates standalone `claude-keepalive.ps1` | SendKeys approach is fragile and wrong | Remove entirely — cache keepalive cannot work via hooks |
| `#requires -RunAsAdministrator` | Unnecessary — we're not modifying system files | Remove — nothing requires admin |
| Creates `preprocess-for-claude.bat/.ps1` | Manual preprocessing is obsoleted by hooks | Remove — hooks handle this |
| Writes to `.claude.json` (not `settings.json`) | Wrong file — `.claude.json` is for different purpose | Write to `settings.json` only |

### 5.3 Parameters

```powershell
param(
    [switch]$DryRun,           # Show what would change, don't apply
    [switch]$ReducedPrivacy,   # Only disable telemetry (keep auto-updates)
    [switch]$SkipDeps,         # Skip dependency checking/installation
    [switch]$Experimental,     # Include undocumented env vars
    [switch]$Force,            # Overwrite without prompting
    # Security hook (default ON):
    [switch]$NoGuard,          # Disable file-guard hook (not recommended)
    # UX hooks (default ON):
    [switch]$NoNotify,         # Disable desktop notification hook
    [switch]$NoContextRefresh, # Disable post-compact context re-injection hook
    # Opt-in hooks (default OFF):
    [switch]$AutoApprove,      # Enable auto-approval whitelist for safe bash commands
    [switch]$AutoFormat        # Enable auto-formatting after file edits (requires formatter)
)
```

---

## 6. Detailed Implementation: Each Function

### 6.1 `Test-Dependencies` / `Install-Dependencies`

Keep the existing dependency check logic but simplify:
- Check `magick.exe` (ImageMagick)
- Check `markitdown` (Python pip package)
- Check `pdftotext.exe` (poppler/xpdf-utils)
- For each missing dep: explain what it does, offer to install via winget/choco/pip
- **Do NOT require admin** — use `--user` for pip, winget doesn't need admin

### 6.2 `Set-ClaudeSettings` (NEW — replaces multiple old functions)

This single function replaces `Set-PrivacyConfiguration`, `Set-WindowsEnvironment`, `Set-ClaudeConfiguration`, and `New-SettingsJson`. It:

1. Reads existing `~/.claude/settings.json` (if any)
2. Merges in our optimizations (preserving user's existing settings)
3. Writes back the merged JSON

**Merge logic:**
- If `env` key exists, merge our env vars into it (don't overwrite user's custom vars)
- If `hooks` key exists, merge our hooks (don't duplicate if same hook already registered)
- If `autoCompactEnabled` exists, set to `true`
- Preserve any other keys the user has set

**JSON to generate** (full example with all default-on hooks, bash path — substitute `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<user>\.claude\hooks\<name>.ps1"` with absolute path when bash is absent):

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "autoCompactEnabled": true,
  "env": {
    "BASH_MAX_OUTPUT_LENGTH": "10000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_TELEMETRY": "1",
    "OTEL_LOG_USER_PROMPTS": "0",
    "OTEL_LOG_TOOL_DETAILS": "0",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "180000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "70",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/pretooluse.sh",
            "timeout": 30
          }
        ]
      },
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/file-guard.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/posttooluse.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/notify.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/post-compact.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**With `-AutoApprove`**: Add a second PreToolUse entry matching `"Bash"` pointing to `auto-approve.ps1`.

**With `-AutoFormat`**: Add a second PostToolUse entry matching `"Write|Edit"` pointing to `post-edit-format.ps1`.

**Reduced privacy mode** (`-ReducedPrivacy`): Omit `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, keep only `DISABLE_TELEMETRY`.

**Experimental mode** (`-Experimental`): Add these to the `env` block:
```json
{
  "CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS": "8000",
  "ENABLE_CLAUDE_CODE_SM_COMPACT": "1"
}
```

### 6.3 `New-HookScripts` (NEW — replaces inline script generation)

Detects bash availability first (`Get-Command bash -ErrorAction SilentlyContinue`). When bash is available, generates `.sh` scripts and uses `bash ~/.claude/hooks/<name>.sh` as the command. When bash is absent, generates `.ps1` scripts and uses `powershell -NoProfile -ExecutionPolicy Bypass -File "<absolute_path>.ps1"` — the absolute path resolved from `$env:USERPROFILE` at script-run time.

See Section 12 for the full source of each bash hook script.

### 6.4 `New-ClaudeMdTemplate`

Creates a `CLAUDE.md` template file. See Section 8 for the content.

### 6.5 `Test-Optimizations` (NEW — validation)

Runs validation checks. See Section 9 for the strategy.

### 6.6 `Show-Summary` (NEW — before/after comparison)

Displays what was configured and estimated token savings.

---

## 7. Hook Scripts to Generate

### 7.1 `pretooluse.ps1` — PreToolUse Image Resize + Binary-to-Markdown

This is the most complex hook. It intercepts `Read` tool calls and:
1. For images (.png, .jpg, .jpeg, .gif, .webp, .bmp): resize if too large, exit 0 (let Claude read resized file)
2. For binary documents (.pdf, .docx, .xlsx, .pptx): convert to markdown, write to stderr, exit 2

```powershell
# pretooluse.ps1 — PreToolUse hook for Read tool
# Receives JSON on stdin. Exit codes: 0=proceed, 2=intercept (stderr shown to Claude)

param()

$ErrorActionPreference = 'Stop'

# Configuration
$MAX_DIMENSION = if ($env:CLAUDE_IMAGE_MAX_DIMENSION) { [int]$env:CLAUDE_IMAGE_MAX_DIMENSION } else { 2000 }
$MAX_FILE_SIZE_MB = if ($env:CLAUDE_IMAGE_MAX_SIZE_MB) { [int]$env:CLAUDE_IMAGE_MAX_SIZE_MB } else { 5 }
$QUALITY = if ($env:CLAUDE_IMAGE_QUALITY) { [int]$env:CLAUDE_IMAGE_QUALITY } else { 85 }
$LOG_FILE = Join-Path $env:TEMP "claude-hook-validation.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    Add-Content -Path $LOG_FILE -Value "$timestamp | PreToolUse | $Message" -ErrorAction SilentlyContinue
}

# Read JSON from stdin
$inputJson = $null
try {
    $inputJson = [Console]::In.ReadToEnd()
    if (-not $inputJson) {
        Write-Log "EMPTY_INPUT"
        exit 0
    }
} catch {
    Write-Log "STDIN_READ_ERROR | $_"
    exit 0
}

# Parse JSON
$payload = $null
try {
    $payload = $inputJson | ConvertFrom-Json
} catch {
    Write-Log "JSON_PARSE_ERROR | $_"
    exit 0
}

# Only handle Read tool
if ($payload.tool_name -ne 'Read') {
    exit 0
}

# Extract file path
$filePath = $payload.tool_input.filePath
if (-not $filePath) {
    $filePath = $payload.tool_input.file_path
}
if (-not $filePath) {
    Write-Log "NO_FILE_PATH"
    exit 0
}

Write-Log "FILE | $filePath"

# Check if file exists
if (-not (Test-Path $filePath -PathType Leaf)) {
    Write-Log "FILE_NOT_FOUND | $filePath"
    exit 0
}

$extension = [System.IO.Path]::GetExtension($filePath).ToLower()

# --- IMAGE HANDLING: resize in-place, exit 0 ---
$imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.tiff', '.tif')
if ($extension -in $imageExtensions) {
    Write-Log "IMAGE_DETECTED | $filePath"

    # Check for ImageMagick
    $magick = Get-Command magick.exe -ErrorAction SilentlyContinue
    if (-not $magick) {
        Write-Log "NO_IMAGEMAGICK | Skipping resize"
        exit 0
    }

    try {
        # Get current dimensions
        $identify = & magick.exe identify -format "%wx%h" "$filePath" 2>$null
        if ($identify -match '(\d+)x(\d+)') {
            $width = [int]$Matches[1]
            $height = [int]$Matches[2]
            $fileSize = (Get-Item $filePath).Length
            $maxBytes = $MAX_FILE_SIZE_MB * 1024 * 1024

            if ($width -gt $MAX_DIMENSION -or $height -gt $MAX_DIMENSION -or $fileSize -gt $maxBytes) {
                Write-Log "RESIZING | ${width}x${height} | $fileSize bytes"

                # Resize to temp, then replace
                $tempFile = Join-Path $env:TEMP "claude-resize-$([System.IO.Path]::GetFileName($filePath))"
                & magick.exe "$filePath" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" -quality $QUALITY "$tempFile" 2>$null

                if (Test-Path $tempFile) {
                    Copy-Item $tempFile $filePath -Force
                    Remove-Item $tempFile -ErrorAction SilentlyContinue
                    $newSize = (Get-Item $filePath).Length
                    Write-Log "RESIZED | $fileSize -> $newSize bytes"
                }
            } else {
                Write-Log "WITHIN_LIMITS | ${width}x${height} | $fileSize bytes"
            }
        }
    } catch {
        Write-Log "RESIZE_ERROR | $_"
    }

    exit 0  # Always exit 0 for images — let Claude read the (now resized) file
}

# --- BINARY DOCUMENT HANDLING: convert to markdown, exit 2 ---
$pdfExtensions = @('.pdf')
$docExtensions = @('.docx', '.xlsx', '.pptx', '.doc', '.xls', '.ppt')

if ($extension -in $pdfExtensions) {
    # Try pdftotext first (faster, better for text-heavy PDFs)
    $pdftotext = Get-Command pdftotext.exe -ErrorAction SilentlyContinue
    if ($pdftotext) {
        try {
            $tempTxt = Join-Path $env:TEMP "claude-pdf-$([guid]::NewGuid().ToString('N')).txt"
            & pdftotext.exe -layout "$filePath" "$tempTxt" 2>$null
            if (Test-Path $tempTxt) {
                $content = Get-Content $tempTxt -Raw -ErrorAction SilentlyContinue
                Remove-Item $tempTxt -ErrorAction SilentlyContinue
                if ($content) {
                    # Truncate if too long (hook output cap is 10,000 chars)
                    if ($content.Length -gt 9500) {
                        $content = $content.Substring(0, 9500) + "`n`n[... TRUNCATED — file too large for hook output. Use pdftotext manually for full content.]"
                    }
                    Write-Log "PDF_CONVERTED | $filePath | $($content.Length) chars"
                    [Console]::Error.Write("Converted PDF content from ${filePath}:`n`n$content")
                    exit 2
                }
            }
        } catch {
            Write-Log "PDFTOTEXT_ERROR | $_"
        }
    }

    # Fallback to markitdown
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        try {
            $content = & markitdown "$filePath" 2>$null
            if ($content) {
                $contentStr = $content -join "`n"
                if ($contentStr.Length -gt 9500) {
                    $contentStr = $contentStr.Substring(0, 9500) + "`n`n[... TRUNCATED]"
                }
                Write-Log "PDF_MARKITDOWN | $filePath | $($contentStr.Length) chars"
                [Console]::Error.Write("Converted PDF content from ${filePath}:`n`n$contentStr")
                exit 2
            }
        } catch {
            Write-Log "MARKITDOWN_ERROR | $_"
        }
    }

    Write-Log "NO_PDF_CONVERTER | $filePath"
    exit 0  # No converter available, let Claude try to read it
}

if ($extension -in $docExtensions) {
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
        try {
            $content = & markitdown "$filePath" 2>$null
            if ($content) {
                $contentStr = $content -join "`n"
                if ($contentStr.Length -gt 9500) {
                    $contentStr = $contentStr.Substring(0, 9500) + "`n`n[... TRUNCATED]"
                }
                Write-Log "DOC_CONVERTED | $filePath | $($contentStr.Length) chars"
                [Console]::Error.Write("Converted document content from ${filePath}:`n`n$contentStr")
                exit 2
            }
        } catch {
            Write-Log "MARKITDOWN_DOC_ERROR | $_"
        }
    }

    Write-Log "NO_DOC_CONVERTER | $filePath"
    exit 0  # No converter available
}

# Not a binary file — let Claude read normally
exit 0
```

### 7.2 `posttooluse.ps1` — PostToolUse Validation Logger

This is simple — it logs tool usage for validation/debugging:

```powershell
# posttooluse.ps1 — PostToolUse hook (all tools)
# Logs tool usage for validation. Always exits 0 (never blocks).

param()

$LOG_FILE = Join-Path $env:TEMP "claude-hook-validation.log"

try {
    $inputJson = [Console]::In.ReadToEnd()
    if ($inputJson) {
        $payload = $inputJson | ConvertFrom-Json
        $toolName = $payload.tool_name
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        Add-Content -Path $LOG_FILE -Value "$timestamp | PostToolUse | FIRED | Tool: $toolName" -ErrorAction SilentlyContinue
    }
} catch {
    # Silently ignore errors — never block
}

exit 0
```

### 7.3 Why No Bash Hooks on Windows

The current implementation uses `bash ~/.claude/hooks/...` which requires:
- WSL installed and configured, OR
- Git Bash in PATH

Both are fragile assumptions. PowerShell is **always available** on Windows 10+. The rewrite uses PowerShell hooks as primary, eliminating this dependency.

For Linux/macOS port: use bash hooks (the existing `.sh` scripts, cleaned up).

---

## 8. CLAUDE.md Template to Generate

The compaction system in Claude Code looks for a `## Compact Instructions` section in CLAUDE.md and uses it to guide summarization. The optimizer should generate a template at `~/.claude/CLAUDE.md` (user-level, applies globally):

```markdown
# Claude Code Optimization Guide

## Cost-First Defaults
- **Default model**: sonnet (or haiku for quick tasks)
- **Always use offset/limit** for reads >500 lines
- **Pre-convert**: PDF->text, Office->Markdown, images->2000x2000 max
- **Compact at**: 150K tokens

## File Reading Guidelines
### Always Use Pagination
For files >500 lines, always specify offset and limit:
```
Read file.ts {"offset": 1, "limit": 100}
```

### Search Before Reading
Use Grep/Glob to find specific content before reading entire files.

### Binary File Handling
Pre-convert binary files before reading:
- PDFs: Use pdftotext.exe or markitdown
- DOCX/XLSX/PPTX: markitdown
- Images: magick.exe -resize 2000x2000

## Compact Instructions
Focus on: current task state, file paths changed, pending errors, and last user instruction verbatim. Skip background theory. Keep code snippets only if they're the direct subject of the next task. Omit completed sub-tasks. Preserve file paths with line numbers for any code being actively edited. Keep error messages verbatim if they're not yet resolved.
```

**IMPORTANT**: Only write this if `~/.claude/CLAUDE.md` doesn't already exist. If it exists, append the `## Compact Instructions` section only if one doesn't already exist.

---

## 9. Validation Strategy

### 9.1 What We CAN Validate

| Check | How | Pass criteria |
|-------|-----|---------------|
| settings.json exists | `Test-Path` | File exists at expected path |
| settings.json is valid JSON | `ConvertFrom-Json` | Parses without error |
| `autoCompactEnabled` is true | JSON key check | `$settings.autoCompactEnabled -eq $true` |
| `env` vars are set | JSON key check | All expected vars present in `env` object |
| Hook scripts exist | `Test-Path` | Files exist at expected paths |
| Hook scripts are executable | Try parsing them | `[ScriptBlock]::Create((Get-Content ... -Raw))` parses |
| Hook commands in settings are valid | JSON check | `hooks.PreToolUse[*].hooks[*].command` contains valid paths |
| ImageMagick available | `Get-Command magick.exe` | Found in PATH |
| markitdown available | `Get-Command markitdown` | Found in PATH |
| pdftotext available | `Get-Command pdftotext.exe` | Found in PATH |
| CLAUDE.md has compact instructions | Content check | Contains `## Compact Instructions` |

### 9.2 What We CANNOT Validate (Without Running Claude Code)

| Check | Why |
|-------|-----|
| Hooks actually fire | Requires an active Claude Code session |
| env vars are actually applied | Requires Claude Code to read settings.json |
| Token savings are realized | Requires running real tasks and comparing costs |
| Binary interception works | Requires Claude to trigger a Read on a binary file |

### 9.3 Validation Implementation

Add a `Test-Optimizations` function that runs all checks from 9.1 and outputs a report:

```powershell
function Test-Optimizations {
    $results = @()

    # Check 1: settings.json exists
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    $results += @{
        Check = "settings.json exists"
        Pass = Test-Path $settingsPath
        Path = $settingsPath
    }

    # Check 2: settings.json is valid JSON
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $results += @{ Check = "settings.json valid JSON"; Pass = $true }
        } catch {
            $results += @{ Check = "settings.json valid JSON"; Pass = $false; Error = $_.Exception.Message }
        }
    }

    # Check 3: autoCompactEnabled
    if ($settings) {
        $results += @{
            Check = "autoCompactEnabled is true"
            Pass = ($settings.autoCompactEnabled -eq $true)
        }
    }

    # Check 4: env vars in settings
    $expectedVars = @(
        "BASH_MAX_OUTPUT_LENGTH",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
        "DISABLE_TELEMETRY",
        "CLAUDE_CODE_AUTO_COMPACT_WINDOW",
        "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
        "CLAUDE_CODE_DISABLE_AUTO_MEMORY"
    )
    foreach ($var in $expectedVars) {
        $val = $settings.env.$var
        $results += @{
            Check = "env.$var is set"
            Pass = (-not [string]::IsNullOrEmpty($val))
            Value = $val
        }
    }

    # Check 5: Hook scripts exist
    $hooksDir = Join-Path $env:USERPROFILE ".claude\hooks"
    foreach ($script in @("pretooluse.ps1", "posttooluse.ps1")) {
        $scriptPath = Join-Path $hooksDir $script
        $results += @{
            Check = "$script exists"
            Pass = Test-Path $scriptPath
            Path = $scriptPath
        }
    }

    # Check 6: Hook scripts parse correctly
    foreach ($script in @("pretooluse.ps1", "posttooluse.ps1")) {
        $scriptPath = Join-Path $hooksDir $script
        if (Test-Path $scriptPath) {
            try {
                $content = Get-Content $scriptPath -Raw
                [ScriptBlock]::Create($content) | Out-Null
                $results += @{ Check = "$script syntax valid"; Pass = $true }
            } catch {
                $results += @{ Check = "$script syntax valid"; Pass = $false; Error = $_.Exception.Message }
            }
        }
    }

    # Check 7: Dependencies
    foreach ($cmd in @("magick.exe", "markitdown", "pdftotext.exe")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        $results += @{
            Check = "$cmd available"
            Pass = ($null -ne $found)
            Note = if ($found) { $found.Source } else { "Not found in PATH" }
        }
    }

    # Check 8: CLAUDE.md compact instructions
    $claudeMd = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
    if (Test-Path $claudeMd) {
        $content = Get-Content $claudeMd -Raw
        $results += @{
            Check = "CLAUDE.md has Compact Instructions"
            Pass = ($content -match '## Compact Instructions')
        }
    } else {
        $results += @{
            Check = "CLAUDE.md exists"
            Pass = $false
            Path = $claudeMd
        }
    }

    # Display results
    Write-Host ""
    Write-Host "Validation Results" -ForegroundColor Cyan
    Write-Host ("=" * 60)

    $passCount = 0
    $failCount = 0
    foreach ($r in $results) {
        if ($r.Pass) {
            Write-Host "[PASS] $($r.Check)" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "[FAIL] $($r.Check)" -ForegroundColor Red
            if ($r.Error) { Write-Host "       Error: $($r.Error)" -ForegroundColor Yellow }
            if ($r.Note) { Write-Host "       Note: $($r.Note)" -ForegroundColor Yellow }
            $failCount++
        }
    }

    Write-Host ""
    Write-Host "Total: $passCount passed, $failCount failed out of $($results.Count) checks" -ForegroundColor Cyan

    return ($failCount -eq 0)
}
```

### 9.4 Manual Validation (User Instructions)

After running the optimizer, instruct the user to:

1. Start Claude Code: `claude`
2. Ask Claude: "What environment variables do you see for BASH_MAX_OUTPUT_LENGTH?"
3. Ask Claude: "Read a .pdf file" (should trigger hook intercept)
4. Check the log file: `Get-Content $env:TEMP\claude-hook-validation.log -Tail 20`
5. Run `/cost` to see baseline token usage
6. Run a task, then `/cost` again to compare

---

## 10. Known Issues in Current Script

### 10.1 Issues to Fix

| # | Issue | Current behavior | Fix |
|---|-------|-----------------|-----|
| 1 | `#requires -RunAsAdministrator` | Script requires admin | Remove — nothing requires admin privileges |
| 2 | Env vars set via profile + registry | Modifies `$PROFILE` and Windows env vars | Use `settings.json` `env` key exclusively |
| 3 | Writes to `.claude.json` | Wrong file for settings | Write to `settings.json` only |
| 4 | Bash hooks on Windows | `bash ~/.claude/hooks/...` was believed to fail | It works — Claude Code resolves `bash` through PATH. When Git for Windows/MSYS2 is installed (e.g., via Chocolatey), bash is available. Generate `.sh` hooks when bash found in PATH; fall back to `.ps1` with absolute paths only when bash is absent |
| 5 | `cache-keepalive.sh` as PostToolUse | Named misleadingly; does nothing for caching | Rename to validation logger, remove "keepalive" concept |
| 6 | `claude-keepalive.ps1` SendKeys | Sends keystrokes to Claude window | Remove entirely — fundamentally wrong approach |
| 7 | `preprocess-for-claude.bat/.ps1` | Manual preprocessing scripts | Remove — hooks handle this automatically |
| 8 | Missing `BASH_MAX_OUTPUT_LENGTH` | Not set anywhere | Add to `env` in settings.json |
| 9 | Missing `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Not set | Add to `env` |
| 10 | Missing `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Not set | Add to `env` |
| 11 | Empty `CLAUDE.md` and `CLAUDE.md-template` | No compact instructions | Generate with compact instructions |
| 12 | No validation function | Separate fragile validation scripts | Inline validation in main script |
| 13 | Hook log paths use `/tmp/` | Linux path, doesn't exist on Windows by default | Keep `/tmp/` in bash hooks — MSYS2 maps `/tmp/` to a valid temp directory. Only use `$env:TEMP` in PowerShell fallback hooks |
| 14 | Image resize hook modifies file in-place without reliable backup | Could corrupt user's images | Resize to temp, then copy back |
| 15 | `pretooluse.sh` parses `"filePath"` (camelCase) via `grep/sed` | Claude Code sends `"file_path"` (snake_case) — `PARSED_PATH \| <empty>` in logs | Use `jq -r '.tool_input.file_path // .tool_input.filePath // empty'`; never `grep/sed` for JSON |

### 10.2 Things to Keep

| # | Feature | Why |
|---|---------|-----|
| 1 | Dependency detection (magick, markitdown, pdftotext) | Still needed |
| 2 | winget/choco installation fallback chain | Good UX |
| 3 | DryRun mode | Essential for trust |
| 4 | Colored output functions | Good UX |
| 5 | Backup before overwriting settings | Safety |

---

## 11. Appendix: Official vs Undocumented Features

### 11.1 Cross-Reference Table

| Feature | IMPLEMENTATION-PLAN.md claim | Official docs say | Verdict |
|---------|------------------------------|-------------------|---------|
| `BASH_MAX_OUTPUT_LENGTH` | Default 30K, can lower | Officially documented env var | **CONFIRMED** |
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | Default 25K, can lower | NOT in official env vars list | **UNDOCUMENTED** — use with warning |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | 1-100 range, controls compact threshold | Officially documented | **CONFIRMED** |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Effective context window | Officially documented | **CONFIRMED** |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Disables background memory | Officially documented | **CONFIRMED** |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Umbrella for auto-update+telemetry+error-reporting+feedback | Officially documented | **CONFIRMED** |
| `ENABLE_CLAUDE_CODE_SM_COMPACT` | Session memory compaction | NOT in official docs | **UNDOCUMENTED** |
| `DISABLE_INTERLEAVED_THINKING` | Disables interleaved thinking | Official docs show `CLAUDE_CODE_DISABLE_THINKING` and `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` instead | **WRONG NAME** — use official names |
| `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` | Disables advisor | NOT in official docs | **UNDOCUMENTED** |
| Hook exit 2 intercept pattern | stderr shown to Claude | Official docs confirm exit 2 = blocking, stderr fed to Claude | **CONFIRMED** |
| `settings.json` `env` key | Sets env vars per-session | Official settings reference confirms | **CONFIRMED** |
| Hook `shell` field | Can use `"powershell"` | Not explicitly documented but `command` field with `powershell` prefix works | **WORKS IN PRACTICE** |
| PostToolUse "keeps cache warm" | Hook fires after each tool | PostToolUse fires after tools but does NOT make API calls — cache TTL is about API-level caching, not local | **MISCONCEPTION** — hooks don't affect API cache |

### 11.2 The Cache Keepalive Misconception

The current `cache-keepalive.sh` PostToolUse hook is based on a misunderstanding:

- **Claim**: A PostToolUse hook that fires after each tool "keeps the prompt cache warm"
- **Reality**: Prompt cache TTL is at the **Anthropic API level**. It expires after ~5 minutes of no API calls. A local hook script running on your machine does NOT make API calls and therefore cannot keep the cache warm.
- **What actually keeps cache warm**: Making API requests (i.e., sending messages to Claude) within the 5-minute window. This can only be done by the user typing messages or Claude making tool calls — not by a local hook.
- **Conclusion**: Remove the "keepalive" concept entirely. The PostToolUse hook should be a simple validation logger, not falsely named "cache-keepalive".

---

## Summary: Implementation Checklist

For the implementing model, here is the exact order of operations:

- [ ] 1. Remove `#requires -RunAsAdministrator` line
- [ ] 2. Update `param()` block with new parameters (`-Experimental`, `-Force`)
- [ ] 3. Keep and clean up dependency check/install functions (remove admin requirement)
- [ ] 4. Delete `Set-PrivacyConfiguration` function (env vars go in settings.json now)
- [ ] 5. Delete `Set-WindowsEnvironment` function (same reason)
- [ ] 6. Delete `Set-ClaudeConfiguration` function (was writing to wrong file `.claude.json`)
- [ ] 7. Delete `New-PreprocessScript` function (hooks handle this)
- [ ] 8. Delete `New-KeepaliveScript` function (misconception)
- [ ] 9. Delete `New-SettingsJson` function (will be replaced)
- [ ] 10. Create new `Set-ClaudeSettings` function that writes `settings.json` with merged env + hooks
- [ ] 11. Create new `New-HookScripts` function that detects bash availability, generates `.sh` hooks (bash path) or `.ps1` hooks (PowerShell fallback with absolute paths)
- [ ] 12. Create new `New-ClaudeMdTemplate` function for compact instructions
- [ ] 13. Create new `Test-Optimizations` validation function
- [ ] 14. Create new `Show-Summary` function with before/after display
- [ ] 15. Update `Main` function to call new functions in correct order
- [ ] 16. Change log paths from `/tmp/` to `$env:TEMP` only in PowerShell fallback hooks; keep `/tmp/` in bash hooks (MSYS2 maps it)
- [ ] 17. Test with `-DryRun` flag — verify no files written
- [ ] 18. Test without `-DryRun` on a clean system
- [ ] 19. Verify settings.json is valid and hooks reference correct paths
- [ ] 20. Run `Test-Optimizations` validation function
- [ ] 21. Run all TC-H hook unit tests — all must pass
- [ ] 22. Run all TC-O optimizer output tests — all must pass
- [ ] 23. Run TC-E01 (DryRun no-write) and TC-E03 (idempotency) edge case tests

---

## 12. Additional Hooks: Security, Automation & UX

### 12.1 Overview Table

| Hook file | Event | Matcher | Default | Flag to disable/enable | Purpose |
|-----------|-------|---------|---------|------------------------|---------|
| `file-guard.sh` | PreToolUse | `Write\|Edit\|MultiEdit\|Bash` | **ON** | `-NoGuard` disables | Block writes to sensitive paths |
| `notify.sh` | Notification | `*` | **ON** | `-NoNotify` disables | Windows balloon tip / cross-platform desktop alert |
| `post-compact.sh` | SessionStart | `compact` | **ON** | `-NoContextRefresh` disables | Re-inject CLAUDE.md after compaction |
| `auto-approve.sh` | PreToolUse | `Bash` | **OFF** | `-AutoApprove` enables | Auto-allow safe read-only commands |
| `post-edit-format.sh` | PostToolUse | `Write\|Edit\|MultiEdit` | **OFF** | `-AutoFormat` enables | Run prettier/black/gofmt after edits |

Each hook is a standalone bash script. The PowerShell fallback for systems without bash is described in section 12.7.

---

### 12.2 `file-guard.sh` — Sensitive File Write Protection

**Purpose**: Intercept Write, Edit, MultiEdit, and Bash tool calls. If the target path matches a sensitive pattern (`.env`, `.git/`, private keys, lock files, credentials), exit 2 to block the tool. Claude receives the stderr message explaining why it was blocked.

**When to install**: Always (unless `-NoGuard` is passed).

**settings.json registration snippet**:
```json
{
  "matcher": "Write|Edit|MultiEdit|Bash",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/file-guard.sh",
      "timeout": 10
    }
  ]
}
```

**Full bash source** (`~/.claude/hooks/file-guard.sh`):
```bash
#!/usr/bin/env bash
# file-guard.sh — blocks writes to sensitive files and paths
# Event: PreToolUse
# Matcher: Write|Edit|MultiEdit|Bash
# Exit 0 = allow | Exit 2 = block (stderr message shown to Claude)

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"
COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"

LOG_FILE="/tmp/claude-file-guard.log"

# Sensitive path patterns (POSIX extended regex)
BLOCKED_PATTERNS=(
  '\.env$'
  '\.env\.'
  '\.git/'
  'package-lock\.json$'
  'yarn\.lock$'
  'pnpm-lock\.yaml$'
  '\.ssh/'
  'id_rsa'
  'id_ed25519'
  'credentials\.json$'
  '\.aws/credentials'
  '\.gnupg/'
  'secrets\.'
  '\.pem$'
  '\.key$'
)

block_with_reason() {
  local path="$1" pattern="$2"
  echo "[file-guard] $(date '+%Y-%m-%dT%H:%M:%S') BLOCKED tool=$TOOL_NAME path=$path pattern=$pattern" >> "$LOG_FILE"
  echo "BLOCKED: '$path' matches protected pattern '$pattern'. If you genuinely need to edit this file, the user must do it manually." >&2
  exit 2
}

check_path() {
  local path="$1"
  if [[ -z "$path" ]]; then return; fi
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$path" | grep -qE "$pattern"; then
      block_with_reason "$path" "$pattern"
    fi
  done
}

# Write / Edit / MultiEdit: check tool_input.file_path
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then
  check_path "$FILE_PATH"
fi

# Bash: scan the command string for suspicious path patterns
if [[ "$TOOL_NAME" == "Bash" && -n "$COMMAND" ]]; then
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qE "$pattern"; then
      echo "[file-guard] $(date '+%Y-%m-%dT%H:%M:%S') BLOCKED bash command matching pattern=$pattern" >> "$LOG_FILE"
      echo "BLOCKED: Bash command appears to touch a protected path (pattern: $pattern). If intentional, the user must run this command manually." >&2
      exit 2
    fi
  done
fi

echo "[file-guard] $(date '+%Y-%m-%dT%H:%M:%S') ALLOWED tool=$TOOL_NAME path=$FILE_PATH" >> "$LOG_FILE"
exit 0
```

**Notes**:
- The `BLOCKED_PATTERNS` array uses POSIX extended regex, compatible with `grep -E`.
- Bash tool matching is intentionally conservative — it matches the raw command string. False positives are possible (e.g., a `cat README.md` mentioning `.env`). If too noisy, users can disable with `-NoGuard`.
- Exit 2 causes Claude Code to skip the tool and show the stderr message to Claude, allowing Claude to explain the block to the user.
- The log file at `/tmp/claude-file-guard.log` is append-only; MSYS2 maps `/tmp/` to a valid temp directory on Windows.

---

### 12.3 `notify.sh` — Cross-Platform Desktop Notifications

**Purpose**: When Claude Code emits a Notification event (task complete, needs attention, etc.), show a native desktop notification. On Windows, uses `powershell.exe` to show a Windows Forms balloon tip. Falls back to `notify-send` (Linux), `osascript` (macOS), or a terminal bell.

**When to install**: Always (unless `-NoNotify` is passed).

**settings.json registration snippet**:
```json
{
  "matcher": "*",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/notify.sh",
      "timeout": 15
    }
  ]
}
```

**Full bash source** (`~/.claude/hooks/notify.sh`):
```bash
#!/usr/bin/env bash
# notify.sh — cross-platform desktop notifications for Claude Code events
# Event: Notification
# Exit 0 = let Claude Code show default notification too
# Exit 2 = we handled it, suppress default notification

INPUT="$(cat)"
MESSAGE="$(echo "$INPUT" | jq -r '.message // .title // "Claude Code notification"')"
TITLE="$(echo "$INPUT" | jq -r '.title // "Claude Code"')"

LOG_FILE="/tmp/claude-notify.log"
echo "[notify] $(date '+%Y-%m-%dT%H:%M:%S') title=$TITLE msg=$MESSAGE" >> "$LOG_FILE"

# Sanitize: remove single quotes to avoid shell injection in powershell.exe -Command string
SAFE_TITLE="${TITLE//\'/}"
SAFE_MESSAGE="${MESSAGE//\'/}"

# Windows: balloon tip via Windows Forms
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "
    Add-Type -AssemblyName System.Windows.Forms
    \$icon = New-Object System.Windows.Forms.NotifyIcon
    \$icon.Icon = [System.Drawing.SystemIcons]::Information
    \$icon.BalloonTipTitle = '$SAFE_TITLE'
    \$icon.BalloonTipText = '$SAFE_MESSAGE'
    \$icon.Visible = \$true
    \$icon.ShowBalloonTip(5000)
    Start-Sleep -Milliseconds 5500
    \$icon.Dispose()
  " 2>/dev/null
  exit 2
fi

# Linux: notify-send
if command -v notify-send >/dev/null 2>&1; then
  notify-send "$TITLE" "$MESSAGE" --expire-time=5000 2>/dev/null
  exit 2
fi

# macOS: osascript
if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$SAFE_MESSAGE\" with title \"$SAFE_TITLE\"" 2>/dev/null
  exit 2
fi

# Last resort: terminal bell
printf '\a' >/dev/tty 2>/dev/null || true
exit 0
```

**Notes**:
- Exit 2 suppresses Claude Code's own default notification handling. Exit 0 lets it show as well (double notification). Use exit 2 to avoid duplicates.
- The `powershell.exe -WindowStyle Hidden` prevents a console window flash on Windows.
- Single quotes are stripped from title/message before embedding in the `-Command` string to prevent PowerShell injection. For a more robust approach, the PowerShell fallback script (12.7) should be used instead.
- `Start-Sleep -Milliseconds 5500` keeps the .NET process alive long enough for the balloon to display before `Dispose()` is called.

---

### 12.4 `post-compact.sh` — Context Re-injection After Compaction

**Purpose**: After Claude Code compacts the context window, the CLAUDE.md instructions are no longer in context. This `SessionStart` hook with the `"compact"` matcher fires immediately after compaction and writes the contents of `~/.claude/CLAUDE.md` to stdout, which Claude Code injects into the new context.

**When to install**: Always (unless `-NoContextRefresh` is passed).

**settings.json registration snippet**:
```json
{
  "matcher": "compact",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/post-compact.sh",
      "timeout": 10
    }
  ]
}
```

**Full bash source** (`~/.claude/hooks/post-compact.sh`):
```bash
#!/usr/bin/env bash
# post-compact.sh — re-injects ~/.claude/CLAUDE.md after context compaction
# Event: SessionStart
# Matcher: "compact" (fires after context compaction, not on normal session start)
# Stdout content is injected into Claude's context as a system message
# Exit 0 = proceed

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
LOG_FILE="/tmp/claude-post-compact.log"

echo "[post-compact] $(date '+%Y-%m-%dT%H:%M:%S') compaction detected, re-injecting context" >> "$LOG_FILE"

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "[post-compact] CLAUDE.md not found at $CLAUDE_MD — skipping injection" >> "$LOG_FILE"
  exit 0
fi

# Output the CLAUDE.md content to stdout
# Claude Code injects this into the model's context
echo "## Post-Compaction Context Refresh"
echo ""
echo "Your persistent instructions from ~/.claude/CLAUDE.md have been re-injected below."
echo "These apply for the remainder of this session."
echo ""
cat "$CLAUDE_MD"

echo "[post-compact] $(date '+%Y-%m-%dT%H:%M:%S') injected $(wc -l < "$CLAUDE_MD") lines" >> "$LOG_FILE"
exit 0
```

**Notes**:
- The `"compact"` matcher on `SessionStart` is the documented way to hook post-compaction. It fires only when compaction has occurred, not on every session start.
- Stdout is injected verbatim into Claude's context. Keep the CLAUDE.md concise — long files increase every request's token cost.
- This hook is the reason the optimizer writes a CLAUDE.md with token-budget instructions (Section 8). Without this hook, those instructions are lost after compaction.

---

### 12.5 `auto-approve.sh` — Whitelist Safe Bash Commands (Opt-in)

**Purpose**: Automatically approve Bash tool calls matching a whitelist of safe, read-only commands (file listings, version checks, git status queries, etc.), bypassing the user permission prompt for those commands. Outputs the `permissionDecision: "allow"` JSON on exit 0.

**When to install**: Only when `-AutoApprove` is passed.

**settings.json registration snippet** (added as a second PreToolUse entry):
```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/auto-approve.sh",
      "timeout": 5
    }
  ]
}
```

**Full bash source** (`~/.claude/hooks/auto-approve.sh`):
```bash
#!/usr/bin/env bash
# auto-approve.sh — auto-approves safe read-only bash commands
# Event: PreToolUse
# Matcher: Bash
# Opt-in: only installed with -AutoApprove
# Exit 0 + JSON stdout = auto-approve | Exit 0 (no JSON) = defer to normal permission prompt

INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"
LOG_FILE="/tmp/claude-auto-approve.log"

# Whitelisted command prefixes (read-only, safe)
SAFE_PREFIXES=(
  "ls"
  "cat "
  "echo "
  "pwd"
  "which "
  "where "
  "git status"
  "git log"
  "git diff"
  "git branch"
  "git show"
  "git remote"
  "git stash list"
  "npm list"
  "npm run"
  "pip list"
  "pip show"
  "python --version"
  "python3 --version"
  "node --version"
  "node -v"
  "npm --version"
  "npm -v"
  "Get-Content "
  "Get-ChildItem"
  "Write-Host"
  "Select-String"
  "type "
  "dir "
)

for prefix in "${SAFE_PREFIXES[@]}"; do
  # Match: command equals prefix exactly, or command starts with prefix followed by space/flag
  if [[ "$COMMAND" == "$prefix" || "$COMMAND" == "$prefix "* ]]; then
    echo "[auto-approve] $(date '+%Y-%m-%dT%H:%M:%S') APPROVED: $COMMAND" >> "$LOG_FILE"
    printf '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
  fi
done

# Not on whitelist — let Claude Code show normal permission prompt
echo "[auto-approve] $(date '+%Y-%m-%dT%H:%M:%S') DEFERRED (not whitelisted): $COMMAND" >> "$LOG_FILE"
exit 0
```

**Notes**:
- The `permissionDecision: "allow"` JSON must be the **only** content on stdout (no trailing newline from echo; use `printf` or `echo -n`). The plan uses `printf` to avoid the newline.
- Commands are matched by prefix. `"git status"` matches `git status`, `git status --short`, etc. It does NOT match `git status && rm -rf /` because the suffix check is not validated — this is an intentional limitation; the whitelist is conservative.
- This hook is opt-in because auto-approving commands reduces visibility. Users who want full control over every tool call should not use this flag.
- If the command is not whitelisted, exit 0 without JSON output — this defers to normal Claude Code permission handling (it will prompt the user).

---

### 12.6 `post-edit-format.sh` — Auto-Format After Edits (Opt-in)

**Purpose**: After a Write, Edit, or MultiEdit tool call completes, automatically run the appropriate formatter for the file type (prettier for JS/TS/CSS/HTML/JSON/Markdown, black for Python, gofmt for Go, rustfmt for Rust, rubocop for Ruby). If no formatter is found for the file type, exit silently.

**When to install**: Only when `-AutoFormat` is passed.

**settings.json registration snippet** (added as a second PostToolUse entry):
```json
{
  "matcher": "Write|Edit|MultiEdit",
  "hooks": [
    {
      "type": "command",
      "command": "bash ~/.claude/hooks/post-edit-format.sh",
      "timeout": 30
    }
  ]
}
```

**Full bash source** (`~/.claude/hooks/post-edit-format.sh`):
```bash
#!/usr/bin/env bash
# post-edit-format.sh — auto-formats files after Write/Edit/MultiEdit
# Event: PostToolUse
# Matcher: Write|Edit|MultiEdit
# Opt-in: only installed with -AutoFormat
# Exit 0 always (formatting failures are non-fatal)

INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')"
LOG_FILE="/tmp/claude-auto-format.log"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Extract lowercase extension (strip leading dot)
EXT="${FILE_PATH##*.}"
EXT="${EXT,,}"  # lowercase (bash 4+)

FORMAT_RESULT=""

case "$EXT" in
  js|jsx|ts|tsx|json|css|scss|less|html|htm|md|markdown|yaml|yml)
    if command -v prettier >/dev/null 2>&1; then
      prettier --write "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="prettier"
    fi
    ;;
  py)
    if command -v black >/dev/null 2>&1; then
      black --quiet "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="black"
    elif command -v autopep8 >/dev/null 2>&1; then
      autopep8 --in-place "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="autopep8"
    fi
    ;;
  go)
    if command -v gofmt >/dev/null 2>&1; then
      gofmt -w "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="gofmt"
    fi
    ;;
  rs)
    if command -v rustfmt >/dev/null 2>&1; then
      rustfmt "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="rustfmt"
    fi
    ;;
  rb)
    if command -v rubocop >/dev/null 2>&1; then
      rubocop --autocorrect --format quiet "$FILE_PATH" 2>/dev/null && FORMAT_RESULT="rubocop"
    fi
    ;;
  *)
    # No formatter registered for this extension
    ;;
esac

if [[ -n "$FORMAT_RESULT" ]]; then
  echo "[auto-format] $(date '+%Y-%m-%dT%H:%M:%S') Formatted $FILE_PATH with $FORMAT_RESULT" >> "$LOG_FILE"
else
  echo "[auto-format] $(date '+%Y-%m-%dT%H:%M:%S') No formatter for $FILE_PATH (.$EXT)" >> "$LOG_FILE"
fi

exit 0
```

**Notes**:
- `EXT="${EXT,,}"` requires bash 4+. MSYS2 bash is version 5.x — this is safe. For systems that might have bash 3 (macOS default before Catalina), replace with `EXT="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"`.
- PostToolUse hooks cannot block the tool (it already ran). Formatting failures are silently logged; they never interrupt Claude's workflow.
- `MultiEdit` is included because it performs multiple edits in a single tool call — the tool_input still contains `file_path`.
- The hook re-reads `tool_input.file_path` (not `tool_response`) because at PostToolUse time, we want the path of the file that was just written/edited.

---

### 12.7 PowerShell Fallback Versions

When bash is not available on the system, the optimizer generates `.ps1` versions of each hook. The PowerShell commands in settings.json must use **absolute paths** (no tilde expansion in PowerShell arguments passed via Windows process creation):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<user>\.claude\hooks\file-guard.ps1"
```

The implementing model must generate these `.ps1` files in parallel with the `.sh` files, selecting which to register in settings.json based on the bash detection result. The PowerShell versions follow the same logic as the bash versions above, with these substitutions:

| Bash construct | PowerShell equivalent |
|----------------|-----------------------|
| `` INPUT="$(cat)" `` | `$InputJson = [Console]::In.ReadToEnd()` |
| `jq -r '.tool_name // empty'` | `($payload \| ConvertFrom-Json).tool_name` |
| `echo "..." \| grep -qE "$pattern"` | `$value -match $pattern` |
| `exit 2` | `exit 2` (same) |
| Write stderr: `echo "..." >&2` | `[Console]::Error.WriteLine("...")` |
| Write stdout (JSON): `printf '...'` | `[Console]::Out.Write('...')` |
| `/tmp/logfile.log` | `"$env:TEMP\claude-<name>.log"` |
| `$HOME/.claude/CLAUDE.md` | `"$env:USERPROFILE\.claude\CLAUDE.md"` |

The PowerShell fallback for `notify.ps1` is simpler since `powershell.exe` IS the process — no subprocess needed:

```powershell
# notify.ps1 — Windows balloon tip (PowerShell fallback version)
param()
$ErrorActionPreference = 'SilentlyContinue'
$InputJson = [Console]::In.ReadToEnd()
$payload = $InputJson | ConvertFrom-Json
$message = if ($payload.message) { $payload.message } elseif ($payload.title) { $payload.title } else { "Claude Code notification" }
$title = if ($payload.title) { $payload.title } else { "Claude Code" }

Add-Type -AssemblyName System.Windows.Forms
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = [System.Drawing.SystemIcons]::Information
$icon.BalloonTipTitle = $title
$icon.BalloonTipText = $message
$icon.Visible = $true
$icon.ShowBalloonTip(5000)
Start-Sleep -Milliseconds 5500
$icon.Dispose()
exit 2
```

---

## 13. Test Cases for Implementation Validation

These test cases must be run (manually or automated) to verify the optimizer and hooks work correctly. They are organized into four categories. The implementing model should include a `Test-Optimizations` function that runs the TC-O and TC-E categories automatically after install.

---

### TC-H: Hook Unit Tests (bash)

Run by piping synthetic JSON to the hook script and checking exit code + log output.

**Setup** (run before TC-H tests):
```bash
export HOOK_DIR="$HOME/.claude/hooks"
export LOG=/tmp/claude-hook-validation.log
```

---

#### TC-H01 — `file_path` snake_case key parsed correctly

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.png"}}' \
  | bash "$HOOK_DIR/pretooluse.sh"
# Expect: log shows path=/tmp/test.png (not <empty>)
grep "file_path=/tmp/test.png\|path=/tmp/test.png\|FILE.*test.png" /tmp/claude-hook-validation.log
```
**Pass criteria**: Exit 0 and path appears in log. Not `<empty>`.

---

#### TC-H02 — `filePath` camelCase fallback parsed correctly

```bash
echo '{"tool_name":"Read","tool_input":{"filePath":"/tmp/test.png"}}' \
  | bash "$HOOK_DIR/pretooluse.sh"
grep "test.png" /tmp/claude-hook-validation.log
```
**Pass criteria**: Same as TC-H01. Both key formats must work.

---

#### TC-H03 — Empty `tool_input` object

```bash
echo '{"tool_name":"Read","tool_input":{}}' | bash "$HOOK_DIR/pretooluse.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0. No crash (no exit 1 or unhandled error). Log shows `NO_FILE_PATH` or equivalent.

---

#### TC-H04 — Completely empty JSON input

```bash
echo '{}' | bash "$HOOK_DIR/pretooluse.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0. Script handles missing `tool_name` gracefully.

---

#### TC-H05 — Non-image file passed to pretooluse

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/readme.txt"}}' \
  | bash "$HOOK_DIR/pretooluse.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0. Log shows the file is not an image (pass-through). No image processing attempted.

---

#### TC-H06 — Non-Read tool passed to pretooluse

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | bash "$HOOK_DIR/pretooluse.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0 immediately. No file processing logic runs.

---

#### TC-H07 — Image file, ImageMagick NOT present (mock by temporarily renaming)

```bash
# Temporarily hide magick from PATH
OLD_PATH="$PATH"
export PATH="/usr/bin:/bin"
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.jpg"}}' \
  | bash "$HOOK_DIR/pretooluse.sh"
EXIT=$?
export PATH="$OLD_PATH"
echo "Exit: $EXIT"
```
**Pass criteria**: Exit 0 (graceful degradation). Log shows `NO_IMAGEMAGICK` or equivalent. Does not exit 1.

---

#### TC-H08 — Image file with ImageMagick present and file is within limits

```bash
# Create a small test image
convert -size 100x100 xc:white /tmp/tc-h08-test.png 2>/dev/null || \
  magick -size 100x100 xc:white /tmp/tc-h08-test.png 2>/dev/null

echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/tc-h08-test.png"}}' \
  | bash "$HOOK_DIR/pretooluse.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0. Log shows `WITHIN_LIMITS` or similar. File unchanged.

---

#### TC-H09 — PostToolUse parses `tool_name` correctly

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"output":"file.txt"}}' \
  | bash "$HOOK_DIR/posttooluse.sh"
grep "Tool: Bash\|tool=Bash\|tool_name=Bash" /tmp/claude-hook-validation.log | tail -1
```
**Pass criteria**: Log contains the tool name `Bash`, not `unknown` or empty.

---

#### TC-H10 — Malformed JSON input

```bash
echo 'NOT VALID JSON {{{' | bash "$HOOK_DIR/pretooluse.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0 (never exit 1 on bad input). Script may log a parse error but must not crash.

---

#### TC-H11 — file-guard blocks write to `.env` file

```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/home/user/project/.env"}}' \
  | bash "$HOOK_DIR/file-guard.sh"
EXIT=$?
echo "Exit: $EXIT"
```
**Pass criteria**: Exit 2. Stderr contains `BLOCKED` message mentioning `.env`.

---

#### TC-H12 — file-guard allows write to non-sensitive file

```bash
echo '{"tool_name":"Write","tool_input":{"file_path":"/home/user/project/src/main.ts"}}' \
  | bash "$HOOK_DIR/file-guard.sh"
echo "Exit: $?"
```
**Pass criteria**: Exit 0.

---

#### TC-H13 — file-guard blocks Bash command touching `.ssh/`

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}' \
  | bash "$HOOK_DIR/file-guard.sh"
EXIT=$?
echo "Exit: $EXIT"
```
**Pass criteria**: Exit 2. Stderr contains `BLOCKED` message.

---

#### TC-H14 — auto-approve approves whitelisted command

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git status --short"}}' \
  | bash "$HOOK_DIR/auto-approve.sh"
EXIT=$?
echo "Exit: $EXIT"
```
**Pass criteria**: Exit 0. Stdout contains `"permissionDecision":"allow"`.

---

#### TC-H15 — auto-approve defers non-whitelisted command

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./dist"}}' \
  | bash "$HOOK_DIR/auto-approve.sh"
EXIT=$?
STDOUT="$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf ./dist"}}' | bash "$HOOK_DIR/auto-approve.sh")"
echo "Exit: $EXIT | Stdout: '$STDOUT'"
```
**Pass criteria**: Exit 0. Stdout is empty (no `permissionDecision` JSON).

---

### TC-O: Optimizer Output Tests (PowerShell)

Run after executing `optimize-claude.ps1`. All tests read the written `~/.claude/settings.json`.

```powershell
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
```

---

#### TC-O01 — settings.json parses as valid JSON

```powershell
try { $null = Get-Content $settingsPath -Raw | ConvertFrom-Json; Write-Host "PASS" }
catch { Write-Host "FAIL: $($_.Exception.Message)" }
```

---

#### TC-O02 — autoCompactEnabled is true

```powershell
if ($settings.autoCompactEnabled -eq $true) { "PASS" } else { "FAIL: autoCompactEnabled=$($settings.autoCompactEnabled)" }
```

---

#### TC-O03 — All 8 required env vars present

```powershell
$required = @(
  "BASH_MAX_OUTPUT_LENGTH",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
  "DISABLE_TELEMETRY",
  "OTEL_LOG_USER_PROMPTS",
  "OTEL_LOG_TOOL_DETAILS",
  "CLAUDE_CODE_AUTO_COMPACT_WINDOW",
  "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
  "CLAUDE_CODE_DISABLE_AUTO_MEMORY"
)
$envVars = $settings.env.PSObject.Properties.Name
foreach ($v in $required) {
  if ($envVars -contains $v) { "PASS: $v" } else { "FAIL: missing $v" }
}
```

---

#### TC-O04 — All env var values are strings (not integers)

```powershell
$settings.env.PSObject.Properties | ForEach-Object {
  if ($_.Value -is [string]) { "PASS: $($_.Name)" }
  else { "FAIL: $($_.Name) is $($_.Value.GetType().Name)" }
}
```

---

#### TC-O05 — BASH_MAX_OUTPUT_LENGTH is exactly "10000"

```powershell
if ($settings.env.BASH_MAX_OUTPUT_LENGTH -eq "10000") { "PASS" }
else { "FAIL: got $($settings.env.BASH_MAX_OUTPUT_LENGTH)" }
```

---

#### TC-O06 — CLAUDE_AUTOCOMPACT_PCT_OVERRIDE is in range 1–100

```powershell
$val = [int]$settings.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
if ($val -ge 1 -and $val -le 100) { "PASS: $val" }
else { "FAIL: $val is out of range 1-100" }
```

---

#### TC-O07 — PreToolUse hook registered with non-empty command

```powershell
$pre = $settings.hooks.PreToolUse
if ($pre -and $pre.Count -gt 0 -and $pre[0].hooks[0].command) { "PASS" }
else { "FAIL: no PreToolUse hook or empty command" }
```

---

#### TC-O08 — PostToolUse hook registered

```powershell
$post = $settings.hooks.PostToolUse
if ($post -and $post.Count -gt 0) { "PASS" } else { "FAIL: no PostToolUse hook" }
```

---

#### TC-O09 — All hooks have timeout > 0

```powershell
$allHooks = @()
$settings.hooks.PSObject.Properties | ForEach-Object {
  $_.Value | ForEach-Object { $_.hooks | ForEach-Object { $allHooks += $_ } }
}
$allHooks | ForEach-Object {
  if ($_.timeout -gt 0) { "PASS: timeout=$($_.timeout)" }
  else { "FAIL: hook has timeout=$($_.timeout)" }
}
```

---

#### TC-O10 — Hook command file exists on disk

```powershell
$settings.hooks.PSObject.Properties | ForEach-Object {
  $_.Value | ForEach-Object {
    $_.hooks | ForEach-Object {
      $cmd = $_.command
      # Extract path: either after "bash " or after "-File "
      if ($cmd -match 'bash\s+(~[^\s]+)') {
        $path = $Matches[1] -replace '^~', $env:USERPROFILE
        if (Test-Path $path) { "PASS: $path" } else { "FAIL: not found $path" }
      } elseif ($cmd -match '-File\s+"([^"]+)"') {
        $path = $Matches[1]
        if (Test-Path $path) { "PASS: $path" } else { "FAIL: not found $path" }
      }
    }
  }
}
```

---

#### TC-O11 — Bash hook passes syntax check

```powershell
$hooksDir = Join-Path $env:USERPROFILE ".claude\hooks"
Get-ChildItem $hooksDir -Filter "*.sh" | ForEach-Object {
  $result = bash -n $_.FullName 2>&1
  if ($LASTEXITCODE -eq 0) { "PASS: $($_.Name)" }
  else { "FAIL: $($_.Name) — $result" }
}
```

---

#### TC-O12 — Hook command format matches detected shell

```powershell
$bashAvailable = (Get-Command bash -ErrorAction SilentlyContinue) -ne $null
$settings.hooks.PSObject.Properties | ForEach-Object {
  $_.Value | ForEach-Object {
    $_.hooks | ForEach-Object {
      $cmd = $_.command
      if ($bashAvailable) {
        if ($cmd -match '^bash\s+~') { "PASS (bash): $cmd" }
        else { "FAIL: bash available but command doesn't use 'bash ~': $cmd" }
      } else {
        if ($cmd -match 'powershell.*-File.*[A-Z]:\\') { "PASS (ps1): $cmd" }
        else { "FAIL: no bash but command doesn't use absolute ps1 path: $cmd" }
      }
    }
  }
}
```

---

#### TC-O13 — ~/.claude/CLAUDE.md exists with compact instructions

```powershell
$claudeMd = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
if (Test-Path $claudeMd) {
  $content = Get-Content $claudeMd -Raw
  if ($content -match "Compact") { "PASS: CLAUDE.md exists with compact section" }
  else { "FAIL: CLAUDE.md exists but missing Compact instructions" }
} else { "FAIL: CLAUDE.md not found" }
```

---

#### TC-O14 — settings.json has `$schema` property

```powershell
$raw = Get-Content $settingsPath -Raw | ConvertFrom-Json
if ($raw.PSObject.Properties.Name -contains '$schema') { "PASS" }
else { "FAIL: no `$schema` key in settings.json" }
```

---

### TC-E: Edge Case & Safety Tests

---

#### TC-E01 — `-DryRun` flag leaves settings.json unmodified

```powershell
$before = (Get-Item (Join-Path $env:USERPROFILE ".claude\settings.json") -ErrorAction SilentlyContinue)?.LastWriteTime
.\optimize-claude.ps1 -DryRun
$after = (Get-Item (Join-Path $env:USERPROFILE ".claude\settings.json") -ErrorAction SilentlyContinue)?.LastWriteTime
if ($before -eq $after) { "PASS: settings.json not modified" }
else { "FAIL: settings.json was modified by -DryRun" }
```

---

#### TC-E02 — `-DryRun` flag creates no hook scripts

```powershell
$hooksBefore = (Get-ChildItem (Join-Path $env:USERPROFILE ".claude\hooks") -ErrorAction SilentlyContinue).Count
.\optimize-claude.ps1 -DryRun
$hooksAfter = (Get-ChildItem (Join-Path $env:USERPROFILE ".claude\hooks") -ErrorAction SilentlyContinue).Count
if ($hooksBefore -eq $hooksAfter) { "PASS" }
else { "FAIL: -DryRun created hook scripts (before=$hooksBefore after=$hooksAfter)" }
```

---

#### TC-E03 — Idempotency: running optimizer twice produces identical settings.json

```powershell
.\optimize-claude.ps1 -Force
$hash1 = (Get-FileHash (Join-Path $env:USERPROFILE ".claude\settings.json") -Algorithm SHA256).Hash
.\optimize-claude.ps1 -Force
$hash2 = (Get-FileHash (Join-Path $env:USERPROFILE ".claude\settings.json") -Algorithm SHA256).Hash
if ($hash1 -eq $hash2) { "PASS: identical output" }
else { "FAIL: second run produced different settings.json" }
```

---

#### TC-E04 — Custom keys in existing settings.json are preserved

```powershell
# Setup: inject a custom key
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
$existing | Add-Member -NotePropertyName "myCustomKey" -NotePropertyValue "preserved" -Force
$existing | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

# Run optimizer
.\optimize-claude.ps1 -Force

# Check
$after = Get-Content $settingsPath -Raw | ConvertFrom-Json
if ($after.myCustomKey -eq "preserved") { "PASS: custom key preserved" }
else { "FAIL: custom key lost (value=$($after.myCustomKey))" }
```

---

#### TC-E05 — Backup created before overwriting settings.json

```powershell
.\optimize-claude.ps1 -Force
$backup = Get-ChildItem (Join-Path $env:USERPROFILE ".claude") -Filter "settings.json.bak*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($backup) { "PASS: backup found at $($backup.FullName)" }
else { "FAIL: no backup file found" }
```

---

#### TC-E06 — Runs without admin elevation

```powershell
# Verify the script does not call Start-Process with -Verb RunAs or #requires -RunAsAdministrator
$scriptContent = Get-Content .\optimize-claude.ps1 -Raw
if ($scriptContent -notmatch '#requires.*RunAsAdministrator' -and $scriptContent -notmatch 'RunAs') {
  "PASS: no admin escalation found"
} else {
  "FAIL: script contains admin escalation"
}
```

---

#### TC-E07 — Read-only settings.json produces clear error (not exception)

```powershell
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
# Make read-only
Set-ItemProperty $settingsPath -Name IsReadOnly -Value $true
try {
  $output = .\optimize-claude.ps1 -Force 2>&1
  if ($output -match "ERROR|read.only|cannot|access denied" -or $LASTEXITCODE -ne 0) {
    "PASS: clear error reported"
  } else {
    "FAIL: no error reported for read-only file"
  }
} finally {
  # Restore
  Set-ItemProperty $settingsPath -Name IsReadOnly -Value $false
}
```

---

### TC-S: Shell Detection Tests

---

#### TC-S01 — Bash in PATH → hook commands use `bash ~/` prefix

```powershell
# Verify bash is detectable
$bashInPath = (Get-Command bash -ErrorAction SilentlyContinue) -ne $null
if (-not $bashInPath) { Write-Host "SKIP: bash not available on this system"; return }

.\optimize-claude.ps1 -Force
$settings = Get-Content (Join-Path $env:USERPROFILE ".claude\settings.json") -Raw | ConvertFrom-Json
$allCommands = @()
$settings.hooks.PSObject.Properties | ForEach-Object {
  $_.Value | ForEach-Object { $_.hooks | ForEach-Object { $allCommands += $_.command } }
}
$nonBash = $allCommands | Where-Object { $_ -notmatch '^bash\s+~' }
if (-not $nonBash) { "PASS: all hook commands use bash ~/..." }
else { "FAIL: some hooks not using bash prefix: $($nonBash -join '; ')" }
```

---

#### TC-S02 — Bash NOT in PATH → hook commands use absolute PowerShell path

```powershell
# Mock: temporarily set PATH to exclude bash
$savedPath = $env:PATH
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -notmatch 'bash|Git|MSYS|mingw' }) -join ';'
try {
  .\optimize-claude.ps1 -Force
  $settings = Get-Content (Join-Path $env:USERPROFILE ".claude\settings.json") -Raw | ConvertFrom-Json
  $allCommands = @()
  $settings.hooks.PSObject.Properties | ForEach-Object {
    $_.Value | ForEach-Object { $_.hooks | ForEach-Object { $allCommands += $_.command } }
  }
  $nonPS = $allCommands | Where-Object { $_ -notmatch 'powershell.*-File.*\.ps1' }
  if (-not $nonPS) { "PASS: all hook commands use PowerShell absolute path" }
  else { "FAIL: some hooks not using ps1 fallback: $($nonPS -join '; ')" }
} finally {
  $env:PATH = $savedPath
}
```

---

#### TC-S03 — PowerShell fallback path is absolute (no tilde)

```powershell
$savedPath = $env:PATH
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -notmatch 'bash|Git|MSYS|mingw' }) -join ';'
try {
  .\optimize-claude.ps1 -Force
  $settings = Get-Content (Join-Path $env:USERPROFILE ".claude\settings.json") -Raw | ConvertFrom-Json
  $allCommands = @()
  $settings.hooks.PSObject.Properties | ForEach-Object {
    $_.Value | ForEach-Object { $_.hooks | ForEach-Object { $allCommands += $_.command } }
  }
  $tildeCmd = $allCommands | Where-Object { $_ -match '~' }
  if (-not $tildeCmd) { "PASS: no tilde in PowerShell fallback commands" }
  else { "FAIL: tilde found in command (won't expand on Windows): $($tildeCmd -join '; ')" }
} finally {
  $env:PATH = $savedPath
}
```
