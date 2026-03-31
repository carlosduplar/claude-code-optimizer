# Claude Code Tool System Architecture

## Overview

Claude Code's tool system is a comprehensive framework that enables the AI to interact with the filesystem, execute commands, manage tasks, and extend functionality through external integrations like MCP (Model Context Protocol) and LSP (Language Server Protocol).

## Core Architecture

### Main Files

| File | Purpose | Lines |
|------|---------|-------|
| `src/tools.ts` | Central tool registry and assembly | 389 |
| `src/Tool.ts` | Base tool abstraction and types | 792 |
| `src/constants/tools.ts` | Tool name constants and restrictions | 112 |

## Tool Registration System

### Tool Assembly

**File**: `src/tools.ts` (lines 193-251)

```typescript
export function getAllBaseTools(): Tools {
  return [
    AgentTool,
    TaskOutputTool,
    BashTool,
    ...(hasEmbeddedSearchTools() ? [] : [GlobTool, GrepTool]),
    ExitPlanModeV2Tool,
    FileReadTool,
    FileEditTool,
    FileWriteTool,
    NotebookEditTool,
    WebFetchTool,
    TodoWriteTool,
    WebSearchTool,
    // ... conditional tools based on feature flags
  ]
}
```

### Tool Retrieval with Permission Filtering

**File**: `src/tools.ts` (lines 271-327)

```typescript
export function getTools(permissionContext: ToolPermissionContext): Tools {
  const allTools = getAllBaseTools()
  // Filter by deny rules
  const allowedTools = filterToolsByDenyRules(allTools, permissionContext)
  // Handle REPL mode (hide primitive tools when REPL enabled)
  // Return filtered list
}
```

## Tool Type Definition

**File**: `src/Tool.ts` (lines 362-695)

The `Tool` type defines the complete tool contract:

### Core Methods

| Method | Purpose | Lines |
|--------|---------|-------|
| `call()` | Execute the tool | 379-385 |
| `validateInput()` | Pre-execution validation | 489-492 |
| `checkPermissions()` | Permission check | 500-503 |
| `description()` | Get tool description | 386-393 |
| `prompt()` | Get system prompt for tool | 518-523 |

### Metadata Properties

| Property | Type | Purpose |
|----------|------|---------|
| `name` | `string` | Tool identifier |
| `aliases` | `string[]` | Alternative names |
| `inputSchema` | Zod schema | Input validation |
| `outputSchema` | Zod schema | Output validation |
| `isEnabled()` | `() => boolean` | Availability check |
| `isReadOnly()` | `boolean` | State modification check |
| `isDestructive()` | `boolean` | Irreversible operation check |
| `isMcp` | `boolean` | MCP tool indicator |
| `isLsp` | `boolean` | LSP tool indicator |
| `shouldDefer` | `boolean` | ToolSearch requirement |
| `alwaysLoad` | `boolean` | Always in initial prompt |
| `mcpInfo` | `{serverName, toolName}` | MCP tool identification |

### UI Rendering Methods

| Method | Purpose |
|--------|---------|
| `renderToolUseMessage()` | Render tool use UI |
| `renderToolResultMessage()` | Render result UI |
| `renderToolUseProgressMessage()` | Render progress UI |
| `renderToolUseRejectedMessage()` | Render rejection UI |

### Tool Factory

**File**: `src/Tool.ts` (lines 783-791)

```typescript
export function buildTool<InputSchema, Output, Progress>(
  config: ToolConfig<InputSchema, Output, Progress>
): Tool<InputSchema, Output, Progress> {
  return { ...TOOL_DEFAULTS, ...config }
}
```

## Permission System Integration

### ToolPermissionContext Structure

**File**: `src/Tool.ts` (lines 122-138)

```typescript
export type ToolPermissionContext = DeepImmutable<{
  mode: PermissionMode                    // 'default' | 'acceptEdits' | 'plan' | 'bypassPermissions' | 'auto' | 'dontAsk'
  additionalWorkingDirectories: Map<string, AdditionalWorkingDirectory>
  alwaysAllowRules: ToolPermissionRulesBySource
  alwaysDenyRules: ToolPermissionRulesBySource
  alwaysAskRules: ToolPermissionRulesBySource
  isBypassPermissionsModeAvailable: boolean
  isAutoModeAvailable?: boolean
  strippedDangerousRules?: ToolPermissionRulesBySource
  shouldAvoidPermissionPrompts?: boolean    // For background agents
  awaitAutomatedChecksBeforeDialog?: boolean // For coordinator workers
  prePlanMode?: PermissionMode
}>
```

### Permission Rule Sources

**File**: `src/utils/permissions/permissions.ts` (lines 109-114)

```typescript
const PERMISSION_RULE_SOURCES = [
  ...SETTING_SOURCES,  // 'userSettings', 'projectSettings', 'localSettings', 'policySettings', 'flagSettings'
  'cliArg',
  'command',
  'session',
] as const
```

