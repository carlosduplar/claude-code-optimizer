# Claude Code Skill and Plugin System

## Overview

Claude Code has a sophisticated skill and plugin system that allows extending its capabilities through:

- **Skills**: Markdown-based instructions that define reusable workflows (stored in `SKILL.md` files)
- **Plugins**: Full-featured extensions that can provide skills, hooks, MCP servers, and LSP servers
- **Bundled Skills**: Built-in skills that ship with Claude Code
- **Dynamic Skills**: Skills discovered from `.claude/skills/` directories during file operations

---

## Skill Architecture

### Key Components

| Component | File Path | Purpose |
|-----------|-----------|---------|
| `SkillLoader` | `src/skills/loadSkillsDir.ts` | Loads skills from disk directories |
| `BundledSkillRegistry` | `src/skills/bundledSkills.ts` | Registers built-in skills |
| `SkillTool` | `src/tools/SkillTool/SkillTool.ts` | Tool for model to invoke skills |
| `Command Registry` | `src/commands.ts` | Aggregates all command sources |
| `PluginLoader` | `src/utils/plugins/loadPluginCommands.ts` | Loads plugin-provided skills |

### Skill Sources (Priority Order)

Skills are loaded from multiple sources in this order:

1. **Bundled Skills** (`src/skills/bundled/`) - Built into the CLI
2. **Built-in Plugin Skills** (`src/plugins/bundled/`) - User-toggleable built-in features
3. **Skill Directory Skills** (`~/.claude/skills/`, `.claude/skills/`) - User and project skills
4. **Dynamic Skills** (discovered during file operations) - Nested project skills
5. **Workflow Commands** (if WORKFLOW_SCRIPTS enabled) - Workflow-backed skills
6. **Plugin Commands** - From installed plugins
7. **Built-in Commands** - Core CLI commands

---

## Skill Loading and Registration

### Loading Flow

**Entry Point**: `src/commands.ts:449-469` (`loadAllCommands`)

```typescript
const loadAllCommands = memoize(async (cwd: string): Promise<Command[]> => {
  const [
    { skillDirCommands, pluginSkills, bundledSkills, builtinPluginSkills },
    pluginCommands,
    workflowCommands,
  ] = await Promise.all([
    getSkills(cwd),
    getPluginCommands(),
    getWorkflowCommands ? getWorkflowCommands(cwd) : Promise.resolve([]),
  ])

  return [
    ...bundledSkills,
    ...builtinPluginSkills,
    ...skillDirCommands,
    ...workflowCommands,
    ...pluginCommands,
    ...pluginSkills,
    ...COMMANDS(),  // Built-in commands
  ]
})
```

### Skill Directory Loading

**File**: `src/skills/loadSkillsDir.ts`

Skills are loaded from these locations (lines 638-714):

| Source | Path | Condition |
|--------|------|-----------|
| Managed (Policy) | `managed/.claude/skills/` | Unless `CLAUDE_CODE_DISABLE_POLICY_SKILLS` |
| User | `~/.claude/skills/` | If `userSettings` enabled and not plugin-only |
| Project | `.claude/skills/` (up to home) | If `projectSettings` enabled and not plugin-only |
| Additional | `--add-dir` paths | Always if provided |
| Legacy Commands | `.claude/commands/` | If not `skillsLocked` |

### Dynamic Skill Discovery

**File**: `src/skills/loadSkillsDir.ts:861-915`

When files are accessed, Claude Code discovers nested skills:

```typescript
export async function discoverSkillDirsForPaths(
  filePaths: string[],
  cwd: string,
): Promise<string[]> {
  // Walks up from file paths to find .claude/skills/ directories
  // below cwd (excluding cwd itself, which is loaded at startup)
}
```

---

## Skill Directory Structure

### Standard Skill Format

Skills use a **directory-based structure**:

```
.claude/skills/
├── skill-name/
│   └── SKILL.md          # Required - skill definition
├── another-skill/
│   └── SKILL.md
└── ...
```

