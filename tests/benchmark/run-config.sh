#!/bin/bash
# Run benchmark for specific config
# Usage: run-config.sh <config_name> <run_number>

set -e

CONFIG_NAME="$1"
RUN_NUMBER="$2"

if [ -z "$CONFIG_NAME" ] || [ -z "$RUN_NUMBER" ]; then
    echo "Usage: $0 <config_name> <run_number>" >&2
    exit 1
fi

# Verify claude -p (headless) available
if ! command -v claude >/dev/null 2>&1; then
    echo "Error: claude command not found" >&2
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCHMARK_DIR="$SCRIPT_DIR"
CORPUS_DIR="$BENCHMARK_DIR/corpus"
RESULTS_DIR="$BENCHMARK_DIR/results"
PROMPTS_FILE="$SCRIPT_DIR/prompts.txt"

mkdir -p "$RESULTS_DIR"

# Clear tool-results cache for corpus project
CACHE_DIR="$HOME/.claude/projects"
if [ -d "$CACHE_DIR" ]; then
    find "$CACHE_DIR" -type d -name "*corpus*" -exec rm -rf {} + 2>/dev/null || true
fi

# Clear session memory
SESSION_MEM="$HOME/.claude/projects/corpus/session-memory.jsonl"
if [ -f "$SESSION_MEM" ]; then
    rm -f "$SESSION_MEM"
fi

# Run all prompts
RUN_START=$(date +%s)

while IFS= read -r prompt || [ -n "$prompt" ]; do
    [ -z "$prompt" ] && continue

    echo "Running: $prompt"

    # Run claude -p (headless)
    cd "$CORPUS_DIR"
    claude -p "$prompt" >/dev/null 2>&1 || true

done < "$PROMPTS_FILE"

RUN_END=$(date +%s)
RUN_DURATION=$((RUN_END - RUN_START))

# Find newest transcript in projects dir
TRANSCRIPT_DIR="$HOME/.claude/projects"
NEWEST_TRANSCRIPT=$(find "$TRANSCRIPT_DIR" -name "session-memory.jsonl" -type f 2>/dev/null | head -1)

# Fallback: find any .jsonl file
if [ -z "$NEWEST_TRANSCRIPT" ]; then
    NEWEST_TRANSCRIPT=$(find "$TRANSCRIPT_DIR" -name "*.jsonl" -type f 2>/dev/null | head -1)
fi

if [ -z "$NEWEST_TRANSCRIPT" ]; then
    echo "Error: No transcript found after run" >&2
    exit 1
fi

# Parse session
RESULT=$("$SCRIPT_DIR/parse-session.sh" "$NEWEST_TRANSCRIPT")

# Add metadata
FINAL_RESULT=$(echo "$RESULT" | jq --arg config "$CONFIG_NAME" \
    --arg run "$RUN_NUMBER" \
    --arg duration "$RUN_DURATION" \
    '. + {config: $config, run_number: ($run | tonumber), duration_seconds: ($duration | tonumber), timestamp: now}')

# Save result
OUTPUT_FILE="$RESULTS_DIR/${CONFIG_NAME}-run-${RUN_NUMBER}.json"
echo "$FINAL_RESULT" > "$OUTPUT_FILE"

echo "Config $CONFIG_NAME run $RUN_NUMBER complete: $OUTPUT_FILE"
echo "Duration: ${RUN_DURATION}s"
