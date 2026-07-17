# ccbar

A full-width red bar across the bottom edge of every screen that tells you, from
across the room, that Claude Code is busy working.

- **Red bar** — at least one session is busy (Claude working).
- **No bar** — everything idle: waiting on you, needing input, or nothing running.

Any busy session shows the bar; it clears the moment the last one finishes.

## How it works

1. Claude Code **hooks** (`~/.claude/settings.json`) fire on state change and run
   `hook.sh`, which writes one small JSON file per session into
   `~/.claude/ccbar/state/<session_id>.json`. `SessionEnd` deletes it.
   - `UserPromptSubmit` → `busy`
   - `Stop` → `waiting`
   - `Notification` → `needs_input`
   - `SessionEnd` → removes the file
2. `ccbar` (AppKit, borderless click-through window at `.screenSaver` level on
   every `NSScreen`, all Spaces) polls the state dir every 0.4s and shows a red
   bar if any session is `busy`, otherwise nothing.

Multi-session just works: each session is its own file, keyed by `session_id`.
Stale files (>12h) are ignored.

## Build

```bash
swiftc ccbar.swift -o ccbar -framework Cocoa
```

## Run at login

Installed as a LaunchAgent (`~/Library/LaunchAgents/com.ccbar.plist`,
`RunAtLoad` + `KeepAlive`).

```bash
launchctl load   ~/Library/LaunchAgents/com.ccbar.plist   # start now + at login
launchctl unload ~/Library/LaunchAgents/com.ccbar.plist   # stop
```

After editing `ccbar.swift`: rebuild, then `unload` + `load` to restart.

## Tweaks (top of `ccbar.swift`)

- `barHeight` — thickness (px). Bump to 24+ for a bigger room.
- `atTop` — `true` to pin the bar to the top edge instead (default: bottom).
- `barColor` — the bar color.

## Notes

- Hooks are read at session start, so **already-open** sessions won't drive the
  bar until they restart. New sessions work immediately.
- `Stop` is the main-agent stop only (subagent stops are a separate `SubagentStop`
  event, not hooked), so the bar tracks real turn boundaries.
