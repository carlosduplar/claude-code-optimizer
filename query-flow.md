# Claude Code Query Flow and Message Streaming

## Overview

The query flow in Claude Code handles the entire lifecycle of an AI request: from user input through API communication, response streaming, error handling, and result processing. The architecture is designed for resilience with multiple fallback layers.

## Entry Points

### Main Query Entry

**File**: `src/query.ts` (lines 219-239)

```typescript
export async function* query(params: QueryParams): AsyncGenerator<...> {
  const consumedCommandUuids: string[] = []
  const terminal = yield* queryLoop(params, consumedCommandUuids)
  // ... notify completed commands
  return terminal
}
```

The `query()` function:
- Sets up command tracking
- Delegates to `queryLoop()` for actual processing
- Cleans up consumed commands on completion

### SDK Entry Point

**File**: `src/QueryEngine.ts` (lines 184-207, 209-295)

```typescript
export class QueryEngine {
  constructor(config: QueryEngineConfig) { ... }
  
  async *submitMessage(prompt: string | ContentBlockParam[], options?): AsyncGenerator<SDKMessage> {
    // Handles full query lifecycle with state management
  }
}
```

Provides:
- Session state persistence across turns
- Message management
- Abort controller handling
- Transcript recording
- Permission denial tracking

## Core API Service

**File**: `src/services/api/claude.ts` (3419 lines)

### Streaming vs Non-Streaming Entry Points

**Streaming Entry** (lines 752-780):

```typescript
export async function* queryModelWithStreaming({
  messages, systemPrompt, thinkingConfig, tools, signal, options
}): AsyncGenerator<StreamEvent | AssistantMessage | SystemAPIErrorMessage> {
  return yield* withStreamingVCR(messages, async function* () {
    yield* queryModel(messages, systemPrompt, thinkingConfig, tools, signal, options)
  })
}
```

**Non-Streaming Entry** (lines 709-750):

```typescript
export async function queryModelWithoutStreaming({...}): Promise<AssistantMessage> {
  for await (const message of withStreamingVCR(messages, async function* () {
    yield* queryModel(...)
  })) {
    if (message.type === 'assistant') {
      assistantMessage = message
    }
  }
  return assistantMessage
}
```

### Main Query Implementation: `queryModel` (lines 1017-2892)

#### Request Preparation (lines 1028-1760)

- Off-switch checks for capacity management
- Request ID tracking from previous messages (lines 1051-1055)
- Beta header assembly (lines 1071-1222)
- Tool schema building with deferred loading support (lines 1165-1256)
- Message normalization (lines 1266-1316)
- Fingerprint computation for attribution (line 1325)
- System prompt construction (lines 1358-1369)
- Cached microcompact configuration (lines 1189-1205)

#### Streaming Request Execution (lines 1776-1846)

```typescript
const generator = withRetry(
  () => getAnthropicClient({
    maxRetries: 0, // Manual retry implementation
    model: options.model,
    fetchOverride: options.fetchOverride,
    source: options.querySource,
  }),
  async (anthropic, attempt, context) => {
    const result = await anthropic.beta.messages
      .create({ ...params, stream: true }, { signal, headers })
      .withResponse()
    return result.data
  },
  { model, fallbackModel, thinkingConfig, signal, querySource }
)
```

#### Streaming Event Processing (lines 1931-2304)

The streaming loop handles:

- **Idle timeout watchdog** (lines 1874-1928): Aborts streams with no chunks for 90s
- **Stall detection** (lines 1937-1967): Logs gaps >30s between events

**Event types**:

| Event | Lines | Purpose |
|-------|-------|---------|
| `message_start` | 1980-1993 | Captures initial usage, TTFT |
| `content_block_start` | 1995-2051 | Initializes content blocks |
| `content_block_delta` | 2053-2169 | Accumulates text/thinking/JSON |
| `content_block_stop` | 2171-2211 | Yields complete assistant messages |
| `message_delta` | 2213-2293 | Updates usage, stop_reason, cost |
| `message_stop` | 2295-2297 | Final cleanup |

### Non-Streaming Fallback: `executeNonStreamingRequest` (lines 818-917)

