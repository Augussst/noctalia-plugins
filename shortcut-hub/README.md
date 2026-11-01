# Shortcut Hub

A panel of shortcuts with no limit on how many: the panels of your other
plugins, Noctalia's own panels, and shell commands. Use it for the tools you
open now and then, which don't deserve a keybind or one of the control
center's six shortcut slots.

## Plugin

| Field | Value |
| --- | --- |
| ID | `augussst/shortcut-hub` |
| Entries | Panels: `compact`, `panel`, `wide`; launcher providers: `launcher`, `search`; shortcut: `open`; bar widget: `hub` |
| Launcher Prefix | `/hub` (every panel), `/hubs` (hub items only, also in global search) |

## Requirements

`sh` on `PATH`: custom commands run with `/bin/sh -c`. Shell panels (Launcher,
Clipboard, ...) are opened with the `noctalia` CLI, which comes with Noctalia.

## Usage

The hub is a panel in three sizes. Open one with:

```sh
noctalia msg panel-toggle augussst/shortcut-hub:compact
noctalia msg panel-toggle augussst/shortcut-hub:panel
noctalia msg panel-toggle augussst/shortcut-hub:wide
```

| Panel | Width | Columns |
| --- | --- | --- |
| `compact` | 320 px | 3 |
| `panel` | 440 px | 4 |
| `wide` | 640 px | 6 |

The height follows the number of tiles. Click a tile to open it. Bind one of
the commands above to a key, or use one of these:

- **Control center:** add the **More** shortcut (`open`) in the control center's
  shortcut settings. It opens the hub, so one slot reaches everything.
- **Bar:** add the **Shortcut Hub** widget (`hub`) in the bar settings.
- **Launcher:** type `/hub` to list your hub items, then every panel of every
  enabled plugin and the shell panels; type more to filter, for example
  `/hub notes`. Activating a result opens it. In normal launcher search, only
  the items already in your hub appear, so internal panels of other plugins do
  not clutter it (`/hubs` shows the same list).

The control-center shortcut, the bar widget and the launcher open the size
chosen in the **Panel size** setting.

### Editing the hub

Click the pencil in the panel header, or open the panel straight into edit
mode:

```sh
noctalia msg panel-open augussst/shortcut-hub:panel edit
```

- **In the hub:** reorder with the arrows, remove with the bin.
- **Plugin panels:** every `[[panel]]` of every enabled plugin, with a `+`
  to add it. Some plugins have internal panels (for example a result popup)
  that do nothing useful on their own; just don't add those.
- **Shell panels:** Launcher, Control Center, Clipboard, Wallpaper, Session
  Menu, Settings.
- **Custom command:** a label, a shell command, and an optional
  [Tabler icon](https://tabler.io/icons) name. Any `noctalia msg ...` command
  works, for example `noctalia msg nightlight-toggle`.

Click the check mark to finish. The panel closes and reopens for a moment so
its height fits the grid again: Noctalia grows a panel to fit its content but
does not shrink it while it stays open.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `panel_size` | `select` | `normal` | Size opened by the control-center shortcut, the bar widget and the launcher: `compact`, `normal` or `wide`. Keybinds can open any size directly. |
| `columns` | `int` | `0` | Tiles per row. `0` uses the size's own count (3, 4 or 6). Capped so tiles stay at least about 70 px wide. |
| `glyph` (bar widget) | `glyph` | `layout-grid` | Icon of the bar widget. |

Tile corners follow the shell's `corner_radius_scale`.

## IPC

While a hub panel is open, switch between the grid and edit mode:

```sh
noctalia msg plugin augussst/shortcut-hub:panel all edit
noctalia msg plugin augussst/shortcut-hub:panel all view
```

Use `:compact` or `:wide` instead of `:panel` for the other sizes.

## Notes

- **Files read:** the shell settings `plugins.enabled` and `plugins.source`,
  and the `plugin.toml` of each enabled plugin, to list their panels. Only
  `id`, `name`, `icon` and the `[[panel]]` ids are read. For `path` sources
  the manifest is read from the source folder; for git sources from
  Noctalia's unpacked copy, found next to this plugin's data folder
  (`<state>/plugins/materialized/<source>/<plugin>`). That layout is not a
  documented API, so a future Noctalia version could break the panel list
  (the hub itself keeps working).
- **Files written:** only `items.json` in this plugin's data folder
  (`noctalia.pluginDataDir()`).
- **Processes:** `noctalia msg panel-toggle <id>` or
  `noctalia msg settings-toggle` for shell panels, `sh -c` to reopen the panel
  after editing (`sleep 0.2; noctalia msg panel-open <id>`), and your own
  custom commands with `/bin/sh -c`. Plugin panels open through
  `noctalia.togglePanel` without a process.
- **Network:** none.
- **Limit:** a tile can open a panel or run a command, but it cannot press
  another plugin's control-center shortcut: Noctalia has no API for that.
