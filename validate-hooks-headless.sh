#!/bin/bash
#
# Claude Code Hook Validation - Headless Mode
# Tests ACTUAL hook execution with proper verification methods
#
# This script:
# 1. Creates test files (images, PDFs, documents)
# 2. Runs Claude Code in headless mode
# 3. Sends commands to trigger hooks
# 4. Verifies hooks fired by checking side effects and transcript
# 5. Generates validation report with proof

# Don't exit on error - we handle failures manually
# set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
VERBOSE=false
KEEP_ARTIFACTS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/.validation-test"
RESULTS_DIR="$SCRIPT_DIR/.validation-results"
HOOK_LOG="/tmp/hook-validation.log"
TIMEOUT=60

# Claude Code command (search common locations)
CLAUDE_CMD=""
if command -v claude >/dev/null 2>&1; then
    CLAUDE_CMD="claude"
elif [[ -x "$HOME/.local/bin/claude" ]]; then
    CLAUDE_CMD="$HOME/.local/bin/claude"
elif [[ -x "/usr/local/bin/claude" ]]; then
    CLAUDE_CMD="/usr/local/bin/claude"
fi

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
PRETOOLUSE_FIRED=false
POSTTOOLUSE_FIRED=false
RESIZED_IMAGE_CREATED=false
PDF_CONVERTED=false

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

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}[⚠ SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

print_proof() {
    echo -e "${CYAN}[PROOF]${NC} $1"
}

# Cleanup
cleanup() {
    if [[ "$KEEP_ARTIFACTS" == "false" ]]; then
        rm -rf "$TEST_DIR" "$RESULTS_DIR"
        rm -f "$HOOK_LOG"
    fi
}
trap cleanup EXIT

# Show help
show_help() {
    cat << EOF
Claude Code Hook Validation - Headless Mode

Usage: $0 [OPTIONS]

OPTIONS:
    --verbose       Show detailed output
    --keep          Keep test files and results
    --help          Show this help

DESCRIPTION:
    This script automatically runs Claude Code in headless mode,
    triggers hooks by reading test files, and validates the hooks
    actually fired by checking side effects and log files.

VERIFICATION METHODS:
    1. PreToolUse: Checks for resized images in /tmp/
    2. PostToolUse: Checks hook log file for entries
    3. PDF: Checks if PDF text extraction worked

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --keep)
                KEEP_ARTIFACTS=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    print_section "CHECKING PREREQUISITES"

    # Check Claude Code
    if [[ -z "$CLAUDE_CMD" ]]; then
        print_error "Claude Code not found"
        print_status "Searched: PATH, ~/.local/bin/claude, /usr/local/bin/claude"
        exit 1
    fi
    print_success "Claude Code found: $CLAUDE_CMD"

    # Check version
    local version
    version=$($CLAUDE_CMD --version 2>&1 || echo "unknown")
    print_status "Claude Code version: $version"

    # Check settings.json (user-level only)
    if [[ ! -f "$HOME/.claude/settings.json" ]]; then
        print_error "No settings.json found at ~/.claude/settings.json"
        print_status "Run optimize-claude.sh first to install hooks"
        exit 1
    fi
    print_success "Found settings.json at ~/.claude/settings.json"

    # Check hooks configured
    local settings_file="$HOME/.claude/settings.json"

    if ! grep -q '"PreToolUse"' "$settings_file" 2>/dev/null; then
        print_error "PreToolUse hook not configured"
        exit 1
    fi
    print_success "PreToolUse hook configured"

    if ! grep -q '"PostToolUse"' "$settings_file" 2>/dev/null; then
        print_error "PostToolUse hook not configured"
        exit 1
    fi
    print_success "PostToolUse hook configured"

    # Check dependencies
    if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
        print_success "ImageMagick found"
    else
        print_warning "ImageMagick not found - image tests may fail"
    fi

    if command -v pdftotext >/dev/null 2>&1; then
        print_success "pdftotext (poppler) found"
    else
        print_warning "pdftotext not found - PDF tests may be limited"
    fi
}

