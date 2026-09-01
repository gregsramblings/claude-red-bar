#!/bin/bash
# ccredbar hook: write per-session state for the edge-bar app.
# Called by Claude Code hooks with one arg: busy | waiting | notify | end
# Reads the hook JSON payload on stdin; needs session_id (+ cwd, and the
# Notification message to tell a real prompt from the idle timeout).
state="$1"
dir="$HOME/.claude/ccredbar/state"
mkdir -p "$dir"

input=$(cat)
sid=$(printf '%s' "$input" | plutil -extract session_id raw -o - - 2>/dev/null)
[ -z "$sid" ] && exit 0                 # no session id -> nothing to track

f="$dir/$sid.json"

if [ "$state" = "end" ]; then
  rm -f "$f"
  exit 0
fi

# Notification hook fires for BOTH a real prompt (permission / an actual question)
# and the ~60s idle timeout. Only the former should pulse the bar. The idle
# message reads "Claude is waiting for your input"; treat that as "done" (no bar),
# everything else as needs_input (pulse).
if [ "$state" = "notify" ]; then
  msg=$(printf '%s' "$input" | plutil -extract message raw -o - - 2>/dev/null)
  case "$msg" in
    *"waiting for your input"*) state="waiting" ;;      # idle timeout -> no bar
    *)                          state="needs_input" ;;  # active question -> pulse
  esac
fi

cwd=$(printf '%s' "$input" | plutil -extract cwd raw -o - - 2>/dev/null)
ts=$(date +%s)
printf '{"state":"%s","cwd":"%s","ts":%s}\n' "$state" "$cwd" "$ts" > "$f"
exit 0