### SKILL.md Location Rules

**From** `src/skills/loadSkillsDir.ts:405-480`:

- Only **directory format** is supported in `/skills/` directories: `skill-name/SKILL.md`
- Single `.md` files are **NOT** supported in `/skills/` directories
- Legacy `/commands/` directories support both formats

### Conditional Skills (Path-Filtered)

Skills can specify `paths` frontmatter to only activate when matching files are touched:

```yaml
---
name: my-skill
paths: src/**/*.tsx  # Only activates when .tsx files are accessed
---
```

Implementation at `src/skills/loadSkillsDir.ts:997-1058` (`activateConditionalSkillsForPaths`)

---

## Bundled Skills

### Registration

**File**: `src/skills/bundled/index.ts`

All bundled skills are initialized at startup:

```typescript
export function initBundledSkills(): void {
  registerUpdateConfigSkill()
  registerKeybindingsSkill()
  registerVerifySkill()
  registerDebugSkill()
  registerLoremIpsumSkill()
  registerSkillifySkill()
  registerRememberSkill()
  registerSimplifySkill()
  registerBatchSkill()
  registerStuckSkill()
  // Feature-gated skills...
  if (feature('RUN_SKILL_GENERATOR')) {
    const { registerRunSkillGeneratorSkill } = require('./runSkillGenerator.js')
    registerRunSkillGeneratorSkill()
  }
}
```

### Bundled Skill Definition

**File**: `src/skills/bundledSkills.ts:15-41`

```typescript
export type BundledSkillDefinition = {
  name: string
  description: string
  aliases?: string[]
  whenToUse?: string
  argumentHint?: string
  allowedTools?: string[]
  model?: string
  disableModelInvocation?: boolean
  userInvocable?: boolean
  isEnabled?: () => boolean
  hooks?: HooksSettings
  context?: 'inline' | 'fork'
  agent?: string
  files?: Record<string, string>  // Additional reference files to extract
  getPromptForCommand: (args: string, context: ToolUseContext) => Promise<ContentBlockParam[]>
}
```

### Available Bundled Skills

| Skill | File | Description | Feature Flag |
|-------|------|-------------|------------|
| `update-config` | `updateConfig.ts` | Update Claude Code configuration | - |
| `keybindings` | `keybindings.ts` | Manage keyboard shortcuts | - |
| `verify` | `verify.ts` | Verify code changes by running app | - |
| `debug` | `debug.ts` | Debug assistant | - |
| `lorem-ipsum` | `loremIpsum.ts` | Generate placeholder text | - |
| `skillify` | `skillify.ts` | Capture session as reusable skill | - |
| `remember` | `remember.ts` | Review and organize auto-memory | - |
| `simplify` | `simplify.ts` | Review code for reuse/quality | - |
| `batch` | `batch.ts` | Batch process files | - |
| `stuck` | `stuck.ts` | Help when stuck | - |
| `dream` | `dream.ts` | Kairos dream mode | `KAIROS` |
| `hunter` | `hunter.ts` | Review artifacts | `REVIEW_ARTIFACT` |
| `loop` | `loop.ts` | Agent triggers | `AGENT_TRIGGERS` |
| `schedule-remote-agents` | `scheduleRemoteAgents.ts` | Remote agent scheduling | `AGENT_TRIGGERS_REMOTE` |
| `claude-api` | `claudeApi.ts` | Build Claude apps | `BUILDING_CLAUDE_APPS` |
| `run-skill-generator` | `runSkillGenerator.js` | Generate skills from sessions | `RUN_SKILL_GENERATOR` |

---

## Skill Generators (RUN_SKILL_GENERATOR)

### Feature Flag

**File**: `src/skills/bundled/index.ts:73-78`

```typescript
if (feature('RUN_SKILL_GENERATOR')) {
  const { registerRunSkillGeneratorSkill } = require('./runSkillGenerator.js')
  registerRunSkillGeneratorSkill()
}
```

