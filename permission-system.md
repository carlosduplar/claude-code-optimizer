# Claude Code Permission System & YOLO/Auto Mode

## Overview

Claude Code employs a sophisticated multi-layered permission system that controls when and how tools can execute. The system supports multiple permission modes, AI-powered classification ("auto mode" / "YOLO mode"), and extensive configuration options.

## Permission Modes

### Core Modes (defined in `src/types/permissions.ts`, lines 16-38)

| Mode | Description | Behavior |
|------|-------------|----------|
| `default` | Standard mode | Interactive prompts for sensitive operations |
| `acceptEdits` | Auto-accept edits | Automatically accepts file edits in working directory |
| `plan` | Plan mode | Requires approval before executing any tool |
| `bypassPermissions` | Bypass all checks | **Dangerous** - No permission prompts |
| `dontAsk` | Deny silently | Auto-denies instead of asking |
| `auto` | **AI-powered classification** | Uses classifier to decide allow/deny |

### Mode Cycling (Shift+Tab)

**File**: `src/utils/permissions/getNextPermissionMode.ts` (lines 34-79)

Cycle order: `default` → `acceptEdits` → `plan` → `bypassPermissions` → `auto` → back to `default`

For Anthropic employees (`USER_TYPE=ant`): skips `acceptEdits` and `plan` when `auto` is available.

## The Auto-Mode/YOLO Classifier

### Main Implementation

**File**: `src/utils/permissions/yoloClassifier.ts` (1495 lines)

### Key Functions

| Function | Lines | Purpose |
|----------|-------|---------|
| `classifyYoloAction()` | 1012-1306 | Main entry point for classification |
| `buildYoloSystemPrompt()` | 484-540 | Builds system prompt with rules |
| `buildTranscriptForClassifier()` | 434-442 | Builds conversation transcript for context |
| `classifyYoloActionXml()` | 711-996 | Two-stage XML classifier |