# Create test files
create_test_files() {
    print_section "CREATING TEST FILES"

    mkdir -p "$TEST_DIR"
    print_status "Test directory: $TEST_DIR"

    # Create test image
    local cmd
    if command -v magick >/dev/null 2>&1; then
        cmd="magick"
    elif command -v convert >/dev/null 2>&1; then
        cmd="convert"
    fi

    if [[ -n "$cmd" ]]; then
        $cmd -size 3000x3000 xc:blue "$TEST_DIR/test-image.png" 2>/dev/null
        print_success "Created test-image.png (3000x3000 pixels)"
    else
        print_error "Cannot create test image - ImageMagick not available"
    fi

    # Create test text file
    echo "This is a test document for Claude Code hook validation." > "$TEST_DIR/test-doc.txt"
    print_success "Created test-doc.txt"

    # Check for existing test PDF in project root
    if [[ -f "$SCRIPT_DIR/test-document.pdf" ]]; then
        print_success "Found existing test-document.pdf"
    fi

    ls -la "$TEST_DIR"
}

# Run Claude Code headlessly
run_claude_headless() {
    local input_cmd="$1"
    local output_file="$2"
    local description="$3"

    print_status "Running: $description"

    if $VERBOSE; then
        echo "--- Claude Code Input ---"
        echo "$input_cmd"
        echo "-------------------------"
    fi

    # Clear hook log before running
    rm -f "$HOOK_LOG"

    # Run with timeout
    if ! timeout $TIMEOUT bash -c "echo '$input_cmd' | $CLAUDE_CMD -p" > "$output_file" 2>&1; then
        print_warning "Claude command timed out or failed"
    fi

    if $VERBOSE && [[ -f "$output_file" ]]; then
        echo "--- Claude Code Output ---"
        cat "$output_file"
        echo "--------------------------"
    fi

    [[ -f "$output_file" ]]
}

# Test 1: PreToolUse Hook - Image Processing
test_pretooluse_hook() {
    print_section "TEST 1: PreToolUse Hook (Image Processing)"

    print_status "Testing if PreToolUse hook fires when reading an image..."

    # Clean up
    rm -f /tmp/resized_*.png "$HOOK_LOG"

    # Run Claude
    local output_file="$RESULTS_DIR/claude-output-image.txt"
    local test_image
    test_image=$(cd "$TEST_DIR" && pwd)/test-image.png

    print_status "Reading image: $test_image"

    if ! run_claude_headless "Read $test_image" "$output_file" "Read image file"; then
        print_error "Failed to run Claude Code"
        return 1
    fi

    if [[ -s "$output_file" ]]; then
        print_success "Claude Code produced output"
    else
        print_error "No output captured"
        return 1
    fi

    # Wait for hook
    sleep 2

    # Check for resized image
    print_status "Checking for resized image in /tmp/..."

    if ls /tmp/resized_*.png 2>/dev/null | grep -q .; then
        local resized_file
        resized_file=$(ls /tmp/resized_*.png 2>/dev/null | head -1)
        local original_size resized_size
        original_size=$(stat -c%s "$TEST_DIR/test-image.png" 2>/dev/null || stat -f%z "$TEST_DIR/test-image.png" 2>/dev/null)
        resized_size=$(stat -c%s "$resized_file" 2>/dev/null || stat -f%z "$resized_file" 2>/dev/null)

        print_success "PreToolUse hook FIRED and resized the image!"
        print_proof "Resized file: $resized_file"
        print_proof "Original: $original_size bytes → Resized: $resized_size bytes"

        if [[ $resized_size -lt $original_size ]]; then
            local reduction=$((100 - (resized_size * 100 / original_size)))
            print_proof "Size reduction: ${reduction}%"
        fi

        PRETOOLUSE_FIRED=true
        RESIZED_IMAGE_CREATED=true
    else
        print_error "PreToolUse hook did NOT fire - no resized image found"
        print_status "Expected: /tmp/resized_*.png"
        PRETOOLUSE_FIRED=false
    fi
}

