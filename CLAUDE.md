# CLAUDE.md

`ccbar` — a full-width red edge bar (bottom of every screen) that signals, from
across the room, that Claude Code is busy. Red = at least one session working; no
bar = everything idle (waiting on you, needing input, or nothing running).

## Layout

- `ccbar.swift` — the whole app (AppKit, single file). Borderless, click-through
  (`ignoresMouseEvents`), `.screenSaver` window level, on all Spaces, one window per
  `NSScreen`. Polls the state dir every 0.4s and paints the top-priority color.
- `hook.sh` — Claude Code hook target. Reads the hook JSON on stdin, extracts
  `session_id` (+ `cwd`) with `plutil`, writes/deletes one state file per session.
- `install.sh` — builds, generates the LaunchAgent (path derived from the repo
  location), loads it, and prints the hooks block to add to `settings.json`.
- `uninstall.sh` — unloads/removes the LaunchAgent and state dir.
- `ccbar` — compiled binary (gitignored; built by `install.sh`).

## Build & run

`./install.sh` does everything (build + LaunchAgent + print hooks). It is
idempotent — re-run it after any change to `ccbar.swift` to rebuild and restart the
agent. Manual equivalent:

```bash
swiftc ccbar.swift -o ccbar -framework Cocoa              # build
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
`*.json`, ignores entries older than 12h, and shows the red bar iff any live entry
has `state == "busy"`. `waiting` / `needs_input` / no file → no bar.

`hook.sh` still writes all three states (waiting/needs_input carry `cwd` + `ts` for
possible future use), but only `busy` drives the bar — see `anyBusy()` in
`ccbar.swift`. Keep the `busy` string in sync across both files; it is the whole API.

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
  bottom edge — current default), `pollInterval`, `staleAfter`, `barColor`.
- No dependencies, no build step beyond `swiftc`. Keep it one file.
- `hook.sh` must stay fast and never block a turn: parse, write, exit. No network.
- Parse hook JSON with `plutil` (always present on macOS) — do not assume `jq`.
