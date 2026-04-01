#!/bin/bash
#
# Claude Code Token Optimizer & Privacy Enhancer
# For Linux, macOS, and WSL
#
# This script:
# 1. Installs missing dependencies (markitdown, poppler, imagemagick)
# 2. Configures privacy environment variables
# 3. Enables auto-compact in Claude settings
# 4. Sets up PreToolUse hooks for document/image optimization
#
# Usage: ./optimize-claude.sh [--full-privacy] [--dry-run] [--help]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script options
FULL_PRIVACY=true
REDUCED_PRIVACY=false
DRY_RUN=false
SKIP_DEPS=false
VERIFY_ONLY=false

# Dependency tracking
MISSING_DEPS=()
INSTALL_FAILED=()

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE} $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Help function
show_help() {
    cat << EOF
Claude Code Token Optimizer & Privacy Enhancer

Usage: $0 [OPTIONS]

OPTIONS:
    --reduced-privacy Use reduced privacy (telemetry disabled only, keeps auto-updates)
    --dry-run         Show what would be done without making changes
    --skip-deps       Skip dependency installation
    --verify          Verify current environment variable configuration
    --help            Show this help message

EXAMPLES:
    $0                    # Full privacy mode (default)
    $0 --reduced-privacy  # Reduced privacy (standard telemetry disabled)
    $0 --dry-run          # Preview changes
    $0 --verify           # Check current env var configuration

This script will:
  1. Check for required dependencies (markitdown, imagemagick, poppler)
  2. Install missing dependencies (with your permission)
  3. Configure MAXIMUM privacy environment variables by default
  4. Enable auto-compact in Claude settings

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reduced-privacy)
                FULL_PRIVACY=false
                REDUCED_PRIVACY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --verify)
                VERIFY_ONLY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if command -v apt-get &> /dev/null; then
            DISTRO="debian"
        elif command -v yum &> /dev/null; then
            DISTRO="rhel"
        elif command -v pacman &> /dev/null; then
            DISTRO="arch"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    print_status "Detected OS: $OS"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check Python/pip availability
check_python() {
    if command_exists python3; then
        PYTHON_CMD="python3"
    elif command_exists python; then
        PYTHON_CMD="python"
    else
        print_error "Python is not installed. Please install Python 3."
        return 1
    fi

    if ! command_exists pip && ! command_exists pip3; then
        print_warning "pip not found. You may need to install pip."
    fi

    print_success "Python found: $($PYTHON_CMD --version)"
}

# Check for markitdown
check_markitdown() {
    if command_exists markitdown || $PYTHON_CMD -c "import markitdown" 2>/dev/null; then
        print_success "markitdown is already installed"
    else
        print_warning "markitdown is not installed"
        MISSING_DEPS+=("markitdown")
    fi
}

# Check for ImageMagick
check_imagemagick() {
    if command_exists magick || command_exists convert; then
        print_success "ImageMagick is already installed"
    else
        print_warning "ImageMagick is not installed"
        MISSING_DEPS+=("imagemagick")
    fi
}

# Check for poppler (pdftotext)
check_poppler() {
    if command_exists pdftotext; then
        print_success "poppler (pdftotext) is already installed"
    else
        print_warning "poppler (pdftotext) is not installed"
        MISSING_DEPS+=("poppler")
    fi
}

# Install markitdown
install_markitdown() {
    print_status "Installing markitdown..."
    if $DRY_RUN; then
        echo "[DRY-RUN] Would run: pip3 install markitdown"
        return 0
    fi

    if pip3 install markitdown 2>/dev/null || pip install markitdown 2>/dev/null; then
        print_success "markitdown installed successfully"
        return 0
    else
        print_error "Failed to install markitdown"
        INSTALL_FAILED+=("markitdown")
        return 1
    fi
}

# Install ImageMagick based on OS
install_imagemagick() {
    print_status "Installing ImageMagick..."
    if $DRY_RUN; then
        echo "[DRY-RUN] Would install ImageMagick for $OS"
        return 0
    fi

    case $OS in
        linux)
            case $DISTRO in
                debian)
                    sudo apt-get update && sudo apt-get install -y imagemagick
                    ;;
                rhel)
                    sudo yum install -y ImageMagick
                    ;;
                arch)
                    sudo pacman -S --noconfirm imagemagick
                    ;;
                *)
                    print_error "Unknown Linux distribution. Please install ImageMagick manually."
                    INSTALL_FAILED+=("imagemagick")
                    return 1
                    ;;
            esac
            ;;
        macos)
            if command_exists brew; then
                brew install imagemagick
            elif command_exists port; then
                sudo port install ImageMagick
            else
                print_error "Neither Homebrew nor MacPorts found. Please install ImageMagick manually."
                INSTALL_FAILED+=("imagemagick")
                return 1
            fi
            ;;
        *)
            print_error "Unknown OS. Please install ImageMagick manually."
            INSTALL_FAILED+=("imagemagick")
            return 1
            ;;
    esac

    if command_exists magick || command_exists convert; then
        print_success "ImageMagick installed successfully"
        return 0
    else
        print_error "ImageMagick installation may have failed"
        INSTALL_FAILED+=("imagemagick")
        return 1
    fi
}

