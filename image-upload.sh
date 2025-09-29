#!/bin/bash

# <xbar.var>string(VAR_HOST="mini"): SSH Host for upload</xbar.var>
# <xbar.var>string(VAR_PATH="~/Downloads/"): Remote path for uploaded files</xbar.var>

# Set defaults if variables are not set by xbar
VAR_HOST="${VAR_HOST:-mini}"
VAR_PATH="${VAR_PATH:-~/Downloads/}"

# Ensure path ends with /
[[ "${VAR_PATH}" != */ ]] && VAR_PATH="${VAR_PATH}/"

# Constants
LAUNCHAGENT_LABEL="com.user.screenshot-auto-upload"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
UPLOAD_DIR="$HOME/Pictures/ScreenshotsAutoUpload"
ORIGINAL_LOCATION_KEY="${LAUNCHAGENT_LABEL}.original"

# Check if auto-upload is enabled
is_auto_enabled() {
    launchctl list 2>/dev/null | grep -q "$LAUNCHAGENT_LABEL"
}

# Get original screenshot directory
get_original_dir() {
    defaults read "$ORIGINAL_LOCATION_KEY" location 2>/dev/null || echo "$HOME/Desktop"
}

# Enable auto-upload
enable_auto_upload() {
    # Save current screenshot location
    current=$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")
    defaults write "$ORIGINAL_LOCATION_KEY" location "$current"

    # Create upload directory
    mkdir -p "$UPLOAD_DIR"

    # Change screenshot location
    defaults write com.apple.screencapture location "$UPLOAD_DIR"
    killall SystemUIServer

    # Get the absolute path of this script
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    # Create LaunchAgent plist
    cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHAGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
        <string>process_screenshot</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$UPLOAD_DIR</string>
    </array>
    <key>ThrottleInterval</key>
    <integer>2</integer>
</dict>
</plist>
EOF

    # Load LaunchAgent
    launchctl load "$LAUNCHAGENT_PLIST" 2>/dev/null

    osascript -e "display notification \"Auto-upload enabled. Screenshots will be uploaded automatically.\" with title \"Screenshot Auto-Upload\""
}

# Disable auto-upload
disable_auto_upload() {
    # Restore original screenshot location
    original=$(get_original_dir)
    defaults write com.apple.screencapture location "$original"
    defaults delete "$ORIGINAL_LOCATION_KEY" 2>/dev/null
    killall SystemUIServer

    # Unload and remove LaunchAgent
    launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null
    rm -f "$LAUNCHAGENT_PLIST"

    osascript -e "display notification \"Auto-upload disabled. Screenshots will save to: ${original/#$HOME/~}\" with title \"Screenshot Auto-Upload\""
}

# Toggle auto-upload
if [[ "$1" == "toggle_auto" ]]; then
    if is_auto_enabled; then
        disable_auto_upload
    else
        enable_auto_upload
    fi
    exit
fi

# Process screenshot from LaunchAgent
if [[ "$1" == "process_screenshot" ]]; then
    # Wait a moment for file to be fully written
    sleep 0.5

    # Find the newest screenshot file
    NEWEST=$(ls -t "$UPLOAD_DIR"/*.{png,jpg,jpeg} 2>/dev/null | head -1)

    if [[ -z "$NEWEST" ]]; then
        exit
    fi

    # Check if file is still being written (size changing)
    SIZE1=$(stat -f%z "$NEWEST" 2>/dev/null || echo 0)
    sleep 0.2
    SIZE2=$(stat -f%z "$NEWEST" 2>/dev/null || echo 0)

    if [[ "$SIZE1" != "$SIZE2" ]]; then
        exit
    fi

    # Generate remote filename
    FILENAME="img_$(date +%Y%m%d_%H%M%S)_$RANDOM.${NEWEST##*.}"
    ORIGINAL_SIZE=$(stat -f%z "$NEWEST" 2>/dev/null || echo 0)

    # Optimize if it's a PNG
    if [[ "${NEWEST##*.}" == "png" ]]; then
        OPTIMIZED="/tmp/opt_$FILENAME"
        JPEG_FILE="${OPTIMIZED%.png}.jpg"

        # Try to convert to JPEG for better compression
        sips -s format jpeg -s formatOptions 85 -Z 2000 "$NEWEST" --out "$JPEG_FILE" &>/dev/null

        if [[ -f "$JPEG_FILE" ]]; then
            JPEG_SIZE=$(stat -f%z "$JPEG_FILE" 2>/dev/null || echo $ORIGINAL_SIZE)
            if [[ $JPEG_SIZE -lt $ORIGINAL_SIZE ]]; then
                UPLOAD_FILE="$JPEG_FILE"
                FILENAME="${FILENAME%.png}.jpg"
            else
                UPLOAD_FILE="$NEWEST"
                rm -f "$JPEG_FILE"
            fi
        else
            UPLOAD_FILE="$NEWEST"
        fi
    else
        UPLOAD_FILE="$NEWEST"
    fi

    # Upload file
    if scp "$UPLOAD_FILE" "${VAR_HOST}:${VAR_PATH}$FILENAME" &>/dev/null; then
        echo -n "${VAR_PATH}$FILENAME" | pbcopy

        # Show size reduction info if optimized
        FINAL_SIZE=$(stat -f%z "$UPLOAD_FILE" 2>/dev/null || echo 0)
        if [[ "$UPLOAD_FILE" != "$NEWEST" && $FINAL_SIZE -lt $ORIGINAL_SIZE && $ORIGINAL_SIZE -gt 0 ]]; then
            REDUCTION=$((($ORIGINAL_SIZE - $FINAL_SIZE) * 100 / $ORIGINAL_SIZE))
            osascript -e "display notification \"Path copied. Reduced ${REDUCTION}% ($(($ORIGINAL_SIZE/1024))KB → $(($FINAL_SIZE/1024))KB)\" with title \"Screenshot Uploaded\""
            rm -f "$UPLOAD_FILE"
        else
            osascript -e "display notification \"Path copied to clipboard. Size: $(($FINAL_SIZE/1024))KB\" with title \"Screenshot Uploaded\""
        fi

        # Delete original after successful upload
        rm -f "$NEWEST"
    else
        osascript -e "display notification \"Upload failed for ${NEWEST##*/}\" with title \"Upload Error\""
    fi

    exit
