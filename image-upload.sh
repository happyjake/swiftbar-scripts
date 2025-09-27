#!/bin/bash

# Upload action
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
    # (good balance between size and quality)
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
    if scp "$UPLOAD_FILE" "mini:~/Downloads/$FILENAME" &>/dev/null; then
        echo -n "~/Downloads/$FILENAME" | pbcopy

        # Show size reduction info
        FINAL_SIZE=$(stat -f%z "$UPLOAD_FILE" 2>/dev/null || echo 0)
        if [[ $FINAL_SIZE -lt $ORIGINAL_SIZE && $ORIGINAL_SIZE -gt 0 ]]; then
            REDUCTION=$((($ORIGINAL_SIZE - $FINAL_SIZE) * 100 / $ORIGINAL_SIZE))
            osascript -e "display notification \"Reduced ${REDUCTION}% ($(($ORIGINAL_SIZE/1024))KB → $(($FINAL_SIZE/1024))KB)\" with title \"Uploaded\""
        else
            osascript -e 'display notification "Path copied" with title "Uploaded"'
        fi
    else
        osascript -e 'display notification "Upload failed" with title "Error"'
    fi
    rm -f "$TMP" "$OPTIMIZED_TMP" "$JPEG_FILE"
    exit
fi

# Menu display
echo "📤"
echo "---"
echo "Upload to mini | bash='$0' param1=upload terminal=false refresh=true"