# CLAUDE.md

`ccbar` — a full-width edge bar (top or bottom of every screen) that signals, from
across the room, the state of your Claude Code sessions. Green = a session waits on
you; red pulsing = a session needs input; no bar = all busy.

## Layout

- `ccbar.swift` — the whole app (AppKit, single file). Borderless, click-through
  (`ignoresMouseEvents`), `.screenSaver` window level, on all Spaces, one window per
  `NSScreen`. Polls the state dir every 0.4s and paints the top-priority color.
- `hook.sh` — Claude Code hook target. Reads the hook JSON on stdin, extracts
  `session_id` (+ `cwd`) with `plutil`, writes/deletes one state file per session.
- `com.ccbar.plist` — LaunchAgent (copy of the installed one) for run-at-login.
- `ccbar` — compiled binary (gitignored).

## Build & run

```bash
swiftc ccbar.swift -o ccbar -framework Cocoa      # build
launchctl unload ~/Library/LaunchAgents/com.ccbar.plist   # restart after a rebuild
launchctl load   ~/Library/LaunchAgents/com.ccbar.plist
```

The binary is not checked in — always rebuild after clone.

## State protocol (the contract between the two halves)

`hook.sh <state>` writes `~/.claude/ccbar/state/<session_id>.json`:

```json
{ "state": "busy|waiting|needs_input", "cwd": "...", "ts": 1700000000 }
```

`SessionEnd` calls `hook.sh end`, which deletes the file. The app reads every
`*.json`, ignores entries older than 12h, and maps `state`:

- `busy` → no bar
- `waiting` → green
- `needs_input` → red, pulsing

Priority across all sessions: `needs_input` > `waiting` > none. Keep these three
state strings in sync across `hook.sh` and `topState()` in `ccbar.swift` — they are
the whole API.

## Wiring (lives outside this repo)

Claude Code hooks in `~/.claude/settings.json` drive `hook.sh`:

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash /path/to/ccbar/hook.sh busy" }] }],
  "Stop":            [{ "hooks": [{ "type": "command", "command": "bash /path/to/ccbar/hook.sh waiting" }] }],
  "Notification":    [{ "hooks": [{ "type": "command", "command": "bash /path/to/ccbar/hook.sh needs_input" }] }],
  "SessionEnd":      [{ "hooks": [{ "type": "command", "command": "bash /path/to/ccbar/hook.sh end" }] }]
}
```

Hooks are snapshotted at session start — **already-open sessions won't drive the bar
until restarted**. New sessions work immediately. `Stop` is the main-agent stop only
(`SubagentStop` is a separate, unhooked event), so the bar tracks real turn
boundaries.

## Conventions

- Config constants live at the top of `ccbar.swift`: `barHeight`, `atTop` (false =
  bottom edge — current default), `pollInterval`, `staleAfter`, `colorFor`.
- No dependencies, no build step beyond `swiftc`. Keep it one file.
- `hook.sh` must stay fast and never block a turn: parse, write, exit. No network.
- Parse hook JSON with `plutil` (always present on macOS) — do not assume `jq`.
