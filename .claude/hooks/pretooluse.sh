#!/usr/bin/env bash
# PreToolUse Hook - Image Resizing Interceptor
#
# Claude Code protocol:
#   exit 0  → proceed normally (tool runs as usual)
#   exit 1  → hard block (tool is blocked, Claude sees an error)
#   exit 2  → soft intercept (tool is skipped, Claude receives our stdout as the result)
#
# For images: resize → write binary to stdout → exit 2 (Claude reads resized bytes)
# For all other files: exit 0 (Claude reads normally)

# Read JSON payload from stdin (Claude always sends it)
INPUT=$(cat)

# Log raw input for debugging
echo "$(date -Iseconds) | PreToolUse | INPUT | $INPUT" >> /tmp/hook-validation.log

# Extract file_path from tool_input using jq.
# Claude Code sends snake_case (file_path); camelCase (filePath) is listed as fallback
# for forward-compatibility. Two-step: first pull tool_input object, then the key.
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // {}' 2>/dev/null) || TOOL_INPUT="{}"
FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // .filePath // empty' 2>/dev/null) || FILE_PATH=""

echo "$(date -Iseconds) | PreToolUse | PARSED_PATH | ${FILE_PATH:-<empty>}" >> /tmp/hook-validation.log

# If no file path found, let the tool run normally
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check if this is a PNG/JPG/JPEG (case-insensitive)
LOWER=$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')
case "$LOWER" in
    *.png|*.jpg|*.jpeg)
        ;;
    *)
        # Not an image - let Claude read it normally
        echo "$(date -Iseconds) | PreToolUse | PASS_THROUGH | $FILE_PATH" >> /tmp/hook-validation.log
        exit 0
        ;;
esac

# Verify the file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "$(date -Iseconds) | PreToolUse | FILE_NOT_FOUND | $FILE_PATH" >> /tmp/hook-validation.log
    exit 0
fi

# Choose ImageMagick binary
if command -v magick >/dev/null 2>&1; then
    MAGICK="magick"
elif command -v convert >/dev/null 2>&1; then
    MAGICK="convert"
else
    echo "$(date -Iseconds) | PreToolUse | NO_IMAGEMAGICK | $FILE_PATH" >> /tmp/hook-validation.log
    exit 0  # Graceful degradation: let Claude read the original
fi

# Resize to /tmp (preserve original)
OUTPUT_FILE="/tmp/resized_$(basename "$FILE_PATH")"

# '2000x2000>' means "shrink only if larger than 2000x2000, preserve aspect ratio"
# The quotes are mandatory - unquoted > is shell redirection
if ! "$MAGICK" "$FILE_PATH" -resize '2000x2000>' -quality 85 "$OUTPUT_FILE" 2>/dev/null; then
    echo "$(date -Iseconds) | PreToolUse | RESIZE_FAILED | $FILE_PATH" >> /tmp/hook-validation.log
    exit 0  # Graceful degradation
fi

echo "$(date -Iseconds) | PreToolUse | RESIZED | $FILE_PATH -> $OUTPUT_FILE" >> /tmp/hook-validation.log

# Output the resized image bytes to stdout.
# 'cat' passes raw bytes through without any encoding - this is the correct
# way to write binary to stdout in POSIX sh. Do NOT assign to a variable first
# (that would corrupt binary data through whitespace/null stripping).
cat "$OUTPUT_FILE"

# exit 2 tells Claude Code: "skip the real Read tool, use my stdout as the result"
exit 2