### Permission Check Flow

**File**: `src/utils/permissions/permissions.ts` (`hasPermissionsToUseTool`, lines 473-956)

The permission system follows a multi-step pipeline:

**Step 1 - Rule-based checks:**
1. **1a** - Check if entire tool is denied (`getDenyRuleForTool`, line 287-292)
2. **1b** - Check if tool has "always ask" rule (`getAskRuleForTool`, line 297-302)
3. **1c** - Run tool-specific permission check (`tool.checkPermissions()`, line 1216)
4. **1d** - Tool implementation denied
5. **1e** - Tool requires user interaction
6. **1f** - Content-specific ask rules
7. **1g** - Safety checks (bypass-immune)

**Step 2 - Mode-based decisions:**
- **2a** - Check `bypassPermissions` mode (lines 1268-1281)
- **2b** - Check if entire tool is always allowed (`toolAlwaysAllowedRule`, lines 275-282)

**Step 3 - Transformations:**
- **dontAsk mode** - Convert 'ask' to 'deny' (lines 505-517)
- **auto mode** - Use AI classifier for approval (lines 520-927)

### Key Permission Functions

**`getDenyRuleForTool()`** (permissions.ts, lines 287-292):

```typescript
export function getDenyRuleForTool(
  context: ToolPermissionContext,
  tool: Pick<Tool, 'name' | 'mcpInfo'>,
): PermissionRule | null {
  return getDenyRules(context).find(rule => toolMatchesRule(tool, rule)) || null
}
```

**`filterToolsByDenyRules()`** (src/tools.ts, lines 262-269):

```typescript
export function filterToolsByDenyRules<
  T extends { name: string; mcpInfo?: { serverName: string; toolName: string } },
>(tools: readonly T[], permissionContext: ToolPermissionContext): T[] {
  return tools.filter(tool => !getDenyRuleForTool(permissionContext, tool))
}
```

## Bash Provider System

### Shell Provider Interface

**File**: `src/utils/shell/shellProvider.ts` (lines 1-33)

```typescript
export const SHELL_TYPES = ['bash', 'powershell'] as const
export type ShellType = (typeof SHELL_TYPES)[number]
export const DEFAULT_HOOK_SHELL: ShellType = 'bash'

export type ShellProvider = {
  type: ShellType
  shellPath: string
  detached: boolean
  buildExecCommand(command: string, opts: {...}): Promise<{ commandString: string; cwdFilePath: string }>
  getSpawnArgs(commandString: string): string[]
  getEnvironmentOverrides(command: string): Promise<Record<string, string>>
}
```

### Shell Detection

**File**: `src/utils/shell/resolveDefaultShell.ts` (lines 12-14)

```typescript
export function resolveDefaultShell(): 'bash' | 'powershell' {
  return getInitialSettings().defaultShell ?? 'bash'
}
```

### PowerShell Tool Enablement

**File**: `src/utils/shell/shellToolUtils.ts`

The `isPowerShellToolEnabled()` function provides the runtime gate for PowerShellTool on Windows platforms.

## MCP Integration Architecture

### Main Files

| File | Purpose |
|------|---------|
| `src/services/mcp/client.ts` | MCP client implementation |
| `src/services/mcp/types.ts` | MCP type definitions |
| `src/tools/MCPTool/MCPTool.ts` | MCP tool wrapper |

### MCP Tool Creation

MCP tools are dynamically created from connected servers. The `MCPTool` in `src/tools/MCPTool/MCPTool.ts` (lines 27-77) serves as a base template that gets overridden in `mcpClient.ts` with:
- Real MCP tool name
- Input/output schemas from MCP server
- Actual implementation via `client.callTool()`

### MCP Tool Name Format

**File**: `src/utils/mcpStringUtils.ts`

```typescript
// Format: mcp__serverName__toolName
export function buildMcpToolName(serverName: string, toolName: string): string {
  return `mcp__${normalizeNameForMCP(serverName)}__${normalizeNameForMCP(toolName)}`
}
```

### MCP Permission Handling

**File**: `src/utils/permissions/permissions.ts` (lines 247-268)

```typescript
// MCP tools matched by fully qualified name or server prefix
function toolMatchesRule(tool: Pick<Tool, 'name' | 'mcpInfo'>, rule: PermissionRule>): boolean {
  const nameForRuleMatch = getToolNameForPermissionCheck(tool)
  
  // Direct tool name match
  if (rule.ruleValue.toolName === nameForRuleMatch) return true
  
  // MCP server-level permission: "mcp__server1" matches all tools from server1
  const ruleInfo = mcpInfoFromString(rule.ruleValue.toolName)
  const toolInfo = mcpInfoFromString(nameForRuleMatch)
  
  return (
    ruleInfo !== null &&
    toolInfo !== null &&
    (ruleInfo.toolName === undefined || ruleInfo.toolName === '*') &&
    ruleInfo.serverName === toolInfo.serverName
  )
}
```

