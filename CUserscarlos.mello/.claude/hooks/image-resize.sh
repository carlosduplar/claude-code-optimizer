#!/usr/bin/env bash
#===============================================================================
# Claude Code Image Resize Hook - PreToolUse (Read)
#===============================================================================
# Resizes image files BEFORE they're read by the Read tool to prevent API errors.
# Uses the sanitizer approach: modifies file in-place with backup, then exit 0.
#
# Place in: ~/.claude/hooks/image-resize.sh
# Make executable: chmod +x ~/.claude/hooks/image-resize.sh
#===============================================================================

set -euo pipefail

# Configuration - adjust via environment variables
MAX_DIMENSION=${CLAUDE_IMAGE_MAX_DIMENSION:-2000}                    # Max pixels (default: 2000)
MAX_FILE_SIZE_BYTES=$((${CLAUDE_IMAGE_MAX_SIZE_MB:-5} * 1024 * 1024)) # Max file size (default: 5MB)
QUALITY=${CLAUDE_IMAGE_QUALITY:-85}                                    # JPEG quality (default: 85)
DEBUG=${CLAUDE_IMAGE_DEBUG:-0}                                         # Enable debug logging (default: 0)
DEBUG_LOG="/tmp/claude-image-resize.log"

# Logging function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [image-resize] $*"
    if [[ "$DEBUG" == "1" ]]; then
        echo "$msg" >> "$DEBUG_LOG"
    fi
    # Always log validation events
    echo "$(date -Iseconds) | PreToolUse | $*" >> /tmp/hook-validation.log
}

# Get ImageMagick command (newer versions use 'magick', older use 'convert')
get_convert_cmd() {
    if command -v magick &> /dev/null; then
        echo "magick"
    elif command -v convert &> /dev/null; then
        echo "convert"
    else
        echo ""
    fi
}

# Check if file is an image by extension
is_image_file() {
    local file_path="$1"
    local ext="${file_path##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
        png|jpg|jpeg|gif|webp|bmp|tiff|tif)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Resize an image file if it exceeds limits
resize_if_needed() {
    local img_path="$1"
    local convert_cmd=$(get_convert_cmd)

    if [[ -z "$convert_cmd" ]]; then
        log "ERROR | ImageMagick not found. Install with: apt install imagemagick"
        echo "⚠️ ImageMagick not installed. Large images may cause API errors." >&2
        return 1
    fi

    if [[ ! -f "$img_path" ]]; then
        log "FILE_NOT_FOUND | $img_path"
        return 1
    fi

    # Get current dimensions
    local dimensions=$($convert_cmd "$img_path" -format "%wx%h" info: 2>/dev/null) || {
        log "DIMENSIONS_FAILED | $img_path"
        return 1
    }
    local width=$(echo "$dimensions" | cut -d'x' -f1)
    local height=$(echo "$dimensions" | cut -d'x' -f2)

    # Validate we got numeric dimensions
    if ! [[ "$width" =~ ^[0-9]+$ ]] || ! [[ "$height" =~ ^[0-9]+$ ]]; then
        log "INVALID_DIMENSIONS | $dimensions for $img_path"
        return 1
    fi

    # Get file size (works on both macOS and Linux)
    local file_size
    if [[ "$(uname)" == "Darwin" ]]; then
        file_size=$(stat -f%z "$img_path" 2>/dev/null)
    else
        file_size=$(stat -c%s "$img_path" 2>/dev/null)
    fi

    log "DIMENSIONS | $img_path | ${width}x${height} | ${file_size} bytes"

    local needs_resize=0

    # Check dimensions
    if [[ "$width" -gt "$MAX_DIMENSION" ]] || [[ "$height" -gt "$MAX_DIMENSION" ]]; then
        needs_resize=1
        log "EXCEEDS_DIMENSION | ${width}x${height} > ${MAX_DIMENSION}"
    fi

    # Check file size
    if [[ "$file_size" -gt "$MAX_FILE_SIZE_BYTES" ]]; then
        needs_resize=1
        log "EXCEEDS_SIZE | ${file_size} > ${MAX_FILE_SIZE_BYTES} bytes"
    fi

    if [[ "$needs_resize" -eq 1 ]]; then
        # Create backup
        local backup="${img_path}.original"
        cp "$img_path" "$backup"

        # Resize: maintain aspect ratio, max dimension on either side
        # The ">" means only shrink, never enlarge
        $convert_cmd "$backup" \
            -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" \
            -quality "$QUALITY" \
            "$img_path"

        # Log results
        local new_dimensions=$($convert_cmd "$img_path" -format "%wx%h" info: 2>/dev/null)
        local new_size
        if [[ "$(uname)" == "Darwin" ]]; then
            new_size=$(stat -f%z "$img_path" 2>/dev/null)
        else
            new_size=$(stat -c%s "$img_path" 2>/dev/null)
        fi

        log "RESIZED | $img_path | ${dimensions} → ${new_dimensions} | ${file_size} → ${new_size} bytes"
        echo "📐 Image resized: ${dimensions} → ${new_dimensions} to comply with API limits" >&2

        # Remove backup (comment this line to keep backups)
        rm -f "$backup"
    else
        log "WITHIN_LIMITS | $img_path | No resize needed"
    fi

    return 0
}

# Main execution
INPUT=$(cat)

# Gracefully handle invalid JSON
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}' 2>/dev/null) || TOOL_INPUT="{}"

# Exit gracefully if we couldn't parse the input
if [[ -z "$TOOL_NAME" ]]; then
    log "PARSE_ERROR | Could not parse tool_name from input"
    exit 0
fi

log "TOOL | $TOOL_NAME"

# Only process Read tool
if [[ "$TOOL_NAME" == "Read" ]]; then
    # Get the file path from tool input (handles both filePath and file_path)
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.filePath // .file_path // empty' 2>/dev/null) || FILE_PATH=""

    if [[ -z "$FILE_PATH" ]]; then
        log "NO_FILE_PATH | Empty file path in Read tool input"
        exit 0
    fi

    log "FILE_PATH | $FILE_PATH"

    # Check if it's an image file
    if is_image_file "$FILE_PATH"; then
        log "IMAGE_DETECTED | $FILE_PATH"

        if [[ -f "$FILE_PATH" ]]; then
            resize_if_needed "$FILE_PATH"
        else
            log "FILE_NOT_FOUND | $FILE_PATH"
        fi
    else
        log "NOT_IMAGE | $FILE_PATH | Skipping"
    fi
fi

# Always exit 0 - let Claude read the file normally (now resized if needed)
exit 0
