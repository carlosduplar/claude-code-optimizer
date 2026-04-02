#!/bin/bash
#
# Claude Code Hook Execution Monitor
# Verifies that Claude Code ACTUALLY triggers existing hooks during operation
#
# This script:
# 1. Creates test files that should trigger existing hooks
# 2. Provides instructions for testing
# 3. Verifies hook execution by checking logs/clues
#
# Usage: ./monitor-hooks.sh [--verify] [--reset] [--test]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILES_DIR="$SCRIPT_DIR/.hook-test-files"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Functions
print_header() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN} $1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

# Show help
show_help() {
    cat << EOF
Claude Code Hook Execution Monitor

Usage: $0 [COMMAND]

COMMANDS:
    --test       Create test files and show test instructions
    --verify     Check if hooks are configured and provide verification steps
    --reset      Clean up test files
    --help       Show this help message

WORKFLOW:
    1. Run optimize-claude.sh first (installs hooks)
    2. Restart Claude Code completely
    3. Run: ./monitor-hooks.sh --test (creates test files)
    4. In Claude Code, run: Read .hook-test-files/test-image.png
    5. Check if hooks fired (see verification methods below)
    6. Run: ./monitor-hooks.sh --reset (cleanup)

VERIFICATION METHODS:

Method 1: Check for resized image
  The PreToolUse hook should create: /tmp/resized_test-image.png
  Run: ls -la /tmp/resized_*.png

Method 2: Check Claude Code output
  The PostToolUse hook outputs JSON. Look for cache_keepalive in Claude's output.

Method 3: Monitor temp files
  Watch /tmp for files created by hooks during operation.

This tool verifies that Claude Code ACTUALLY triggers hooks automatically.

EOF
}

# Create test files
create_test_files() {
    print_header "Creating Test Files"

    # Create test files directory
    mkdir -p "$TEST_FILES_DIR"
    print_status "Test files directory: $TEST_FILES_DIR"

    # Create a test image (large enough to trigger resize)
    if command -v convert >/dev/null 2>&1 || command -v magick >/dev/null 2>&1; then
        local cmd=$(command -v magick >/dev/null 2>&1 && echo "magick" || echo "convert")
        $cmd -size 3000x3000 xc:blue "$TEST_FILES_DIR/test-image.png" 2>/dev/null
        print_success "Created test-image.png (3000x3000 pixels)"
    else
        print_warning "ImageMagick not available - cannot create test image"
    fi

    # Create a test PDF
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        local py_cmd=$(command -v python3 >/dev/null 2>&1 && echo "python3" || echo "python")
        $py_cmd << PYTHON_EOF 2>/dev/null
from reportlab.pdfgen import canvas
c = canvas.Canvas("$TEST_FILES_DIR/test-document.pdf")
c.drawString(100, 700, "Test PDF document for hook monitoring")
c.drawString(100, 680, "This file is used to test if Claude Code triggers hooks")
c.save()
PYTHON_EOF
        if [[ -f "$TEST_FILES_DIR/test-document.pdf" ]]; then
            print_success "Created test-document.pdf"
        fi
    fi

    # Create a test text file
    echo "This is a test text file." > "$TEST_FILES_DIR/test-document.txt"
    print_success "Created test-document.txt"

    echo ""
    echo -e "${BOLD}Test files created:${NC}"
    ls -la "$TEST_FILES_DIR" 2>/dev/null || print_warning "Could not list test files"
}

