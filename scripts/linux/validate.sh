#!/bin/bash
#
# Claude Code Optimizer - Configuration Validation Suite
# Validates setup with optional headless hook testing

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERBOSE=false
TEST_HOOKS=false
CLAUDE_CMD=""

# Test counters
TESTS_PASSED=0; TESTS_FAILED=0; TESTS_SKIPPED=0

# Print functions
print_header() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN} $1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_section() {
    echo -e "\n${BOLD}${BLUE}$1${NC}"
    echo -e "${BLUE}$(printf '%.0s=' $(seq 1 ${#1}))${NC}"
}

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓ PASS]${NC} $1"; ((TESTS_PASSED++)); }
print_error() { echo -e "${RED}[✗ FAIL]${NC} $1"; ((TESTS_FAILED++)); }
print_warning() { echo -e "${YELLOW}[⚠ SKIP]${NC} $1"; ((TESTS_SKIPPED++)); }
print_metric() { echo -e "${CYAN}[METRIC]${NC} $1"; }

# Count tokens in file (rough approximation: chars / 4)
count_tokens() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "0"; return; }
    local chars=$(wc -c < "$file" 2>/dev/null || echo "0")
    echo $((chars / 4))
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose) VERBOSE=true; shift ;;
            --test-hooks) TEST_HOOKS=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
Claude Code Optimizer - Configuration Validation
Usage: ./validate.sh [OPTIONS]

Validates that all optimizations are correctly configured.
Optionally tests hooks in headless mode using --test-hooks.

Options:
  --verbose      Show detailed output
  --test-hooks   Run headless hook tests (requires jq, API credits)
  --help         Show this help message

Tests:
  1. Dependencies (ImageMagick, pdftotext, markitdown)
  2. Privacy environment variables
  3. Auto-compact configuration
  4. Hook configuration (PreToolUse, PostToolUse)
  5. Headless hook execution (optional with --test-hooks)
  6. Claude Code installation
EOF
}

# Find Claude binary
find_claude() {
    if command -v claude >/dev/null 2>&1; then
        CLAUDE_CMD="claude"
    elif [[ -x "$HOME/.local/bin/claude" ]]; then
        CLAUDE_CMD="$HOME/.local/bin/claude"
    elif [[ -x "/usr/local/bin/claude" ]]; then
        CLAUDE_CMD="/usr/local/bin/claude"
    fi
}

# Test 1: Check prerequisites
# Check Claude Code is installed
check_claude() {
    find_claude

    if [[ -z "$CLAUDE_CMD" ]]; then
        print_error "Claude Code not found in PATH"
        print_status "Install from: https://claude.ai/code"
        return 1
    fi

    local version=$($CLAUDE_CMD --version 2>&1 | head -1 || echo "unknown")
    print_success "Claude Code found: $version"
    return 0
}

# Test 2: Check dependencies
check_dependencies() {
    print_section "📦 DEPENDENCIES"

    # ImageMagick
    if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
        local img_cmd=$(command -v magick 2>/dev/null || command -v convert 2>/dev/null)
        print_success "ImageMagick installed ($img_cmd)"
    else
        print_error "ImageMagick not found (required for image optimization)"
        print_status "Install: sudo apt-get install imagemagick  # Debian/Ubuntu"
        print_status "        sudo yum install imagemagick      # RHEL/CentOS"
        print_status "        brew install imagemagick          # macOS"
    fi

    # pdftotext (poppler)
    if command -v pdftotext >/dev/null 2>&1; then
        print_success "pdftotext (poppler) installed"
    else
        print_error "pdftotext not found (required for PDF text extraction)"
        print_status "Install: sudo apt-get install poppler-utils  # Debian/Ubuntu"
        print_status "        sudo yum install poppler-utils      # RHEL/CentOS"
        print_status "        brew install poppler                # macOS"
    fi

    # markitdown (skip in Termux)
    if [[ -n "$TERMUX_VERSION" ]] || [[ -d "/data/data/com.termux" ]]; then
        print_status "Skipping markitdown check (Termux detected - not supported)"
    elif command -v markitdown >/dev/null 2>&1; then
        print_success "markitdown installed"
    else
        print_warning "markitdown not found (optional, for Office document conversion)"
        print_status "Install: pip install markitdown"
    fi

    # jq (for headless hook testing)
    if command -v jq >/dev/null 2>&1; then
        print_success "jq installed (required for --test-hooks)"
    else
        if $TEST_HOOKS; then
            print_error "jq not found (required for --test-hooks)"
            print_status "Install: sudo apt-get install jq  # Debian/Ubuntu"
            print_status "        brew install jq           # macOS"
            TEST_HOOKS=false
        else
            print_warning "jq not found (install for --test-hooks capability)"
        fi
    fi
}