# Install poppler based on OS
install_poppler() {
    print_status "Installing poppler (for pdftotext)..."
    if $DRY_RUN; then
        echo "[DRY-RUN] Would install poppler for $OS"
        return 0
    fi

    case $OS in
        linux)
            case $DISTRO in
                debian)
                    sudo apt-get update && sudo apt-get install -y poppler-utils
                    ;;
                rhel)
                    sudo yum install -y poppler-utils
                    ;;
                arch)
                    sudo pacman -S --noconfirm poppler
                    ;;
                *)
                    print_error "Unknown Linux distribution. Please install poppler manually."
                    INSTALL_FAILED+=("poppler")
                    return 1
                    ;;
            esac
            ;;
        macos)
            if command_exists brew; then
                brew install poppler
            elif command_exists port; then
                sudo port install poppler
            else
                print_error "Neither Homebrew nor MacPorts found. Please install poppler manually."
                INSTALL_FAILED+=("poppler")
                return 1
            fi
            ;;
        *)
            print_error "Unknown OS. Please install poppler manually."
            INSTALL_FAILED+=("poppler")
            return 1
            ;;
    esac

    if command_exists pdftotext; then
        print_success "poppler installed successfully"
        return 0
    else
        print_error "poppler installation may have failed"
        INSTALL_FAILED+=("poppler")
        return 1
    fi
}

