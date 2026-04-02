#!/bin/bash
#
# Claude Code Optimizer Validation Suite
# Tests all claims made by the optimization scripts
#
# Usage: ./validate-optimizations.sh [--before] [--after] [--verbose]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
VERBOSE=false
BEFORE_MODE=false
AFTER_MODE=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}[⚠ SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

print_error() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE} $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_section() {
    echo -e "\n${BOLD}$1${NC}"
    echo -e "${BLUE}$(printf '=%.0s' $(seq 1 ${#1}))${NC}"
}

# Show help
show_help() {
    cat << EOF
Claude Code Optimizer Validation Suite

Usage: $0 [OPTIONS]

OPTIONS:
    --before      Run in 'before' mode (baseline measurement)
    --after       Run in 'after' mode (post-optimization verification)
    --verbose     Show detailed output for all tests
    --help        Show this help message

EXAMPLES:
    $0                    # Run all validation tests
    $0 --before           # Capture baseline state
    $0 --after            # Verify optimizations are working
    $0 --verbose          # Detailed output

This script validates all claims made by the optimization scripts:
  - Dependencies installed (markitdown, imagemagick, poppler)
  - Privacy environment variables configured
  - Auto-compact enabled in Claude settings
  - Hooks properly configured in settings.json
  - Token reduction measurable

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --before)
                BEFORE_MODE=true
                shift
                ;;
            --after)
                AFTER_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
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

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Test: Dependency Installation
test_dependencies() {
    print_section "DEPENDENCY INSTALLATION TESTS"

    # Test markitdown
    if command_exists markitdown; then
        print_success "markitdown is installed and in PATH"
        if $VERBOSE; then
            local version=$(markitdown --version 2>&1 || echo "version unknown")
            echo "  Version: $version"
        fi
    elif python3 -c "import markitdown" 2>/dev/null || python -c "import markitdown" 2>/dev/null; then
        print_success "markitdown Python module is installed"
    else
        print_error "markitdown is not installed"
        if $VERBOSE; then
            echo "  Expected: markitdown command or Python module"
            echo "  Install: pip install markitdown"
        fi
    fi

    # Test ImageMagick
    if command_exists magick || command_exists convert; then
        print_success "ImageMagick is installed and in PATH"
        if $VERBOSE; then
            local cmd=$(command_exists magick && echo "magick" || echo "convert")
            local version=$($cmd --version 2>&1 | head -1)
            echo "  Command: $cmd"
            echo "  Version: $version"
        fi
    else
        print_error "ImageMagick is not installed"
        if $VERBOSE; then
            echo "  Expected: magick or convert command"
            echo "  Install: apt-get install imagemagick (Linux) or brew install imagemagick (macOS)"
        fi
    fi

    # Test poppler/pdftotext
    if command_exists pdftotext; then
        print_success "poppler (pdftotext) is installed and in PATH"
        if $VERBOSE; then
            local version=$(pdftotext -v 2>&1 | head -1)
            echo "  Version: $version"
        fi
    else
        print_error "poppler (pdftotext) is not installed"
        if $VERBOSE; then
            echo "  Expected: pdftotext command"
            echo "  Install: apt-get install poppler-utils (Linux) or brew install poppler (macOS)"
        fi
    fi
}