# Test 2: PostToolUse Hook - Cache Keepalive
test_posttooluse_hook() {
    print_section "TEST 2: PostToolUse Hook (Cache Keepalive)"

    print_status "Testing if PostToolUse hook fires after tool use..."

    # Clear log
    rm -f "$HOOK_LOG"

    # Run Claude
    local output_file="$RESULTS_DIR/claude-output-ls.txt"

    print_status "Running: ls"

    if ! run_claude_headless "ls" "$output_file" "List directory"; then
        print_error "Failed to run Claude Code"
        return 1
    fi

    if [[ -s "$output_file" ]]; then
        print_success "Claude Code produced output"
    else
        print_error "No output captured"
        return 1
    fi

    # Check hook log
    print_status "Checking hook log file..."

    if [[ -f "$HOOK_LOG" ]]; then
        local hook_count
        hook_count=$(wc -l < "$HOOK_LOG")
        if [[ $hook_count -gt 0 ]]; then
            print_success "PostToolUse hook FIRED - $hook_count entries in log!"
            print_proof "Hook log ($HOOK_LOG):"
            head -5 "$HOOK_LOG" | while read -r line; do
                echo "  $line"
            done
            POSTTOOLUSE_FIRED=true
        else
            print_error "Hook log is empty"
            POSTTOOLUSE_FIRED=false
        fi
    else
        print_error "PostToolUse hook did NOT fire - no hook log found"
        print_status "Expected: $HOOK_LOG to contain hook entries"
        POSTTOOLUSE_FIRED=false
    fi
}