fi

# Manual upload from clipboard
if [[ "$1" == "upload" ]]; then
    FILENAME="img_$(date +%Y%m%d_%H%M%S)_$RANDOM.png"
    TMP="/tmp/$FILENAME"

    # Save clipboard image to temp file
    osascript -e "set png to the clipboard as «class PNGf»
                  set f to open for access POSIX file \"$TMP\" with write permission
                  write png to f
                  close access f" 2>/dev/null

    # Get original file size
    ORIGINAL_SIZE=$(stat -f%z "$TMP" 2>/dev/null || echo 0)

    # Optimize image for smaller size
    OPTIMIZED_TMP="/tmp/opt_$FILENAME"

    # Convert to JPEG with 85% quality for better compression
    JPEG_FILE="${OPTIMIZED_TMP%.png}.jpg"
    sips -s format jpeg -s formatOptions 85 -Z 2000 "$TMP" --out "$JPEG_FILE" &>/dev/null

    # Use optimized file if it's smaller, otherwise keep original
    if [[ -f "$JPEG_FILE" ]]; then
        JPEG_SIZE=$(stat -f%z "$JPEG_FILE" 2>/dev/null || echo $ORIGINAL_SIZE)
        if [[ $JPEG_SIZE -lt $ORIGINAL_SIZE ]]; then
            mv "$JPEG_FILE" "$OPTIMIZED_TMP"
            UPLOAD_FILE="$OPTIMIZED_TMP"
            FILENAME="${FILENAME%.png}.jpg"
        else
            UPLOAD_FILE="$TMP"
            rm -f "$JPEG_FILE"
        fi
    else
        UPLOAD_FILE="$TMP"
    fi

    # Upload and copy path
    if scp "$UPLOAD_FILE" "${VAR_HOST}:${VAR_PATH}$FILENAME" &>/dev/null; then
        echo -n "${VAR_PATH}$FILENAME" | pbcopy

        # Show size reduction info
        FINAL_SIZE=$(stat -f%z "$UPLOAD_FILE" 2>/dev/null || echo 0)
        if [[ $FINAL_SIZE -lt $ORIGINAL_SIZE && $ORIGINAL_SIZE -gt 0 ]]; then
            REDUCTION=$((($ORIGINAL_SIZE - $FINAL_SIZE) * 100 / $ORIGINAL_SIZE))
            osascript -e "display notification \"Reduced ${REDUCTION}% ($(($ORIGINAL_SIZE/1024))KB → $(($FINAL_SIZE/1024))KB)\" with title \"Uploaded\""
        else
            osascript -e "display notification \"Path copied. Size: $(($FINAL_SIZE/1024))KB\" with title \"Uploaded\""
        fi
    else
        osascript -e 'display notification "Upload failed" with title "Error"'
    fi
    rm -f "$TMP" "$OPTIMIZED_TMP" "$JPEG_FILE"
    exit
fi

# Menu display
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
if is_auto_enabled; then
    echo "📤✅"
    echo "---"
    echo "✅ Auto: ON → ${VAR_HOST}:${VAR_PATH} | bash='$SCRIPT_PATH' param1=toggle_auto terminal=false refresh=true"
else
    echo "📤"
    echo "---"
    echo "❌ Auto: OFF | bash='$SCRIPT_PATH' param1=toggle_auto terminal=false refresh=true"
fi
echo "📸 Upload Clipboard | bash='$SCRIPT_PATH' param1=upload terminal=false refresh=true"