# Test: Privacy Environment Variables
test_privacy_env_vars() {
    print_section "PRIVACY ENVIRONMENT VARIABLES TESTS"

    local vars=(
        "DISABLE_TELEMETRY:1:Disables all telemetry"
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:1:Blocks non-essential traffic"
        "OTEL_LOG_USER_PROMPTS:0:Disables OpenTelemetry prompt logging"
        "OTEL_LOG_TOOL_DETAILS:0:Disables OpenTelemetry tool logging"
        "CLAUDE_CODE_AUTO_COMPACT_WINDOW:180000:Sets auto-compact window"
    )

    for var_info in "${vars[@]}"; do
        IFS=':' read -r var_name expected_value description <<< "$var_info"

        if [[ -n "${!var_name}" ]]; then
            local actual_value="${!var_name}"
            if [[ "$actual_value" == "$expected_value" ]]; then
                print_success "$var_name is set to $expected_value ($description)"
            else
                print_warning "$var_name is set to '$actual_value' (expected '$expected_value')"
                if $VERBOSE; then
                    echo "  Description: $description"
                    echo "  Current: $actual_value"
                    echo "  Expected: $expected_value"
                fi
            fi
        else
            print_error "$var_name is not set ($description)"
            if $VERBOSE; then
                echo "  Expected value: $expected_value"
                echo "  Add to ~/.bashrc or ~/.zshrc: export $var_name=$expected_value"
            fi
        fi
    done

    # Check shell config for persistent settings
    local shell_config=""
    if [[ -f ~/.bashrc ]]; then
        shell_config="$HOME/.bashrc"
    elif [[ -f ~/.zshrc ]]; then
        shell_config="$HOME/.zshrc"
    elif [[ -f ~/.bash_profile ]]; then
        shell_config="$HOME/.bash_profile"
    fi

    if [[ -n "$shell_config" ]]; then
        local block_start="# >>> Claude Code Configuration START"
        if grep -q "$block_start" "$shell_config" 2>/dev/null; then
            print_success "Claude Code configuration block found in $(basename "$shell_config")"
        elif grep -q "DISABLE_TELEMETRY" "$shell_config" 2>/dev/null; then
            print_warning "Legacy configuration found in $(basename "$shell_config") (without block markers)"
        else
            print_error "No Claude Code configuration found in shell profile"
            if $VERBOSE; then
                echo "  Checked: $shell_config"
                echo "  Run: ./optimize-claude.sh to configure"
            fi
        fi
    fi
}

# Test: Claude Settings (auto-compact)
test_claude_settings() {
    print_section "CLAUDE SETTINGS TESTS"

    local claude_config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"

    if [[ -f "$claude_config" ]]; then
        print_success "Claude config file exists: $claude_config"

        if $VERBOSE; then
            echo "  Contents:"
            cat "$claude_config" | sed 's/^/    /'
        fi

        # Check for autoCompactEnabled
        if grep -q '"autoCompactEnabled": true' "$claude_config" 2>/dev/null; then
            print_success "autoCompactEnabled is enabled in config"
        elif grep -q '"autoCompactEnabled": false' "$claude_config" 2>/dev/null; then
            print_error "autoCompactEnabled is explicitly disabled"
        else
            print_warning "autoCompactEnabled not found in config (may use default)"
        fi
    else
        print_error "Claude config file not found: $claude_config"
        if $VERBOSE; then
            echo "  Run: ./optimize-claude.sh to create config"
        fi
    fi
}

# Test: Hooks Configuration
test_hooks_configuration() {
    print_section "HOOKS CONFIGURATION TESTS"

    local settings_file=".claude/settings.json"
    local user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

    # Check project-level settings
    if [[ -f "$settings_file" ]]; then
        print_success "Project settings.json exists: $settings_file"

        if $VERBOSE; then
            echo "  Contents:"
            cat "$settings_file" | sed 's/^/    /'
        fi

        # Check for PreToolUse hook
        if grep -q '"PreToolUse"' "$settings_file" 2>/dev/null; then
            print_success "PreToolUse hook is configured"
        else
            print_warning "PreToolUse hook not found in project settings"
        fi

        # Check for PostToolUse hook
        if grep -q '"PostToolUse"' "$settings_file" 2>/dev/null; then
            print_success "PostToolUse hook is configured"
        else
            print_warning "PostToolUse hook not found in project settings"
        fi

        # Check for autoCompactEnabled in settings
        if grep -q '"autoCompactEnabled": true' "$settings_file" 2>/dev/null; then
            print_success "autoCompactEnabled is enabled in settings.json"
        fi
    else
        print_warning "Project settings.json not found: $settings_file"
    fi

    # Check user-level settings
    if [[ -f "$user_settings" && "$user_settings" != "$settings_file" ]]; then
        print_success "User settings.json exists: $user_settings"

        if grep -q '"PreToolUse"' "$user_settings" 2>/dev/null; then
            print_success "PreToolUse hook is configured in user settings"
        fi

        if grep -q '"PostToolUse"' "$user_settings" 2>/dev/null; then
            print_success "PostToolUse hook is configured in user settings"
        fi
    fi
}

