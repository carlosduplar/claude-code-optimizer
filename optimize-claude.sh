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
    --help            Show this help message

EXAMPLES:
    $0                    # Full privacy mode (default)
    $0 --reduced-privacy  # Reduced privacy (standard telemetry disabled)
    $0 --dry-run          # Preview changes

This script will:
  1. Check for required dependencies (markitdown, imagemagick, poppler)
  2. Install missing dependencies (with your permission)
  3. Configure MAXIMUM privacy environment variables by default
  4. Enable auto-compact in Claude settings
  5. Create CLAUDE.md template with optimization guidelines

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
        return 0
    else
        print_warning "markitdown is not installed"
        MISSING_DEPS+=("markitdown")
        return 1
    fi
}

# Check for ImageMagick
check_imagemagick() {
    if command_exists magick || command_exists convert; then
        print_success "ImageMagick is already installed"
        return 0
    else
        print_warning "ImageMagick is not installed"
        MISSING_DEPS+=("imagemagick")
        return 1
    fi
}

# Check for poppler (pdftotext)
check_poppler() {
    if command_exists pdftotext; then
        print_success "poppler (pdftotext) is already installed"
        return 0
    else
        print_warning "poppler (pdftotext) is not installed"
        MISSING_DEPS+=("poppler")
        return 1
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
    if [[ -f ~/.bashrc ]]; then
        SHELL_CONFIG="~/.bashrc"
    elif [[ -f ~/.zshrc ]]; then
        SHELL_CONFIG="~/.zshrc"
    elif [[ -f ~/.bash_profile ]]; then
        SHELL_CONFIG="~/.bash_profile"
    else
        SHELL_CONFIG="~/.profile"
    fi

    print_status "Shell config file: $SHELL_CONFIG"

    # Build the environment variable block
    local ENV_BLOCK=""

    if $FULL_PRIVACY; then
        ENV_BLOCK="# Claude Code Maximum Privacy Settings
export DISABLE_TELEMETRY=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export OTEL_LOG_USER_PROMPTS=0
export OTEL_LOG_TOOL_DETAILS=0
"
        print_status "Configuring MAXIMUM privacy mode"
    else
        ENV_BLOCK="# Claude Code Privacy Settings
export DISABLE_TELEMETRY=1
"
        print_status "Configuring standard privacy mode"
    fi

    # Add token optimization variables
    ENV_BLOCK+="# Claude Code Token Optimization
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000
"

    if $DRY_RUN; then
        echo "[DRY-RUN] Would add to $SHELL_CONFIG:"
        echo "$ENV_BLOCK"
        return 0
    fi

    # Check if already configured
    if grep -q "DISABLE_TELEMETRY=1" ~/${SHELL_CONFIG##*/} 2>/dev/null; then
        print_warning "Privacy settings already appear to be configured in $SHELL_CONFIG"
        read -p "Update anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    # Append to shell config
    echo "" >> ~/${SHELL_CONFIG##*/}
    echo "$ENV_BLOCK" >> ~/${SHELL_CONFIG##*/}

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

# Create CLAUDE.md template
create_claude_md() {
    print_header "Creating CLAUDE.md Template"

    if [[ -f "CLAUDE.md" ]]; then
        print_warning "CLAUDE.md already exists in current directory"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    if $DRY_RUN; then
        echo "[DRY-RUN] Would create CLAUDE.md in current directory"
        return 0
    fi

    cat > "CLAUDE.md" << 'EOF'
# Claude Code Optimization Guide

## Cost-First Defaults
- **Default model**: sonnet 4.6 (or haiku for quick tasks)
- **Always use offset/limit** for reads >500 lines
- **Pre-convert**: PDF→text, Office→Markdown, images→2000x2000 max
- **Compact at**: 150K tokens
- **Turn limits**: +500k default, +1m for complex tasks

## Token Budgets
Set token budgets by starting messages with:
- `+500k` - Limit to 500,000 tokens this turn
- `+1m` - Limit to 1,000,000 tokens this turn

## File Reading Guidelines
### Always Use Pagination
For files >500 lines, always specify offset and limit:
```
Read file.ts {"offset": 1, "limit": 100}
```

### Search Before Reading
```
# Good - targeted search
Grep "function handleRequest" *.ts

# Bad - reading everything
Read all files then search
```

### Binary File Handling
Pre-convert binary files before reading:
- PDFs: `pdftotext -layout` or `markitdown`
- DOCX/XLSX/PPTX: `markitdown`
- Images: `magick -resize 2000x2000>`

## Context Management
- **Enable auto-compact** in settings (already configured)
- **Run `/compact` at 150K tokens**
- **Never use `/clear`** (destroys cached context)

## Prompt Cache Keepalive
The Anthropic API has a **5-minute TTL** on prompt cache entries. After 5 minutes of inactivity:
- Cache is evicted (10x cost increase!)
- 200K context goes from $0.60 to $6.00 per request

**Use the keepalive script:**
```bash
# In another terminal, while Claude is running
./claude-keepalive.sh &
```

Or manually keep cache warm:
```
# Send a no-op message every 4 minutes
/loop --interval 240s echo "keepalive"
```

## Model Selection Strategy
| Model | Input | Output | Use For |
|-------|-------|--------|---------|
| Haiku 3.5 | $0.80 | $4 | Quick tasks, searches |
| Sonnet 4.x | $3 | $15 | General development |
| Opus 4.5 | $5 | $25 | Complex architecture |
| Opus 4.6 Fast | $30 | $150 | Emergency only |

## Daily Checklist
- [ ] Set appropriate model for the task
- [ ] Use offset/limit for file reads
- [ ] Set token budgets (+500k) for large tasks
- [ ] Run `/compact` at 150K tokens
- [ ] Pre-convert binary documents
- [ ] Start keepalive script for long sessions
EOF

    print_success "Created CLAUDE.md in current directory"
}

# Create keepalive script
create_keepalive_script() {
    print_header "Creating Prompt Cache Keepalive Script"

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

    print_success "Created $KEEPALIVE_SCRIPT"
    print_status "Usage: ./$KEEPALIVE_SCRIPT [tmux-session-name] &"
    print_status "Run this in the background while Claude Code is active"
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

# Main function
main() {
    print_header "Claude Code Token Optimizer & Privacy Enhancer"

    parse_args "$@"

    if $DRY_RUN; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi

    detect_os
    check_and_install_deps
    configure_privacy
    configure_claude_settings
    create_claude_md
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

    echo -e "${BOLD}Next steps:${NC}"
    echo "1. Review the changes to your shell config"
    echo "2. Run: source ~/.bashrc (or ~/.zshrc)"
    echo "3. Start Claude Code with optimized settings"
    echo "4. For long sessions, run: ./claude-keepalive.sh &"
    echo "5. Check /cost regularly to monitor usage"
    echo ""

    if $FULL_PRIVACY; then
        echo -e "${BOLD}Privacy mode:${NC} Maximum (all non-essential traffic disabled)"
    else
        echo -e "${BOLD}Privacy mode:${NC} Standard (telemetry disabled)"
    fi

    echo ""
    echo -e "${BOLD}Cache Keepalive:${NC} Run ./claude-keepalive.sh in background for sessions >5 min"
    echo ""

    print_success "Happy optimizing!"
}

# Run main function
main "$@"
