# Using Claude Code with Custom API Providers

## Overview

Claude Code uses the Anthropic Node.js SDK (`@anthropic-ai/sdk`) which speaks the **Anthropic Messages API** protocol. Any provider that implements the `/v1/messages` endpoint in Anthropic's request/response format can be used as a drop-in backend by setting environment variables.

This document covers the configuration, gotchas, and limitations discovered through testing against Fireworks AI.

## Configuration

### Required Environment Variables

```bash
# Authentication — use ANTHROPIC_API_KEY, NOT ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY=fw_your_fireworks_api_key

# Custom endpoint
ANTHROPIC_BASE_URL=https://api.fireworks.ai/inference

# Model selection (all must point to the same model for a single-model setup)
ANTHROPIC_MODEL=accounts/fireworks/models/kimi-k2p5
ANTHROPIC_SMALL_FAST_MODEL=accounts/fireworks/models/kimi-k2p5
```

### How the Anthropic SDK Constructs Requests

The SDK reads `ANTHROPIC_BASE_URL` from the environment and appends the API path:

```
ANTHROPIC_BASE_URL=https://api.fireworks.ai/inference
  -> Requests go to: https://api.fireworks.ai/inference/v1/messages
```

The request body uses Anthropic's format (`model`, `messages`, `max_tokens` as top-level fields), not OpenAI's format.

## Critical: ANTHROPIC_API_KEY vs ANTHROPIC_AUTH_TOKEN

**You must use `ANTHROPIC_API_KEY`, not `ANTHROPIC_AUTH_TOKEN`.**

These two env vars control different headers:

| Env Var | Header Sent | Source in Code |
|---|---|---|
| `ANTHROPIC_API_KEY` | `x-api-key: <value>` | `src/services/api/client.ts:302` via `getAnthropicApiKey()` |
| `ANTHROPIC_AUTH_TOKEN` | `Authorization: Bearer <value>` | `src/services/api/client.ts:322-327` via `configureApiKeyHeaders()` |

The Anthropic SDK uses `apiKey` (constructor param) to set the `x-api-key` header. The `Authorization: Bearer` header from `ANTHROPIC_AUTH_TOKEN` is supplementary — it is set in `defaultHeaders` but does **not** replace the SDK's primary auth mechanism.

When a proxy like LiteLLM sits in front of the provider, it typically authenticates using the `x-api-key` header (Anthropic convention) and ignores `Authorization: Bearer`. If `ANTHROPIC_API_KEY` is not set, `x-api-key` is sent as `null`, causing a 401:

```
401 {"error":{"message":"litellm.AuthenticationError: AuthenticationError:
Fireworks_aiException - Error code: 401 - {'error': {'message':
'The API key you provided is invalid.', 'code': 'UNAUTHORIZED'}}"}}
```

**Relevant code:**
- `src/services/api/client.ts:300-315` — client constructor, `apiKey` field
- `src/services/api/client.ts:318-328` — `configureApiKeyHeaders()`, `Authorization: Bearer` field
- `src/utils/auth.ts:214-305` — `getAnthropicApiKey()` resolution chain

## Model ID Format

Model IDs are provider-specific. Fireworks uses path-based identifiers:

| Format | Purpose | Example |
|---|---|---|
| `accounts/fireworks/models/<name>` | Direct model hosting | `accounts/fireworks/models/kimi-k2p5` |
| `accounts/fireworks/routers/<name>` | Routed model (OpenAI-compat namespace) | `accounts/fireworks/routers/kimi-k2p5-turbo` |

Both formats work with the Anthropic Messages API on Fireworks, but only if the model supports the Anthropic protocol. Not all models on Fireworks support it — image generation models (`flux-*`) do not.

### Listing Available Models

Query the OpenAI-compatible models endpoint to discover available models:

```bash
curl -s -H "Authorization: Bearer $ANTHROPIC_API_KEY" \
  "$ANTHROPIC_BASE_URL/v1/models" | jq '.data[] | {id, supports_chat}'
```

Response fields of interest:
- `supports_chat: true` — model handles conversational requests
- `supports_tools: true` — model supports tool/function calling
- `supports_image_input: true` — model accepts images
- `context_length` — maximum context window

### Testing a Model Directly

Verify a model works with the Anthropic Messages API before configuring Claude Code:

```bash
curl -s -X POST "$ANTHROPIC_BASE_URL/v1/messages" \
  -H "Authorization: Bearer $ANTHROPIC_API_KEY" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "accounts/fireworks/models/kimi-k2p5",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_tokens": 10
  }'
```

A successful response returns an Anthropic-format message object with `type: "message"`.

## How Claude Code Resolves the Model

Model selection priority order (from `src/utils/model/model.ts:55-98`):

1. Session override (`/model` command) — highest priority
2. CLI flag (`--model`)
3. `ANTHROPIC_MODEL` environment variable
4. Saved `settings.model`
5. Built-in default (Sonnet 4.6 / Opus 4.6 depending on tier)

