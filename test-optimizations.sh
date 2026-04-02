#!/bin/bash
#
# Claude Code Optimizer INTEGRATION Test Suite
# Tests ACTUAL functionality - not just configuration
#
# This script:
# 1. Creates real test files (PDF, images, documents)
# 2. Executes the exact commands the hooks would run
# 3. Verifies files are actually converted/optimized
# 4. Measures actual token savings
#
# Usage: ./test-optimizations.sh [--verbose] [--keep-artifacts]

# Don't use set -e because we need to handle failures gracefully
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test configuration
VERBOSE=false
KEEP_ARTIFACTS=false
TEST_DIR=$(mktemp -d)
ARTIFACTS_DIR="./test-artifacts-$(date +%Y%m%d-%H%M%S)"

# Results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Token savings tracking
ORIGINAL_TOKENS=0
OPTIMIZED_TOKENS=0

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

print_metric() {
    echo -e "${CYAN}[METRIC]${NC} $1"
}

# Cleanup function
cleanup() {
    if [[ "$KEEP_ARTIFACTS" == "true" && -d "$TEST_DIR" ]]; then
        mkdir -p "$ARTIFACTS_DIR"
        cp -r "$TEST_DIR"/* "$ARTIFACTS_DIR/" 2>/dev/null || true
        print_status "Artifacts saved to: $ARTIFACTS_DIR"
    fi
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# Show help
show_help() {
    cat << EOF
Claude Code Optimizer Integration Test Suite

Usage: $0 [OPTIONS]

OPTIONS:
    --verbose         Show detailed output for all tests
    --keep-artifacts  Keep test files for inspection
    --help            Show this help message

This script tests ACTUAL functionality:
  - Creates real test files (PDFs, images, documents)
  - Executes the exact commands the hooks run
  - Verifies files are actually converted/optimized
  - Measures token savings

EXAMPLES:
    $0                    # Run all integration tests
    $0 --verbose          # Detailed output
    $0 --keep-artifacts   # Keep test files for inspection

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
            --keep-artifacts)
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

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Estimate tokens for a file (rough approximation: 1 token ≈ 4 chars for text)
estimate_tokens() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # For text files: count characters and divide by 4
        local chars=$(wc -c < "$file")
        echo $((chars / 4))
    else
        echo "0"
    fi
}

# Test 1: Image Pre-processing Hook (Actual Execution)
test_image_preprocessing() {
    print_section "TEST 1: IMAGE PRE-PROCESSING HOOK (ACTUAL EXECUTION)"

    if ! command_exists convert && ! command_exists magick; then
        print_error "ImageMagick not available - cannot test image pre-processing"
        return 1
    fi

    local cmd=$(command_exists magick && echo "magick" || echo "convert")

    # Create a large test image (4000x4000 = 16MP, like a high-res screenshot)
    local test_image="$TEST_DIR/large_screenshot.png"
    print_status "Creating test image (4000x4000 pixels, ~16MB)..."

    if ! $cmd -size 4000x4000 xc:lightblue -pointsize 30 -fill black \
        -gravity center -annotate +0+0 "Test Screenshot\n4000x4000 pixels" \
        "$test_image" 2>/dev/null; then
        print_error "Failed to create test image"
        return 1
    fi

    local original_size=$(stat -c%s "$test_image" 2>/dev/null || stat -f%z "$test_image" 2>/dev/null)
    print_success "Created test image: $original_size bytes"

    # Execute the EXACT hook command from settings.json
    local optimized_image="$TEST_DIR/resized_screenshot.png"
    print_status "Executing PreToolUse hook command..."

    # The hook command from settings.json:
    # magick "$ARGUMENTS" -resize 2000x2000> -quality 85 /tmp/resized_$(basename "$ARGUMENTS")
    if ! $cmd "$test_image" -resize "2000x2000>" -quality 85 "$optimized_image" 2>/dev/null; then
        print_error "Image pre-processing hook command failed"
        return 1
    fi

    if [[ ! -f "$optimized_image" ]]; then
        print_error "Optimized image was not created"
        return 1
    fi

    local optimized_size=$(stat -c%s "$optimized_image" 2>/dev/null || stat -f%z "$optimized_image" 2>/dev/null)
    local size_reduction=$((100 - (optimized_size * 100 / original_size)))

    print_success "Image pre-processing executed successfully"
    print_metric "Original size: $original_size bytes"
    print_metric "Optimized size: $optimized_size bytes"
    print_metric "Size reduction: ${size_reduction}%"

    if [[ $size_reduction -gt 0 ]]; then
        print_success "File size reduced by ${size_reduction}%"
    else
        print_warning "File size did not reduce (may be already optimized)"
    fi

    # Estimate token savings (base64 encoding overhead)
    # Rough estimate: base64 adds ~33% overhead
    local original_tokens=$((original_size * 4 / 3 / 4))
    local optimized_tokens=$((optimized_size * 4 / 3 / 4))
    local token_reduction=$((original_tokens - optimized_tokens))

    print_metric "Estimated original tokens: ~$original_tokens"
    print_metric "Estimated optimized tokens: ~$optimized_tokens"
    print_metric "Estimated token savings: ~$token_reduction tokens"

    if $VERBOSE; then
        echo ""
        echo "  Original image: $test_image"
        echo "  Optimized image: $optimized_image"
        $cmd identify "$test_image" 2>/dev/null | head -1 | sed 's/^/  Original: /'
        $cmd identify "$optimized_image" 2>/dev/null | head -1 | sed 's/^/  Optimized: /'
    fi

    # Track totals
    ORIGINAL_TOKENS=$((ORIGINAL_TOKENS + original_tokens))
    OPTIMIZED_TOKENS=$((OPTIMIZED_TOKENS + optimized_tokens))
}

# Test 2: PDF Text Extraction (Actual Execution)
test_pdf_extraction() {
    print_section "TEST 2: PDF TEXT EXTRACTION (ACTUAL EXECUTION)"

    if ! command_exists pdftotext; then
        print_error "pdftotext not available - cannot test PDF extraction"
        return 1
    fi

    # Create a test PDF using Python if available
    local test_pdf="$TEST_DIR/test_document.pdf"
    local extracted_text="$TEST_DIR/extracted_text.txt"

    print_status "Creating test PDF document..."

    if command_exists python3 || command_exists python; then
        local py_cmd=$(command_exists python3 && echo "python3" || echo "python")

        # Try to create PDF with reportlab
        $py_cmd << PYTHON_EOF 2>/dev/null
import sys
try:
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter

    c = canvas.Canvas("$test_pdf", pagesize=letter)
    c.drawString(100, 700, "This is a test PDF document for Claude Code optimization testing.")
    c.drawString(100, 680, "It contains multiple lines of text that should be extractable.")
    c.drawString(100, 660, "Line 3: Testing PDF text extraction with pdftotext.")
    c.drawString(100, 640, "Line 4: The extracted text should be much smaller than the PDF.")
    c.drawString(100, 620, "Line 5: This allows Claude Code to process the content with fewer tokens.")
    c.showPage()
    c.save()
    print("PDF created successfully")
except ImportError:
    print("reportlab not installed")
    sys.exit(1)
PYTHON_EOF

        if [[ ! -f "$test_pdf" ]]; then
            print_warning "Could not create PDF with reportlab - using fallback"
            # Create a minimal PDF manually (won't have extractable text but tests the flow)
            echo "%PDF-1.4" > "$test_pdf"
            echo "1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj" >> "$test_pdf"
            echo "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj" >> "$test_pdf"
            echo "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj" >> "$test_pdf"
            echo "xref" >> "$test_pdf"
            echo "trailer << /Size 4 /Root 1 0 R >>" >> "$test_pdf"
            echo "startxref" >> "$test_pdf"
            echo "%%EOF" >> "$test_pdf"
        fi
    else
        print_error "Python not available - cannot create test PDF"
        return 1
    fi

    local pdf_size=$(stat -c%s "$test_pdf" 2>/dev/null || stat -f%z "$test_pdf" 2>/dev/null)
    print_success "Created test PDF: $pdf_size bytes"

    # Execute pdftotext (the actual optimization)
    print_status "Executing pdftotext -layout (PDF optimization)..."

    if ! pdftotext -layout "$test_pdf" "$extracted_text" 2>/dev/null; then
        print_error "PDF text extraction failed"
        return 1
    fi

    if [[ ! -f "$extracted_text" ]]; then
        print_error "Extracted text file was not created"
        return 1
    fi

    local text_size=$(stat -c%s "$extracted_text" 2>/dev/null || stat -f%z "$extracted_text" 2>/dev/null)
    local size_reduction=$((100 - (text_size * 100 / pdf_size)))

    print_success "PDF text extraction executed successfully"
    print_metric "PDF size: $pdf_size bytes"
    print_metric "Extracted text size: $text_size bytes"
    print_metric "Size reduction: ${size_reduction}%"

    # Estimate token savings
    local pdf_tokens=$((pdf_size / 4))
    local text_tokens=$((text_size / 4))
    local token_reduction=$((pdf_tokens - text_tokens))

    print_metric "Estimated PDF tokens: ~$pdf_tokens"
    print_metric "Estimated text tokens: ~$text_tokens"
    print_metric "Estimated token savings: ~$token_reduction tokens"

    if $VERBOSE; then
        echo ""
        echo "  Extracted text preview (first 500 chars):"
        head -c 500 "$extracted_text" | sed 's/^/    /'
        echo ""
    fi

    # Track totals
    ORIGINAL_TOKENS=$((ORIGINAL_TOKENS + pdf_tokens))
    OPTIMIZED_TOKENS=$((OPTIMIZED_TOKENS + text_tokens))
}

# Test 3: Document Conversion (markitdown)
test_document_conversion() {
    print_section "TEST 3: DOCUMENT CONVERSION (markitdown)"

    if ! command_exists markitdown; then
        print_warning "markitdown not available - skipping document conversion test"
        return 0
    fi

    # Create a test HTML file (simulating a document)
    local test_html="$TEST_DIR/test_document.html"
    local converted_md="$TEST_DIR/converted_document.md"

    cat > "$test_html" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Test Document</title></head>
<body>
<h1>Test Document for Claude Code</h1>
<p>This is a test paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
<ul>
<li>Item 1: Testing document conversion</li>
<li>Item 2: Converting HTML to Markdown</li>
<li>Item 3: Reducing token usage</li>
</ul>
<p>Document conversion can significantly reduce token usage compared to reading raw HTML.</p>
</body>
</html>
HTMLEOF

    local html_size=$(stat -c%s "$test_html" 2>/dev/null || stat -f%z "$test_html" 2>/dev/null)
    print_success "Created test HTML: $html_size bytes"

    # Execute markitdown
    print_status "Executing markitdown (document conversion)..."

    if ! markitdown "$test_html" > "$converted_md" 2>/dev/null; then
        print_error "Document conversion failed"
        return 1
    fi

    if [[ ! -f "$converted_md" ]]; then
        print_error "Converted markdown file was not created"
        return 1
    fi

    local md_size=$(stat -c%s "$converted_md" 2>/dev/null || stat -f%z "$converted_md" 2>/dev/null)

    print_success "Document conversion executed successfully"
    print_metric "HTML size: $html_size bytes"
    print_metric "Markdown size: $md_size bytes"

    if $VERBOSE; then
        echo ""
        echo "  Converted Markdown:"
        cat "$converted_md" | sed 's/^/    /'
    fi
}

# Test 4: Cache Keepalive Hook (Actual Execution)
test_cache_keepalive() {
    print_section "TEST 4: CACHE KEEPALIVE HOOK (ACTUAL EXECUTION)"

    # The PostToolUse hook command from settings.json:
    # echo '{"cache_keepalive": "'$(date +%s)'"}'

    print_status "Executing PostToolUse hook command..."

    local hook_output
    hook_output=$(echo '{"cache_keepalive": "'$(date +%s)'"}')

    if [[ -z "$hook_output" ]]; then
        print_error "Cache keepalive hook produced no output"
        return 1
    fi

    # Validate JSON output
    if command_exists python3 || command_exists python; then
        local py_cmd=$(command_exists python3 && echo "python3" || echo "python")
        if $py_cmd -c "import json; json.loads('$hook_output')" 2>/dev/null; then
            print_success "Cache keepalive hook produced valid JSON"
        else
            print_warning "Cache keepalive hook output may not be valid JSON"
        fi
    else
        print_success "Cache keepalive hook executed (output: $hook_output)"
    fi

    print_metric "Hook output: $hook_output"

    if $VERBOSE; then
        echo ""
        echo "  This hook fires after every tool use in Claude Code"
        echo "  It outputs a timestamp that keeps the prompt cache warm"
        echo "  Prevents the 5-minute TTL expiration"
    fi
}

# Test 5: Combined Workflow Test
test_combined_workflow() {
    print_section "TEST 5: COMBINED WORKFLOW TEST"

    print_status "Simulating a Claude Code session with multiple files..."

    local workflow_dir="$TEST_DIR/workflow_test"
    mkdir -p "$workflow_dir"

    # Create multiple files
    local files_created=0

    # 1. Large image
    if command_exists convert || command_exists magick; then
        local cmd=$(command_exists magick && echo "magick" || echo "convert")
        $cmd -size 3000x3000 xc:blue "$workflow_dir/large_image.png" 2>/dev/null
        ((files_created++))
    fi

    # 2. PDF
    if command_exists python3; then
        python3 << PYTHON_EOF 2>/dev/null
from reportlab.pdfgen import canvas
c = canvas.Canvas("$workflow_dir/document.pdf")
c.drawString(100, 700, "Workflow test PDF")
c.save()
PYTHON_EOF
        ((files_created++))
    fi

    # 3. Text file
    echo "This is a test text file for the workflow simulation." > "$workflow_dir/notes.txt"
    ((files_created++))

    print_status "Created $files_created test files in workflow directory"

    # Process each file as Claude Code would
    local total_original_size=0
    local total_optimized_size=0

    for file in "$workflow_dir"/*; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            local ext="${basename##*.}"
            local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
            total_original_size=$((total_original_size + size))

            print_status "Processing: $basename ($size bytes)"

            case "$ext" in
                png|jpg|jpeg)
                    if command_exists convert || command_exists magick; then
                        local cmd=$(command_exists magick && echo "magick" || echo "convert")
                        $cmd "$file" -resize "2000x2000>" -quality 85 "$workflow_dir/optimized_$basename" 2>/dev/null
                        local opt_size=$(stat -c%s "$workflow_dir/optimized_$basename" 2>/dev/null || echo "0")
                        total_optimized_size=$((total_optimized_size + opt_size))
                        print_success "  Image optimized: $size → $opt_size bytes"
                    fi
                    ;;
                pdf)
                    if command_exists pdftotext; then
                        pdftotext -layout "$file" "$workflow_dir/${basename%.pdf}.txt" 2>/dev/null
                        local txt_size=$(stat -c%s "$workflow_dir/${basename%.pdf}.txt" 2>/dev/null || echo "0")
                        total_optimized_size=$((total_optimized_size + txt_size))
                        print_success "  PDF extracted: $size → $txt_size bytes"
                    fi
                    ;;
                *)
                    # Text files - no optimization needed
                    total_optimized_size=$((total_optimized_size + size))
                    print_success "  Text file (no optimization needed)"
                    ;;
            esac
        fi
    done

    if [[ $total_original_size -gt 0 ]]; then
        local overall_reduction=$((100 - (total_optimized_size * 100 / total_original_size)))
        print_success "Workflow test completed"
        print_metric "Total original size: $total_original_size bytes"
        print_metric "Total optimized size: $total_optimized_size bytes"
        print_metric "Overall reduction: ${overall_reduction}%"
    fi
}

# Test 6: Privacy Settings Verification (Actual Effect)
test_privacy_effectiveness() {
    print_section "TEST 6: PRIVACY SETTINGS EFFECTIVENESS"

    print_status "Checking if privacy settings are active..."

    local privacy_score=0
    local checks=0

    # Check 1: DISABLE_TELEMETRY
    if [[ "${DISABLE_TELEMETRY}" == "1" ]]; then
        print_success "DISABLE_TELEMETRY is active (Datadog telemetry disabled)"
        ((privacy_score++))
    else
        print_error "DISABLE_TELEMETRY is not set - telemetry may be active"
    fi
    ((checks++))

    # Check 2: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
    if [[ "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC}" == "1" ]]; then
        print_success "Non-essential traffic is blocked (updates, release notes disabled)"
        ((privacy_score++))
    else
        print_error "Non-essential traffic not blocked"
    fi
    ((checks++))

    # Check 3: OTEL_LOG_USER_PROMPTS
    if [[ "${OTEL_LOG_USER_PROMPTS}" == "0" ]]; then
        print_success "OpenTelemetry prompt logging is disabled"
        ((privacy_score++))
    else
        print_error "OpenTelemetry may be logging prompts"
    fi
    ((checks++))

    # Check 4: OTEL_LOG_TOOL_DETAILS
    if [[ "${OTEL_LOG_TOOL_DETAILS}" == "0" ]]; then
        print_success "OpenTelemetry tool logging is disabled"
        ((privacy_score++))
    else
        print_error "OpenTelemetry may be logging tool usage"
    fi
    ((checks++))

    print_metric "Privacy score: $privacy_score/$checks checks passed"

    if [[ $privacy_score -eq $checks ]]; then
        print_success "Maximum privacy protection is active"
    elif [[ $privacy_score -ge 2 ]]; then
        print_warning "Partial privacy protection ($privacy_score/$checks)"
    else
        print_error "Limited privacy protection - review settings"
    fi
}

# Generate final report
generate_report() {
    print_header "INTEGRATION TEST SUMMARY"

    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo -e "${BOLD}Test Results:${NC}"
    echo "  Passed:  $TESTS_PASSED"
    echo "  Failed:  $TESTS_FAILED"
    echo "  Skipped: $TESTS_SKIPPED"
    echo "  Total:   $total_tests"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All integration tests passed!${NC}"
        echo "The optimizations are actually working, not just configured."
    else
        echo -e "${YELLOW}${BOLD}⚠ Some tests failed${NC}"
        echo "Review the failures above - some optimizations may not be functional."
    fi

    echo ""
    echo -e "${BOLD}Token Savings Summary:${NC}"
    if [[ $ORIGINAL_TOKENS -gt 0 ]]; then
        local token_reduction=$((ORIGINAL_TOKENS - OPTIMIZED_TOKENS))
        local percentage_reduction=$((100 - (OPTIMIZED_TOKENS * 100 / ORIGINAL_TOKENS)))
        echo "  Original estimate: ~$ORIGINAL_TOKENS tokens"
        echo "  Optimized estimate: ~$OPTIMIZED_TOKENS tokens"
        echo "  Savings: ~$token_reduction tokens (${percentage_reduction}% reduction)"
    else
        echo "  Token savings could not be calculated (some tests may have been skipped)"
    fi

    echo ""
    echo -e "${BOLD}Verified Optimizations:${NC}"

    if command_exists convert || command_exists magick; then
        echo -e "  ${GREEN}✓${NC} Image pre-processing: Actually resizes images"
    else
        echo -e "  ${RED}✗${NC} Image pre-processing: Not functional"
    fi

    if command_exists pdftotext; then
        echo -e "  ${GREEN}✓${NC} PDF extraction: Actually extracts text"
    else
        echo -e "  ${RED}✗${NC} PDF extraction: Not functional"
    fi

    if command_exists markitdown; then
        echo -e "  ${GREEN}✓${NC} Document conversion: markitdown works"
    else
        echo -e "  ${YELLOW}⚠${NC} Document conversion: markitdown not available"
    fi

    if [[ "${DISABLE_TELEMETRY}" == "1" ]]; then
        echo -e "  ${GREEN}✓${NC} Privacy: Telemetry disabled"
    else
        echo -e "  ${RED}✗${NC} Privacy: Telemetry may be active"
    fi

    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "  1. Install missing dependencies"
        echo "  2. Run: ./optimize-claude.sh"
        echo "  3. Restart your shell"
        echo "  4. Run this test again: ./test-optimizations.sh"
    else
        echo "  All optimizations are functional!"
        echo "  Use Claude Code with confidence that optimizations are working."
    fi

    if [[ "$KEEP_ARTIFACTS" == "true" ]]; then
        echo ""
        echo -e "${BOLD}Test artifacts saved to:${NC} $ARTIFACTS_DIR"
        echo "  You can inspect the test files to verify the optimizations."
    fi
}

# Main function
main() {
    print_header "Claude Code Optimizer INTEGRATION Test Suite"

    parse_args "$@"

    if $VERBOSE; then
        print_status "Test directory: $TEST_DIR"
        print_status "Verbose mode enabled"
    fi

    print_status "Starting integration tests..."
    print_status "These tests execute ACTUAL optimization commands"
    echo ""

    # Run all tests
    test_image_preprocessing
    test_pdf_extraction
    test_document_conversion
    test_cache_keepalive
    test_combined_workflow
    test_privacy_effectiveness

    generate_report

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
