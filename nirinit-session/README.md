# Session Restore

A Noctalia plugin that asks before niri restores your last session. It wraps
[nirinit](https://github.com/amaanq/nirinit), which normally reopens every
saved window the moment it starts, with no way to say no.

> **Vibe-coded.** Written with Claude Code and tested on one machine (niri,
> nirinit 0.3.x). Read the code before you trust it.

## Plugin

| Field | Value |
| --- | --- |
| ID | `augussst/nirinit-session` |
| Entries | Bar widget `indicator`, panel `panel` |

## How it works

nirinit restores at startup and then saves every N seconds. Instead of
starting nirinit directly, niri starts `bin/nirinit-ctl start`:

1. If the saved `session.json` has windows nirinit would reopen, it is moved to
   `pending.json`.
2. `nirinit-ctl` then becomes nirinit. With nothing to restore, nirinit just
   saves your new session as usual.
3. The widget sees `pending.json` and (setting **Open at login**) opens the
   panel once. **Restore** runs a second, short nirinit on a copy of the
   pending file, so windows open with the same positions and sizes, and the
   live `session.json` is never touched. **Start fresh** moves it to
   `session.last.json` (the panel can **Bring it back**). **Later** leaves it
   waiting; it stays until you answer, even across logins.

## Settings tab

- **At login**: ask (default) or restore automatically (`ctl.json` `mode`).
- **Save every N seconds**: overrides `--save-interval` from the autostart
  line (0 = use the argument).
- **Never reopen these apps**: edits `apps = [...]` under `[skip]` in
  `~/.config/nirinit/config.toml` (comments kept, backup `config.toml.bak`),
  with buttons to add apps from your saved windows.

nirinit reads its config once at startup, so all of these apply at the next
login. Wrapper settings live in `~/.config/nirinit/ctl.json`.

Apps in your nirinit `[skip]` list are not counted, as nirinit would not reopen
them.

## Setup

Needs `nirinit` in `~/.local/bin` (or on `PATH`) and `python3`.

    noctalia msg plugins enable augussst/nirinit-session

Add the **Session Restore** widget to your bar, then make niri start the
wrapper instead of nirinit. In `autostart.kdl`:

    spawn-at-startup "~/.local/bin/nirinit-ctl" "start" "--save-interval" "120"

with a link to the script:

    ln -sf ~/.local/share/noctalia/plugins/<source>/nirinit-session/bin/nirinit-ctl ~/.local/bin/nirinit-ctl

(For a path source, link to the script in your checkout.) Without the plugin
enabled the session would be held and never offered, so enable it first.
`nirinit-ctl start --auto ...` restores like plain nirinit.

## What it reads, writes and runs

- Runs `python3 bin/nirinit-ctl` and `pgrep`.
- Reads and, from the Settings tab, edits `~/.config/nirinit/config.toml`; writes `ctl.json` next to it; reads and the files in
  `~/.local/share/nirinit/`; moves them between `session.json`,
  `pending.json`, `session.last.json` and `session.restored.json`.
- Writes `~/.cache/nirinit-ctl/` (a lock and the "already asked" marker).
