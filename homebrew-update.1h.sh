#!/bin/bash

# Constants
LAUNCHAGENT_LABEL="com.user.homebrew-weekly-update"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
LAST_UPDATE_KEY="${LAUNCHAGENT_LABEL}.lastupdate"
LOG_FILE="$HOME/Library/Logs/homebrew-update.log"

# Determine Homebrew path (M1 vs Intel)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
  BREW_PATH="/opt/homebrew/bin/brew"
else
  BREW_PATH="/usr/local/bin/brew"
fi

# Check if auto-update is enabled
is_auto_enabled() {
  launchctl list 2>/dev/null | grep -q "$LAUNCHAGENT_LABEL"
}

# Get last update timestamp
get_last_update() {
  defaults read "$LAST_UPDATE_KEY" timestamp 2>/dev/null || echo "0"
}

# Calculate relative time
relative_time() {
  local timestamp=$1
  local now=$(date +%s)
  local diff=$((now - timestamp))
  local prefix=""
  local suffix=""

  if [[ $diff -lt 0 ]]; then
    diff=$((-diff))
    prefix="in "
  else
    suffix=" ago"
  fi

  if [[ $diff -lt 60 ]]; then
    echo "now"
  elif [[ $diff -lt 3600 ]]; then
    echo "${prefix}$((diff / 60))m${suffix}"
  elif [[ $diff -lt 86400 ]]; then
    echo "${prefix}$((diff / 3600))h${suffix}"
  elif [[ $diff -lt 604800 ]]; then
    echo "${prefix}$((diff / 86400))d${suffix}"
  else
    echo "${prefix}$((diff / 604800))w${suffix}"
  fi
}

# Calculate next update time (next Sunday at 10 AM)
get_next_update() {
  local day_of_week=$(date +%w)
  local days_until_sunday=$((7 - day_of_week))
  [[ $days_until_sunday -eq 0 ]] && days_until_sunday=7

  # Get next Sunday at 10 AM
  local next_sunday=$(date -v +${days_until_sunday}d -v10H -v0M -v0S +%s)
  local now=$(date +%s)

  # If it's Sunday and before 10 AM, update is today
  if [[ $day_of_week -eq 0 ]] && [[ $(date +%H) -lt 10 ]]; then
    next_sunday=$(date -v10H -v0M -v0S +%s)
  fi

  echo "$next_sunday"
}

# Enable auto-update
enable_auto_update() {
  # Get the absolute path of this script
  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Create LaunchAgent plist
  cat >"$LAUNCHAGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHAGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
        <string>run_update</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>10</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StartOnMount</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
EOF

  # Load LaunchAgent
  launchctl load "$LAUNCHAGENT_PLIST" 2>/dev/null

  osascript -e 'display notification "Weekly updates enabled (Sundays 10 AM)" with title "Homebrew Auto-Update"'
}

# Disable auto-update
disable_auto_update() {
  launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null
  rm -f "$LAUNCHAGENT_PLIST"

  osascript -e 'display notification "Auto-update disabled" with title "Homebrew Auto-Update"'
}

# Toggle auto-update
if [[ "$1" == "toggle_auto" ]]; then
  if is_auto_enabled; then
    disable_auto_update
  else
    enable_auto_update
  fi
  exit
fi

# Run the actual update
if [[ "$1" == "run_update" ]]; then
  # Guard: Check if update is needed (>7 days since last update)
  LAST_UPDATE=$(get_last_update)
  NOW=$(date +%s)
  DAYS_SINCE_UPDATE=$(((NOW - LAST_UPDATE) / 86400))

  if [[ $LAST_UPDATE -ne 0 ]] && [[ $DAYS_SINCE_UPDATE -lt 7 ]]; then
    echo "Update not needed. Last update was $DAYS_SINCE_UPDATE days ago."
    exit 0
  fi

  echo "=== Homebrew Update Started: $(date) ==="

  # Update Homebrew itself
  echo "Updating Homebrew..."
  $BREW_PATH update

  # Upgrade formulae
  echo "Upgrading formulae..."
  $BREW_PATH upgrade

  # Upgrade casks
  echo "Upgrading casks..."
  $BREW_PATH upgrade --cask

  # Cleanup old versions
  echo "Cleaning up..."
  $BREW_PATH cleanup -s
  $BREW_PATH autoremove

  # Save timestamp
  defaults write "$LAST_UPDATE_KEY" timestamp "$(date +%s)"

  # Count of installed packages
  FORMULAE_COUNT=$($BREW_PATH list --formula | wc -l | tr -d ' ')
  CASK_COUNT=$($BREW_PATH list --cask | wc -l | tr -d ' ')

  echo "=== Update Complete: $(date) ==="
  echo "Formulae: $FORMULAE_COUNT, Casks: $CASK_COUNT"

  osascript -e "display notification \"Formulae: $FORMULAE_COUNT, Casks: $CASK_COUNT\" with title \"Homebrew Updated\""
  exit
fi

# Manual update
if [[ "$1" == "manual_update" ]]; then
  osascript -e 'display notification "Starting manual update..." with title "Homebrew"'
  # Get the absolute path of this script
  SCRIPT_FULL_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Create a temporary script to run the update
  TEMP_SCRIPT="/tmp/homebrew_update_$$.sh"
  cat >"$TEMP_SCRIPT" <<EOF
#!/bin/bash
'$SCRIPT_FULL_PATH' run_update
echo ""
echo "Press any key to close this window..."
read -n 1
exit
EOF
  chmod +x "$TEMP_SCRIPT"

  # Open the script in Terminal
  open -a Terminal "$TEMP_SCRIPT"
  exit
fi

# Open log file
if [[ "$1" == "open_log" ]]; then
  # Create log file if it doesn't exist
  [[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE"
  open "$LOG_FILE"
  exit
fi

# Show log in Finder
if [[ "$1" == "show_log" ]]; then
  # Create log file if it doesn't exist
  [[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE"
  open -R "$LOG_FILE"
  exit
fi

# Menu display
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if is_auto_enabled; then
  echo "🍺✅"
  echo "---"

  # Get times
  LAST_UPDATE=$(get_last_update)
  if [[ $LAST_UPDATE -eq 0 ]]; then
    LAST_TIME="never"
  else
    LAST_TIME="$(relative_time $LAST_UPDATE)"
  fi

  NEXT_UPDATE=$(get_next_update)
  NEXT_TIME="$(relative_time $NEXT_UPDATE)"

  echo "✅ Auto: ON • Last: $LAST_TIME • Next: $NEXT_TIME | bash='$SCRIPT_PATH' param1=toggle_auto terminal=false refresh=true"
else
  echo "🍺"
  echo "---"
  echo "❌ Auto: OFF | bash='$SCRIPT_PATH' param1=toggle_auto terminal=false refresh=true"
fi

echo "🔄 Update Now | bash='$SCRIPT_PATH' param1=manual_update terminal=false refresh=true"
echo "📋 Log | bash='$SCRIPT_PATH' param1=open_log terminal=false"
echo "  ⌥ Show in Finder | bash='$SCRIPT_PATH' param1=show_log terminal=false alternate=true"

