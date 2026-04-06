#!/bin/bash
# Parse Claude session transcript and extract token metrics
# Usage: parse-session.sh <transcript_path>

set -e

TRANSCRIPT_PATH="$1"

if [ -z "$TRANSCRIPT_PATH" ]; then
    echo "Usage: $0 <transcript_path>" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq required but not installed" >&2
    exit 1
fi

if [ ! -f "$TRANSCRIPT_PATH" ]; then
    echo "Error: Transcript not found: $TRANSCRIPT_PATH" >&2
    exit 1
fi

# Initialize counters
INPUT_TOKENS=0
OUTPUT_TOKENS=0
CACHE_READ=0
CACHE_WRITE=0
API_CALLS=0
COMPACTION_EVENTS=0

# Parse JSONL transcript
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue

    # Check for usage data in the line
    if echo "$line" | jq -e '.usage' >/dev/null 2>&1; then
        API_CALLS=$((API_CALLS + 1))

        # Extract tokens
        in_tokens=$(echo "$line" | jq -r '.usage.input_tokens // 0')
        out_tokens=$(echo "$line" | jq -r '.usage.output_tokens // 0')

        INPUT_TOKENS=$((INPUT_TOKENS + in_tokens))
        OUTPUT_TOKENS=$((OUTPUT_TOKENS + out_tokens))

        # Check for cache metrics
        if echo "$line" | jq -e '.usage.cache_read_tokens' >/dev/null 2>&1; then
            cache_r=$(echo "$line" | jq -r '.usage.cache_read_tokens // 0')
            CACHE_READ=$((CACHE_READ + cache_r))
        fi

        if echo "$line" | jq -e '.usage.cache_write_tokens' >/dev/null 2>&1; then
            cache_w=$(echo "$line" | jq -r '.usage.cache_write_tokens // 0')
            CACHE_WRITE=$((CACHE_WRITE + cache_w))
        fi
    fi

    # Detect compaction events
    if echo "$line" | jq -e '.type == "compaction"' >/dev/null 2>&1; then
        COMPACTION_EVENTS=$((COMPACTION_EVENTS + 1))
    fi

    # Alternative: check for compaction in message
    if echo "$line" | grep -q "compaction" 2>/dev/null; then
        if echo "$line" | jq -e '.message' >/dev/null 2>&1; then
            has_compaction=$(echo "$line" | jq -r 'select(.message | contains("compaction")) | 1 // 0')
            if [ "$has_compaction" = "1" ]; then
                COMPACTION_EVENTS=$((COMPACTION_EVENTS + 1))
            fi
        fi
    fi
done < "$TRANSCRIPT_PATH"

# Calculate cost
# Formula: input*0.000003 + cache_creation*0.00000375 + cache_read*0.0000003 + output*0.000015
# Using awk for floating point math
COST=$(awk "BEGIN {
    input = $INPUT_TOKENS * 0.000003;
    cache_creation = $CACHE_WRITE * 0.00000375;
    cache_read = $CACHE_READ * 0.0000003;
    output = $OUTPUT_TOKENS * 0.000015;
    printf \"%.6f\", input + cache_creation + cache_read + output
}")

# Output JSON
jq -n \
    --argjson input_tokens "$INPUT_TOKENS" \
    --argjson output_tokens "$OUTPUT_TOKENS" \
    --argjson cache_read "$CACHE_READ" \
    --argjson cache_write "$CACHE_WRITE" \
    --argjson api_calls "$API_CALLS" \
    --argjson compaction_events "$COMPACTION_EVENTS" \
    --argjson cost "$COST" \
    '{
        input_tokens: $input_tokens,
        output_tokens: $output_tokens,
        cache_read: $cache_read,
        cache_write: $cache_write,
        api_calls: $api_calls,
        compaction_events: $compaction_events,
        estimated_cost_usd: $cost
    }'