```typescript
export async function* executeNonStreamingRequest(
  clientOptions,
  retryOptions,
  paramsFromContext,
  onAttempt,
  captureRequest,
  originatingRequestId?, // For funnel correlation
): AsyncGenerator<SystemAPIErrorMessage, BetaMessage> {
  const fallbackTimeoutMs = getNonstreamingFallbackTimeoutMs() // 120s remote, 300s local
  const generator = withRetry(
    () => getAnthropicClient({ maxRetries: 0, ... }),
    async (anthropic, attempt, context) => {
      const adjustedParams = adjustParamsForNonStreaming(retryParams, MAX_NON_STREAMING_TOKENS)
      return await anthropic.beta.messages.create(adjustedParams, { signal, timeout: fallbackTimeoutMs })
    },
    { model, fallbackModel, thinkingConfig, signal, initialConsecutive529Errors }
  )
}
```

## Retry Logic

**File**: `src/services/api/withRetry.ts`

### Core Retry Function (lines 170-517)

```typescript
export async function* withRetry<T>(
  getClient: () => Promise<Anthropic>,
  operation: (client, attempt, context) => Promise<T>,
  options: RetryOptions,
): AsyncGenerator<SystemAPIErrorMessage, T> {
  const maxRetries = getMaxRetries(options) // Default: 10
  let consecutive529Errors = options.initialConsecutive529Errors ?? 0
  // ... retry loop with exponential backoff
}
```

### Retry Configuration

| Setting | Default | Location |
|---------|---------|----------|
| `DEFAULT_MAX_RETRIES` | 10 | lines 52-56 |
| `MAX_529_RETRIES` | 3 | line 54 |
| `BASE_DELAY_MS` | 500 | line 55 |

### Retry Delay with Exponential Backoff + Jitter (lines 530-548)

```typescript
export function getRetryDelay(
  attempt: number,
  retryAfterHeader?: string | null,
  maxDelayMs = 32000,
): number {
  if (retryAfterHeader) {
    const seconds = parseInt(retryAfterHeader, 10)
    if (!isNaN(seconds)) return seconds * 1000
  }
  
  const baseDelay = Math.min(BASE_DELAY_MS * Math.pow(2, attempt - 1), maxDelayMs)
  const jitter = Math.random() * 0.25 * baseDelay
  return baseDelay + jitter
}
```

### 529 Error Handling (lines 62-89, 326-365)

```typescript
const FOREGROUND_529_RETRY_SOURCES = new Set<QuerySource>([
  'repl_main_thread', 'sdk', 'agent:*', 'compact', 'auto_mode', ...
])

function shouldRetry529(querySource: QuerySource | undefined): boolean {
  return querySource === undefined || FOREGROUND_529_RETRY_SOURCES.has(querySource)
}

// After MAX_529_RETRIES (3), trigger model fallback
if (consecutive529Errors >= MAX_529_RETRIES && options.fallbackModel) {
  throw new FallbackTriggeredError(options.model, options.fallbackModel)
}
```

## Side Queries

**File**: `src/utils/sideQuery.ts`

### Purpose

Lightweight API wrapper for "side queries" outside the main conversation loop - used for:
- Permission explainers
- Session search
- Model validation
- Parallel permission checks (classifiers)

### Implementation (lines 107-222)

```typescript
export async function sideQuery(opts: SideQueryOptions): Promise<BetaMessage> {
  const client = await getAnthropicClient({
    maxRetries, // default: 2
    model,
    source: 'side_query',
  })
  
  // Build system with attribution header
  const systemBlocks: TextBlockParam[] = [
    attributionHeader ? { type: 'text', text: attributionHeader } : null,
    ...(!skipSystemPromptPrefix ? [{ type: 'text', text: getCLISyspromptPrefix(...) }] : []),
    ...(Array.isArray(system) ? system : system ? [{ type: 'text', text: system }] : []),
  ].filter(Boolean)
  
  const response = await client.beta.messages.create({
    model: normalizedModel,
    system: systemBlocks,
    messages,
    ...(tools && { tools }),
    ...(output_format && { output_config: { format: output_format } }),
    ...(betas.length > 0 && { betas }),
    metadata: getAPIMetadata(),
  }, { signal })
  
  // Telemetry logging
  logEvent('tengu_api_success', { requestId, querySource, ... })
  return response
}
```