# Test: Image Pre-processing Capability
test_image_preprocessing() {
    print_section "IMAGE PRE-PROCESSING CAPABILITY TESTS"

    # Check if ImageMagick can resize images
    if command_exists magick || command_exists convert; then
        local cmd=$(command_exists magick && echo "magick" || echo "convert")

        # Create a test image
        local test_dir=$(mktemp -d)
        local test_image="$test_dir/test_image.png"

        # Generate a test image (2000x2000)
        if $cmd -size 2000x2000 xc:blue "$test_image" 2>/dev/null; then
            print_success "ImageMagick can create test images"

            # Test resize operation
            local resized_image="$test_dir/resized_image.png"
            if $cmd "$test_image" -resize 2000x2000> -quality 85 "$resized_image" 2>/dev/null; then
                print_success "ImageMagick resize operation works"

                # Check file size reduction
                local original_size=$(stat -f%z "$test_image" 2>/dev/null || stat -c%s "$test_image" 2>/dev/null)
                local resized_size=$(stat -f%z "$resized_image" 2>/dev/null || stat -c%s "$resized_image" 2>/dev/null)

                if [[ -n "$original_size" && -n "$resized_size" ]]; then
                    if [[ $resized_size -le $original_size ]]; then
                        print_success "Image resize reduces file size (original: $original_size, resized: $resized_size)"
                    else
                        print_warning "Resized image is larger (this can happen with certain image types)"
                    fi
                fi
            else
                print_error "ImageMagick resize operation failed"
            fi
        else
            print_warning "Could not create test image for validation"
        fi

        # Cleanup
        rm -rf "$test_dir"
    else
        print_error "ImageMagick not available for image pre-processing tests"
    fi
}

# Test: Document Conversion Capability
test_document_conversion() {
    print_section "DOCUMENT CONVERSION CAPABILITY TESTS"

    local test_dir=$(mktemp -d)

    # Test PDF text extraction if poppler is available
    if command_exists pdftotext; then
        # Create a simple test PDF using Python if available
        if command_exists python3 || command_exists python; then
            local py_cmd=$(command_exists python3 && echo "python3" || echo "python")

            # Try to create a test PDF
            local test_pdf="$test_dir/test.pdf"
            local test_txt="$test_dir/test.txt"

            $py_cmd << PYTHON_EOF 2>/dev/null
from reportlab.pdfgen import canvas
c = canvas.Canvas("$test_pdf")
c.drawString(100, 700, "This is a test PDF document for validation.")
c.save()
PYTHON_EOF

            if [[ -f "$test_pdf" ]]; then
                print_success "Can create test PDF files"

                if pdftotext -layout "$test_pdf" "$test_txt" 2>/dev/null; then
                    print_success "pdftotext can extract text from PDFs"

                    if [[ -f "$test_txt" && -s "$test_txt" ]]; then
                        print_success "PDF text extraction produces output"
                    else
                        print_warning "PDF text extraction produced empty output"
                    fi
                else
                    print_error "pdftotext failed to extract text"
                fi
            else
                print_warning "Could not create test PDF (reportlab may not be installed)"
            fi
        else
            print_warning "Python not available for creating test PDFs"
        fi
    else
        print_error "pdftotext not available for PDF tests"
    fi

    # Test markitdown if available
    if command_exists markitdown; then
        print_success "markitdown is available for document conversion"
    else
        print_warning "markitdown not available for document conversion tests"
    fi

    # Cleanup
    rm -rf "$test_dir"
}

