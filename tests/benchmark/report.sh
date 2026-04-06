#!/bin/bash
# Generate benchmark comparison report

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCHMARK_DIR="$SCRIPT_DIR"
RESULTS_DIR="$BENCHMARK_DIR/results"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq required but not installed" >&2
    exit 1
fi

if [ ! -d "$RESULTS_DIR" ]; then
    echo "Error: Results directory not found: $RESULTS_DIR" >&2
    exit 1
fi

# Compute averages for a config
compute_config_stats() {
    local config=$1
    local files=$(find "$RESULTS_DIR" -name "${config}-run-*.json" 2>/dev/null)

    if [ -z "$files" ]; then
        echo "null"
        return
    fi

    local total_runs=$(echo "$files" | wc -l)

    local total_input=0
    local total_output=0
    local total_cache_read=0
    local total_cache_write=0
    local total_api_calls=0
    local total_compaction=0
    local total_cost=0
    local total_duration=0

    for f in $files; do
        total_input=$((total_input + $(jq -r '.input_tokens // 0' "$f")))
        total_output=$((total_output + $(jq -r '.output_tokens // 0' "$f")))
        total_cache_read=$((total_cache_read + $(jq -r '.cache_read // 0' "$f")))
        total_cache_write=$((total_cache_write + $(jq -r '.cache_write // 0' "$f")))
        total_api_calls=$((total_api_calls + $(jq -r '.api_calls // 0' "$f")))
        total_compaction=$((total_compaction + $(jq -r '.compaction_events // 0' "$f")))
        total_cost=$(awk "BEGIN { print $total_cost + $(jq -r '.estimated_cost_usd // 0' \"$f\") }")
        total_duration=$(awk "BEGIN { print $total_duration + $(jq -r '.duration_seconds // 0' \"$f\") }")
    done

    # Calculate averages
    awk "BEGIN {
        n = $total_runs
        printf \"{\\\"config\\\": \\\"$config\\\", \\\"runs\\\": %d, \\\"avg_input_tokens\\\": %.0f, \\\"avg_output_tokens\\\": %.0f, \\\"avg_cache_read\\\": %.0f, \\\"avg_cache_write\\\": %.0f, \\\"avg_api_calls\\\": %.1f, \\\"avg_compaction_events\\\": %.1f, \\\"avg_cost_usd\\\": %.6f, \\\"avg_duration_seconds\\\": %.1f}\",\n            n,
            $total_input / n,
            $total_output / n,
            $total_cache_read / n,
            $total_cache_write / n,
            $total_api_calls / n,
            $total_compaction / n,
            $total_cost / n,
            $total_duration / n
    }"
}

# Calculate percent change
calc_pct_change() {
    local baseline=$1
    local value=$2
    awk "BEGIN {
        if ($baseline == 0) { print \"N/A\"; exit }
        pct = (($value - $baseline) / $baseline) * 100
        printf \"%.1f\", pct
    }"
}

# Main
main() {
    echo "Claude Code Token Benchmark Report"
    echo "=================================="
    echo "Generated: $(date)"
    echo ""

    # Get stats for all configs
    STATS_A=$(compute_config_stats "config-a")
    STATS_B=$(compute_config_stats "config-b")
    STATS_C=$(compute_config_stats "config-c")
    STATS_D=$(compute_config_stats "config-d")

    if [ "$STATS_A" = "null" ]; then
        echo "No results found. Run run-all.sh first."
        exit 1
    fi

    # Extract baseline values
    BASE_INPUT=$(echo "$STATS_A" | jq -r '.avg_input_tokens // 0')
    BASE_OUTPUT=$(echo "$STATS_A" | jq -r '.avg_output_tokens // 0')
    BASE_COST=$(echo "$STATS_A" | jq -r '.avg_cost_usd // 0')
    BASE_COMPACT=$(echo "$STATS_A" | jq -r '.avg_compaction_events // 0')

    # Print comparison table
    printf "%-15s %12s %12s %12s %15s %12s\n" \
        "Config" "Input Tok" "Output Tok" "API Calls" "Cost ($)" "vs A %"
    printf "%-15s %12s %12s %12s %15s %12s\n" \
        "---------------" "------------" "------------" "------------" "---------------" "------------"

    for config_json in "$STATS_A" "$STATS_B" "$STATS_C" "$STATS_D"; do
        [ "$config_json" = "null" ] && continue

        config=$(echo "$config_json" | jq -r '.config')
        input_t=$(echo "$config_json" | jq -r '.avg_input_tokens')
        output_t=$(echo "$config_json" | jq -r '.avg_output_tokens')
        api_calls=$(echo "$config_json" | jq -r '.avg_api_calls')
        cost=$(echo "$config_json" | jq -r '.avg_cost_usd')

        # Calculate % change vs baseline (using cost)
        pct_change=$(calc_pct_change "$BASE_COST" "$cost")

        printf "%-15s %12.0f %12.0f %12.1f %15.6f %11s%%\n" \
            "$config" "$input_t" "$output_t" "$api_calls" "$cost" "$pct_change"
    done

    echo ""
    echo "Detailed Stats:"
    echo "---------------"

    for config_json in "$STATS_A" "$STATS_B" "$STATS_C" "$STATS_D"; do
        [ "$config_json" = "null" ] && continue

        echo ""
        echo "$config_json" | jq .
    done
}

main "$@"