## Tool Call Execution Flow

### Execution Pipeline

**File**: `src/services/tools/toolExecution.ts`

**Main execution function handles:**
1. Pre-tool hooks (`runPreToolUseHooks`, line 130)
2. Permission validation via `canUseTool()` callback
3. Input validation via `tool.validateInput()`
4. Tool execution via `tool.call()`
5. Post-tool hooks (`runPostToolUseHooks`, line 129)
6. Result processing and telemetry

### Tool Pool Assembly

**File**: `src/tools.ts` (lines 345-367)

```typescript
export function assembleToolPool(
  permissionContext: ToolPermissionContext,
  mcpTools: Tools,
): Tools {
  const builtInTools = getTools(permissionContext)
  const allowedMcpTools = filterToolsByDenyRules(mcpTools, permissionContext)
  
  // Sort for prompt-cache stability, built-ins first
  const byName = (a: Tool, b: Tool) => a.name.localeCompare(b.name)
  return uniqBy(
    [...builtInTools].sort(byName).concat(allowedMcpTools.sort(byName)),
    'name',
  )
}
```

## Tool Validation Logic

### Input Validation

**File**: `src/Tool.ts` (lines 489-492)

```typescript
validateInput?(
  input: z.infer<Input>,
  context: ToolUseContext,
): Promise<ValidationResult>
```

### Permission Validation

**File**: `src/Tool.ts` (lines 500-503)

```typescript
checkPermissions(
  input: z.infer<Input>,
  context: ToolUseContext,
): Promise<PermissionResult>
```

### Validation Results

**File**: `src/Tool.ts` (lines 95-101)

```typescript
export type ValidationResult =
  | { result: true }
  | {
      result: false
      message: string
      errorCode: number
    }
```

## Key Tool Categories and Restrictions

### Agent-Disallowed Tools

**File**: `src/constants/tools.ts` (lines 36-46)

```typescript
export const ALL_AGENT_DISALLOWED_TOOLS = new Set([
  TASK_OUTPUT_TOOL_NAME,
  EXIT_PLAN_MODE_V2_TOOL_NAME,
  ENTER_PLAN_MODE_TOOL_NAME,
  // Allow Agent tool only for ant users
  ...(process.env.USER_TYPE === 'ant' ? [] : [AGENT_TOOL_NAME]),
  ASK_USER_QUESTION_TOOL_NAME,
  TASK_STOP_TOOL_NAME,
  ...(feature('WORKFLOW_SCRIPTS') ? [WORKFLOW_TOOL_NAME] : []),
])
```

### Async Agent Allowed Tools

**File**: `src/constants/tools.ts` (lines 55-71)

```typescript
export const ASYNC_AGENT_ALLOWED_TOOLS = new Set([
  FILE_READ_TOOL_NAME,
  WEB_SEARCH_TOOL_NAME,
  TODO_WRITE_TOOL_NAME,
  GREP_TOOL_NAME,
  WEB_FETCH_TOOL_NAME,
  GLOB_TOOL_NAME,
  ...SHELL_TOOL_NAMES,
  FILE_EDIT_TOOL_NAME,
  FILE_WRITE_TOOL_NAME,
  // ... etc
])
```

## Summary of Key Files and Line Numbers

| File | Key Lines | Purpose |
|------|-----------|---------|
| `src/tools.ts` | 193-251 | Tool registration |
| `src/tools.ts` | 262-269 | `filterToolsByDenyRules()` |
| `src/tools.ts` | 271-327 | `getTools()` - main entry |
| `src/tools.ts` | 345-367 | `assembleToolPool()` |
| `src/Tool.ts` | 362-695 | Tool type definition |
| `src/Tool.ts` | 783-791 | `buildTool()` factory |
| `src/utils/permissions/permissions.ts` | 287-292 | `getDenyRuleForTool()` |
| `src/utils/permissions/permissions.ts` | 473-956 | `hasPermissionsToUseTool()` |
| `src/utils/permissions/permissions.ts` | 1158-1319 | `hasPermissionsToUseToolInner()` |
| `src/utils/shell/shellProvider.ts` | 1-33 | Shell provider interface |
| `src/utils/shell/powershellProvider.ts` | 27-123 | PowerShell provider |
| `src/services/mcp/client.ts` | 595+ | MCP connection logic |
| `src/tools/MCPTool/MCPTool.ts` | 27-77 | MCP tool template |
| `src/tools/BashTool/BashTool.tsx` | 420-825 | Bash tool implementation |
| `src/tools/AgentTool/AgentTool.tsx` | 196-999+ | Agent tool implementation |
| `src/constants/tools.ts` | 36-88 | Tool restrictions |