### Skillify Skill (Session-to-Skill)

**File**: `src/skills/bundled/skillify.ts`

The `/skillify` command captures the current session as a reusable skill:

1. Analyzes session memory and user messages
2. Interviews the user about the process (4 rounds of questions)
3. Generates a `SKILL.md` with proper frontmatter
4. Saves to either:
   - `.claude/skills/<name>/SKILL.md` (project-specific)
   - `~/.claude/skills/<name>/SKILL.md` (personal)

---

## MCP Skill Building

### Overview

MCP (Model Context Protocol) servers can be converted to skills automatically.

### Key Files

| File | Purpose |
|------|---------|
| `src/services/mcp/client.ts` | MCP client implementation |
| `src/services/mcp/MCPConnectionManager.tsx` | Connection management |
| `src/skills/mcpSkillBuilders.ts` | Skill builder registry |

### MCP Skill Builder Registration

**File**: `src/skills/mcpSkillBuilders.ts:26-44`

```typescript
export type MCPSkillBuilders = {
  createSkillCommand: typeof createSkillCommand
  parseSkillFrontmatterFields: typeof parseSkillFrontmatterFields
}

// Registration happens at loadSkillsDir.ts module init
registerMCPSkillBuilders({
  createSkillCommand,
  parseSkillFrontmatterFields,
})
```

### MCP Skill Loading

MCP skills are loaded from:
- Plugin-declared MCP servers with `mcpServers` in manifest
- User-configured MCP servers
- MCPB (MCP Bundle) files

---

## Skill Improvement Surveys

### Feature Overview

**File**: `src/utils/hooks/skillImprovement.ts`

Automatically detects user preferences and corrections during skill execution, then suggests improvements to the skill definition.

### How It Works

1. **Hook Registration** (lines 175-181):

```typescript
export function initSkillImprovement(): void {
  if (feature('SKILL_IMPROVEMENT') &&
      getFeatureValue_CACHED_MAY_BE_STALE('tengu_copper_panda', false)) {
    registerPostSamplingHook(createSkillImprovementHook())
  }
}
```

2. **Detection** (every 5 user messages):
   - Analyzes recent conversation for preferences/corrections
   - Generates `SkillUpdate[]` with section, change, and reason

3. **Application** (lines 188-267):
   - LLM rewrites the SKILL.md with improvements
   - Preserves frontmatter exactly
   - File written back to disk

---

## Workflow Scripts (WORKFLOW_SCRIPTS)

### Feature Flag

**File**: `src/commands.ts:86-90`

```typescript
const workflowsCmd = feature('WORKFLOW_SCRIPTS')
  ? (require('./commands/workflows/index.js') as typeof import('./commands/workflows/index.js')).default
  : null
```

### Workflow Tool

**File**: `src/tools.ts:129-132`

```typescript
const WorkflowTool = feature('WORKFLOW_SCRIPTS')
  ? (() => {
      require('./tools/WorkflowTool/bundled/index.js').initBundledWorkflows()
      return require('./tools/WorkflowTool/WorkflowTool.js').WorkflowTool
    })()
  : null
```

### Workflow Command Factory

**File**: `src/commands.ts:401-405`

```typescript
const getWorkflowCommands = feature('WORKFLOW_SCRIPTS')
  ? (require('./tools/WorkflowTool/createWorkflowCommand.js') as typeof import('./tools/WorkflowTool/createWorkflowCommand.js')).getWorkflowCommands
  : null
```

### Workflow Integration

Workflows appear in command listings with `kind: 'workflow'` (line 233 in `src/types/command.ts`), which affects how they're displayed in the UI (badged as "workflow" in autocomplete).

---

## Skill Tool Implementation

### Tool Definition

**File**: `src/tools/SkillTool/SkillTool.ts:331-869`

The `Skill` tool allows the model to invoke skills:

```typescript
export const SkillTool: Tool<InputSchema, Output, Progress> = buildTool({
  name: SKILL_TOOL_NAME,  // "Skill"
  searchHint: 'invoke a slash-command skill',
  maxResultSizeChars: 100_000,
  // ...
})
```