### Classification Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Step 1: Check Preconditions (permissions.ts:518-526)        │
│  - Is auto mode active?                                       │
│  - Is it a classifier-approvable safety check?                │
├─────────────────────────────────────────────────────────────┤
│  Step 2: Fast-Paths (permissions.ts:593-686)               │
│  - Skip if requiresUserInteraction()                          │
│  - Check acceptEdits mode would allow (fast path)           │
│  - Check safe-tool allowlist                                  │
├─────────────────────────────────────────────────────────────┤
│  Step 3: Build Transcript (yoloClassifier.ts:302-360)        │
│  - Extract user messages                                      │
│  - Extract assistant tool_use blocks                        │
│  - Encode via toAutoClassifierInput()                       │
├─────────────────────────────────────────────────────────────┤
│  Step 4: Run Classifier (yoloClassifier.ts:1012-1306)        │
│  - Build system prompt with permissions template            │
│  - Build user prompt with transcript + action               │
│  - Call sideQuery with structured output                    │
├─────────────────────────────────────────────────────────────┤
│  Step 5: Process Result (permissions.ts:718-926)             │
│  - Log telemetry                                              │
│  - If blocked: update denial tracking                       │
│  - Check denial limits                                        │
│  - Return allow/deny decision                               │
└─────────────────────────────────────────────────────────────┘
```

### Response Schema (yoloClassifier.ts:252-258)

```typescript
{
  thinking: string,       // Step-by-step reasoning
  shouldBlock: boolean,    // true = deny, false = allow
  reason: string           // Explanation of decision
}
```

## Two-Stage XML Classifier

**File**: `src/utils/permissions/yoloClassifier.ts` (lines 542-996)

### Three Modes Supported

| Mode | Description | Use Case |
|------|-------------|----------|
| `both` (default) | Stage 1 (fast) → Stage 2 (thinking) if blocked | Balanced speed/accuracy |
| `fast` | Stage 1 only with reason | Quick decisions |
| `thinking` | Stage 2 only with chain-of-thought | Complex decisions |

### Stage 1 (Fast)
- **Max tokens**: 64 (256 in fast-only mode)
- **Suffix**: `"\nErr on the side of blocking. <block> immediately."`
- **Stop sequence**: `"</block>"`
- **Output**: `<block>yes/no</block>`

### Stage 2 (Thinking)
- **Max tokens**: 4096
- **Suffix**: Asks for careful review and chain-of-thought
- **Output**: `<thinking>...</thinking><block>yes/no</block><reason>...</reason>`

### Configuration (lines 1308-1389)

```typescript
type AutoModeConfig = {
  model?: string                    // Override classifier model
  twoStageClassifier?: boolean | 'fast' | 'thinking'
  forceExternalPermissions?: boolean
  jsonlTranscript?: boolean        // Newline-delimited JSON format
}
```

## Configuration Options

### Environment Variables

| Variable | Purpose | Location |
|----------|---------|----------|
| `CLAUDE_CODE_AUTO_MODE_MODEL` | Override classifier model | yoloClassifier.ts:1336 |
| `CLAUDE_CODE_DUMP_AUTO_MODE` | Dump classifier requests/responses | yoloClassifier.ts:150, 160 |
| `CLAUDE_CODE_TWO_STAGE_CLASSIFIER` | Enable XML classifier | yoloClassifier.ts:1359 |
| `CLAUDE_CODE_JSONL_TRANSCRIPT` | Use JSONL format | yoloClassifier.ts:1379 |
| `USER_TYPE=ant` | Enable ant-only features | Various |

### Settings Schema

```typescript
autoMode: {
  allow: string[]       // Custom allow rules
  soft_deny: string[]   // Custom deny rules  
  environment: string[] // Environment context
}
```

## Dangerous Permission Detection

**File**: `src/utils/permissions/permissionSetup.ts` (lines 85-285)

Detects and strips dangerous patterns:

- `Bash(*)` - allows all bash commands
- `Bash(python:*)` - allows arbitrary Python execution
- `PowerShell(iex:*)` - allows Invoke-Expression
- `Agent(*)` - allows all sub-agents
- Any interpreter wildcard patterns

## Denial Tracking & Circuit Breakers

**File**: `src/utils/permissions/denialTracking.ts` (lines 1-45)

```typescript
const DENIAL_LIMITS = {
  maxConsecutive: 3,   // Fall back to prompting after 3 consecutive denials
  maxTotal: 20,        // Fall back after 20 total denials
}
```

**File**: `src/utils/permissions/autoModeState.ts` (lines 1-39)

State tracking:
- `autoModeActive`: Is classifier currently running
- `autoModeFlagCli`: Was auto mode requested via CLI
- `autoModeCircuitBroken`: Disabled via GrowthBook circuit breaker

## Permission Decision Pipeline

**File**: `src/utils/permissions/permissions.ts` (lines 1158-1319)

### Decision Order (`hasPermissionsToUseToolInner`):

1. **Deny rules** - Tool entirely denied
2. **Ask rules** - Tool requires explicit permission
3. **Tool.checkPermissions()** - Tool-specific validation
4. **User interaction required** - Tool needs interactive input
5. **Content-specific ask rules** - Pattern-based rules
6. **Safety checks** - Sensitive path checks (.git/, .claude/)
7. **Bypass permissions mode** - Skip remaining checks
8. **Always allow rules** - Tool pre-approved
9. **Auto mode classifier** - AI evaluation
10. **Passthrough → Ask** - Default to prompting

## Tool Permission Context

**File**: `src/Tool.ts` (lines 123-138)

```typescript
type ToolPermissionContext = DeepImmutable<{
  mode: PermissionMode
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

## Safe Tool Allowlist

**File**: `src/utils/permissions/classifierDecision.ts` (lines 56-94)

Tools that bypass the classifier:
- Read operations: `FileRead`, `Grep`, `Glob`, `LSP`
- Task management: `TodoWrite`, `TaskCreate`, `TaskGet`, etc.
- Plan mode: `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`
- Coordination: `SendMessage`, `TeamCreate`, `TeamDelete`
- Utilities: `Sleep`, `ToolSearch`

## Permission Explainer

**File**: `src/utils/permissions/permissionExplainer.ts` (250 lines)

Generates human-readable explanations for permission requests:
- **Risk levels**: LOW, MEDIUM, HIGH
- Uses Haiku model via sideQuery
- Provides: explanation, reasoning, risk description

## Key Decision Points (Code Snippets)

### Auto Mode Activation Check (permissions.ts:518-526)

```typescript
if (
  feature('TRANSCRIPT_CLASSIFIER') &&
  (appState.toolPermissionContext.mode === 'auto' ||
    (appState.toolPermissionContext.mode === 'plan' &&
      (autoModeStateModule?.isAutoModeActive() ?? false)))
)
```

### Classifier Call (permissions.ts:688-699)

```typescript
const action = formatActionForClassifier(tool.name, input)
setClassifierChecking(toolUseID)
let classifierResult
try {
  classifierResult = await classifyYoloAction(
    context.messages,
    action,
    context.options.tools,
    appState.toolPermissionContext,
    context.abortController.signal,
  )
} finally {
  clearClassifierChecking(toolUseID)
}
```

### Iron Gate (Fail-Closed) Check (permissions.ts:845-852)

```typescript
if (classifierResult.unavailable) {
  if (
    getFeatureValue_CACHED_WITH_REFRESH(
      'tengu_iron_gate_closed',
      true,
      CLASSIFIER_FAIL_CLOSED_REFRESH_MS,
    )
  ) {
    // Deny with retry guidance
  }
}
```

## File Structure

```
src/utils/permissions/
├── yoloClassifier.ts          # Main auto-mode classifier (1495 lines)
├── permissions.ts             # Core permission logic (1486 lines)
├── permissionSetup.ts         # Mode transitions & setup (1469 lines)
├── permissionExplainer.ts     # Permission explanations (250 lines)
├── classifierDecision.ts      # Safe tool allowlist (98 lines)
├── classifierShared.ts        # Shared utilities (39 lines)
├── autoModeState.ts           # Auto mode state (39 lines)
├── denialTracking.ts          # Denial limits (45 lines)
├── getNextPermissionMode.ts   # Mode cycling (101 lines)
├── PermissionMode.ts          # Mode definitions (141 lines)
├── PermissionResult.ts        # Result types (35 lines)
├── PermissionRule.ts          # Rule type definitions (40 lines)
├── PermissionUpdate.ts        # Update application logic
├── dangerousPatterns.ts       # Dangerous pattern detection
├── bashClassifier.ts          # Bash-specific classifier
├── filesystem.ts              # File permission utilities
├── pathValidation.ts          # Path security checks
└── ... (other supporting files)

src/types/permissions.ts       # Central type definitions (441 lines)
```

## Summary

The Claude Code permission system is a sophisticated security framework with:

1. **Multiple permission modes** with Shift+Tab cycling
2. **AI-powered auto-mode** using a two-stage XML classifier
3. **Comprehensive rule system** with allow/deny/ask behaviors
4. **Dangerous permission detection** to prevent bypasses
5. **Denial tracking** with fallback to prompting after limits
6. **Circuit breakers** for emergency disabling
7. **Extensive telemetry** for monitoring and debugging
8. **Tool-specific permission hooks** for custom validation

The classifier (`yoloClassifier.ts`) is the heart of auto-mode, using conversation context and structured prompting to make security decisions, with comprehensive fallback mechanisms to ensure user safety.
