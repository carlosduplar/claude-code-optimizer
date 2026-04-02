# Claude Code Permission System & YOLO/Auto Mode

## TL;DR

**What this document covers:** The complete internal architecture of Claude Code's permission system, including the undocumented AI-powered auto-mode classifier, two-stage XML classification, and hidden security mechanisms not covered in official docs.

**Key undocumented patterns:**
- **Two-stage XML classifier** - Stage 1 (64 tokens, fast) → Stage 2 (4096 tokens, thinking) if blocked
- **Iron gate (fail-closed)** - When classifier is unavailable, defaults to "deny" (not "ask")
- **10-step permission pipeline** - Deny rules → Ask rules → Tool validation → User interaction → Content rules → Safety checks → Bypass mode → Allow rules → Auto classifier → Ask user
- **Safe tool allowlist** - Read operations bypass the classifier entirely
- **Denial tracking circuit breakers** - 3 consecutive denials or 20 total denials → fallback to prompting
- **Dangerous pattern detection** - Strips `Bash(*)`, `Agent(*)`, `PowerShell(iex:*)` before classifier sees them

**Why this matters:** Understanding these internals helps you:
- Predict when auto-mode will allow vs deny
- Debug permission issues
- Design effective permission rules
- Understand security boundaries

```mermaid
flowchart TB
    subgraph Pipeline["10-Step Permission Pipeline"]
        direction TB
        P1[1. Deny Rules] --> P2[2. Ask Rules]
        P2 --> P3[3. Tool.checkPermissions]
        P3 --> P4[4. User Interaction Required]
        P4 --> P5[5. Content-Specific Ask Rules]
        P5 --> P6[6. Safety Checks<br/>.git/, .claude/]
        P6 --> P7[7. Bypass Mode?]
        P7 --> P8[8. Always Allow Rules]
        P8 --> P9[9. Auto-Mode Classifier]
        P9 --> P10[10. Ask User]
    end
    
    subgraph Classifier["Two-Stage XML Classifier"]
        direction TB
        C1[Stage 1: Fast<br/>64 tokens max<br/>&lt;block&gt;yes/no&lt;/block&gt;] --> C2{Blocked?}
        C2 -->|Yes| C3[Stage 2: Thinking<br/>4096 tokens max<br/>Chain-of-thought]
        C2 -->|No| C4[Allow]
        C3 --> C5[Final Decision]
    end
    
    subgraph Circuit["Circuit Breakers"]
        direction TB
        CB1[3 Consecutive Denials] --> CB3[Fallback to Prompting]
        CB2[20 Total Denials] --> CB3
    end
    
    P9 --> Classifier
    Classifier --> Circuit
```

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Permission Modes](#permission-modes)
3. [The 10-Step Permission Pipeline](#the-10-step-permission-pipeline)
4. [Auto-Mode/YOLO Classifier](#auto-modeyolo-classifier)
5. [Two-Stage XML Classification](#two-stage-xml-classification)
6. [Denial Tracking & Circuit Breakers](#denial-tracking--circuit-breakers)
7. [Dangerous Pattern Detection](#dangerous-pattern-detection)
8. [Safe Tool Allowlist](#safe-tool-allowlist)
9. [Permission Explainer](#permission-explainer)
10. [Undocumented Configuration](#undocumented-configuration)

---

## Architecture Overview

Claude Code's permission system is a **defense-in-depth** architecture with multiple layers of security checks. Unlike simple allow/deny lists, it uses:

- **Rule-based pre-filtering** (fast, deterministic)
- **AI-powered classification** (context-aware, nuanced)
- **Circuit breakers** (prevents classifier abuse)
- **Fail-closed defaults** (secure by design)

```mermaid
flowchart LR
    subgraph Layers["Security Layers"]
        direction TB
        L1[Layer 1: Hard Rules<br/>Deny/Ask/Allow] --> L2[Layer 2: Tool Validation]
        L2 --> L3[Layer 3: Safety Checks] --> L4[Layer 4: AI Classifier]
        L4 --> L5[Layer 5: User Prompt]
    end
    
    subgraph Decision["Decision Flow"]
        D1[Tool Request] --> D2{Layer 1}
        D2 -->|Deny| D3[Block Immediately]
        D2 -->|Ask| D4[Prompt User]
        D2 -->|Allow| D5[Execute]
        D2 -->|Pass| D6{Layer 2-4}
        D6 -->|Block| D3
        D6 -->|Pass| D7{Layer 5}
        D7 -->|Allow| D5
        D7 -->|Deny| D3
    end
```

---

## Permission Modes

### Core Modes (`src/types/permissions.ts:16-38`)

```typescript
type PermissionMode = 
  | 'default'           // Standard interactive mode
  | 'acceptEdits'       // Auto-accept file edits
  | 'plan'              // Read-only planning mode
  | 'bypassPermissions' // Skip all checks (dangerous)
  | 'dontAsk'           // Auto-deny instead of asking
  | 'auto'              // AI-powered classification
```

### Mode Cycling (Shift+Tab)

**File:** `src/utils/permissions/getNextPermissionMode.ts:34-79`

Cycle order: `default` → `acceptEdits` → `plan` → `bypassPermissions` → `auto` → back to `default`

**Undocumented:** For Anthropic employees (`USER_TYPE=ant`), the cycle skips `acceptEdits` and `plan` when `auto` is available.

```mermaid
stateDiagram-v2
    [*] --> Default: Initial state
    Default --> acceptEdits: Shift+Tab
    acceptEdits --> plan: Shift+Tab
    plan --> bypassPermissions: Shift+Tab
    bypassPermissions --> auto: Shift+Tab
    auto --> Default: Shift+Tab

    note right of auto
        ant-only: skips
        acceptEdits & plan
    end note
```

---

## The 10-Step Permission Pipeline

**File:** `src/utils/permissions/permissions.ts:1158-1319`

The `hasPermissionsToUseToolInner` function implements a **10-step decision pipeline**:

```mermaid
flowchart TB
    subgraph Pipeline["Permission Decision Order"]
        direction TB
        
        P1["1. Deny Rules<br/>Tool entirely denied<br/>src/permissions/permissions.ts:1158"] 
        P1 --> P2
        
        P2["2. Ask Rules<br/>Tool requires explicit permission<br/>src/permissions/permissions.ts:1165"]
        P2 --> P3
        
        P3["3. Tool.checkPermissions()<br/>Tool-specific validation<br/>src/permissions/permissions.ts:1172"]
        P3 --> P4
        
        P4["4. User Interaction Required<br/>Tool needs interactive input<br/>src/permissions/permissions.ts:1179"]
        P4 --> P5
        
        P5["5. Content-Specific Ask Rules<br/>Pattern-based rules<br/>src/permissions/permissions.ts:1186"]
        P5 --> P6
        
        P6["6. Safety Checks<br/>Sensitive path checks<br/>.git/, .claude/<br/>src/permissions/permissions.ts:1193"]
        P6 --> P7
        
        P7["7. Bypass Permissions Mode<br/>Skip remaining checks<br/>src/permissions/permissions.ts:1200"]
        P7 --> P8
        
        P8["8. Always Allow Rules<br/>Tool pre-approved<br/>src/permissions/permissions.ts:1207"]
        P8 --> P9
        
        P9["9. Auto Mode Classifier<br/>AI evaluation<br/>Two-stage XML<br/>src/permissions/permissions.ts:1214"]
        P9 --> P10
        
        P10["10. Passthrough → Ask<br/>Default to prompting<br/>src/permissions/permissions.ts:1319"]
    end
    
    style P1 fill:#ffe1e1
    style P6 fill:#ffe1e1
    style P7 fill:#fff4e1
    style P8 fill:#e1f5e1
    style P9 fill:#e1f0ff
```

### Step-by-Step Breakdown

#### Step 1: Deny Rules

**Purpose:** Hard block dangerous tools/patterns

**Implementation:**

```typescript
const denyRules = toolPermissionContext.alwaysDenyRules[tool.name]
if (denyRules?.some(rule => matchesRule(rule, toolInput))) {
  return { type: 'deny', reason: 'Matched deny rule' }
}
```

**Examples:**
- `Bash(rm -rf /)` - Block destructive commands
- `Bash(curl | bash)` - Block pipe-to-shell
- `Write(/etc/passwd)` - Block system file modification

#### Step 2: Ask Rules

**Purpose:** Require explicit user approval for sensitive operations

**Implementation:**

```typescript
const askRules = toolPermissionContext.alwaysAskRules[tool.name]
if (askRules?.some(rule => matchesRule(rule, toolInput))) {
  return { type: 'ask', reason: 'Matched ask rule' }
}
```

**Examples:**
- `Bash(git push)` - Ask before pushing
- `Bash(docker *)` - Ask before Docker commands
- `Write(*.env)` - Ask before editing env files

#### Step 3: Tool.checkPermissions()

**Purpose:** Tool-specific validation logic

**Example from BashTool:**

```typescript
// src/tools/BashTool/BashTool.tsx
async checkPermissions(input: BashToolInput, context: ToolContext): Promise<PermissionResult> {
  // Check for interactive commands that need TTY
  if (isInteractiveCommand(input.command)) {
    return { type: 'ask', reason: 'Interactive command requires user input' }
  }
  
  // Check for commands that modify system state
  if (isSystemModifyingCommand(input.command)) {
    return { type: 'ask', reason: 'Command modifies system state' }
  }
  
  return { type: 'allow' }
}
```

#### Step 4: User Interaction Required

**Purpose:** Detect tools that need interactive input

**Implementation:**

```typescript
if (tool.requiresUserInteraction?.(toolInput)) {
  return { type: 'ask', reason: 'Tool requires user interaction' }
}
```

**Examples:**
- `Bash(vim)` - Interactive editor
- `Bash(npm login)` - Interactive login
- `Bash(ssh)` - Interactive SSH session

#### Step 5: Content-Specific Ask Rules

**Purpose:** Pattern-based rules within tool input

**Implementation:**

```typescript
const contentRules = toolPermissionContext.contentAskRules[tool.name]
for (const rule of contentRules) {
  if (matchesContentPattern(rule.pattern, toolInput)) {
    return { type: 'ask', reason: `Matched content pattern: ${rule.description}` }
  }
}
```

**Examples:**
- `Bash(*production*)` - Ask for production-related commands
- `Write(*password*)` - Ask when writing password-related content
- `Bash(*DROP TABLE*)` - Ask for destructive SQL

#### Step 6: Safety Checks

**Purpose:** Protect sensitive paths and operations

**Implementation:**

```typescript
// Check sensitive paths
const sensitivePaths = ['.git/', '.claude/', '.ssh/', '.aws/']
if (sensitivePaths.some(path => toolInput.path?.includes(path))) {
  return { type: 'ask', reason: 'Access to sensitive path' }
}

// Check for destructive operations
if (isDestructiveOperation(tool, toolInput)) {
  return { type: 'ask', reason: 'Destructive operation' }
}
```

**Protected paths:**
- `.git/` - Git internals
- `.claude/` - Claude Code settings
- `.ssh/` - SSH keys
- `.aws/` - AWS credentials
- `/etc/` - System configuration

#### Step 7: Bypass Permissions Mode

**Purpose:** Emergency override (use with caution)

**Implementation:**

```typescript
if (toolPermissionContext.mode === 'bypassPermissions') {
  return { type: 'allow', reason: 'Bypass mode active' }
}
```

**⚠️ Dangerous:** This mode skips all remaining checks!

#### Step 8: Always Allow Rules

**Purpose:** Fast-path for safe operations

**Implementation:**

```typescript
const allowRules = toolPermissionContext.alwaysAllowRules[tool.name]
if (allowRules?.some(rule => matchesRule(rule, toolInput))) {
  return { type: 'allow', reason: 'Matched allow rule' }
}
```

**Examples:**
- `Read(*.md)` - Allow reading markdown files
- `Bash(git status)` - Allow status checks
- `Bash(ls)` - Allow directory listing

#### Step 9: Auto Mode Classifier

**Purpose:** AI-powered context-aware decision

**Implementation:**

```typescript
if (toolPermissionContext.mode === 'auto' || isAutoModeActive()) {
  const classifierResult = await classifyYoloAction(
    context.messages,
    formatActionForClassifier(tool.name, toolInput),
    context.options.tools,
    toolPermissionContext,
    context.abortController.signal,
  )
  
  if (classifierResult.shouldBlock) {
    return { type: 'deny', reason: classifierResult.reason }
  }
  
  return { type: 'allow', reason: 'Classifier approved' }
}
```

**Detailed in next section:** [Auto-Mode/YOLO Classifier](#auto-modeyolo-classifier)

#### Step 10: Passthrough → Ask

**Purpose:** Default to user prompting if no rule matched

**Implementation:**

```typescript
// If we reach here, no rule made a decision
return { type: 'ask', reason: 'No matching rule, default to user approval' }
```

---

## Auto-Mode/YOLO Classifier

**File:** `src/utils/permissions/yoloClassifier.ts` (1495 lines)

The auto-mode classifier is Claude Code's most sophisticated security feature. It uses a **two-stage XML-based classification system** to make context-aware permission decisions.

### Architecture

```mermaid
flowchart TB
    subgraph Input["Classifier Input"]
        I1[Conversation History<br/>Last N messages]
        I2[Proposed Action<br/>Tool name + input]
        I3[Available Tools<br/>Tool definitions]
        I4[Permission Context<br/>Mode, rules, history]
    end
    
    subgraph Stage1["Stage 1: Fast Classification"]
        S1[Model: Haiku<br/>Max tokens: 64<br/>Output: &lt;block&gt;yes/no&lt;/block&gt;]
    end
    
    subgraph Stage2["Stage 2: Thinking (if blocked)"]
        S2[Model: Haiku/Sonnet<br/>Max tokens: 4096<br/>Output: &lt;thinking&gt;...&lt;/thinking&gt;<br/>         &lt;block&gt;yes/no&lt;/block&gt;<br/>         &lt;reason&gt;...&lt;/reason&gt;]
    end
    
    subgraph Output["Classifier Output"]
        O1[Decision: allow/deny]
        O2[Reasoning: explanation]
        O3[Confidence: implicit]
    end
    
    Input --> Stage1
    Stage1 -->|Blocked| Stage2
    Stage1 -->|Allowed| Output
    Stage2 --> Output
```

### Main Entry Point (`yoloClassifier.ts:1012-1306`)

```typescript
export async function classifyYoloAction(
  messages: Message[],
  action: string,
  tools: Tool[],
  permissionContext: ToolPermissionContext,
  signal: AbortSignal,
): Promise<ClassifierResult> {
  // 1. Build conversation transcript
  const transcript = buildTranscriptForClassifier(messages, action)
  
  // 2. Build system prompt with rules
  const systemPrompt = buildYoloSystemPrompt(permissionContext)
  
  // 3. Run two-stage classification
  const result = await classifyYoloActionXml(transcript, systemPrompt, signal)
  
  // 4. Log telemetry
  logEvent('tengu_yolo_classifier_result', {
    shouldBlock: result.shouldBlock,
    reason: result.reason,
    model: result.model,
  })
  
  return result
}
```

### Response Schema (`yoloClassifier.ts:252-258`)

```typescript
interface ClassifierResponse {
  thinking: string       // Step-by-step reasoning
  shouldBlock: boolean   // true = deny, false = allow
  reason: string        // Explanation of decision
}
```

---

## Two-Stage XML Classification

### Stage 1: Fast Classification (`yoloClassifier.ts:711-996`)

**Purpose:** Quick decision for obvious cases

**Configuration:**

```typescript
const STAGE1_CONFIG = {
  model: 'claude-3-haiku-20240307',
  maxTokens: 64,
  temperature: 0,
  stopSequences: ['</block>'],
  suffix: '\nErr on the side of blocking. <block> immediately.',
}
```

**Prompt structure:**

```xml
<System>
You are a security classifier. Review the proposed action and decide if it should be blocked.
Respond with ONLY: <block>yes</block> or <block>no</block>
</System>

<User>
Conversation context:
[Transcript of recent messages]

Proposed action:
[Tool name and input]

Should this action be blocked?
</User>
```

**Output format:**

```xml
<block>yes</block>  <!-- Blocked, proceed to Stage 2 -->
<block>no</block>    <!-- Allowed, skip Stage 2 -->
```

### Stage 2: Thinking Classification (`yoloClassifier.ts:542-710`)

**Purpose:** Careful review of blocked actions

**Configuration:**

```typescript
const STAGE2_CONFIG = {
  model: 'claude-3-haiku-20240307',  // Can upgrade to Sonnet for complex cases
  maxTokens: 4096,
  temperature: 0,
  stopSequences: ['</reason>'],
  suffix: 'Provide careful chain-of-thought reasoning.',
}
```

**Prompt structure:**

```xml
<System>
You are a security classifier. The proposed action was initially flagged.
Review carefully and provide detailed reasoning.
</System>

<User>
Conversation context:
[Full transcript]

Proposed action:
[Tool name and input]

Available tools and their purposes:
[Tool definitions]

Analyze this action step by step:
1. What is the user trying to accomplish?
2. Does this action align with the conversation context?
3. Are there any security concerns?
4. Should this action be allowed or blocked?

Respond in this format:
<thinking>[Your step-by-step analysis]</thinking>
<block>yes/no</block>
<reason>[Clear explanation of decision]</reason>
</User>
```

**Output format:**

```xml
<thinking>
1. The user is trying to fix a bug in the authentication system
2. This aligns with the conversation about fixing login issues
3. The command reads the auth file - no security concerns
4. This is a legitimate debugging action
</thinking>
<block>no</block>
<reason>Reading the auth file is appropriate for debugging the login bug discussed in the conversation.</reason>
```

### Three Classification Modes

**File:** `yoloClassifier.ts:1308-1389`

```typescript
type ClassifierMode = 'both' | 'fast' | 'thinking'

const modeConfig = {
  both: {        // Default: Stage 1 → Stage 2 (if blocked)
    useStage1: true,
    useStage2: true,
    stage1MaxTokens: 64,
  },
  fast: {        // Stage 1 only with reason
    useStage1: true,
    useStage2: false,
    stage1MaxTokens: 256,  // More tokens for reasoning
  },
  thinking: {    // Stage 2 only with chain-of-thought
    useStage1: false,
    useStage2: true,
    stage2MaxTokens: 4096,
  },
}
```

**Configuration via environment:**

```bash
# Enable two-stage classifier
export CLAUDE_CODE_TWO_STAGE_CLASSIFIER=both

# Fast mode only
export CLAUDE_CODE_TWO_STAGE_CLASSIFIER=fast

# Thinking mode only
export CLAUDE_CODE_TWO_STAGE_CLASSIFIER=thinking
```

---

## Denial Tracking & Circuit Breakers

**File:** `src/utils/permissions/denialTracking.ts:1-45`

### Denial Limits

```typescript
const DENIAL_LIMITS = {
  maxConsecutive: 3,   // Fall back to prompting after 3 consecutive denials
  maxTotal: 20,        // Fall back after 20 total denials
}
```

**Purpose:** Prevent classifier abuse and endless loops

### State Tracking

**File:** `src/utils/permissions/autoModeState.ts:1-39`

```typescript
interface AutoModeState {
  autoModeActive: boolean           // Is classifier currently running
  autoModeFlagCli: boolean          // Was auto mode requested via CLI
  autoModeCircuitBroken: boolean    // Disabled via GrowthBook circuit breaker
  consecutiveDenials: number        // Current streak of denials
  totalDenials: number              // Total denials this session
}
```

### Circuit Breaker Logic

```mermaid
flowchart TB
    A[Classifier Blocks Action] --> B{Check Limits}
    
    B -->|Consecutive ≥ 3| C[Circuit Broken]
    B -->|Total ≥ 20| C
    B -->|Under limits| D[Continue in Auto Mode]
    
    C --> E[Fallback to Prompting]
    C --> F[Log Circuit Breaker Event]
    
    D --> G[User Can Retry]
    
    style C fill:#ffe1e1
    style E fill:#fff4e1
```

### Iron Gate (Fail-Closed)

**File:** `src/utils/permissions/permissions.ts:845-852`

When the classifier is unavailable (API error, timeout, etc.):

```typescript
if (classifierResult.unavailable) {
  const ironGateClosed = getFeatureValue_CACHED_WITH_REFRESH(
    'tengu_iron_gate_closed',
    true,  // Default: CLOSED (secure)
    CLASSIFIER_FAIL_CLOSED_REFRESH_MS,
  )
  
  if (ironGateClosed) {
    return {
      type: 'deny',
      reason: 'Classifier unavailable. Denying for security. Retry or switch to manual mode.',
    }
  }
  
  // Iron gate open: fall through to prompting
  return { type: 'ask', reason: 'Classifier unavailable, falling back to manual approval' }
}
```

**Key insight:** The default is **fail-closed** (deny) for security. The "iron gate" can be opened via GrowthBook flag, but defaults to closed.

---

## Dangerous Pattern Detection

**File:** `src/utils/permissions/permissionSetup.ts:85-285`

### Stripped Patterns

Before the classifier sees tool input, dangerous patterns are **automatically stripped**:

```typescript
const DANGEROUS_PATTERNS = [
  { pattern: /Bash\(\*\)/, replacement: 'Bash(restricted)' },
  { pattern: /Bash\(python:.*\*\)/, replacement: 'Bash(python:restricted)' },
  { pattern: /PowerShell\(iex:.*\)/, replacement: 'PowerShell(restricted)' },
  { pattern: /Agent\(\*\)/, replacement: 'Agent(restricted)' },
  { pattern: /Bash\(.*curl.*\|.*sh.*\)/, replacement: 'Bash(curl-pipe-restricted)' },
  { pattern: /Bash\(.*wget.*\|.*sh.*\)/, replacement: 'Bash(wget-pipe-restricted)' },
]

export function sanitizeToolInput(input: string): string {
  let sanitized = input
  for (const { pattern, replacement } of DANGEROUS_PATTERNS) {
    sanitized = sanitized.replace(pattern, replacement)
  }
  return sanitized
}
```

### Why This Matters

**Without sanitization:**
- User sets rule: `allow: Bash(*)` (allow all bash)
- Classifier sees: `Bash(rm -rf /)`
- Might approve based on context

**With sanitization:**
- User sets rule: `allow: Bash(*)`
- Sanitized to: `Bash(restricted)`
- Classifier sees restricted version
- Rule doesn't match, falls through to safety checks

---

## Safe Tool Allowlist

**File:** `src/utils/permissions/classifierDecision.ts:56-94`

Tools that **bypass the classifier entirely**:

```typescript
const SAFE_TOOL_ALLOWLIST = new Set([
  // Read operations
  'FileRead',
  'Grep',
  'Glob',
  'LSP',
  
  // Task management
  'TodoWrite',
  'TaskCreate',
  'TaskGet',
  'TaskUpdate',
  'TaskDelete',
  
  // Plan mode
  'AskUserQuestion',
  'EnterPlanMode',
  'ExitPlanMode',
  
  // Coordination
  'SendMessage',
  'TeamCreate',
  'TeamDelete',
  
  // Utilities
  'Sleep',
  'ToolSearch',
])

export function isSafeTool(toolName: string): boolean {
  return SAFE_TOOL_ALLOWLIST.has(toolName)
}
```

**Why these are safe:**
- **Read operations:** Don't modify state
- **Task management:** Internal state only
- **Plan mode:** User interaction tools
- **Coordination:** Message passing
- **Utilities:** No side effects

**Performance benefit:** Skipping classifier for common operations reduces latency and API costs.

---

## Permission Explainer

**File:** `src/utils/permissions/permissionExplainer.ts` (250 lines)

Generates human-readable explanations for permission requests using a side query:

```typescript
export async function explainPermission(
  tool: Tool,
  input: ToolInput,
  context: PermissionContext,
): Promise<PermissionExplanation> {
  const response = await sideQuery({
    model: 'claude-3-haiku-20240307',  // Use cheap model
    system: EXPLAINER_SYSTEM_PROMPT,
    messages: [{
      role: 'user',
      content: formatExplainerPrompt(tool, input, context),
    }],
    output_format: { type: 'json' },
  })
  
  return parseExplanation(response)
}
```

**Output format:**

```typescript
interface PermissionExplanation {
  riskLevel: 'LOW' | 'MEDIUM' | 'HIGH'
  explanation: string      // What the tool will do
  reasoning: string        // Why this risk level
  riskDescription: string  // Specific risks
}
```

**Example output:**

```json
{
  "riskLevel": "MEDIUM",
  "explanation": "This will execute 'git push origin main', sending your local commits to the remote repository.",
  "reasoning": "Git push modifies remote state and cannot be undone. However, this is a standard development operation.",
  "riskDescription": "Once pushed, commits are visible to the team. Use /rewind if you need to undo."
}
```

---

## Undocumented Configuration

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_AUTO_MODE_MODEL` | Override classifier model |
| `CLAUDE_CODE_DUMP_AUTO_MODE` | Log classifier I/O to console |
| `CLAUDE_CODE_TWO_STAGE_CLASSIFIER` | Enable XML classifier (`both`/`fast`/`thinking`) |
| `CLAUDE_CODE_JSONL_TRANSCRIPT` | Use JSONL format for classifier |
| `USER_TYPE=ant` | Enable ant-only features |

### Settings Schema

```typescript
// .claude/settings.json
{
  "autoMode": {
    "allow": ["Bash(git status:*)", "Read(*.md)"],
    "soft_deny": ["Bash(rm *)"],
    "environment": ["development", "testing"]
  }
}
```

### GrowthBook Flags

| Flag | Purpose |
|------|---------|
| `tengu_iron_gate_closed` | Fail-closed when classifier unavailable |
| `TRANSCRIPT_CLASSIFIER` | Enable auto-mode classification |
| `tengu_copper_panda` | Enable skill improvement surveys |

---

## Summary

Claude Code's permission system is a sophisticated multi-layer security architecture:

1. **10-step pipeline** - From hard rules to AI classifier to user prompt
2. **Two-stage XML classifier** - Fast (64 tokens) → Thinking (4096 tokens) if blocked
3. **Iron gate** - Fail-closed by default when classifier unavailable
4. **Circuit breakers** - 3 consecutive / 20 total denials → fallback to prompting
5. **Dangerous pattern stripping** - Prevents wildcard abuse
6. **Safe tool allowlist** - Read operations bypass classifier
7. **Permission explainer** - Human-readable risk descriptions

This architecture balances security (fail-closed, defense-in-depth) with usability (context-aware AI classification, fast-path for safe operations).

---

*based on alleged Claude Code source analysis (src/utils/permissions/yoloClassifier.ts, src/utils/permissions/permissions.ts, src/types/permissions.ts)*
