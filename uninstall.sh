#!/bin/bash
# ccbar uninstaller. Stops + removes the LaunchAgent and state dir.
# Does NOT touch ~/.claude/settings.json — remove the "hooks" block yourself.
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.ccbar.plist"

echo "==> stopping ccbar"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HOME/.claude/ccbar"

echo "==> done. Remaining manual step:"
echo "    Remove the ccbar \"hooks\" block from ~/.claude/settings.json"
echo "    (the four entries whose command is 'bash .../ccbar/hook.sh ...')."
echo "    The compiled ./ccbar binary in the repo is left in place; delete the"
echo "    repo folder to fully remove."