The `ANTHROPIC_DEFAULT_*` env vars control fallback defaults used for specific roles:

| Env Var | Used By |
|---|---|
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `getDefaultSonnetModel()` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `getDefaultOpusModel()` |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `getDefaultHaikuModel()` |

For a single-model proxy setup, set all of these to the same model ID.

## Error Handling for Custom Providers

Claude Code has a provider detection system (`src/utils/model/providers.ts`) that affects error messages and behavior:

```typescript
// src/utils/model/providers.ts:6-14
export function getAPIProvider(): APIProvider {
  return isEnvTruthy(process.env.CLAUDE_CODE_USE_BEDROCK)
    ? 'bedrock'
    : isEnvTruthy(process.env.CLAUDE_CODE_USE_VERTEX)
      ? 'vertex'
      : isEnvTruthy(process.env.CLAUDE_CODE_USE_FOUNDRY)
        ? 'foundry'
        : 'firstParty'
}
```

**A custom `ANTHROPIC_BASE_URL` is NOT detected as third-party.** The provider defaults to `'firstParty'` unless one of the three env vars above is set. This has two consequences:

1. **Error messages** reference "the selected model" generically instead of suggesting fallbacks (see `src/services/api/errors.ts:902-914`)
2. **Beta headers** are included that the custom provider may not support (see beta headers section below)

A companion function `isFirstPartyAnthropicBaseUrl()` (`src/utils/model/providers.ts:25-40`) correctly identifies custom base URLs, but it is only used in limited contexts (analytics, tool search) and **not** in error handling or model validation.

## Beta Headers

Claude Code sends Anthropic-specific beta headers in requests. When the provider is detected as `'firstParty'` (which happens for custom base URLs), these headers are included:

| Beta Header | Purpose |
|---|---|
| `claude-code-20250219` | Claude Code tool integration |
| `prompt-caching-2024-07-31:scope` | Prompt caching with scopes |
| `interleaved-thinking-2025-05-14` | Interleaved thinking support |
| `extended-cache-ttl-2025-04-11:redact_thinking` | Extended cache TTL |

These are sent in the `anthropic-beta` request header. Unknown beta headers are typically ignored by providers (tested with Fireworks — no errors), but proxies may behave differently.

To disable experimental beta headers:

```bash
CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
```

**Relevant code:** `src/utils/betas.ts:215-220` — `shouldIncludeFirstPartyOnlyBetas()`

## Limitations When Using Custom Providers

### Model Capability Caching

The model capability system (`src/utils/model/modelCapabilities.ts:46-51`) is gated behind:

```typescript
function isModelCapabilitiesEligible(): boolean {
  if (process.env.USER_TYPE !== 'ant') return false
  if (getAPIProvider() !== 'firstParty') return false
  if (!isFirstPartyAnthropicBaseUrl()) return false
  return true
}
```

Custom providers get `undefined` for capability lookups. This is harmless — capabilities default to standard behavior.

### Model Allowlist

The `availableModels` setting (`src/utils/model/modelAllowlist.ts`) uses Anthropic-centric matching (family aliases like `sonnet`, `opus`, `haiku`, `claude-` prefix matching). Custom model names like `accounts/fireworks/models/kimi-k2p5` pass through without allowlist restrictions when `availableModels` is not configured.

### Model Name Normalization

`normalizeModelStringForAPI()` (`src/utils/model/model.ts:616-618`) strips `[1m]` and `[2m]` suffixes but otherwise passes model names through unchanged. Custom model IDs are not modified.

### First-Party Feature Flags

Several features are gated by `isFirstPartyAnthropicBaseUrl()` returning `false`:

- **Tool search** — disabled by default for custom providers (`src/utils/toolSearch.ts:283-307`)
- **Model capability refresh** — skipped entirely
- **Analytics** — base URL hostname is recorded but behavior is otherwise unchanged

## Troubleshooting

### 401 Authentication Error

```
401 {"error":{"message":"litellm.AuthenticationError: ... 'The API key you provided is invalid.'"}}
```

**Cause:** Using `ANTHROPIC_AUTH_TOKEN` instead of `ANTHROPIC_API_KEY`. The Bearer token header is not recognized by the proxy.

**Fix:** Set `ANTHROPIC_API_KEY` and remove `ANTHROPIC_AUTH_TOKEN`.

### 404 Model Not Found

```
There's an issue with the selected model (<model>). It may not exist or you may not have access to it.
```

**Cause:** The model ID is incorrect for the Anthropic Messages API endpoint. Common mistakes:

- Using `/routers/` when the model is only at `/models/` (or vice versa)
- Adding suffixes like `-turbo` that don't exist in the model registry
- Using a model that doesn't support the Anthropic protocol

**Fix:** Verify the model exists by calling the models endpoint, then test with a direct curl call (see "Testing a Model Directly" above).

### Beta Headers Causing Errors

If the proxy rejects unknown headers, set:

```bash
CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
```

This strips experimental beta headers before they reach the provider.
