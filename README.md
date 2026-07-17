# ccbar

A full-width **red bar** across the bottom edge of every screen that tells you, from
across the room, what Claude Code is doing.

- **Solid red bar** — at least one session is busy (Claude working).
- **Pulsing red bar** — a session **needs a response from you** now (a permission
  prompt, or Claude blocked waiting for input).
- **No bar** — a turn simply finished, or nothing running.

Busy wins: if any session is still working the bar is solid; it pulses only when one
is actually waiting on your input. A turn that just *finishes* clears the bar — it
blinks only when Claude needs you. The bar is click-through (it never intercepts your
mouse) and floats above everything, including fullscreen apps, on every Space and
every monitor.

> Note: Claude Code has no hook for "ended a turn *with a question*," so a plain
> end-of-turn question won't blink immediately — it registers as "done" (no bar). If
> you don't reply, Claude Code's idle notification (~60s) fires and the bar starts
> pulsing then. Permission prompts pulse instantly.

<img src="images/ccbar-desk.jpg" width="320" alt="ccbar in action — the red bar along the bottom edge of the screen shows Claude is busy">

*Solid red along the bottom edge = Claude is working; it pulses when Claude needs a response from you.*

## Requirements

- **macOS** (uses AppKit + `launchd`).
- **Xcode Command Line Tools** — provides `swiftc` to build. Install with:
  ```bash
  xcode-select --install
  ```
- **Claude Code CLI** — this is driven by [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  hooks. It works with any **locally-running** Claude Code (terminal or IDE
  extension). It does **not** work with cloud sessions (claude.ai/code) — those run
  remotely and can't reach your local machine.

No other dependencies: no Homebrew, no `jq`, no runtime. Just the system Swift
compiler and `plutil` (built into macOS).

## Install

```bash
git clone https://github.com/gregsramblings/claude-status-bar.git
cd claude-status-bar
./install.sh
```

`install.sh` builds the app, installs a run-at-login LaunchAgent (paths derived from
wherever you cloned — nothing hardcoded), starts it, then **prints a `hooks` block**.
Copy that block into `~/.claude/settings.json` (merge it into the top-level JSON
object; if you already have a `"hooks"` key, add the four events to it). The block
looks like this, with real paths filled in:

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash /path/to/claude-status-bar/hook.sh busy" }] }],
  "Stop":            [{ "hooks": [{ "type": "command", "command": "bash /path/to/claude-status-bar/hook.sh waiting" }] }],
  "Notification":    [{ "hooks": [{ "type": "command", "command": "bash /path/to/claude-status-bar/hook.sh needs_input" }] }],
  "SessionEnd":      [{ "hooks": [{ "type": "command", "command": "bash /path/to/claude-status-bar/hook.sh end" }] }]
}
```

Then **start a new Claude Code session** and give it something to do — the red bar
appears while it works. (Hooks load at session start, so already-open sessions won't
drive the bar until restarted.)

### Verify

```bash
echo '{"session_id":"test"}' | ./hook.sh busy    # bar should appear
echo '{"session_id":"test"}' | ./hook.sh end     # bar should disappear
```

## Uninstall

```bash
./uninstall.sh
```

Stops and removes the LaunchAgent and the state directory. It intentionally does not
edit `settings.json` — remove the four ccbar `hooks` entries yourself, then delete
the repo folder.

## How it works

1. Claude Code **hooks** fire on state change and run `hook.sh`, which writes one
   small JSON file per session into `~/.claude/ccbar/state/<session_id>.json`:
   - `UserPromptSubmit` → `busy` (you handed off; Claude is working)
   - `Stop` → `waiting` (turn finished)
   - `Notification` → `needs_input` (permission prompt / idle)
   - `SessionEnd` → deletes the file
2. `ccbar` (a tiny AppKit app, one borderless click-through window per screen at
   `.screenSaver` level, on all Spaces) polls the state directory every 0.4s: **solid**
   if any live session is `busy`, else **pulsing** if any is `needs_input`, else
   hidden (`waiting` — a finished turn — shows nothing).

Multi-session just works: each session is its own file keyed by `session_id`, so
three concurrent sessions share one bar — solid if *any* is working, pulsing if *any*
needs your input. Stale files (older than 12h, e.g. from a crash that skipped
`SessionEnd`) are ignored.

## Configuration

Constants at the top of `ccbar.swift` (rebuild + restart the agent after changing —
`./install.sh` again does both):

| Constant       | Default | Meaning                                            |
|----------------|---------|----------------------------------------------------|
| `barHeight`    | `16`    | Bar thickness in px. Bump to 24+ for a big room.   |
| `atTop`        | `false` | `true` pins the bar to the top edge instead.       |
| `barColor`     | red     | The bar color.                                     |
| `pollInterval` | `0.4`   | Seconds between state-dir polls.                   |
| `staleAfter`   | `43200` | Ignore state files older than this (seconds).      |

## Files

| File               | Purpose                                                        |
|--------------------|----------------------------------------------------------------|
| `ccbar.swift`      | The whole app (AppKit, single file).                           |
| `hook.sh`          | Claude Code hook target; writes one state file per session.    |
| `install.sh`       | Build + install LaunchAgent + print the hooks block.           |
| `uninstall.sh`     | Stop + remove the LaunchAgent and state dir.                   |
| `ccbar`            | Compiled binary (gitignored — built by `install.sh`).          |

## Notes

- `Stop` is the main-agent stop only (`SubagentStop` is a separate, unhooked event),
  so the bar tracks real turn boundaries, not sub-agent churn.
- The bar sits at the very bottom edge. If your Dock is at the bottom and hides it,
  set `atTop = true` or increase `barHeight`.
