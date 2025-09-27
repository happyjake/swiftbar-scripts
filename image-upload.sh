#!/bin/bash

# Check for image in clipboard
has_image() {
    osascript -e 'the clipboard as «class PNGf»' &>/dev/null
}

# Upload action
if [[ "$1" == "upload" ]]; then
    FILENAME="img_$(date +%Y%m%d_%H%M%S)_$RANDOM.png"
    TMP="/tmp/$FILENAME"

    # Save clipboard image to temp file
    osascript -e "set png to the clipboard as «class PNGf»
                  set f to open for access POSIX file \"$TMP\" with write permission
                  write png to f
                  close access f" 2>/dev/null

    # Upload and copy path
    if scp "$TMP" "mini:~/Downloads/$FILENAME" &>/dev/null; then
        echo -n "mini:~/Downloads/$FILENAME" | pbcopy
        osascript -e 'display notification "Path copied" with title "Uploaded"'
    else
        osascript -e 'display notification "Upload failed" with title "Error"'
    fi
    rm -f "$TMP"
    exit
fi

# Menu display
if has_image; then
    echo "📤"
    echo "---"
    echo "Upload to mini | bash='$0' param1=upload terminal=false refresh=true"
else
    echo "📋"
    echo "---"
    echo "No image"
fi