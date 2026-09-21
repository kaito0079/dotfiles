#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Open cmux & Jump to Latest Notification
# @raycast.mode silent
# @raycast.icon 🔔

osascript <<'EOF'
tell application "cmux" to activate
delay 0.3
tell application "System Events"
    keystroke "u" using {command down, shift down}
end tell
EOF
