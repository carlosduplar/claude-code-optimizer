# Maximizing Your Claude Subscription: A Step-by-Step Guide to Token Efficiency & Privacy

*A practical, human-readable guide for stretching your Claude Code subscription while protecting your privacy*

---

## Table of Contents

1. [Quick Start (5 Minutes)](#quick-start-5-minutes)
2. [Understanding Your Limits](#understanding-your-limits)
3. [Phase 1: Privacy-First Setup](#phase-1-privacy-first-setup)
4. [Phase 2: Token Optimization Basics](#phase-2-token-optimization-basics)
5. [Phase 3: Advanced Efficiency](#phase-3-advanced-efficiency)
6. [Phase 4: Automation with Hooks](#phase-4-automation-with-hooks)
7. [Daily Workflow Checklist](#daily-workflow-checklist)
8. [Troubleshooting & Verification](#troubleshooting--verification)

---

## Quick Start (5 Minutes)

Want results **right now**? Do these three things:

### 1. Enable Privacy Mode (30 seconds)

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.bash_profile`):

```bash
# Disable all telemetry and nonessential network traffic
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
```

**Why this matters**: Stops data collection and speeds up startup by skipping analytics initialization.

### 2. Enable Auto-Compact (1 minute)

Create or edit `~/.claude.json`:

```json
{
  "autoCompactEnabled": true,
  "theme": "dark"
}
```

**Why this matters**: Automatically compresses conversation when you hit 150K tokens, preventing expensive blocking limits.

### 3. Install Pre-Processing Tools (3 minutes)

```bash
# macOS
brew install poppler  # For pdftotext
brew install imagemagick  # For image resizing
pip install markitdown  # For Office documents

# Ubuntu/Debian
sudo apt-get install poppler-utils imagemagick
pip install markitdown

# Windows (with chocolatey)
choco install poppler imagemagick
pip install markitdown
```

**Why this matters**: Lets you convert expensive binary files to cheap text before Claude sees them.

---

## Understanding Your Limits

### The Two Limit Windows

| Window | Duration | Triggers At | What Happens |
|--------|----------|-------------|--------------|
| **Session Limit** | 5 hours | 90% utilization | Warning, then block |
| **Weekly Limit** | 7 days | 25%, 50%, 75% | Tiered warnings |

**Key insight**: The 5-hour window is your real constraint. One long session can burn through hours of work.

### Rate Limit Headers (What Claude Tracks)

Every API response includes these headers (automatically tracked):
- `anthropic-ratelimit-unified-5h-*` - Your session usage
- `anthropic-ratelimit-unified-7d-*` - Your weekly usage
- `anthropic-ratelimit-unified-overage-*` - Extra usage status

**You don't need to check these manually**—Claude warns you automatically. But understanding them helps you pace yourself.

### The Overage Safety Net

If you hit your main limit:
1. If you have **overage enabled** (account setting), it activates automatically
2. If you have **extra usage disabled**, you get blocked until the window resets

**Recommendation**: Enable overage in your Anthropic account settings as a safety net.

---

## Phase 1: Privacy-First Setup

### Privacy Levels Explained

Claude Code has three privacy tiers:

| Level | Environment Variables | Effect |
|-------|------------------------|--------|
| **Default** | None | Full telemetry, auto-updates, analytics |
| **No Telemetry** | `DISABLE_TELEMETRY=1` | No analytics, keeps functionality |
| **Essential Only** | `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | API calls only, maximum privacy |

The system picks the **most restrictive** setting from all sources.

### Step 1: Choose Your Privacy Level

#### Option A: Maximum Privacy (Recommended for Sensitive Work)

```bash
# Add to ~/.bashrc or ~/.zshrc
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export OTEL_LOG_USER_PROMPTS=0
export OTEL_LOG_TOOL_DETAILS=0
```

**What gets disabled**:
- All Datadog logging
- All 1P event logging
- Auto-updates
- Release notes fetching
- Changelog fetching
- Model capabilities prefetch
- Plugin marketplace sync
- MCP registry sync

**What still works**:
- Anthropic API calls (required)
- OAuth token refresh (if using OAuth)
- All core functionality

#### Option B: Balanced (Recommended for Most Users)

```bash
export DISABLE_TELEMETRY=1
```

**What gets disabled**:
- Analytics and telemetry

**What stays enabled**:
- Auto-updates
- Release notes
- Plugin marketplace
- All functionality

#### Option C: Corporate/Restricted Environment

```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export HTTPS_PROXY=http://proxy.company.com:8080
export CLAUDE_CODE_SIMPLE=1  # Minimal mode
```

### Step 2: Verify Privacy Settings

After setting environment variables, verify they're active:

```bash
# Check variables are exported
export -p | grep -E '(DISABLE_TELEMETRY|NONENTIAL)'

# Should show:
# declare -x CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
# declare -x DISABLE_TELEMETRY="1"
```

Then start Claude and run:

```
/debug
```

Look for:
- `telemetry: disabled` ✓
- `nonessential_traffic: blocked` ✓ (if using essential-only mode)

### Step 3: HIPAA Compliance (If Needed)

For HIPAA-compliant environments, also disable 1M context:

```bash
export CLAUDE_CODE_DISABLE_1M_CONTEXT=1
```

---

## Phase 2: Token Optimization Basics

### The Token Cost Reality

Every token costs money. Here's the pricing hierarchy (per million tokens):

| Model | Input Cost | Output Cost | Use For |
|-------|-----------|-------------|---------|
| **Haiku 3.5** | $0.80 | $4 | Quick tasks, searches |
| **Sonnet 4.x** | $3 | $15 | General development |
| **Opus 4.5** | $5 | $25 | Complex architecture |
| **Opus 4.6** | $5 | $25 | Frontier capabilities |
| **Opus 4.6 Fast** | $30 | $150 | Emergency only |

**Key insight**: Haiku is **3.75x cheaper** than Sonnet for inputs. Use it for exploration.

### Step 1: Set Default Model by Task

**Exploration Phase** (finding files, understanding structure):
```
/model haiku
```

**Development Phase** (writing code, debugging):
```
/model sonnet
```

**Complex Architecture** (system design, refactoring):
```
/model opus
```

### Step 2: Enable Auto-Compact

Edit `~/.claude.json`:

```json
{
  "autoCompactEnabled": true
}
```

**What auto-compact does**:
- Monitors token usage every turn
- Triggers at ~150K tokens (75% of 200K window)
- Automatically compresses older messages
- Preserves recent context

**Never use `/clear`**—it destroys cached context. Always use `/compact` or let auto-compact handle it.

### Step 3: Use Pagination for File Reads

**The Wrong Way** (expensive):
```
Read large-file.ts
```

**The Right Way** (cheap):
```
Read large-file.ts {"offset": 1, "limit": 100}
Read large-file.ts {"offset": 101, "limit": 100}
```

**Why**: Large files read entirely consume massive tokens. The system auto-persists results >50K chars to disk, but it's better to paginate.

### Step 4: Search Before Reading

**The Wrong Way**:
```
Read *.ts  # Read all files, then search
```

**The Right Way**:
```
Grep "function handleRequest" *.ts
```

**Why**: Grep is cheap (uses fast model). Reading everything then searching wastes tokens.

### Step 5: Pre-Process Binary Files

**Images** (always pre-resize):
```bash
# Before attaching to Claude
magick screenshot.png -resize 2000x2000\> -quality 85 optimized.png
```

**PDFs** (convert to text):
```bash
# Option 1: Plain text
pdftotext -layout document.pdf document.txt

# Option 2: Markdown (better structure)
markitdown document.pdf > document.md

# Option 3: Read specific pages only
# In Claude: Read document.pdf {"pages": "1-10"}
```

**Office Documents**:
```bash
markitdown document.docx > document.md
markitdown spreadsheet.xlsx > spreadsheet.md
markitdown presentation.pptx > presentation.md
```

**Why it matters**:
- Images auto-resize but base64 encoding adds ~33% overhead
- PDFs >10 pages get reference treatment (not inlined)
- Office documents as Markdown are 10x cheaper than binary reads

---

## Phase 3: Advanced Efficiency

### Step 1: Set Token Budgets

Start messages with token limits:

```
+500k Review this PR and suggest improvements. Focus on security issues.
```

**Budget syntax**:
- `+500k` = 500,000 tokens
- `+1m` = 1,000,000 tokens
- `use 500k tokens` = verbose format

**Why**: Sets expectations and helps Claude self-limit verbose output.

### Step 2: Batch by Model

**Wrong** (loses cache, wastes tokens):
```
/model haiku
Grep pattern *.ts
/model sonnet  # Cache lost!
Edit file.ts
```

**Right** (preserves cache):
```
/model haiku
Grep pattern *.ts
Read file.ts {"limit": 50}
Read another.ts {"limit": 50}
# Now switch
/model sonnet
Edit file.ts
```

**Why**: Cache hits require identical system prompt, tools, model, and message prefix. Switching models invalidates the cache.

### Step 3: Avoid Parallel Tool Abuse

**The System Limit**: 200K characters aggregate per message for parallel tool results.

**Wrong** (hits limit, gets persisted to disk):
```
# 10 parallel reads, each 30K chars = 300K total
```

**Right** (sequential or paginated):
```
Read file1.ts {"limit": 50}
Read file2.ts {"limit": 50}
```

### Step 4: Optimize MCP Servers

Each MCP server adds to system prompt size (ongoing token cost).

**Check active servers**:
```
/mcp list
```

**Disable unused**:
```
/mcp disable server-name
```

**Rule of thumb**: If you haven't used a server in 3 sessions, disable it.

### Step 5: Use Plan Mode for Complex Tasks

For multi-step operations (>10 turns expected):

```
/plan Implement user authentication system
```

**Benefits**:
- Requires approval for tool use (prevents wasted work from wrong assumptions)
- Keeps focus on the plan
- Reduces accidental expensive detours

---

## Phase 4: Automation with Hooks

Hooks run automatically before/after tool use. They're perfect for token optimization.

### Hook 1: Auto-Resize Images

Add to your `CLAUDE.md` or `~/.claude.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if command -v magick >/dev/null 2>&1 && [ -f \"$ARGUMENTS\" ] && [[ \"$ARGUMENTS\" =~ \.(png|jpg|jpeg)$ ]]; then magick \"$ARGUMENTS\" -resize 2000x2000\> -quality 85 /tmp/resized_$(basename \"$ARGUMENTS\"); fi",
        "if": "Read(*.{png,jpg,jpeg})"
      }]
    }]
  }
}
```

**What it does**: Automatically resizes images before Claude reads them.

### Hook 2: Document Conversion

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if command -v markitdown >/dev/null 2>&1 && [ -f \"$ARGUMENTS\" ] && [[ \"$ARGUMENTS\" =~ \.(pdf|docx|xlsx)$ ]]; then markitdown \"$ARGUMENTS\" > \"${ARGUMENTS%.*}.md\" 2>/dev/null && echo \"Converted: ${ARGUMENTS%.*}.md\"; fi",
        "if": "Read(*.{pdf,docx,xlsx})"
      }]
    }]
  }
}
```

**What it does**: Converts Office/PDF files to Markdown before reading.

### Hook 3: Large File Warning

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if [ -f \"$ARGUMENTS\" ] && [ $(stat -f%z \"$ARGUMENTS\" 2>/dev/null || stat -c%s \"$ARGUMENTS\" 2>/dev/null) -gt 50000 ]; then echo \"WARNING: Large file detected ($(( $(stat -f%z \"$ARGUMENTS\" 2>/dev/null || stat -c%s \"$ARGUMENTS\" 2>/dev/null) / 1024 )) KB). Consider using offset/limit.\"; fi",
        "if": "Read(*.*)"
      }]
    }]
  }
}
```

**What it does**: Warns you before reading files >50KB.

---

## Daily Workflow Checklist

### Morning Setup (2 minutes)

- [ ] Verify model is appropriate (`/model` to check)
- [ ] Confirm auto-compact is enabled
- [ ] Quick MCP audit: `/mcp list` (disable unused)
- [ ] Pre-convert any documents you'll reference today

### Before Each Session (30 seconds)

- [ ] Set token budget if task is large (`+500k` or `+1m`)
- [ ] Choose correct model for the task
- [ ] Pre-resize any screenshots/images you'll attach

### During Session

- [ ] Use `Grep` before `Read`
- [ ] Use `offset` and `limit` for large files
- [ ] Run `/compact` proactively at ~150K tokens
- [ ] Avoid model switching mid-task
- [ ] Convert binary files before reading

### End of Day

- [ ] Check `/cost` to review spend
- [ ] Note any files that should be pre-converted tomorrow
- [ ] Adjust hooks if needed

---

## Troubleshooting & Verification

### Verify Privacy Settings

```bash
# Check env vars
export -p | grep -E '(DISABLE_TELEMETRY|NONENTIAL)'

# In Claude, run:
/debug
```

### Check Token Usage

```
/cost
```

Shows:
- Total cost in USD
- Duration (API vs wall time)
- Lines changed
- Usage by model (input/output/cache)

### Emergency Controls

If you're burning through tokens too fast:

**Hard limit (blocks if exceeded)**:
```bash
export CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE=180000
```

**Disable expensive features**:
```bash
export CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1
export CLAUDE_CODE_DISABLE_ATTACHMENTS=1
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
```

**Switch to Haiku immediately**:
```
/model haiku
```

### Common Issues

**Issue**: "Token usage exceeded warning"
**Solution**: Run `/compact` immediately

**Issue**: Model responses are slow
**Solution**: Check if you're on Fast Mode (`/model`)—it's 6x cost, switch back

**Issue**: Cache misses (repeatedly loading same context)
**Solution**: Stop switching models; batch by model type

**Issue**: Large files causing hangs
**Solution**: Use pagination: `{"offset": 1, "limit": 100}`

---

## Summary: The 80/20 Rule

**20% of efforts that give 80% of savings**:

1. ✅ Enable `DISABLE_TELEMETRY=1` (privacy + speed)
2. ✅ Enable `autoCompactEnabled` (prevents blocking)
3. ✅ Use Haiku for exploration (3.75x cheaper)
4. ✅ Paginate file reads with `offset`/`limit`
5. ✅ Pre-convert PDFs/Office docs with `markitdown`

**Expected results**:
- 50-80% token reduction
- Faster startup (no telemetry init)
- Longer sessions before rate limits
- More productive work per subscription dollar

---

*This guide combines token optimization strategies from Claude Code source analysis with privacy best practices.*
