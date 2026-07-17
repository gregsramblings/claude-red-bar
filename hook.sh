#!/bin/bash
# ccbar hook: write per-session state for the edge-bar app.
# Called by Claude Code hooks with one arg: busy | waiting | needs_input | end
# Reads the hook JSON payload on stdin; only needs session_id (+ cwd for label).
state="$1"
dir="$HOME/.claude/ccbar/state"
mkdir -p "$dir"

input=$(cat)
sid=$(printf '%s' "$input" | plutil -extract session_id raw -o - - 2>/dev/null)
[ -z "$sid" ] && exit 0                 # no session id -> nothing to track

f="$dir/$sid.json"

if [ "$state" = "end" ]; then
  rm -f "$f"
  exit 0
fi

cwd=$(printf '%s' "$input" | plutil -extract cwd raw -o - - 2>/dev/null)
ts=$(date +%s)
printf '{"state":"%s","cwd":"%s","ts":%s}\n' "$state" "$cwd" "$ts" > "$f"
exit 0
