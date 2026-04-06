#!/bin/bash
# Run all benchmark configs A/B/C/D x 3 runs each

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCHMARK_DIR="$SCRIPT_DIR"
CORPUS_DIR="$BENCHMARK_DIR/corpus"

# Config A: No env vars, no CLAUDE.md
run_config_a() {
    local run_num=$1
    echo "=== Config A (baseline) - Run $run_num ==="

    # Ensure no CLAUDE.md in corpus
    rm -f "$CORPUS_DIR/CLAUDE.md"

    # Clear env vars
    unset CLAUDE_CODE_DISABLE_AUTO_MEMORY
    unset ENABLE_CLAUDE_CODE_SM_COMPACT
    unset DISABLE_INTERLEAVED_THINKING
    unset CLAUDE_CODE_DISABLE_ADVISOR_TOOL
    unset CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS
    unset CLAUDE_CODE_DISABLE_POLICY_SKILLS
    unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
    unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE

    "$SCRIPT_DIR/run-config.sh" "config-a" "$run_num"
}

# Config B: Optimizations only (env vars), no CLAUDE.md
run_config_b() {
    local run_num=$1
    echo "=== Config B (env vars only) - Run $run_num ==="

    # Ensure no CLAUDE.md in corpus
    rm -f "$CORPUS_DIR/CLAUDE.md"

    # Export optimization env vars
    export CLAUDE_CODE_DISABLE_AUTO_MEMORY=true
    export ENABLE_CLAUDE_CODE_SM_COMPACT=true
    export DISABLE_INTERLEAVED_THINKING=true
    export CLAUDE_CODE_DISABLE_ADVISOR_TOOL=true
    export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=true
    export CLAUDE_CODE_DISABLE_POLICY_SKILLS=true
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=true
    export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80

    "$SCRIPT_DIR/run-config.sh" "config-b" "$run_num"
}

# Config C: CLAUDE.md only, no env vars
run_config_c() {
    local run_num=$1
    echo "=== Config C (CLAUDE.md only) - Run $run_num ==="

    # Clear env vars
    unset CLAUDE_CODE_DISABLE_AUTO_MEMORY
    unset ENABLE_CLAUDE_CODE_SM_COMPACT
    unset DISABLE_INTERLEAVED_THINKING
    unset CLAUDE_CODE_DISABLE_ADVISOR_TOOL
    unset CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS
    unset CLAUDE_CODE_DISABLE_POLICY_SKILLS
    unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
    unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE

    # Create CLAUDE.md with compact instructions
    cat > "$CORPUS_DIR/CLAUDE.md" << 'EOF'
# CLAUDE.md - Compact Mode

## Memory Management
- Disable automatic memory bank updates
- Enable aggressive compaction at 80% threshold
- Minimize token usage in responses

## Thinking Mode
- Disable interleaved thinking
- Streamline response generation

## Feature Disables
- No advisor tool
- No git instruction injection
- No policy skills
- No non-essential network traffic
EOF

    "$SCRIPT_DIR/run-config.sh" "config-c" "$run_num"
}

# Config D: Both optimizations
run_config_d() {
    local run_num=$1
    echo "=== Config D (both) - Run $run_num ==="

    # Export optimization env vars
    export CLAUDE_CODE_DISABLE_AUTO_MEMORY=true
    export ENABLE_CLAUDE_CODE_SM_COMPACT=true
    export DISABLE_INTERLEAVED_THINKING=true
    export CLAUDE_CODE_DISABLE_ADVISOR_TOOL=true
    export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=true
    export CLAUDE_CODE_DISABLE_POLICY_SKILLS=true
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=true
    export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80

    # Create CLAUDE.md with compact instructions
    cat > "$CORPUS_DIR/CLAUDE.md" << 'EOF'
# CLAUDE.md - Compact Mode

## Memory Management
- Disable automatic memory bank updates
- Enable aggressive compaction at 80% threshold
- Minimize token usage in responses

## Thinking Mode
- Disable interleaved thinking
- Streamline response generation

## Feature Disables
- No advisor tool
- No git instruction injection
- No policy skills
- No non-essential network traffic
EOF

    "$SCRIPT_DIR/run-config.sh" "config-d" "$run_num"
}

# Cleanup function
cleanup_run() {
    # Remove corpus session memory
    SESSION_MEM="$HOME/.claude/projects/corpus/session-memory.jsonl"
    if [ -f "$SESSION_MEM" ]; then
        rm -f "$SESSION_MEM"
    fi

    # Wait between runs
    echo "Waiting 5s..."
    sleep 5
}

# Main
main() {
    echo "Starting benchmark suite..."
    echo "Results dir: $BENCHMARK_DIR/results"

    for run in 1 2 3; do
        echo ""
        echo "########## RUN SET $run ##########"

        run_config_a $run
        cleanup_run

        run_config_b $run
        cleanup_run

        run_config_c $run
        cleanup_run

        run_config_d $run
        cleanup_run
    done

    echo ""
    echo "All runs complete. Results in $BENCHMARK_DIR/results/"
}

main "$@"
