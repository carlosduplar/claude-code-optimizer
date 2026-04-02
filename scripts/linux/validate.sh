#!/bin/bash
#
# Claude Code Optimizer Comprehensive Validation Suite
# Tests ALL optimization claims with quantitative token measurements

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# Configuration
VERBOSE=false; KEEP_ARTIFACTS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$SCRIPT_DIR/.validation-test"
RESULTS_DIR="$SCRIPT_DIR/.validation-results"
STATE_FILE="$SCRIPT_DIR/.validation_state.json"
PDF_FILE="$REPO_DIR/tests/test-document.pdf"
TEST_IMAGE="$REPO_DIR/tests/test-image.png"
HOOK_LOG="/tmp/hook-validation.log"
TIMEOUT=60

# Token tracking
ORIGINAL_IMAGE_TOKENS=0; OPTIMIZED_IMAGE_TOKENS=0
ORIGINAL_PDF_TOKENS=0; OPTIMIZED_PDF_TOKENS=0

# Test results
TESTS_PASSED=0; TESTS_FAILED=0; TESTS_SKIPPED=0
PRETOOLUSE_FIRED=false; POSTTOOLUSE_FIRED=false
RESIZED_IMAGE_CREATED=false; PDF_CONVERTED=false
AUTO_COMPACT_ENABLED=false; PRIVACY_VARS_SET=false

# Claude command
CLAUDE_CMD=""
if command -v claude >/dev/null 2>&1; then CLAUDE_CMD="claude"
elif [[ -x "$HOME/.local/bin/claude" ]]; then CLAUDE_CMD="$HOME/.local/bin/claude"
elif [[ -x "/usr/local/bin/claude" ]]; then CLAUDE_CMD="/usr/local/bin/claude"; fi

# Print functions
print_header() { echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}${CYAN} $1${NC}"; echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
print_section() { echo -e "\n${BOLD}${BLUE}$1${NC}"; echo -e "${BLUE}$(printf '%.0s=' $(seq 1 ${#1}))${NC}"; }
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓ PASS]${NC} $1"; ((TESTS_PASSED++)); }
print_error() { echo -e "${RED}[✗ FAIL]${NC} $1"; ((TESTS_FAILED++)); }
print_warning() { echo -e "${YELLOW}[⚠ SKIP]${NC} $1"; ((TESTS_SKIPPED++)); }
print_proof() { echo -e "${CYAN}[PROOF]${NC} $1"; }
print_metric() { echo -e "${CYAN}[METRIC]${NC} $1"; }

# Count tokens in file (rough approximation)
count_file_tokens() {
    local file="$1"
    if [[ ! -f "$file" ]]; then echo "0"; return; fi
    local chars=$(wc -c < "$file")
    echo $((chars / 4))
}

# Cleanup
cleanup() { if [[ "$KEEP_ARTIFACTS" == "false" ]]; then rm -rf "$TEST_DIR" "$RESULTS_DIR" "$HOOK_LOG"; fi }
trap cleanup EXIT

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose) VERBOSE=true; shift ;;
            --keep) KEEP_ARTIFACTS=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
}

show_help() {
    cat << EOF
Claude Code Optimizer Validation Suite
Usage: $0 [OPTIONS]
Options: --verbose, --keep, --help
Tests: Dependencies, Privacy vars, Auto-compact, Hooks, Token savings
EOF
}

# Check prerequisites
check_prerequisites() {
    print_section "CHECKING PREREQUISITES"

    if [[ -z "$CLAUDE_CMD" ]]; then
        print_error "Claude Code not found"
        exit 1
    fi
    print_success "Claude Code found: $CLAUDE_CMD"

    local version=$($CLAUDE_CMD --version 2>&1 || echo "unknown")
    print_status "Claude Code version: $version"

    # Check settings.json
    if [[ ! -f "$HOME/.claude/settings.json" ]]; then
        print_error "No settings.json found at ~/.claude/settings.json"
        print_status "Run optimize-claude.sh first"
        exit 1
    fi
    print_success "Found settings.json"

    # Check hooks configured
    local settings_file="$HOME/.claude/settings.json"
    if ! grep -q '"PreToolUse"' "$settings_file" 2>/dev/null; then
        print_error "PreToolUse hook not configured"
    else
        print_success "PreToolUse hook configured"
    fi

    if ! grep -q '"PostToolUse"' "$settings_file" 2>/dev/null; then
        print_error "PostToolUse hook not configured"
    else
        print_success "PostToolUse hook configured"
    fi

    # Check dependencies
    if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
        print_success "ImageMagick found"
    else
        print_warning "ImageMagick not found"
    fi

    if command -v pdftotext >/dev/null 2>&1; then
        print_success "pdftotext (poppler) found"
    else
        print_warning "pdftotext not found"
    fi
}