# Test 3: Check privacy configuration
check_privacy() {
    print_section "🔒 PRIVACY CONFIGURATION"

    local privacy_score=0
    local vars=(
        "DISABLE_TELEMETRY:1:Disable all telemetry"
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:1:Block non-essential network traffic"
        "OTEL_LOG_USER_PROMPTS:0:Don't log user prompts"
        "OTEL_LOG_TOOL_DETAILS:0:Don't log tool details"
    )

    for var_info in "${vars[@]}"; do
        IFS=':' read -r var_name expected description <<< "$var_info"
        local actual="${!var_name}"

        if [[ "$actual" == "$expected" ]]; then
            print_success "$var_name=$actual ($description)"
            ((privacy_score++))
        else
            print_error "$var_name not set correctly (expected: $expected, got: ${actual:-'(empty)'})"
            print_status "Add to ~/.bashrc or ~/.zshrc: export $var_name=$expected"
        fi
    done

    # Check auto-compact window
    if [[ "$CLAUDE_CODE_AUTO_COMPACT_WINDOW" == "180000" ]]; then
        print_success "CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000 (3 minute compact window)"
        ((privacy_score++))
    else
        print_error "CLAUDE_CODE_AUTO_COMPACT_WINDOW not set to 180000"
        print_status "Add to shell profile: export CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000"
    fi

    echo ""
    print_metric "Privacy Score: $privacy_score/5"

    if [[ $privacy_score -eq 5 ]]; then
        print_success "Maximum privacy configured ✓"
    elif [[ $privacy_score -ge 3 ]]; then
        print_warning "Partial privacy ($privacy_score/5) - some protections active"
    else
        print_error "Privacy not configured - follow suggestions above"
    fi
}

# Test 3b: Check optimization variables
check_optimization_vars() {
    print_section "⚡ OPTIMIZATION VARIABLES"

    local opt_score=0
    local opt_vars=(
        "CLAUDE_CODE_DISABLE_AUTO_MEMORY:1:Disable auto-memory extraction"
        "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:80:Compact at 80% threshold"
    )

    for var_info in "${opt_vars[@]}"; do
        IFS=':' read -r var_name expected description <<< "$var_info"
        local actual="${!var_name}"

        if [[ "$actual" == "$expected" ]]; then
            print_success "$var_name=$actual ($description)"
            ((opt_score++))
        else
            print_error "$var_name not set correctly (expected: $expected, got: ${actual:-'(empty)'})"
            print_status "Add to ~/.bashrc or ~/.zshrc: export $var_name=$expected"
        fi
    done

    # Check optional boolean vars (true/1 both acceptable)
    local bool_vars=(
        "ENABLE_CLAUDE_CODE_SM_COMPACT:true:Session-memory compaction"
        "DISABLE_INTERLEAVED_THINKING:true:Disable interleaved thinking"
        "CLAUDE_CODE_DISABLE_ADVISOR_TOOL:true:Disable advisor tool"
        "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS:true:Disable git instructions"
        "CLAUDE_CODE_DISABLE_POLICY_SKILLS:true:Disable policy skills"
    )

    for var_info in "${bool_vars[@]}"; do
        IFS=':' read -r var_name expected description <<< "$var_info"
        local actual="${!var_name}"

        if [[ "$actual" == "true" || "$actual" == "1" ]]; then
            print_success "$var_name=$actual ($description)"
            ((opt_score++))
        else
            print_error "$var_name not set (expected: true/1, got: ${actual:-'(empty)'})"
            print_status "Add to ~/.bashrc or ~/.zshrc: export $var_name=true"
        fi
    done

    echo ""
    print_metric "Optimization Score: $opt_score/7"

    if [[ $opt_score -eq 7 ]]; then
        print_success "All optimizations configured ✓"
    elif [[ $opt_score -ge 4 ]]; then
        print_warning "Partial optimizations ($opt_score/7) - some token savings active"
    else
        print_error "Optimizations not configured - follow suggestions above"
    fi
}

