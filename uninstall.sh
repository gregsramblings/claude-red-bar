#!/bin/bash
# ccredbar uninstaller. Stops + removes the LaunchAgent and state dir.
# Does NOT touch ~/.claude/settings.json — remove the "hooks" block yourself.
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.ccredbar.plist"

echo "==> stopping ccredbar"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/.claude/ccredbar"

echo "==> done. Remaining manual step:"
echo "    Remove the ccredbar \"hooks\" block from ~/.claude/settings.json"
echo "    (the four entries whose command is 'bash .../ccredbar/hook.sh ...')."
echo "    The compiled ./ccredbar binary in the repo is left in place; delete the"
echo "    repo folder to fully remove."