### Classifier Usage

The classifier uses `sideQuery` for parallel permission checks, allowing the main query to continue while permissions are validated in parallel.

## Anthropic Client Configuration

**File**: `src/services/api/client.ts`

### Client Factory (lines 88-316)

```typescript
export async function getAnthropicClient({
  apiKey,
  maxRetries,
  model,
  fetchOverride,
  source,
}): Promise<Anthropic> {
  const defaultHeaders = {
    'x-app': 'cli',
    'User-Agent': getUserAgent(),
    'X-Claude-Code-Session-Id': getSessionId(),
    ...(containerId ? { 'x-claude-remote-container-id': containerId } : {}),
    ...(remoteSessionId ? { 'x-claude-remote-session-id': remoteSessionId } : {}),
  }
  
  // Provider-specific configuration
  if (isEnvTruthy(process.env.CLAUDE_CODE_USE_BEDROCK)) {
    return createBedrockClient(ARGS, model)
  }
  if (isEnvTruthy(process.env.CLAUDE_CODE_USE_FOUNDRY)) {
    return createFoundryClient(ARGS)
  }
  if (isEnvTruthy(process.env.CLAUDE_CODE_USE_VERTEX)) {
    return createVertexClient(ARGS, model)
  }
  
  // First-party API
  return new Anthropic({
    apiKey: isClaudeAISubscriber() ? null : apiKey || getAnthropicApiKey(),
    authToken: isClaudeAISubscriber() ? getClaudeAIOAuthTokens()?.accessToken : undefined,
    ...ARGS,
  })
}
```

### Request ID Tracking (lines 356-388)

```typescript
export const CLIENT_REQUEST_ID_HEADER = 'x-client-request-id'

function buildFetch(fetchOverride, source): ClientOptions['fetch'] {
  const inner = fetchOverride ?? globalThis.fetch
  const injectClientRequestId = getAPIProvider() === 'firstParty' && isFirstPartyAnthropicBaseUrl()
  
  return (input, init) => {
    const headers = new Headers(init?.headers)
    if (injectClientRequestId && !headers.has(CLIENT_REQUEST_ID_HEADER)) {
      headers.set(CLIENT_REQUEST_ID_HEADER, randomUUID())
    }
    return inner(input, { ...init, headers })
  }
}
```

## Error Handling

**File**: `src/services/api/errors.ts`

### Error Classification (lines 965-1161)

```typescript
export function classifyAPIError(error: unknown): string {
  if (error instanceof APIConnectionTimeoutError) return 'api_timeout'
  if (error.message?.includes(REPEATED_529_ERROR_MESSAGE)) return 'repeated_529'
  if (error instanceof APIError && error.status === 429) return 'rate_limit'
  if (error instanceof APIError && error.status === 529) return 'server_overload'
  if (isPromptTooLongMessage(...)) return 'prompt_too_long'
  // ... many more cases
}
```

### Assistant Message from Error (lines 425-934)

```typescript
export function getAssistantMessageFromError(
  error: unknown,
  model: string,
  options?: { messages?, messagesForAPI? }
): AssistantMessage {
  // Timeout errors
  if (error instanceof APIConnectionTimeoutError) {
    return createAssistantAPIErrorMessage({ content: API_TIMEOUT_ERROR_MESSAGE })
  }
  
  // Rate limits with quota headers
  if (error instanceof APIError && error.status === 429) {
    const rateLimitType = error.headers?.get('anthropic-ratelimit-unified-representative-claim')
    const overageStatus = error.headers?.get('anthropic-ratelimit-unified-overage-status')
    // ... handle with specific messages
  }
  
  // Prompt too long
  if (error.message.toLowerCase().includes('prompt is too long')) {
    return createAssistantAPIErrorMessage({
      content: PROMPT_TOO_LONG_ERROR_MESSAGE,
      error: 'invalid_request',
      errorDetails: error.message,
    })
  }
  
  // ... many more specific error types
}
```

### Special Error Messages