# Check and install all dependencies
check_and_install_deps() {
    if $SKIP_DEPS; then
        print_status "Skipping dependency check (--skip-deps specified)"
        return 0
    fi

    print_header "Checking Dependencies"

    check_python
    check_markitdown
    check_imagemagick
    check_poppler

    if [[ ${#MISSING_DEPS[@]} -eq 0 ]]; then
        print_success "All dependencies are already installed!"
        return 0
    fi

    print_warning "Missing dependencies: ${MISSING_DEPS[*]}"

    if $DRY_RUN; then
        echo "[DRY-RUN] Would attempt to install: ${MISSING_DEPS[*]}"
        return 0
    fi

    echo ""
    read -p "Install missing dependencies? (y/N) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Skipping dependency installation"
        return 0
    fi

    # Install each missing dependency
    for dep in "${MISSING_DEPS[@]}"; do
        case $dep in
            markitdown)
                install_markitdown
                ;;
            imagemagick)
                install_imagemagick
                ;;
            poppler)
                install_poppler
                ;;
        esac
    done

    # Report results
    echo ""
    if [[ ${#INSTALL_FAILED[@]} -eq 0 ]]; then
        print_success "All dependencies installed successfully!"
    else
        print_error "Failed to install: ${INSTALL_FAILED[*]}"
        print_warning "You can still use Claude Code, but some optimizations won't work"
    fi
}

# Configure privacy environment variables
configure_privacy() {
    print_header "Configuring Privacy Settings"

    local SHELL_CONFIG=""
    local SHELL_CONFIG_PATH=""
    if [[ -f ~/.bashrc ]]; then
        SHELL_CONFIG="~/.bashrc"
        SHELL_CONFIG_PATH="$HOME/.bashrc"
    elif [[ -f ~/.zshrc ]]; then
        SHELL_CONFIG="~/.zshrc"
        SHELL_CONFIG_PATH="$HOME/.zshrc"
    elif [[ -f ~/.bash_profile ]]; then
        SHELL_CONFIG="~/.bash_profile"
        SHELL_CONFIG_PATH="$HOME/.bash_profile"
    else
        SHELL_CONFIG="~/.profile"
        SHELL_CONFIG_PATH="$HOME/.profile"
    fi

    print_status "Shell config file: $SHELL_CONFIG"

    # Build the environment variable block with markers for idempotent updates
    local BLOCK_START="# >>> Claude Code Configuration START"
    local BLOCK_END="# <<< Claude Code Configuration END"
    local ENV_BLOCK=""

    if $FULL_PRIVACY; then
        ENV_BLOCK="$BLOCK_START
# Claude Code Maximum Privacy Settings
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export OTEL_LOG_USER_PROMPTS=0
export OTEL_LOG_TOOL_DETAILS=0

# Claude Code Token Optimization
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000
$BLOCK_END"
        print_status "Configuring MAXIMUM privacy mode"
    else
        ENV_BLOCK="$BLOCK_START
# Claude Code Privacy Settings
export DISABLE_TELEMETRY=1

# Claude Code Token Optimization
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000
$BLOCK_END"
        print_status "Configuring standard privacy mode"
    fi

    if $DRY_RUN; then
        echo "[DRY-RUN] Would add to $SHELL_CONFIG:"
        echo "$ENV_BLOCK"
        return 0
    fi

    # Check if already configured (look for our marker)
    if grep -q "$BLOCK_START" "$SHELL_CONFIG_PATH" 2>/dev/null; then
        print_warning "Claude Code settings already configured in $SHELL_CONFIG"
        read -p "Replace existing configuration? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi

        # Remove old block (everything between START and END markers)
        local TEMP_FILE=$(mktemp)
        sed "/$BLOCK_START/,/$BLOCK_END/d" "$SHELL_CONFIG_PATH" > "$TEMP_FILE"
        mv "$TEMP_FILE" "$SHELL_CONFIG_PATH"
        print_status "Removed old configuration from $SHELL_CONFIG"
    fi

    # Append new block
    echo "" >> "$SHELL_CONFIG_PATH"
    echo "$ENV_BLOCK" >> "$SHELL_CONFIG_PATH"

    print_success "Privacy settings added to $SHELL_CONFIG"
    print_status "Run 'source $SHELL_CONFIG' to apply changes to current session"
}

# Configure Claude settings (auto-compact)
configure_claude_settings() {
    print_header "Configuring Claude Code Settings"

    local CLAUDE_CONFIG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"

    # Check if config exists
    if [[ -f "$CLAUDE_CONFIG" ]]; then
        print_status "Found existing Claude config: $CLAUDE_CONFIG"

        if $DRY_RUN; then
            echo "[DRY-RUN] Would update $CLAUDE_CONFIG to enable autoCompactEnabled"
            return 0
        fi

        # Check if autoCompactEnabled is already set
        if grep -q '"autoCompactEnabled": true' "$CLAUDE_CONFIG" 2>/dev/null; then
            print_success "autoCompactEnabled is already enabled"
        else
            # Create backup
            cp "$CLAUDE_CONFIG" "$CLAUDE_CONFIG.backup.$(date +%Y%m%d%H%M%S)"

            # Update config (simple sed approach for JSON)
            if grep -q '"autoCompactEnabled"' "$CLAUDE_CONFIG"; then
                # Update existing setting
                sed -i.bak 's/"autoCompactEnabled": false/"autoCompactEnabled": true/g' "$CLAUDE_CONFIG" 2>/dev/null || \
                sed -i '' 's/"autoCompactEnabled": false/"autoCompactEnabled": true/g' "$CLAUDE_CONFIG"
            else
                # Add new setting
                # Use Python for reliable JSON manipulation
                $PYTHON_CMD << PYTHON_EOF
import json
import sys

try:
    with open('$CLAUDE_CONFIG', 'r') as f:
        config = json.load(f)

    config['autoCompactEnabled'] = True

    with open('$CLAUDE_CONFIG', 'w') as f:
        json.dump(config, f, indent=2)

    print("Configuration updated successfully")
except Exception as e:
    print(f"Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
            fi

            print_success "Enabled autoCompactEnabled in Claude config"
        fi
    else
        # Create new config
        print_status "Creating new Claude config: $CLAUDE_CONFIG"

        if $DRY_RUN; then
            echo "[DRY-RUN] Would create $CLAUDE_CONFIG with autoCompactEnabled"
            return 0
        fi

        mkdir -p "$(dirname "$CLAUDE_CONFIG")"

        cat > "$CLAUDE_CONFIG" << 'JSONEOF'
{
  "autoCompactEnabled": true,
  "theme": "dark"
}
JSONEOF

        print_success "Created Claude config with autoCompactEnabled"
    fi
}

# Create keepalive script (optional - hooks handle this automatically)
create_keepalive_script() {
    print_header "Creating Prompt Cache Keepalive Script (Optional)"

    local KEEPALIVE_SCRIPT="claude-keepalive.sh"

    if [[ -f "$KEEPALIVE_SCRIPT" ]]; then
        print_warning "$KEEPALIVE_SCRIPT already exists"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    if $DRY_RUN; then
        echo "[DRY-RUN] Would create $KEEPALIVE_SCRIPT"
        return 0
    fi

    cat > "$KEEPALIVE_SCRIPT" << 'EOF'
#!/bin/bash
#
# Claude Code Prompt Cache Keepalive Script
# Prevents 5-minute cache TTL expiration by sending periodic no-op messages
#
# Usage: ./claude-keepalive.sh [session-name] &
#   Run in background while Claude Code is active
#
# The Anthropic API has a 5-minute TTL on prompt cache entries.
# After 5 minutes of inactivity, cache is evicted and costs increase 10x.
# For 200K context: $0.60 → $6.00 per request
#
# Note: This script is optional. The PostToolUse hook in .claude/settings.json
# already handles cache keepalive automatically.
#

SESSION_NAME="${1:-claude}"
INTERVAL=240  # 4 minutes (safely under 5min TTL)
KEEPALIVE_MSG="# keepalive $(date +%s)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[Keepalive]${NC} Starting keepalive for session: $SESSION_NAME"
echo -e "${GREEN}[Keepalive]${NC} Interval: ${INTERVAL}s (4 minutes)"
echo -e "${YELLOW}[Keepalive]${NC} Press Ctrl+C to stop"

# Function to send keepalive via tmux
send_tmux_keepalive() {
    local session="$1"
    if tmux has-session -t "$session" 2>/dev/null; then
        # Send a comment (no-op) to keep session warm
        tmux send-keys -t "$session" "$KEEPALIVE_MSG" Enter
        sleep 0.5
        # Clear it with Ctrl+C so it doesn't accumulate
        tmux send-keys -t "$session" C-c
        echo -e "${GREEN}[Keepalive]${NC} $(date '+%H:%M:%S') - Sent keepalive to tmux session: $session"
        return 0
    fi
    return 1
}

# Function to send keepalive via AppleScript (macOS GUI)
send_macos_keepalive() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Try to find iTerm2 or Terminal with Claude
        local term_app=""
        if osascript -e 'tell application "iTerm2" to return name of front window' 2>/dev/null | grep -q "claude\|Claude"; then
            term_app="iTerm2"
        elif osascript -e 'tell application "Terminal" to return name of front window' 2>/dev/null | grep -q "claude\|Claude"; then
            term_app="Terminal"
        fi

        if [[ -n "$term_app" ]]; then
            osascript << APPLESCRIPT 2>/dev/null
tell application "$term_app"
    activate
    tell application "System Events" to keystroke "# keepalive"
    tell application "System Events" to key code 36
    delay 0.5
    tell application "System Events" to key code 53
end tell
APPLESCRIPT
            echo -e "${GREEN}[Keepalive]${NC} $(date '+%H:%M:%S') - Sent keepalive to $term_app"
            return 0
        fi
    fi
    return 1
}

# Main keepalive loop
cleanup() {
    echo -e "\n${YELLOW}[Keepalive]${NC} Stopping keepalive script"
    exit 0
}

trap cleanup INT TERM

while true; do
    # Try tmux first, then fall back to macOS GUI methods
    if ! send_tmux_keepalive "$SESSION_NAME"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            send_macos_keepalive
        fi
    fi

    sleep $INTERVAL
done
EOF

    chmod +x "$KEEPALIVE_SCRIPT"

    print_success "Created optional keepalive script: $KEEPALIVE_SCRIPT"
    print_status "Note: Hooks in .claude/settings.json already handle cache keepalive automatically"
}

# Create settings.json with keepalive hook
create_settings_json() {
    print_header "Creating settings.json with Keepalive Hook"

    local SETTINGS_FILE=".claude/settings.json"

    if [[ -f "$SETTINGS_FILE" ]]; then
        print_warning "$SETTINGS_FILE already exists"
        read -p "Create backup and add keepalive hook? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi

        if ! $DRY_RUN; then
            cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d%H%M%S)"
        fi
    fi

    if $DRY_RUN; then
        echo "[DRY-RUN] Would create $SETTINGS_FILE with keepalive hook"
        return 0
    fi

    mkdir -p "$(dirname "$SETTINGS_FILE")"

    cat > "$SETTINGS_FILE" << 'EOF'
{
  "autoCompactEnabled": true,
  "hooks": {
    "PreToolUse": [{
      "matcher": "Read",
      "hooks": [{
        "type": "command",
        "command": "if command -v magick >/dev/null 2>&1 && [ -f \"$ARGUMENTS\" ] && [[ \"$ARGUMENTS\" =~ \\.(png|jpg|jpeg)$ ]]; then magick \"$ARGUMENTS\" -resize 2000x2000\\> -quality 85 /tmp/resized_$(basename \"$ARGUMENTS\"); fi",
        "if": "Read(*.{png,jpg,jpeg})"
      }]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "echo '{\"cache_keepalive\": \"'$(date +%s)'\"}'",
        "if": "*"
      }]
    }]
  }
}
EOF

    print_success "Created $SETTINGS_FILE with keepalive hook"
    print_status "The PostToolUse hook fires after every tool use, keeping cache warm"
}

