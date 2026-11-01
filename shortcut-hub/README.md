# Shortcut Hub

A panel of shortcuts with no limit on how many: the panels of your other
plugins, Noctalia's own panels, and shell commands. Use it for the tools you
open now and then, which don't deserve a keybind or one of the control
center's six slots.

## What it adds

| Entry | What it does |
| --- | --- |
| Panels `:compact`, `:panel`, `:wide` | A grid of tiles in three sizes (320, 440 and 640 px wide; 3, 4 and 6 columns). The height follows the number of tiles. Click a tile to open it; the pencil button switches to edit mode. |
| Launcher `/hub` | Your hub items, then every panel of every enabled plugin and the shell panels. Type to filter. |
| Launcher (global search) | Only the items in your hub, so typing e.g. "notes" in the normal launcher finds them. Also reachable as `/hubs`. |
| Control-center shortcut "More" | Opens the hub. Put it in one control-center slot to reach everything else. |
| Bar widget | Opens the hub. |

## Using it

Open the hub any of these ways:

    noctalia msg panel-toggle augussst/shortcut-hub:panel     # normal
    noctalia msg panel-toggle augussst/shortcut-hub:compact   # or :wide
    noctalia msg panel-open augussst/shortcut-hub:panel edit  # straight into edit mode

or bind the first command to a key, add the "More" tile to the control
center, or add the bar widget.

In edit mode:

- **In the hub**: reorder with the arrows, remove with the bin.
- **Plugin panels**: every `[[panel]]` of every enabled plugin. Some plugins
  have internal panels (for example a result popup) that do nothing useful
  when opened on their own; just don't add those.
- **Shell panels**: Launcher, Control Center, Clipboard, Wallpaper, Session
  Menu, Settings.
- **Custom command**: a label, a shell command, and an optional
  [Tabler icon](https://tabler.io/icons) name. Any `noctalia msg ...` command
  works here, e.g. `noctalia msg nightlight-toggle` or
  `noctalia msg caffeine-toggle`.

Settings (Settings → Plugins → Shortcut Hub):

- **Panel size**: Compact, Normal or Wide. This is the size the bar widget,
  the "More" tile and the launcher open. A keybind can open any size directly.
- **Columns**: tiles per row; `0` (default) uses the size's own column count.

While the panel is open, `noctalia msg plugin augussst/shortcut-hub:panel all
edit` (or `view`) switches mode. Leaving edit mode closes and reopens the
panel for a moment: Noctalia grows a panel to fit its content but does not
shrink it while it stays open.

## Limits

- Tiles open panels or run commands. They cannot press another plugin's
  control-center tile (`[[shortcut]]`): Noctalia has no API for that. Use a
  command instead when the plugin offers one.
- Plugin panels are found by reading each enabled plugin's `plugin.toml`
  (from its source folder, or Noctalia's unpacked copy for git sources).
  Only the `id`, `name`, `icon` and `[[panel]]` ids are read.

## What it reads, writes and runs

- Reads: the shell settings `plugins.enabled` and `plugins.source`, and the
  `plugin.toml` of each enabled plugin.
- Writes: `items.json` in its own data folder
  (`~/.local/state/noctalia/plugins/data/augussst/shortcut-hub/`).
- Runs: `noctalia msg panel-toggle <id>` / `noctalia msg settings-toggle` for
  shell panels, and your custom commands with `/bin/sh -c`.
