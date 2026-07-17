#!/bin/bash
# ccbar installer. Builds the app, installs a run-at-login LaunchAgent, and
# prints the Claude Code hooks block to add to your settings. Paths are derived
# from wherever this repo lives — nothing is hardcoded.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.claude/ccbar/state"
PLIST="$HOME/Library/LaunchAgents/com.ccbar.plist"
SETTINGS="$HOME/.claude/settings.json"

echo "==> ccbar install (from $DIR)"

# 1. dependencies
if [[ "$(uname)" != "Darwin" ]]; then
  echo "!! macOS only." >&2; exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "!! swiftc not found. Install the Xcode Command Line Tools:" >&2
  echo "     xcode-select --install" >&2
  exit 1
fi

# 2. build
echo "==> building"
swiftc "$DIR/ccbar.swift" -o "$DIR/ccbar" -framework Cocoa
chmod +x "$DIR/hook.sh"

# 3. state dir
mkdir -p "$STATE_DIR"

# 4. LaunchAgent (generated with this repo's path)
echo "==> installing LaunchAgent -> $PLIST"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ccbar</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DIR/ccbar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "==> ccbar is running (and will start at login)."

# 5. hooks
echo
echo "================================================================"
echo "LAST STEP — wire up Claude Code hooks."
echo
echo "Add this \"hooks\" block to $SETTINGS"
echo "(merge it into the top-level object; if a \"hooks\" key already"
echo " exists, add these four events to it):"
echo "----------------------------------------------------------------"
cat <<EOF
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash $DIR/hook.sh busy" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash $DIR/hook.sh waiting" }] }
    ],
    "Notification": [
      { "hooks": [{ "type": "command", "command": "bash $DIR/hook.sh notify" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "bash $DIR/hook.sh end" }] }
    ]
  }
EOF
echo "----------------------------------------------------------------"
echo
echo "Then start a NEW Claude Code session (hooks load at session start;"
echo "already-open sessions won't drive the bar until restarted)."
echo "The red bar appears at the bottom of every screen while Claude works."
