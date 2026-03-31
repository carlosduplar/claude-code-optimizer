# Claude Code Session Memory and Context Management

## Executive Summary

Claude Code employs a multi-layered context management system to handle long-running conversations while staying within API token limits. The architecture consists of:

- **Proactive compaction** (before API limits are hit)
- **Reactive compaction** (when API returns 413/prompt-too-long)
- **Session memory extraction** (continuous background summarization)
- **Micro-compaction** (tool result management)

---

## Session Memory System (memdir)

### Core Files

| File | Path | Purpose |
|------|------|---------|
| `memoryTypes.ts` | `src/memdir/memoryTypes.ts` | Four memory type taxonomy |
| `memdir.ts` | `src/memdir/memdir.ts` | Main memory directory management |
| `paths.ts` | `src/memdir/paths.ts` | Auto-memory path resolution |
| `teamMemPaths.ts` | `src/memdir/teamMemPaths.ts` | Team memory path validation |
| `memoryScan.ts` | `src/memdir/memoryScan.ts` | Memory file scanning |
| `findRelevantMemories.ts` | `src/memdir/findRelevantMemories.ts` | Query-time memory relevance |
| `memoryAge.ts` | `src/memdir/memoryAge.ts` | Memory staleness tracking |

### Memory Type Taxonomy

**File**: `src/memdir/memoryTypes.ts` (lines 14-21)

Four constrained memory types capture context NOT derivable from project state:

```typescript
export const MEMORY_TYPES = ['user', 'feedback', 'project', 'reference'] as const
```

| Type | Scope | Purpose |
|------|-------|---------|
| `user` | Private | User's role, goals, knowledge |
| `feedback` | Private/Team | Guidance on approach corrections |
| `project` | Team preferred | Ongoing work, deadlines, decisions |
| `reference` | Team scope | Pointers to external systems |

### Storage Location Resolution

**File**: `src/memdir/paths.ts` (lines 223-235)

```typescript
export const getAutoMemPath = memoize(
  (): string => {
    const override = getAutoMemPathOverride() ?? getAutoMemPathSetting()
    if (override) { return override }
    const projectsDir = join(getMemoryBaseDir(), 'projects')
    return (
      join(projectsDir, sanitizePath(getAutoMemBase()), AUTO_MEM_DIRNAME) + sep
    ).normalize('NFC')
  },
  () => getProjectRoot(),
)
```

**Default path**: `~/.claude/projects/{sanitized-cwd}/memory/`

### Team Memory Security

**File**: `src/memdir/teamMemPaths.ts` (lines 228-284)

Team memory has path traversal protection using `realpathDeepestExisting`:

```typescript
export async function validateTeamMemWritePath(filePath: string): Promise<string> {
  // First pass: normalize .. segments
  const resolvedPath = resolve(filePath)
  if (!resolvedPath.startsWith(teamDir)) {
    throw new PathTraversalError(`Path escapes team memory directory`)
  }
  // Second pass: resolve symlinks on deepest existing ancestor
  const realPath = await realpathDeepestExisting(resolvedPath)
  if (!(await isRealPathWithinTeamDir(realPath))) {
    throw new PathTraversalError(`Path escapes via symlink`)
  }
  return resolvedPath
}
```

---

## Session Memory (Background Extraction)

### Core Files

| File | Path | Purpose |
|------|------|---------|
| `sessionMemory.ts` | `src/services/SessionMemory/sessionMemory.ts` | Extraction orchestration |
| `sessionMemoryUtils.ts` | `src/services/SessionMemory/sessionMemoryUtils.ts` | State management |
| `prompts.ts` | `src/services/SessionMemory/prompts.ts` | Template loading |

### Storage Location

**File**: `src/utils/permissions/filesystem.ts` (lines 261-271)

```typescript
export function getSessionMemoryDir(): string {
  return join(getProjectDir(getCwd()), getSessionId(), 'session-memory') + sep
}

export function getSessionMemoryPath(): string {
  return join(getSessionMemoryDir(), 'summary.md')
}
```

**Path format**: `~/.claude/projects/{project}/{sessionId}/session-memory/summary.md`

### Extraction Triggers

**File**: `src/services/SessionMemory/sessionMemory.ts` (lines 134-181)

Session memory extracts when:

1. **Initialization threshold**: `minimumMessageTokensToInit` (default: 10,000 tokens)
2. **Update threshold**: `minimumTokensBetweenUpdate` (default: 5,000 tokens growth)
3. **Tool calls**: `toolCallsBetweenUpdates` (default: 3 calls)
4. **Natural break**: Last assistant turn has no tool calls

```typescript
export function shouldExtractMemory(messages: Message[]): boolean {
  const hasMetTokenThreshold = hasMetUpdateThreshold(currentTokenCount)
  const hasMetToolCallThreshold = toolCallsSinceLastUpdate >= getToolCallsBetweenUpdates()
  const hasToolCallsInLastTurn = hasToolCallsInLastAssistantTurn(messages)
  
  return (hasMetTokenThreshold && hasMetToolCallThreshold) ||
         (hasMetTokenThreshold && !hasToolCallsInLastTurn)
}
```