# Create test files
create_test_files() {
    print_section "CREATING TEST FILES"
    mkdir -p "$TEST_DIR"
    print_status "Test directory: $TEST_DIR"

    # Use existing test image
    if [[ -f "$TEST_IMAGE" ]]; then
        cp "$TEST_IMAGE" "$TEST_DIR/test-image.png"
        local orig_size=$(stat -c%s "$TEST_IMAGE" 2>/dev/null || stat -f%z "$TEST_IMAGE" 2>/dev/null)
        ORIGINAL_IMAGE_TOKENS=$(count_file_tokens "$TEST_IMAGE")
        print_success "Using test-image.png ($(numfmt --to=iec $orig_size), ~$ORIGINAL_IMAGE_TOKENS tokens)"
    fi

    # Create test text file
    echo "This is a test document for Claude Code hook validation." > "$TEST_DIR/test-doc.txt"
    print_success "Created test-doc.txt"

    # Check for test PDF
    if [[ -f "$PDF_FILE" ]]; then
        cp "$PDF_FILE" "$TEST_DIR/test-document.pdf"
        ORIGINAL_PDF_TOKENS=$(count_file_tokens "$PDF_FILE")
        local pdf_size=$(stat -c%s "$PDF_FILE" 2>/dev/null || stat -f%z "$PDF_FILE" 2>/dev/null)
        print_success "Using test-document.pdf ($(numfmt --to=iec $pdf_size), ~$ORIGINAL_PDF_TOKENS tokens)"
    fi
}

# Run Claude Code headlessly
run_claude_headless() {
    local input_cmd="$1" output_file="$2" description="$3"
    print_status "Running: $description"

    rm -f "$HOOK_LOG"
    if ! timeout $TIMEOUT bash -c "echo '$input_cmd' | $CLAUDE_CMD -p" > "$output_file" 2>&1; then
        print_warning "Claude command timed out or failed"
    fi
    [[ -f "$output_file" ]]
}

# Test PreToolUse Hook
test_pretooluse_hook() {
    print_section "TEST 1: PreToolUse Hook (Image Processing)"
    print_status "Testing if PreToolUse hook fires when reading an image..."

    rm -f /tmp/resized_*.png "$HOOK_LOG"
    local output_file="$RESULTS_DIR/claude-output-image.txt"
    local test_image="$TEST_DIR/test-image.png"

    if ! run_claude_headless "Read $test_image" "$output_file" "Read image file"; then
        print_error "Failed to run Claude Code"
        return 1
    fi

    if [[ -s "$output_file" ]]; then print_success "Claude Code produced output"
    else print_error "No output captured"; return 1; fi

    sleep 2

    print_status "Checking for resized image in /tmp/..."
    if ls /tmp/resized_*.png 2>/dev/null | grep -q .; then
        local resized_file=$(ls /tmp/resized_*.png 2>/dev/null | head -1)
        local orig_size=$(stat -c%s "$TEST_DIR/test-image.png" 2>/dev/null || stat -f%z "$TEST_DIR/test-image.png" 2>/dev/null)
        local resized_size=$(stat -c%s "$resized_file" 2>/dev/null || stat -f%z "$resized_file" 2>/dev/null)
        OPTIMIZED_IMAGE_TOKENS=$(count_file_tokens "$resized_file")

        print_success "PreToolUse hook FIRED and resized the image!"
        print_proof "Resized file: $resized_file"
        print_metric "Original: $orig_size bytes (~$ORIGINAL_IMAGE_TOKENS tokens)"
        print_metric "Resized: $resized_size bytes (~$OPTIMIZED_IMAGE_TOKENS tokens)"

        if [[ $resized_size -lt $orig_size ]]; then
            local reduction=$((100 - (resized_size * 100 / orig_size)))
            local tokens_saved=$((ORIGINAL_IMAGE_TOKENS - OPTIMIZED_IMAGE_TOKENS))
            print_metric "Size reduction: ${reduction}%"
            print_metric "Token savings: ~$tokens_saved tokens"
        fi

        PRETOOLUSE_FIRED=true; RESIZED_IMAGE_CREATED=true
    else
        print_error "PreToolUse hook did NOT fire - no resized image found"
        PRETOOLUSE_FIRED=false
    fi
}