# Test 3: PDF Processing
test_pdf_processing() {
    print_section "TEST 3: PDF Processing (Binary File Optimization)"

    # Use existing test PDF from project root
    local pdf_file="$SCRIPT_DIR/test-document.pdf"
    if [[ ! -f "$pdf_file" ]]; then
        print_warning "No test-document.pdf found in project root - skipping PDF test"
        return 0
    fi

    print_status "Testing PDF text extraction with existing test-document.pdf..."

    local extracted_text="$TEST_DIR/extracted-text.txt"

    # Try pdftotext if available
    if command -v pdftotext >/dev/null 2>&1; then
        print_status "Using pdftotext to extract PDF content..."

        if pdftotext -layout "$pdf_file" "$extracted_text" 2>/dev/null; then
            if [[ -s "$extracted_text" ]]; then
                local pdf_size txt_size
                pdf_size=$(stat -c%s "$pdf_file" 2>/dev/null || stat -f%z "$pdf_file" 2>/dev/null)
                txt_size=$(stat -c%s "$extracted_text" 2>/dev/null || stat -f%z "$extracted_text" 2>/dev/null)

                print_success "PDF text extraction worked!"
                print_proof "PDF size: $pdf_size bytes"
                print_proof "Text size: $txt_size bytes"

                if [[ $txt_size -lt $pdf_size ]]; then
                    local reduction=$((100 - (txt_size * 100 / pdf_size)))
                    print_proof "Size reduction: ${reduction}%"
                fi

                if $VERBOSE; then
                    echo "  Extracted text preview:"
                    head -5 "$extracted_text" | sed 's/^/    /'
                fi

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

# Test 4: Combined Workflow
test_combined_workflow() {
    print_section "TEST 4: Combined Workflow"

    print_status "Testing multiple operations..."

    rm -f "$HOOK_LOG"

    local operations=(
        "Read $TEST_DIR/test-doc.txt"
        "pwd"
        "echo 'test'"
    )

    local total_runs=0
    local hook_entries=0

    for op in "${operations[@]}"; do
        local output_file="$RESULTS_DIR/claude-output-$total_runs.txt"

        print_status "Operation $((total_runs + 1)): $op"

        if run_claude_headless "$op" "$output_file" "$op"; then
            ((total_runs++))
        fi

        sleep 1
    done

    # Count hook entries
    if [[ -f "$HOOK_LOG" ]]; then
        hook_entries=$(wc -l < "$HOOK_LOG")
    fi

    print_status "Completed $total_runs operations"
    print_status "Hook log has $hook_entries entries"

    if [[ $hook_entries -gt 0 ]]; then
        print_success "Hooks fire consistently across multiple operations"
    else
        print_warning "Hooks may not be firing consistently"
    fi
}

# Generate report
generate_report() {
    print_header "HOOK VALIDATION REPORT"

    echo -e "${BOLD}Test Results:${NC}"
    echo "  Passed:  $TESTS_PASSED"
    echo "  Failed:  $TESTS_FAILED"
    echo "  Skipped: $TESTS_SKIPPED"
    echo ""

    echo -e "${BOLD}Hook Execution Summary:${NC}"
    echo ""

    # PreToolUse
    echo -e "${CYAN}PreToolUse Hook (Image Processing):${NC}"
    if $PRETOOLUSE_FIRED; then
        echo -e "  ${GREEN}✓ FIRED${NC} - Image was resized"
        if $RESIZED_IMAGE_CREATED; then
            local resized
            resized=$(ls /tmp/resized_*.png 2>/dev/null | head -1)
            echo "  Evidence: $resized exists"
        fi
    else
        echo -e "  ${RED}✗ DID NOT FIRE${NC}"
        echo "  No resized image found in /tmp/"
    fi
    echo ""

    # PostToolUse
    echo -e "${CYAN}PostToolUse Hook (Cache Keepalive):${NC}"
    if $POSTTOOLUSE_FIRED; then
        echo -e "  ${GREEN}✓ FIRED${NC} - Hook log has entries"
        echo "  Evidence: $HOOK_LOG contains entries"
    else
        echo -e "  ${RED}✗ DID NOT FIRE${NC}"
        echo "  No hook log entries found"
    fi
    echo ""

    # PDF
    echo -e "${CYAN}PDF Processing:${NC}"
    if $PDF_CONVERTED; then
        echo -e "  ${GREEN}✓ WORKING${NC} - PDF text extraction succeeded"
    else
        echo -e "  ${YELLOW}⚠ NOT TESTED${NC} - PDF tools not available or test skipped"
    fi
    echo ""

    # Overall
    echo -e "${BOLD}Overall Verdict:${NC}"
    if $PRETOOLUSE_FIRED && $POSTTOOLUSE_FIRED; then
        echo -e "${GREEN}${BOLD}✓ ALL HOOKS ARE WORKING${NC}"
        echo ""
        echo "Both PreToolUse and PostToolUse hooks are firing automatically."
        echo "The optimizations are active and functional!"
    elif $PRETOOLUSE_FIRED || $POSTTOOLUSE_FIRED; then
        echo -e "${YELLOW}${BOLD}⚠ PARTIALLY WORKING${NC}"
        echo ""
        echo "Some hooks are firing but not all."
    else
        echo -e "${RED}${BOLD}✗ HOOKS NOT FIRING${NC}"
        echo ""
        echo "The hooks are not triggering. Check:"
        echo "  - Claude Code was restarted after installing hooks"
        echo "  - Hook scripts exist in ~/.claude/hooks/"
        echo "  - Hook scripts are executable"
    fi

    echo ""
    echo -e "${BOLD}Artifacts:${NC}"
    if [[ "$KEEP_ARTIFACTS" == "true" ]]; then
        echo "  Test files: $TEST_DIR"
        echo "  Results: $RESULTS_DIR"
        echo "  Hook log: $HOOK_LOG"
    else
        echo "  (Use --keep to preserve test files and results)"
    fi

    # Exit code
    if $PRETOOLUSE_FIRED && $POSTTOOLUSE_FIRED; then
        exit 0
    else
        exit 1
    fi
}

# Main
main() {
    print_header "Claude Code Hook Validation - Headless Mode"

    parse_args "$@"

    mkdir -p "$RESULTS_DIR"

    print_status "This script will:"
    print_status "1. Create test files (image, PDF, text)"
    print_status "2. Run Claude Code in headless mode"
    print_status "3. Send Read commands to trigger hooks"
    print_status "4. Verify hooks fired by checking side effects"
    echo ""

    check_prerequisites
    create_test_files
    test_pretooluse_hook
    test_posttooluse_hook
    test_pdf_processing
    test_combined_workflow

    generate_report
}

main "$@"