### Template Structure

**File**: `src/services/SessionMemory/prompts.ts` (lines 11-41)

Default session memory template with 9 sections:

1. Session Title
2. Current State
3. Task specification
4. Files and Functions
5. Workflow
6. Errors & Corrections
7. Codebase and System Documentation
8. Learnings
9. Key results
10. Worklog

---

## Context Compaction System

### Core Files

| File | Path | Purpose |
|------|------|---------|
| `compact.ts` | `src/services/compact/compact.ts` | Full compaction |
| `autoCompact.ts` | `src/services/compact/autoCompact.ts` | Proactive compaction |
| `microCompact.ts` | `src/services/compact/microCompact.ts` | Tool result management |
| `sessionMemoryCompact.ts` | `src/services/compact/sessionMemoryCompact.ts` | SM-based compaction |
| `prompt.ts` | `src/services/compact/prompt.ts` | Summary prompts |
| `grouping.ts` | `src/services/compact/grouping.ts` | API-round grouping |

### Token Thresholds

**File**: `src/services/compact/autoCompact.ts` (lines 62-91)

```typescript
export const AUTOCOMPACT_BUFFER_TOKENS = 13_000
export const WARNING_THRESHOLD_BUFFER_TOKENS = 20_000
export const ERROR_THRESHOLD_BUFFER_TOKENS = 20_000
export const MANUAL_COMPACT_BUFFER_TOKENS = 3_000

export function getAutoCompactThreshold(model: string): number {
  const effectiveContextWindow = getEffectiveContextWindowSize(model)
  return effectiveContextWindow - AUTOCOMPACT_BUFFER_TOKENS
}
```

### Session Memory Compaction

**File**: `src/services/compact/sessionMemoryCompact.ts`

When both session memory AND compaction are enabled, uses pre-extracted memory instead of on-demand summarization:

```typescript
export async function trySessionMemoryCompaction(
  messages: Message[],
  agentId?: AgentId,
  autoCompactThreshold?: number,
): Promise<CompactionResult | null> {
  // Returns null if session memory compaction cannot be used
  if (!shouldUseSessionMemoryCompaction()) return null
  
  // Calculate messages to keep based on lastSummarizedMessageId
  const startIndex = calculateMessagesToKeepIndex(messages, lastSummarizedIndex)
  const messagesToKeep = messages.slice(startIndex)
  
  // Create compaction result from session memory content
  return createCompactionResultFromSessionMemory(...)
}
```

### Compaction Configuration

**File**: `src/services/compact/sessionMemoryCompact.ts` (lines 47-61)

```typescript
export type SessionMemoryCompactConfig = {
  minTokens: number           // Default: 10,000
  minTextBlockMessages: number // Default: 5
  maxTokens: number           // Default: 40,000
}

export const DEFAULT_SM_COMPACT_CONFIG: SessionMemoryCompactConfig = {
  minTokens: 10_000,
  minTextBlockMessages: 5,
  maxTokens: 40_000,
}
```

---

## Feature Flags

### CACHED_MICROCOMPACT (ant-only)

**Location**: `src/services/compact/microCompact.ts` (lines 52-128)

Uses API cache editing to remove tool results without invalidating cached prefix:

```typescript
async function cachedMicrocompactPath(messages: Message[]): Promise<MicrocompactResult> {
  const toolsToDelete = mod.getToolResultsToDelete(state)
  if (toolsToDelete.length > 0) {
    const cacheEdits = mod.createCacheEditsBlock(state, toolsToDelete)
    pendingCacheEdits = cacheEdits  // Queued for API layer
    return {
      messages,  // Unchanged locally
      compactionInfo: { pendingCacheEdits: { trigger: 'auto', deletedToolIds: toolsToDelete, baselineCacheDeletedTokens } }
    }
  }
}
```

**Trigger**: Count-based (configurable threshold)  
**Keep**: Most recent N results (configurable)

### REACTIVE_COMPACT (ant-only)

**Location**: `src/services/compact/autoCompact.ts` (lines 191-199)

Suppresses proactive autocompact to let reactive compact catch API 413s:

```typescript
if (feature('REACTIVE_COMPACT')) {
  if (getFeatureValue_CACHED_MAY_BE_STALE('tengu_cobalt_raccoon', false)) {
    return false  // Suppress proactive autocompact
  }
}
```

The reactive compact handles 413 responses by progressively truncating from the tail.

---

## History System

### Core File

**File**: `src/history.ts`

### Storage Location (lines 115, 299)

```typescript
const historyPath = join(getClaudeConfigHomeDir(), 'history.jsonl')
// ~/.claude/history.jsonl
```

### Structure (lines 219-225, 281-289)

```typescript
type LogEntry = {
  display: string           // User-facing display text
  pastedContents: Record<number, StoredPastedContent>
  timestamp: number
  project: string          // Project root path
  sessionId?: string       // For current session filtering
}

type StoredPastedContent = {
  id: number
  type: 'text' | 'image'
  content?: string         // Inline for small content (<1024 chars)
  contentHash?: string     // External paste store reference for large content
}
```