# Test 4: Check auto-compact configuration
check_auto_compact() {
    print_section "⚙️  AUTO-COMPACT CONFIGURATION"

    local claude_config="$HOME/.claude/.claude.json"

    if [[ ! -f "$claude_config" ]]; then
        print_error "Claude config not found: $claude_config"
        print_status "Run optimize-claude.sh to create this file"
        return 1
    fi

    if grep -q '"autoCompactEnabled": true' "$claude_config" 2>/dev/null; then
        print_success "autoCompactEnabled: true"
    else
        print_error "autoCompactEnabled not set to true"
        print_status "Run optimize-claude.sh or manually edit $claude_config"
    fi

    # Check attribution settings (saves ~50-100 tokens per commit/PR)
    if grep -q '"attribution"' "$claude_config" 2>/dev/null; then
        if grep -q '"commit":\s*""' "$claude_config" 2>/dev/null && grep -q '"pr":\s*""' "$claude_config" 2>/dev/null; then
            print_success "attribution: commit and pr set to empty (saves ~50-100 tokens)"
        else
            print_warning "attribution found but may not be empty strings"
        fi
    else
        print_warning "attribution not configured (optional, saves ~50-100 tokens per commit/PR)"
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        print_status "Current config contents:"
        cat "$claude_config" 2>/dev/null || print_error "Cannot read config file"
    fi
}

# Test 5: Check hook configuration
check_hooks() {
    print_section "🪝 HOOK CONFIGURATION"

    local settings_file="$HOME/.claude/settings.json"

    if [[ ! -f "$settings_file" ]]; then
        print_error "settings.json not found at ~/.claude/settings.json"
        print_status "Run optimize-claude.sh to configure hooks"
        return 1
    fi

    local pre_configured=false
    local post_configured=false

    if grep -q '"PreToolUse"' "$settings_file" 2>/dev/null; then
        print_success "PreToolUse hook configured"
        pre_configured=true
    else
        print_error "PreToolUse hook not configured"
        print_status "This hook auto-resizes images before Claude processes them"
    fi

    if grep -q '"PostToolUse"' "$settings_file" 2>/dev/null; then
        print_success "PostToolUse hook configured"
        post_configured=true
    else
        print_error "PostToolUse hook not configured"
        print_status "This hook keeps the prompt cache warm (saves 90% on cache misses)"
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        print_status "Current hooks configuration:"
        cat "$settings_file" 2>/dev/null || print_error "Cannot read settings file"
    fi

    if $pre_configured && $post_configured; then
        return 0
    else
        return 1
    fi
}

