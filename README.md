# ccbar

A full-width colored bar across the top edge of every screen that tells you, from
across the room, what Claude Code sessions are doing.

- **No bar** — everything busy (Claude working). Nothing needs you.
- **Green bar** — a session finished its turn and is waiting on *you*.
- **Red bar (pulsing)** — a session needs input (permission prompt / idle).

Priority across all sessions wins the bar: red > green > none. So one red among
three greens shows red until you clear it.

## How it works

1. Claude Code **hooks** (`~/.claude/settings.json`) fire on state change and run
   `hook.sh`, which writes one small JSON file per session into
   `~/.claude/ccbar/state/<session_id>.json`. `SessionEnd` deletes it.
   - `UserPromptSubmit` → `busy`
   - `Stop` → `waiting`
   - `Notification` → `needs_input`
   - `SessionEnd` → removes the file
2. `ccbar` (AppKit, borderless click-through window at `.screenSaver` level on
   every `NSScreen`, all Spaces) polls the state dir every 0.4s and paints the
   top-priority color.

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
- `atTop` — `false` to pin the bar to the bottom edge instead.
- `colorFor` — the two colors.
- pulse — the red `CABasicAnimation` in `Bar.apply`; delete the block for steady red.

## Notes

- Hooks are read at session start, so **already-open** sessions won't drive the
  bar until they restart. New sessions work immediately.
- `Stop` is the main-agent stop only (subagent stops are a separate `SubagentStop`
  event, not hooked), so the bar tracks real turn boundaries.