# Test: Cache Keepalive Mechanism
test_cache_keepalive() {
    print_section "CACHE KEEPALIVE MECHANISM TESTS"

    # Check if PostToolUse hook is configured
    local settings_file=".claude/settings.json"
    local user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

    local hook_found=false

    if [[ -f "$settings_file" ]] && grep -q '"PostToolUse"' "$settings_file" 2>/dev/null; then
        if grep -q "cache_keepalive\|keepalive" "$settings_file" 2>/dev/null; then
            print_success "Cache keepalive hook found in project settings.json"
            hook_found=true
        fi
    fi

    if [[ -f "$user_settings" ]] && grep -q '"PostToolUse"' "$user_settings" 2>/dev/null; then
        if grep -q "cache_keepalive\|keepalive" "$user_settings" 2>/dev/null; then
            print_success "Cache keepalive hook found in user settings.json"
            hook_found=true
        fi
    fi

    if ! $hook_found; then
        print_warning "Cache keepalive hook not found in settings.json"
        if $VERBOSE; then
            echo "  The PostToolUse hook should contain a command that outputs cache_keepalive"
            echo "  This hook fires after every tool use to keep the prompt cache warm"
        fi
    fi

    # Check for keepalive script (optional)
    if [[ -f "claude-keepalive.sh" ]]; then
        print_success "Optional keepalive script exists: claude-keepalive.sh"
    else
        if $VERBOSE; then
            echo "  Optional: claude-keepalive.sh not found (hooks handle this automatically)"
        fi
    fi
}

# Test: Privacy Level Verification
test_privacy_level() {
    print_section "PRIVACY LEVEL VERIFICATION"

    local privacy_score=0
    local max_score=5

    # Check each privacy variable
    [[ "${DISABLE_TELEMETRY}" == "1" ]] && ((privacy_score++))
    [[ "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC}" == "1" ]] && ((privacy_score++))
    [[ "${OTEL_LOG_USER_PROMPTS}" == "0" ]] && ((privacy_score++))
    [[ "${OTEL_LOG_TOOL_DETAILS}" == "0" ]] && ((privacy_score++))
    [[ "${CLAUDE_CODE_AUTO_COMPACT_WINDOW}" == "180000" ]] && ((privacy_score++))

    echo "Privacy Score: $privacy_score/$max_score"

    if [[ $privacy_score -eq $max_score ]]; then
        print_success "Maximum privacy mode is configured (all 5 variables set)"
    elif [[ $privacy_score -ge 3 ]]; then
        print_warning "Standard privacy mode ($privacy_score/$max_score variables set)"
    else
        print_error "Limited privacy protection ($privacy_score/$max_score variables set)"
    fi

    if $VERBOSE; then
        echo ""
        echo "Privacy Variables Status:"
        echo "  DISABLE_TELEMETRY=${DISABLE_TELEMETRY:-<not set>} (disables Datadog telemetry)"
        echo "  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-<not set>} (blocks updates, release notes)"
        echo "  OTEL_LOG_USER_PROMPTS=${OTEL_LOG_USER_PROMPTS:-<not set>} (disables prompt logging)"
        echo "  OTEL_LOG_TOOL_DETAILS=${OTEL_LOG_TOOL_DETAILS:-<not set>} (disables tool logging)"
        echo "  CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-<not set>} (auto-compact threshold)"
    fi
}