# Test 6: Headless hook execution
test_hooks_headless() {
    print_section "🧪 HEADLESS HOOK TESTING"

    if ! $TEST_HOOKS; then
        print_warning "Skipped (use --test-hooks to enable)"
        return 0
    fi

    if [[ -z "$CLAUDE_CMD" ]]; then
        print_error "Claude not found, cannot run headless tests"
        return 1
    fi

    print_status "Running headless hook test (costs ~$0.01-0.02 in API credits)..."
    print_status "Command: claude -p --output-format stream-json --include-hook-events --allowedTools 'Read'"

    local test_image="$REPO_DIR/tests/test-image.png"
    if [[ ! -f "$test_image" ]]; then
        print_warning "Test image not found at $test_image"
        print_status "Creating a simple test image..."
        test_image="/tmp/validate-test.png"
        if command -v magick >/dev/null 2>&1; then
            magick -size 2500x2500 xc:blue "$test_image" 2>/dev/null || {
                print_warning "Could not create test image, skipping headless test"
                return 0
            }
        elif command -v convert >/dev/null 2>&1; then
            convert -size 2500x2500 xc:blue "$test_image" 2>/dev/null || {
                print_warning "Could not create test image, skipping headless test"
                return 0
            }
        else
            print_warning "No image creation tool available, skipping headless test"
            return 0
        fi
    fi

    # Run headless test
    local output_file="/tmp/claude-hook-test-$$.jsonl"
    local hook_events_file="/tmp/claude-hooks-$$.txt"

    print_status "Executing: Read $test_image"

    # Run Claude in headless mode with hook events
    # Note: --include-hook-events requires --verbose flag
    echo "Read $test_image" | "$CLAUDE_CMD" -p \
        --output-format stream-json \
        --verbose \
        --include-hook-events \
        --allowedTools "Read" \
        > "$output_file" 2>&1

    local exit_code=$?

    # Extract hook events
    if [[ -f "$output_file" ]]; then
        # Hook events have type="system" with subtype="hook_started" or "hook_response"
        jq -r 'select(.type == "system" and (.subtype | startswith("hook_"))) | "\(.hook_name):\(.hook_event)"' "$output_file" 2>/dev/null > "$hook_events_file"

        local pre_count=$(grep -c "PreToolUse" "$hook_events_file" 2>/dev/null || echo "0")
        local post_count=$(grep -c "PostToolUse" "$hook_events_file" 2>/dev/null || echo "0")

        if [[ "$pre_count" -gt 0 ]]; then
            print_success "PreToolUse hook fired ($pre_count times)"
        else
            print_error "PreToolUse hook did not fire"
            if [[ "$VERBOSE" == "true" ]]; then
                print_status "Hook events found:"
                cat "$hook_events_file" 2>/dev/null || echo "(none)"
            fi
        fi

        if [[ "$post_count" -gt 0 ]]; then
            print_success "PostToolUse hook fired ($post_count times)"
        else
            print_error "PostToolUse hook did not fire"
        fi

        # Check for resized image evidence (hook creates /tmp/claude-resize-* then copies back)
        # Check the hook log for resize confirmation since temp file is cleaned up
        local resize_happened=$(grep -c "RESIZED" /tmp/claude-hook-validation.log 2>/dev/null || echo "0")
        if [[ "$resize_happened" -gt 0 ]] || ls /tmp/claude-resize-*.png 2>/dev/null | grep -q .; then
            print_success "Image resizing hook executed (resize confirmed in logs)"
        else
            print_warning "Resized image not found (hook may have run but output path differs)"
        fi

        # Show API usage if available
        local usage=$(jq -r 'select(.type == "result") | .usage | "Input: \(.input_tokens // 0), Output: \(.output_tokens // 0), Cache: \(.cache_creation_tokens // 0)/\(.cache_read_tokens // 0)"' "$output_file" 2>/dev/null | tail -1)
        if [[ -n "$usage" && "$usage" != "Input: 0, Output: 0, Cache: 0/0" ]]; then
            print_metric "API Usage: $usage"
        fi
    else
        print_error "No output captured from headless test"
    fi

    # Cleanup
    rm -f "$output_file" "$hook_events_file"

    if [[ $exit_code -ne 0 ]]; then
        print_warning "Claude exited with code $exit_code (may indicate API error or rate limit)"
    fi
}