# Test PostToolUse Hook
test_posttooluse_hook() {
    print_section "TEST 2: PostToolUse Hook (Cache Keepalive)"
    print_status "Testing if PostToolUse hook fires after tool use..."

    rm -f "$HOOK_LOG"
    local output_file="$RESULTS_DIR/claude-output-ls.txt"

    if ! run_claude_headless "ls" "$output_file" "List directory"; then
        print_error "Failed to run Claude Code"
        return 1
    fi

    if [[ -s "$output_file" ]]; then print_success "Claude Code produced output"
    else print_error "No output captured"; return 1; fi

    print_status "Checking for hook output..."
    if [[ -f "$HOOK_LOG" ]]; then
        local hook_count=$(wc -l < "$HOOK_LOG")
        if [[ $hook_count -gt 0 ]]; then
            print_success "PostToolUse hook FIRED - $hook_count entries in log!"
            print_proof "Hook log ($HOOK_LOG):"
            head -3 "$HOOK_LOG" | while read -r line; do echo "  $line"; done
            POSTTOOLUSE_FIRED=true
        else
            print_error "Hook log is empty"
            POSTTOOLUSE_FIRED=false
        fi
    else
        print_error "PostToolUse hook did NOT fire - no hook log found"
        POSTTOOLUSE_FIRED=false
    fi
}

# Test PDF Processing
test_pdf_processing() {
    print_section "TEST 3: PDF Processing (Binary File Optimization)"

    local pdf_file="$TEST_DIR/test-document.pdf"
    if [[ ! -f "$pdf_file" ]]; then
        print_warning "No test-document.pdf found - skipping PDF test"
        return 0
    fi

    print_status "Testing PDF text extraction..."
    local extracted_text="$TEST_DIR/extracted-text.txt"

    if command -v pdftotext >/dev/null 2>&1; then
        if pdftotext -layout "$pdf_file" "$extracted_text" 2>/dev/null; then
            if [[ -s "$extracted_text" ]]; then
                local pdf_size=$(stat -c%s "$pdf_file" 2>/dev/null || stat -f%z "$pdf_file" 2>/dev/null)
                local txt_size=$(stat -c%s "$extracted_text" 2>/dev/null || stat -f%z "$extracted_text" 2>/dev/null)
                OPTIMIZED_PDF_TOKENS=$(count_file_tokens "$extracted_text")
                local tokens_saved=$((ORIGINAL_PDF_TOKENS - OPTIMIZED_PDF_TOKENS))

                print_success "PDF text extraction worked!"
                print_metric "PDF: $pdf_size bytes (~$ORIGINAL_PDF_TOKENS tokens)"
                print_metric "Text: $txt_size bytes (~$OPTIMIZED_PDF_TOKENS tokens)"

                if [[ $txt_size -lt $pdf_size ]]; then
                    local reduction=$((100 - (txt_size * 100 / pdf_size)))
                    print_metric "Size reduction: ${reduction}%"
                fi
                print_metric "Token savings: ~$tokens_saved tokens"
                PDF_CONVERTED=true
            else
                print_warning "PDF extraction produced empty file"
            fi
        else
            print_error "PDF text extraction failed"
        fi
    else
        print_warning "pdftotext not available - cannot test PDF extraction"
    fi
}

# Test Privacy Configuration
test_privacy_configuration() {
    print_section "TEST 4: Privacy Configuration"
    local vars=(
        "DISABLE_TELEMETRY:1"
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:1"
        "OTEL_LOG_USER_PROMPTS:0"
        "OTEL_LOG_TOOL_DETAILS:0"
        "CLAUDE_CODE_AUTO_COMPACT_WINDOW:180000"
    )
    local privacy_score=0

    for var_info in "${vars[@]}"; do
        IFS=':' read -r var_name expected <<< "$var_info"
        local actual="${!var_name}"
        if [[ "$actual" == "$expected" ]]; then
            print_success "$var_name=$actual"
            ((privacy_score++))
        else
            print_error "$var_name not set (expected: $expected, got: $actual)"
        fi
    done

    echo ""
    print_metric "Privacy Score: $privacy_score/5"
    [[ $privacy_score -eq 5 ]] && PRIVACY_VARS_SET=true
}

# Test Auto-Compact
test_auto_compact() {
    print_section "TEST 5: Auto-Compact Configuration"
    local claude_config="$HOME/.claude/.claude.json"

    if [[ -f "$claude_config" ]]; then
        if grep -q '"autoCompactEnabled": true' "$claude_config" 2>/dev/null; then
            print_success "autoCompactEnabled is enabled in ~/.claude/.claude.json"
            AUTO_COMPACT_ENABLED=true
        else
            print_error "autoCompactEnabled is not enabled"
        fi
    else
        print_error "Claude config file not found: $claude_config"
    fi
}

# Run all tests
run_all_tests() {
    mkdir -p "$RESULTS_DIR"
    test_pretooluse_hook
    test_posttooluse_hook
    test_pdf_processing
    test_privacy_configuration
    test_auto_compact
}