### Input/Output Schemas

**Input** (lines 291-298):

```typescript
z.object({
  skill: z.string().describe('The skill name'),
  args: z.string().optional().describe('Optional arguments'),
})
```

**Output** (lines 301-326):

| Mode | Output |
|------|--------|
| Inline | `{ success, commandName, allowedTools?, model?, status: 'inline' }` |
| Forked | `{ success, commandName, status: 'forked', agentId, result }` |

### Skill Execution Modes

1. **Inline** (default): Skill content expands into the current conversation
2. **Forked**: Skill runs as a sub-agent with separate context and token budget

**Forked execution** (lines 122-289):

```typescript
async function executeForkedSkill(
  command: Command & { type: 'prompt' },
  commandName: string,
  args: string | undefined,
  context: ToolUseContext,
  // ...
): Promise<ToolResult<Output>>
```

### Remote Skill Support

For `EXPERIMENTAL_SKILL_SEARCH` feature (lines 604-613, 969-1107):

- Loads remote canonical skills via `_canonical_<slug>` prefix
- Caches skill content from AKI/GCS
- Injects SKILL.md as user message

---

## Skill Manifest Format (SKILL.md)

### Frontmatter Schema

**Based on**: `src/skills/loadSkillsDir.ts:185-265` and `src/utils/plugins/loadPluginCommands.ts`

```yaml
---
name: skill-name                    # Display name (optional)
description: One-line description   # Required or auto-extracted
allowed-tools:                      # Tool permission patterns
  - Read
  - Write
  - Bash(gh:*)
when_to_use: |                      # Auto-invocation trigger description
  Use when the user wants to X.
  Examples: "trigger phrase"
argument-hint: "[file] [options]"   # Argument placeholder display
arguments:                          # Argument names for substitution
  - file
  - options
model: sonnet                       # Model override (optional)
context: fork                       # 'fork' for sub-agent, omit for inline
agent: general-purpose            # Agent type for forked execution
user-invocable: true                # Can users type /skill-name?
disable-model-invocation: false    # Can model invoke via Skill tool?
effort: low                        # Effort level: low/medium/high
paths:                             # Conditional activation patterns
  - src/**/*.tsx
hooks:                             # Post-sampling hooks
  postInlineEdit: ...
shell:                             # Shell command configuration
  timeout: 30000
  cwd: /path/to/dir
---
```

### Content Structure

Standard skill content sections:

```markdown
# Skill Title

Description of what this skill does.

## Inputs
- `$arg_name`: Description of this input

## Goal
Clearly stated goal with success criteria.

## Steps

### 1. Step Name
What to do in this step.

**Success criteria**: Specific criteria for completion.

**Execution**: Direct | Task agent | Teammate | [human]

**Artifacts**: Data produced for later steps.

**Human checkpoint**: When to ask user before proceeding.

**Rules**: Hard constraints for this step.
```

### Variable Substitution

**File**: `src/skills/loadSkillsDir.ts:344-398`

Available substitutions:

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | Full argument string |
| `$arg_name` | Individual argument values |
| `${CLAUDE_SKILL_DIR}` | Skill's directory path |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `!command` | Shell command execution (inline backticks) |

---

## Permissions and Sandboxing

### Skill Tool Permission Flow

**File**: `src/tools/SkillTool/SkillTool.ts:432-578`

1. Check deny rules first (can block specific skills)
2. Auto-allow canonical remote skills (ant-only)
3. Check allow rules
4. Auto-allow skills with only "safe properties"
5. Default: Ask user for permission

### Safe Skill Properties

**File**: `src/tools/SkillTool/SkillTool.ts:875-906`

Properties that don't require permission:

```typescript
const SAFE_SKILL_PROPERTIES = new Set([
  'type', 'progressMessage', 'contentLength', 'argNames', 'model', 'effort',
  'source', 'pluginInfo', 'skillRoot', 'context', 'agent',
  'getPromptForCommand', 'name', 'description', 'aliases',
])
```