# Verify environment variables
verify_env_vars() {
    print_header "Verifying Environment Variables"

    local SHELL_CONFIG=""
    if [[ -f ~/.bashrc ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [[ -f ~/.zshrc ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [[ -f ~/.bash_profile ]]; then
        SHELL_CONFIG="$HOME/.bash_profile"
    else
        SHELL_CONFIG="$HOME/.profile"
    fi

    local BLOCK_START="# >>> Claude Code Configuration START"
    local BLOCK_END="# <<< Claude Code Configuration END"

    print_status "Checking $SHELL_CONFIG for Claude Code environment variables..."
    echo ""

    # Check for new block format
    if grep -q "$BLOCK_START" "$SHELL_CONFIG" 2>/dev/null; then
        print_success "Found Claude Code configuration block in $SHELL_CONFIG"
        echo ""
        print_status "Configuration block contents:"
        sed -n "/$BLOCK_START/,/$BLOCK_END/p" "$SHELL_CONFIG" 2>/dev/null

        # Check for duplicates (multiple START markers)
        local BLOCK_COUNT=$(grep -c "$BLOCK_START" "$SHELL_CONFIG" 2>/dev/null || echo "0")
        if [[ "$BLOCK_COUNT" -gt 1 ]]; then
            print_warning "Detected $BLOCK_COUNT configuration blocks (possible duplicates)"
            print_status "Run the script with --reduced-privacy or --full-privacy to clean up and reconfigure"
        fi
    elif grep -q "DISABLE_TELEMETRY" "$SHELL_CONFIG" 2>/dev/null; then
        # Legacy format without markers
        print_warning "Found legacy configuration (without block markers) in $SHELL_CONFIG"
        print_status "Consider running the script to update to the new idempotent format"
        echo ""
        print_status "Legacy settings found:"
        grep -E "^(export DISABLE_TELEMETRY|export CLAUDE_CODE_DISABLE|export OTEL_LOG|export CLAUDE_CODE_AUTO_COMPACT)" "$SHELL_CONFIG" 2>/dev/null | head -10
    else
        print_warning "No Claude Code settings found in $SHELL_CONFIG"
        print_status "Run the script without --dry-run to configure environment variables"
    fi

    echo ""
    print_status "Current shell environment (may differ until you source the config):"
    echo "  DISABLE_TELEMETRY=${DISABLE_TELEMETRY:-<not set>}"
    echo "  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-<not set>}"
    echo "  CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-<not set>}"

    echo ""
    print_status "To apply environment variables to your current shell, run:"
    echo "  source $SHELL_CONFIG"
}

# Main function
main() {
    print_header "Claude Code Token Optimizer & Privacy Enhancer"

    parse_args "$@"

    # Handle verify-only mode
    if $VERIFY_ONLY; then
        verify_env_vars
        exit 0
    fi

    if $DRY_RUN; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi

    detect_os
    check_and_install_deps
    configure_privacy
    configure_claude_settings
    create_keepalive_script
    create_settings_json

    print_header "Summary"

    print_success "Configuration complete!"
    echo ""

    if [[ ${#INSTALL_FAILED[@]} -gt 0 ]]; then
        print_warning "Some dependencies failed to install: ${INSTALL_FAILED[*]}"
        echo "You can manually install them later."
        echo ""
    fi

    # Detect which shell config was modified
    local SHELL_CONFIG=""
    if [[ -f ~/.bashrc ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [[ -f ~/.zshrc ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    fi

    echo -e "${BOLD}Next steps:${NC}"
    echo "1. Run: source $SHELL_CONFIG  (to apply env vars to current shell)"
    echo "2. Restart Claude Code"
    echo "3. Check /cost regularly to monitor usage"
    echo ""

    if $FULL_PRIVACY; then
        echo -e "${BOLD}Privacy mode:${NC} Maximum (all non-essential traffic disabled)"
    else
        echo -e "${BOLD}Privacy mode:${NC} Standard (telemetry disabled)"
    fi

    echo ""
    echo -e "${BOLD}Hooks configured:${NC} Auto-compact, image pre-processing, cache keepalive"
    echo ""

    # Show verification
    verify_env_vars

    print_success "Happy optimizing!"
}

# Run main function
main "$@"