# Check if hooks are configured
check_hooks_configured() {
    print_header "Checking Hook Configuration"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        print_error "No settings.json found at $SETTINGS_FILE"
        print_status "Run optimize-claude.sh first to install hooks"
        return 1
    fi

    print_success "Found settings.json"

    # Check for PreToolUse hook
    if grep -q '"PreToolUse"' "$SETTINGS_FILE" 2>/dev/null; then
        print_success "PreToolUse hook is configured"
        if grep -q 'magick.*resize' "$SETTINGS_FILE" 2>/dev/null || grep -q 'convert.*resize' "$SETTINGS_FILE" 2>/dev/null; then
            print_success "Image resize command found in PreToolUse hook"
        fi
    else
        print_error "PreToolUse hook not found in settings.json"
        print_status "Run optimize-claude.sh to install hooks"
        return 1
    fi

    # Check for PostToolUse hook
    if grep -q '"PostToolUse"' "$SETTINGS_FILE" 2>/dev/null; then
        print_success "PostToolUse hook is configured"
        if grep -q 'cache_keepalive' "$SETTINGS_FILE" 2>/dev/null; then
            print_success "Cache keepalive command found in PostToolUse hook"
        fi
    else
        print_error "PostToolUse hook not found in settings.json"
        print_status "Run optimize-claude.sh to install hooks"
        return 1
    fi

    echo ""
    print_success "Hooks are configured!"
    return 0
}

# Verify hook execution
verify_hook_execution() {
    print_header "Verifying Hook Execution"

    # First check if hooks are configured
    if ! check_hooks_configured; then
        return 1
    fi

    echo ""
    echo -e "${BOLD}Verification Methods:${NC}"
    echo ""

    # Method 1: Check for resized image
    echo -e "${CYAN}Method 1: Check for Resized Image${NC}"
    echo "The PreToolUse hook should create resized images in /tmp/"
    echo ""
    echo "Check for resized files:"
    echo "  ${CYAN}ls -la /tmp/resized_*.png 2>/dev/null || echo 'No resized files found'${NC}"
    echo ""

    local resized_count=$(ls /tmp/resized_* 2>/dev/null | wc -l)
    if [[ $resized_count -gt 0 ]]; then
        print_success "Found $resized_count resized file(s) in /tmp/"
        ls -la /tmp/resized_* 2>/dev/null | head -5
    else
        print_warning "No resized files found in /tmp/"
        echo "  The PreToolUse hook may not have fired yet"
    fi

    echo ""

    # Method 2: Check temp directory activity
    echo -e "${CYAN}Method 2: Check Temp Directory${NC}"
    echo "Look for files created by Claude Code hooks:"
    echo ""
    echo "Recent files in /tmp:"
    ls -lt /tmp/ 2>/dev/null | head -10 | while read -r line; do
        echo "  $line"
    done

    echo ""

    # Method 3: Check settings.json content
    echo -e "${CYAN}Method 3: Hook Configuration Details${NC}"
    echo "Current hook configuration:"
    echo ""
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        local py_cmd=$(command -v python3 >/dev/null 2>&1 && echo "python3" || echo "python")
        $py_cmd << 'PYTHON_EOF' 2>/dev/null
import json
import sys
import os
try:
    settings_path = os.path.expanduser('~/.claude/settings.json')
    with open(settings_path, 'r') as f:
        config = json.load(f)
    
    hooks = config.get('hooks', {})
    
    print("PreToolUse hooks:")
    for hook in hooks.get('PreToolUse', []):
        print(f"  Matcher: {hook.get('matcher', 'N/A')}")
        for h in hook.get('hooks', []):
            print(f"    Type: {h.get('type', 'N/A')}")
            print(f"    Condition: {h.get('if', 'N/A')}")
            cmd = h.get('command', '')
            if 'resize' in cmd:
                print(f"    Action: Image resize ✓")
    
    print("\nPostToolUse hooks:")
    for hook in hooks.get('PostToolUse', []):
        print(f"  Matcher: {hook.get('matcher', 'N/A')}")
        for h in hook.get('hooks', []):
            print(f"    Type: {h.get('type', 'N/A')}")
            cmd = h.get('command', '')
            if 'cache_keepalive' in cmd or 'keepalive' in cmd:
                print(f"    Action: Cache keepalive ✓")
except Exception as e:
    print(f"Error: {e}")
PYTHON_EOF
    else
        echo "  (Python not available for detailed output)"
    fi

    echo ""
    echo -e "${BOLD}How to Test:${NC}"
    echo ""
    echo "1. Ensure test files exist:"
    echo "   ${CYAN}./monitor-hooks.sh --test${NC}"
    echo ""
    echo "2. In Claude Code, run:"
    echo "   ${CYAN}Read $TEST_FILES_DIR/test-image.png${NC}"
    echo ""
    echo "3. Immediately check for resized image:"
    echo "   ${CYAN}ls -la /tmp/resized_*.png${NC}"
    echo ""
    echo "4. If the file exists, the PreToolUse hook fired and resized the image!"
    echo ""
    echo "5. Run any command in Claude Code (like 'ls') and watch for"
    echo "   cache_keepalive output - that means PostToolUse fired."
}