### Max Items (line 19)

```typescript
const MAX_HISTORY_ITEMS = 100
```

---

## Session Storage (Transcript Persistence)

### Core File

**File**: `src/utils/sessionStorage.ts`

### Session File Location (lines 202-225)

```typescript
export function getTranscriptPath(): string {
  const projectDir = getSessionProjectDir() ?? getProjectDir(getOriginalCwd())
  return join(projectDir, `${getSessionId()}.jsonl`)
}

export function getProjectDir(projectDir: string): string {
  return join(getProjectsDir(), sanitizePath(projectDir))
}
```

**Path format**: `~/.claude/projects/{sanitized-cwd}/{sessionId}.jsonl`

### Entry Types (lines 1126-1264)

The transcript JSONL includes:

| Type | Purpose |
|------|---------|
| `user`, `assistant`, `attachment`, `system` | Message types |
| `summary` | Compact summaries |
| `custom-title`, `ai-title`, `tag` | Metadata |
| `file-history-snapshot` | File checkpoints |
| `content-replacement` | Snip operation records |
| `marble-origami-commit`/`snapshot` | Context collapse records |

---

## Memory Extraction System

### Core File

**File**: `src/services/extractMemories/extractMemories.ts`

### Purpose

Runs at end of query loop to extract durable memories from conversation and write to auto-memory directory.

### Flow (lines 329-523)

1. Check for main-agent memory writes (mutual exclusion)
2. Skip if main agent already wrote to memory files
3. Pre-inject memory directory manifest
4. Run forked agent with restricted tool permissions
5. Advance cursor after successful extraction

### Tool Permissions (lines 171-222)

```typescript
export function createAutoMemCanUseTool(memoryDir: string): CanUseToolFn {
  return async (tool: Tool, input: Record<string, unknown>) => {
    // Allow: Read, Grep, Glob, read-only Bash
    // Allow Edit/Write ONLY for paths within memoryDir
    // Deny: All other tools (MCP, Agent, etc.)
  }
}
```

---

## Context Collapse Integration

Context collapse suppresses autocompact when enabled:

```typescript
if (feature('CONTEXT_COLLAPSE')) {
  const { isContextCollapseEnabled } = require('../contextCollapse/index.js')
  if (isContextCollapseEnabled()) {
    return false  // Context collapse owns headroom management
  }
}
```

---

## Checkpoint System

File checkpoints are implemented via `file-history-snapshot` entries:

**Location**: `src/utils/sessionStorage.ts` (lines 1085-1099)

```typescript
async insertFileHistorySnapshot(
  messageId: UUID,
  snapshot: FileHistorySnapshot,
  isSnapshotUpdate: boolean,
) {
  const fileHistoryMessage: FileHistorySnapshotMessage = {
    type: 'file-history-snapshot',
    messageId,
    snapshot,  // Contains file content at point in time
    isSnapshotUpdate,
  }
  await this.appendEntry(fileHistoryMessage)
}
```

---

## Summary of File Paths and Line Numbers

| Concept | File | Line(s) |
|---------|------|---------|
| Memory types | `src/memdir/memoryTypes.ts` | 14-21 |
| Auto memory path | `src/memdir/paths.ts` | 223-235 |
| Team memory path | `src/memdir/teamMemPaths.ts` | 84-86 |
| Path validation | `src/memdir/teamMemPaths.ts` | 228-284 |
| Session memory path | `src/utils/permissions/filesystem.ts` | 261-271 |
| Session memory extraction | `src/services/SessionMemory/sessionMemory.ts` | 134-181 |
| Compact thresholds | `src/services/compact/autoCompact.ts` | 62-91 |
| Session memory compact | `src/services/compact/sessionMemoryCompact.ts` | 47-61 |
| CACHED_MICROCOMPACT | `src/services/compact/microCompact.ts` | 52-128 |
| REACTIVE_COMPACT | `src/services/compact/autoCompact.ts` | 191-199 |
| History storage | `src/history.ts` | 115, 281-289 |
| Transcript path | `src/utils/sessionStorage.ts` | 202-225 |
| Extract memories | `src/services/extractMemories/extractMemories.ts` | 329-523 |
| compactConversation | `src/services/compact/compact.ts` | 387-763 |

---

## Key Design Decisions

1. **Session Memory vs Project Memory**: Session memory is private to the session (stored at `{projectDir}/{sessionId}/`), while project memory (memdir) is shared across sessions.

2. **Mutual Exclusion**: The main agent and background extraction agent are mutually exclusive - when the main agent writes memories, extraction is skipped.

3. **Token Budget Management**: Multiple layers (microcompact → session memory → autocompact → reactive compact) provide graceful degradation.

4. **Security**: Team memory has symlink traversal protection; auto-memory has path validation.

5. **Prompt Cache Preservation**: CACHED_MICROCOMPACT uses cache_edits API to avoid invalidating the cached prefix.