# Print manual test instructions
print_manual_tests() {
    print_header "🧪 MANUAL HOOK VERIFICATION (Fallback)"

    echo "If headless testing failed or was skipped, verify hooks manually:"
    echo ""

    echo -e "${BOLD}Test 1: PreToolUse Hook (Image Processing)${NC}"
    echo "1. Start an interactive Claude session: claude"
    echo "2. Run this command inside Claude:"
    echo -e "   ${CYAN}Read $REPO_DIR/tests/test-image.png${NC}"
    echo "3. Check if the image was resized:"
    echo -e "   ${CYAN}ls -la /tmp/claude-resize-*.png${NC}"
    echo "4. Expected: A resized image file should exist (~33% smaller)"
    echo ""

    echo -e "${BOLD}Test 2: PostToolUse Hook (Cache Keepalive)${NC}"
    echo "1. In the same Claude session, run:"
    echo -e "   ${CYAN}ls${NC}"
    echo "2. Check the hook log:"
    echo -e "   ${CYAN}cat /tmp/cache-keepalive.log${NC}"
    echo "3. Expected: Log entries showing 'keepalive' timestamps"
    echo "4. The hook fires every ~4 minutes to keep the 5-minute cache alive"
    echo ""

    echo -e "${BOLD}Test 3: PDF Text Extraction${NC}"
    echo "1. Extract text from the test PDF:"
    echo -e "   ${CYAN}pdftotext -layout $REPO_DIR/tests/test-document.pdf /tmp/extracted.txt${NC}"
    echo "2. Compare sizes:"
    echo -e "   ${CYAN}ls -lh $REPO_DIR/tests/test-document.pdf /tmp/extracted.txt${NC}"
    echo "3. Run inside Claude:"
    echo -e "   ${CYAN}Read /tmp/extracted.txt${NC}"
    echo "4. Expected: Text file is ~10x smaller than binary PDF"
    echo ""

    echo -e "${YELLOW}Note:${NC} If you don't have the test files, download them:"
    echo -e "   ${CYAN}wget -O tests/test-document.pdf https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf${NC}"
}

# Generate final report
generate_report() {
    print_header "📊 VALIDATION SUMMARY"

    echo -e "${BOLD}Test Results:${NC} Passed: $TESTS_PASSED | Failed: $TESTS_FAILED | Skipped: $TESTS_SKIPPED"
    echo ""

    # Check if all critical configs are in place
    local all_configs_ok=true

    if [[ $TESTS_FAILED -gt 0 ]]; then
        all_configs_ok=false
    fi

    if $all_configs_ok; then
        print_success "ALL CONFIGURATIONS VALID ✓"
        echo ""
        echo "Your Claude Code environment is properly configured:"
        echo "  • Dependencies installed"
        echo "  • Privacy settings active"
        echo "  • Auto-compact enabled"
        echo "  • Hooks configured"
        if $TEST_HOOKS; then
            echo "  • Hooks tested in headless mode"
        fi
        echo ""
        if ! $TEST_HOOKS; then
            echo -e "${YELLOW}Next step:${NC} Run with --test-hooks to verify hook execution"
        fi
    else
        print_error "CONFIGURATION INCOMPLETE"
        echo ""
        echo "Some optimizations are not configured."
        echo "Review the errors above and run optimize-claude.sh to fix."
    fi

    echo ""
    echo -e "${BOLD}Quick Commands:${NC}"
    echo "  Run optimizer:  ./scripts/linux/optimize-claude.sh"
    echo "  This help:      ./scripts/linux/validate.sh --help"
    echo "  Debug mode:     ./scripts/linux/validate.sh --verbose"
    echo "  Test hooks:     ./scripts/linux/validate.sh --test-hooks"

    if $all_configs_ok; then
        return 0
    else
        return 1
    fi
}

# Main
main() {
    print_header "Claude Code Optimizer - Configuration Validation"
    parse_args "$@"

    check_claude
    check_dependencies
    check_privacy
    check_optimization_vars
    check_auto_compact
    check_hooks
    test_hooks_headless
    print_manual_tests
    generate_report
}

main "$@"