| Message | Purpose |
|---------|---------|
| `PROMPT_TOO_LONG_ERROR_MESSAGE` | Context limit exceeded |
| `REPEATED_529_ERROR_MESSAGE` | Multiple 529 Overloaded errors |
| `CUSTOM_OFF_SWITCH_MESSAGE` | Capacity management message |
| `API_TIMEOUT_ERROR_MESSAGE` | Request timeout |

## Streaming Flow Summary

### Message Flow

```
1. User Input
   |
   v
2. QueryEngine.submitMessage() / query()
   |
   v
3. processUserInput() - slash commands, attachments
   |
   v
4. query() loop
   |
   v
5. queryModelWithStreaming() / queryModelWithoutStreaming()
   |
   v
6. queryModel() - main implementation
   |
   v
7. withRetry() - retry wrapper
   |
   v
8. getAnthropicClient() - client creation
   |
   v
9. anthropic.beta.messages.create({ stream: true })  [streaming]
   |
   v
10. Stream event processing loop
    - message_start
    - content_block_start/delta/stop
    - message_delta
    - message_stop
    |
    v
11. Yield AssistantMessage objects
    |
    v
12. Tool execution (if tool_use blocks present)
    |
    v
13. Recursive query loop continuation
```

### Fallback Flow (Streaming -> Non-Streaming)

When streaming fails (lines 2404-2597):

1. Catch streaming error
2. Log fallback event telemetry
3. Call `executeNonStreamingRequest()` with same params
4. Yield fallback assistant message
5. Continue normal processing

## Key Configuration Values

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| `DEFAULT_MAX_RETRIES` | `withRetry.ts:52` | 10 | Max retry attempts |
| `MAX_529_RETRIES` | `withRetry.ts:54` | 3 | Max consecutive 529 errors before fallback |
| `BASE_DELAY_MS` | `withRetry.ts:55` | 500 | Initial retry delay |
| `MAX_NON_STREAMING_TOKENS` | `claude.ts:3354` | 64000 | Non-streaming token cap |
| `STREAM_IDLE_TIMEOUT_MS` | `claude.ts:1878` | 90000 | Stream watchdog timeout (90s) |
| `STALL_THRESHOLD_MS` | `claude.ts:1936` | 30000 | Stall detection threshold (30s) |

## Beta Headers Management

Beta headers are dynamically assembled in `paramsFromContext()` (claude.ts lines 1538-1729):

```typescript
const betasParams = [...betas] // Start with model betas

// Dynamic additions:
if (getSonnet1mExpTreatmentEnabled(retryContext.model)) {
  betasParams.push(CONTEXT_1M_BETA_HEADER)
}
if (outputFormat && modelSupportsStructuredOutputs(options.model)) {
  betasParams.push(STRUCTURED_OUTPUTS_BETA_HEADER)
}
if (isFastModeForRetry) {
  betasParams.push(FAST_MODE_BETA_HEADER)
}
if (afkHeaderLatched && isAgenticQuery) {
  betasParams.push(AFK_MODE_BETA_HEADER)
}
// ... more dynamic headers
```

## Abort/Cancellation Handling

### Signal Propagation

- `AbortSignal` passed through entire chain
- Checked at retry boundaries (`withRetry.ts:191-192`)
- Passed to SDK: `anthropic.beta.messages.create(..., { signal })`

### User Abort Detection (claude.ts lines 2434-2461)

```typescript
if (streamingError instanceof APIUserAbortError) {
  if (signal.aborted) {
    // Real user abort (ESC key)
    throw streamingError
  } else {
    // SDK timeout - convert to APIConnectionTimeoutError
    throw new APIConnectionTimeoutError({ message: 'Request timed out' })
  }
}
```

### Stream Resource Cleanup (claude.ts lines 1519-1526, 2898-2912)

```typescript
function releaseStreamResources(): void {
  cleanupStream(stream)
  stream = undefined
  if (streamResponse) {
    streamResponse.body?.cancel().catch(() => {})
    streamResponse = undefined
  }
}
```

## Summary

This architecture provides a robust, resilient system with:

- **Multiple fallback layers**: streaming → non-streaming → model fallback
- **Exponential backoff with jitter** for retries
- **Comprehensive telemetry and logging**
- **Resource cleanup** to prevent memory leaks
- **Parallel side queries** for permission checks
- **Rich error classification** and user-friendly messages