# Show test instructions
show_test_instructions() {
    print_header "Hook Testing Instructions"

    # Create test files if needed
    if [[ ! -d "$TEST_FILES_DIR" ]]; then
        print_status "Creating test files first..."
        create_test_files
    fi

    # Check if hooks are configured
    check_hooks_configured

    echo ""
    echo -e "${BOLD}To verify hooks are triggered by Claude Code:${NC}"
    echo ""
    echo "1. ${BOLD}Ensure hooks are installed:${NC}"
    echo "   Run optimize-claude.sh first (if you haven't already)"
    echo ""
    echo "2. ${BOLD}Restart Claude Code completely${NC} (close and reopen the application)"
    echo ""
    echo "3. ${BOLD}Test PreToolUse hook (image processing):${NC}"
    echo "   In Claude Code, run:"
    echo "   ${CYAN}Read $TEST_FILES_DIR/test-image.png${NC}"
    echo ""
    echo "   This should trigger the PreToolUse hook which will:"
    echo "   • Resize the image to max 2000x2000"
    echo "   • Save it to /tmp/resized_test-image.png"
    echo ""
    echo "4. ${BOLD}Verify PreToolUse hook fired:${NC}"
    echo "   In your terminal, run:"
    echo "   ${CYAN}ls -la /tmp/resized_*.png${NC}"
    echo ""
    echo "   If you see /tmp/resized_test-image.png, the hook worked!"
    echo ""
    echo "5. ${BOLD}Test PostToolUse hook (cache keepalive):${NC}"
    echo "   Run any command in Claude Code, such as:"
    echo "   ${CYAN}ls${NC}"
    echo ""
    echo "   Look for JSON output with cache_keepalive in Claude's response."
    echo "   This confirms PostToolUse is firing after every tool use."
    echo ""
    echo "6. ${BOLD}Check hook configuration:${NC}"
    echo "   ./monitor-hooks.sh --verify"
    echo ""
    echo -e "${BOLD}Test files available:${NC}"
    ls -la "$TEST_FILES_DIR" 2>/dev/null || print_warning "Test files not found"
}

# Reset - clean up test files
reset_test_files() {
    print_header "Cleaning Up Test Files"

    if [[ -d "$TEST_FILES_DIR" ]]; then
        rm -rf "$TEST_FILES_DIR"
        print_success "Removed test files directory"
    else
        print_warning "No test files to clean up"
    fi

    # Also clean up any resized images in /tmp
    if ls /tmp/resized_* 2>/dev/null; then
        rm -f /tmp/resized_*
        print_success "Cleaned up resized images in /tmp"
    fi

    echo ""
    print_success "Cleanup complete!"
    echo ""
    echo -e "${BOLD}Note:${NC} This only removes test files, not the hooks."
    echo "The hooks remain active in ~/.claude/settings.json"
}

# Main function
main() {
    case "${1:-}" in
        --test)
            show_test_instructions
            ;;
        --verify)
            verify_hook_execution
            ;;
        --reset)
            reset_test_files
            ;;
        --help|-h)
            show_help
            ;;
        "")
            show_help
            ;;
        *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main
main "$@"