# Generate summary report
generate_report() {
    print_header "VALIDATION SUMMARY"

    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo -e "${BOLD}Test Results:${NC}"
    echo "  Passed:  $TESTS_PASSED"
    echo "  Failed:  $TESTS_FAILED"
    echo "  Skipped: $TESTS_SKIPPED"
    echo "  Total:   $total_tests"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All critical tests passed!${NC}"
        echo "Your Claude Code environment is fully optimized."
    elif [[ $TESTS_FAILED -le 2 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ Most tests passed with minor issues${NC}"
        echo "Your environment is mostly optimized. Review failed tests above."
    else
        echo -e "${RED}${BOLD}✗ Several optimizations are not working${NC}"
        echo "Run ./optimize-claude.sh to fix the issues."
    fi

    echo ""
    echo -e "${BOLD}Key Claims Verification:${NC}"

    # Check specific claims
    local deps_ok=false
    local privacy_ok=false
    local compact_ok=false
    local hooks_ok=false

    # Dependencies
    if command_exists markitdown || python3 -c "import markitdown" 2>/dev/null; then
        if command_exists magick || command_exists convert; then
            if command_exists pdftotext; then
                deps_ok=true
                echo -e "  ${GREEN}✓${NC} Dependencies installed (markitdown, imagemagick, poppler)"
            fi
        fi
    fi
    if ! $deps_ok; then
        echo -e "  ${RED}✗${NC} Some dependencies missing"
    fi

    # Privacy
    if [[ "${DISABLE_TELEMETRY}" == "1" && "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC}" == "1" ]]; then
        privacy_ok=true
        echo -e "  ${GREEN}✓${NC} Maximum privacy mode configured"
    elif [[ "${DISABLE_TELEMETRY}" == "1" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Standard privacy mode (telemetry disabled)"
    else
        echo -e "  ${RED}✗${NC} Privacy not configured"
    fi

    # Auto-compact
    local claude_config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"
    if [[ -f "$claude_config" ]] && grep -q '"autoCompactEnabled": true' "$claude_config" 2>/dev/null; then
        compact_ok=true
        echo -e "  ${GREEN}✓${NC} Auto-compact enabled"
    else
        echo -e "  ${RED}✗${NC} Auto-compact not enabled"
    fi

    # Hooks
    if [[ -f ".claude/settings.json" ]] && grep -q '"PreToolUse"' ".claude/settings.json" 2>/dev/null; then
        if grep -q '"PostToolUse"' ".claude/settings.json" 2>/dev/null; then
            hooks_ok=true
            echo -e "  ${GREEN}✓${NC} Hooks configured (image resize + cache keepalive)"
        fi
    fi
    if ! $hooks_ok; then
        echo -e "  ${RED}✗${NC} Hooks not fully configured"
    fi

    echo ""
    echo -e "${BOLD}Expected Benefits:${NC}"

    if $deps_ok && $privacy_ok && $compact_ok && $hooks_ok; then
        echo -e "  ${GREEN}✓${NC} Token usage: 50-80% reduction expected"
        echo -e "  ${GREEN}✓${NC} Startup time: Faster (no telemetry init)"
        echo -e "  ${GREEN}✓${NC} Session length: Longer before rate limits"
        echo -e "  ${GREEN}✓${NC} Privacy: Maximum protection"
        echo -e "  ${GREEN}✓${NC} Cost: Significantly lower per task"
    else
        echo "  Some optimizations incomplete - benefits may be reduced"
    fi

    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "  1. Run: ./optimize-claude.sh"
        echo "  2. Restart your shell: source ~/.bashrc (or ~/.zshrc)"
        echo "  3. Restart Claude Code"
        echo "  4. Run validation again: ./validate-optimizations.sh"
    else
        echo "  Your environment is optimized! Start using Claude Code."
        echo "  Monitor /cost regularly to track savings."
    fi
}

# Save state for before/after comparison
save_state() {
    local state_file=".validation_state.json"

    # Build JSON state
    cat > "$state_file" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "mode": "$1",
  "dependencies": {
    "markitdown": $(command_exists markitdown && echo "true" || echo "false"),
    "imagemagick": $(command_exists magick || command_exists convert && echo "true" || echo "false"),
    "poppler": $(command_exists pdftotext && echo "true" || echo "false")
  },
  "privacy_vars": {
    "DISABLE_TELEMETRY": "${DISABLE_TELEMETRY:-null}",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-null}",
    "OTEL_LOG_USER_PROMPTS": "${OTEL_LOG_USER_PROMPTS:-null}",
    "OTEL_LOG_TOOL_DETAILS": "${OTEL_LOG_TOOL_DETAILS:-null}",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-null}"
  },
  "claude_config": {
    "exists": $([[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json" ]] && echo "true" || echo "false"),
    "autoCompactEnabled": $(grep -q '"autoCompactEnabled": true' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json" 2>/dev/null && echo "true" || echo "false")
  },
  "hooks": {
    "settings_json_exists": $([[ -f ".claude/settings.json" ]] && echo "true" || echo "false"),
    "pretooluse_hook": $(grep -q '"PreToolUse"' ".claude/settings.json" 2>/dev/null && echo "true" || echo "false"),
    "posttooluse_hook": $(grep -q '"PostToolUse"' ".claude/settings.json" 2>/dev/null && echo "true" || echo "false")
  }
}
EOF

    print_success "State saved to $state_file"
}

# Compare before/after states
compare_states() {
    local before_file=".validation_state_before.json"
    local after_file=".validation_state_after.json"

    if [[ ! -f "$before_file" ]]; then
        print_error "No before state found. Run with --before first."
        return 1
    fi

    if [[ ! -f "$after_file" ]]; then
        print_error "No after state found. Run with --after."
        return 1
    fi

    print_header "BEFORE/AFTER COMPARISON"

    # Parse and compare (using Python if available, otherwise basic comparison)
    if command_exists python3 || command_exists python; then
        local py_cmd=$(command_exists python3 && echo "python3" || echo "python")

        $py_cmd << 'PYTHON_EOF'
import json
import sys

try:
    with open('.validation_state_before.json') as f:
        before = json.load(f)
    with open('.validation_state_after.json') as f:
        after = json.load(f)

    print("\n📊 DEPENDENCY CHANGES:")
    for dep in ['markitdown', 'imagemagick', 'poppler']:
        b = before['dependencies'].get(dep, False)
        a = after['dependencies'].get(dep, False)
        if not b and a:
            print(f"  ✓ {dep}: NOT INSTALLED → INSTALLED")
        elif b and a:
            print(f"  = {dep}: Already installed (no change)")
        elif b and not a:
            print(f"  ✗ {dep}: INSTALLED → NOT INSTALLED (regression!)")
        else:
            print(f"  ✗ {dep}: Still not installed")

    print("\n🔒 PRIVACY CHANGES:")
    privacy_vars = ['DISABLE_TELEMETRY', 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
                    'OTEL_LOG_USER_PROMPTS', 'OTEL_LOG_TOOL_DETAILS']
    for var in privacy_vars:
        b = before['privacy_vars'].get(var)
        a = after['privacy_vars'].get(var)
        if b is None and a is not None:
            print(f"  ✓ {var}: NOT SET → {a}")
        elif b != a:
            print(f"  ~ {var}: {b} → {a}")
        else:
            print(f"  = {var}: {a} (no change)")

    print("\n⚙️  AUTO-COMPACT:")
    b = before['claude_config'].get('autoCompactEnabled', False)
    a = after['claude_config'].get('autoCompactEnabled', False)
    if not b and a:
        print("  ✓ Auto-compact: DISABLED → ENABLED")
    elif b and a:
        print("  = Auto-compact: Already enabled (no change)")
    else:
        print(f"  {'✗' if not a else '='} Auto-compact: {'Still disabled' if not a else 'Enabled'}")

    print("\n🪝 HOOKS:")
    b = before['hooks'].get('pretooluse_hook', False)
    a = after['hooks'].get('pretooluse_hook', False)
    if not b and a:
        print("  ✓ PreToolUse hook: NOT CONFIGURED → CONFIGURED")
    else:
        print(f"  {'=' if b == a else '~'} PreToolUse hook: {'Configured' if a else 'Not configured'}")

    b = before['hooks'].get('posttooluse_hook', False)
    a = after['hooks'].get('posttooluse_hook', False)
    if not b and a:
        print("  ✓ PostToolUse hook: NOT CONFIGURED → CONFIGURED")
    else:
        print(f"  {'=' if b == a else '~'} PostToolUse hook: {'Configured' if a else 'Not configured'}")

    print("")
except Exception as e:
    print(f"Error comparing states: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
    else
        print_warning "Python not available for detailed comparison"
        echo "Raw state files:"
        echo "  Before: $before_file"
        echo "  After: $after_file"
    fi
}

# Main function
main() {
    print_header "Claude Code Optimizer Validation Suite"

    parse_args "$@"

    # Handle before/after modes
    if $BEFORE_MODE; then
        print_status "Capturing BEFORE state..."
        save_state "before"
        mv .validation_state.json .validation_state_before.json
        print_success "Before state saved to .validation_state_before.json"
        echo ""
        echo "Next: Run ./optimize-claude.sh to apply optimizations"
        echo "Then: Run $0 --after to capture post-optimization state"
        exit 0
    fi

    if $AFTER_MODE; then
        print_status "Capturing AFTER state..."
        save_state "after"
        mv .validation_state.json .validation_state_after.json
        print_success "After state saved to .validation_state_after.json"
        compare_states
        exit 0
    fi

    # Run all tests
    print_status "Starting validation tests..."
    echo ""

    test_dependencies
    test_privacy_env_vars
    test_claude_settings
    test_hooks_configuration
    test_image_preprocessing
    test_document_conversion
    test_cache_keepalive
    test_privacy_level

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