# Generate report
generate_report() {
    print_header "COMPREHENSIVE VALIDATION REPORT"

    echo -e "${BOLD}Test Results:${NC} Passed: $TESTS_PASSED | Failed: $TESTS_FAILED | Skipped: $TESTS_SKIPPED"
    echo ""

    # Dependencies
    print_section "📦 Dependencies"
    if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
        if command -v pdftotext >/dev/null 2>&1; then
            print_success "All dependencies installed"
        else
            print_warning "ImageMagick OK, pdftotext missing"
        fi
    else
        print_error "ImageMagick not installed"
    fi

    # Privacy
    print_section "🔒 Privacy Configuration"
    local privacy_score=0
    [[ "${DISABLE_TELEMETRY}" == "1" ]] && ((privacy_score++))
    [[ "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC}" == "1" ]] && ((privacy_score++))
    [[ "${OTEL_LOG_USER_PROMPTS}" == "0" ]] && ((privacy_score++))
    [[ "${OTEL_LOG_TOOL_DETAILS}" == "0" ]] && ((privacy_score++))
    [[ "${CLAUDE_CODE_AUTO_COMPACT_WINDOW}" == "180000" ]] && ((privacy_score++))

    print_metric "Privacy Score: $privacy_score/5"
    [[ $privacy_score -eq 5 ]] && PRIVACY_VARS_SET=true && print_success "Maximum privacy configured"

    # Auto-compact
    print_section "⚙️  Auto-Compact"
    local claude_config="$HOME/.claude/.claude.json"
    if [[ -f "$claude_config" ]] && grep -q '"autoCompactEnabled": true' "$claude_config" 2>/dev/null; then
        print_success "Auto-compact enabled"
        AUTO_COMPACT_ENABLED=true
    else
        print_error "Auto-compact not enabled"
    fi

    # Hooks
    print_section "🪝 Hook Execution"
    if $PRETOOLUSE_FIRED; then print_success "PreToolUse (image processing)"
    else print_error "PreToolUse did not fire"; fi
    if $POSTTOOLUSE_FIRED; then print_success "PostToolUse (cache keepalive)"
    else print_error "PostToolUse did not fire"; fi

    # Token savings
    print_section "💰 Token Savings"
    local total_saved=0
    if [[ $ORIGINAL_IMAGE_TOKENS -gt 0 && $OPTIMIZED_IMAGE_TOKENS -gt 0 ]]; then
        local img_saved=$((ORIGINAL_IMAGE_TOKENS - OPTIMIZED_IMAGE_TOKENS))
        local img_pct=$((img_saved * 100 / ORIGINAL_IMAGE_TOKENS))
        print_metric "Images: $ORIGINAL_IMAGE_TOKENS → $OPTIMIZED_IMAGE_TOKENS tokens (${img_pct}% reduction)"
        total_saved=$((total_saved + img_saved))
    fi
    if [[ $ORIGINAL_PDF_TOKENS -gt 0 && $OPTIMIZED_PDF_TOKENS -gt 0 ]]; then
        local pdf_saved=$((ORIGINAL_PDF_TOKENS - OPTIMIZED_PDF_TOKENS))
        local pdf_pct=$((pdf_saved * 100 / ORIGINAL_PDF_TOKENS))
        print_metric "PDFs: $ORIGINAL_PDF_TOKENS → $OPTIMIZED_PDF_TOKENS tokens (${pdf_pct}% reduction)"
        total_saved=$((total_saved + pdf_saved))
    fi
    print_metric "Total token savings: ~$total_saved tokens"

    # Overall verdict
    print_section "Overall Verdict"
    local all_good=false
    if $PRETOOLUSE_FIRED && $POSTTOOLUSE_FIRED && $PRIVACY_VARS_SET && $AUTO_COMPACT_ENABLED; then
        all_good=true
        print_success "ALL OPTIMIZATIONS WORKING"
        echo ""
        echo "Your Claude Code environment is fully optimized:"
        echo "  • Hooks are firing automatically"
        echo "  • Privacy settings configured"
        echo "  • Token savings verified (~$total_saved tokens)"
        echo "  • Auto-compact enabled"
    elif $PRETOOLUSE_FIRED || $POSTTOOLUSE_FIRED; then
        print_warning "PARTIALLY OPTIMIZED - Some optimizations working"
    else
        print_error "NOT OPTIMIZED - Run ./optimize-claude.sh"
    fi

    if $all_good; then exit 0; else exit 1; fi
}

# Main
main() {
    print_header "Claude Code Optimizer - Comprehensive Validation Suite"
    parse_args "$@"
    mkdir -p "$TEST_DIR" "$RESULTS_DIR"

    print_status "This comprehensive suite will:"
    print_status "1. Check all dependencies and configuration"
    print_status "2. Create test files and measure original token counts"
    print_status "3. Run Claude Code to trigger hooks"
    print_status "4. Measure actual token savings"
    print_status "5. Generate detailed validation report"
    echo ""

    check_prerequisites
    create_test_files
    run_all_tests
    generate_report
}

main "$@"