### Shell Command Sandboxing

**File**: `src/skills/loadSkillsDir.ts:371-396`

- Skills with `context: 'fork'` run in isolated sub-agents
- Shell commands (`!command`) execute with skill-specific permissions
- MCP skills never execute inline shell commands (security boundary)

---

## Plugin System

### Plugin Architecture

**Files**:
- `src/plugins/builtinPlugins.ts` - Built-in plugin registry
- `src/plugins/bundled/index.ts` - Built-in plugin initialization
- `src/utils/plugins/schemas.ts` - Manifest schemas

### Plugin Manifest (plugin.json)

**File**: `src/utils/plugins/schemas.ts:884-898`

```typescript
export const PluginManifestSchema = z.object({
  // Metadata
  name: z.string()
  version: z.string().optional()
  description: z.string().optional()
  author: PluginAuthorSchema.optional()
  homepage: z.string().optional()
  repository: z.string().optional()
  
  // Components
  hooks: HooksConfigSchema.optional()
  commands: z.union([CommandPathsSchema, z.record(CommandMetadataSchema)]).optional()
  agents: AgentPathsSchema.optional()
  skills: SkillPathsSchema.optional()
  outputStyles: OutputStylePathsSchema.optional()
  
  // MCP/LSP
  mcpServers: McpServerConfigSchema.optional()
  lspServers: LspServerConfigSchema.optional()
  channels: ChannelConfigSchema.optional()
  
  // User config
  userConfig: z.record(UserConfigOptionSchema).optional()
  settings: z.record(z.unknown()).optional()
})
```

### Plugin Sources

**File**: `src/utils/plugins/schemas.ts:906-1044`

Plugins can be sourced from:

| Source | Format | Description |
|--------|--------|-------------|
| `url` | URL | Direct URL to marketplace.json |
| `github` | `owner/repo` | GitHub repository |
| `git` | URL | Git repository URL |
| `npm` | Package name | NPM package |
| `pip` | Package name | Python package |
| `file`/`directory` | Path | Local filesystem |
| `hostPattern`/`pathPattern` | Pattern | Pattern-based sources |
| `settings` | Object | Inline marketplace in settings.json |

### Plugin Loading

**File**: `src/utils/plugins/loadPluginCommands.ts:414-677`

Plugin commands are loaded with:
- Namespace prefix: `plugin-name:command-name`
- Variable substitution for `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`
- User config substitution for `${user_config.KEY}`
- Shell command execution with proper context

### Plugin Skills

**File**: `src/utils/plugins/loadPluginCommands.ts:687-838`

Plugin skills are loaded from:
1. Default `skills/` directory within plugin
2. Additional `skillsPaths` from manifest

Skills are namespaced: `plugin-name:skill-name`

---

## Key File Paths Summary

| Component | Path |
|-----------|------|
| Skill Loader | `src/skills/loadSkillsDir.ts` |
| Bundled Skills Registry | `src/skills/bundledSkills.ts` |
| Bundled Skills Index | `src/skills/bundled/index.ts` |
| Skill Tool | `src/tools/SkillTool/SkillTool.ts` |
| Skill Tool Prompt | `src/tools/SkillTool/prompt.ts` |
| Commands Registry | `src/commands.ts` |
| Command Types | `src/types/command.ts` |
| Plugin Types | `src/types/plugin.ts` |
| Plugin Manifest Schema | `src/utils/plugins/schemas.ts` |
| Plugin Loader | `src/utils/plugins/loadPluginCommands.ts` |
| Built-in Plugins | `src/plugins/builtinPlugins.ts` |
| Skill Improvement | `src/utils/hooks/skillImprovement.ts` |
| MCP Skill Builders | `src/skills/mcpSkillBuilders.ts` |
| Plugin Management UI | `src/commands/plugin/ManagePlugins.tsx` |
