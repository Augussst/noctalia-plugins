# Working on these plugins

How to change a plugin, test it in Noctalia, and publish it. Commands are for
fish, but work in bash too.

## Setup (once per machine)

```sh
git clone https://github.com/Augussst/noctalia-plugins ~/Projects/Personal/noctalia-plugins
noctalia msg plugins source add augussst git https://github.com/Augussst/noctalia-plugins
noctalia msg plugins enable augussst/notes-md
noctalia msg plugins enable augussst/lenovo-loq-camera-switch
```

## Repo layout

| Path | What it is |
| --- | --- |
| `<plugin>/` | One folder per plugin. Its name must match the part of the id after the `/` (`augussst/notes-md` → `notes-md/`). Everything in it is installed on users' machines. |
| `<plugin>/plugin.toml` | The manifest: id, name, `version`, `plugin_api`, settings, entries (widgets, panels, launcher). |
| `<plugin>/*.luau` | The code. One file per entry, plus shared modules loaded with `require("./file.luau")`. |
| `<plugin>/translations/en.json` | Every `label_key` / `description_key` used in the manifest, and strings for `noctalia.tr()`. |
| `catalog.toml` | **Generated, never edit by hand.** Git sources list plugins from it. |
| `tools/update_catalog.py` | Regenerates `catalog.toml` from the manifests. |
| `.github/workflows/catalog.yml` | Runs the generator on every push to `main` and commits the result. |
| `tests/` | Tests that run with plain `lua` (not installed with the plugins). |

## Quick change: edit, push, update

Fine for small fixes:

1. Edit the plugin.
2. Bump `version` in its `plugin.toml` (semver: `1.0.0` → `1.0.1` for a fix,
   `1.1.0` for a feature).
3. Commit and push:

   ```sh
   python3 tools/update_catalog.py   # optional, see "The catalog" below
   git add -A
   git commit -m "notes-md: what changed"
   git push
   ```

4. Pull the new version into Noctalia:

   ```sh
   noctalia msg plugins update augussst
   ```

## Bigger work: run straight from your folder

Pushing for every test is slow. Point Noctalia at your working folder instead,
so it loads the files as you save them. Only one source may provide a plugin
id at a time, so swap the GitHub source out while you work:

```sh
noctalia msg plugins source remove augussst
noctalia msg plugins source add augussst-dev path ~/Projects/Personal/noctalia-plugins
noctalia msg plugins enable augussst/notes-md     # and/or the camera plugin
```

After editing, reload the plugin:

```sh
noctalia msg plugins disable augussst/notes-md
noctalia msg plugins enable augussst/notes-md
```

When you are done, push, then switch back:

```sh
noctalia msg plugins source remove augussst-dev
noctalia msg plugins source add augussst git https://github.com/Augussst/noctalia-plugins
noctalia msg plugins enable augussst/notes-md
noctalia msg plugins enable augussst/lenovo-loq-camera-switch
```

Your bar widgets and settings survive the swap: they are tied to the plugin
id, not the source.

## Testing

**Errors.** Noctalia logs script errors and rejected UI properties (typos in
prop names are reported, not silently ignored):

```sh
tail -f ~/.cache/noctalia/noctalia.log | grep -i -E 'luau|error|warn|unknown'
```

**Opening things without clicking.** Panels can be opened from the terminal,
and Notes MD accepts IPC events while its panel is open:

```sh
noctalia msg panel-toggle augussst/notes-md:panel
noctalia msg plugin augussst/notes-md:panel all open "Note name"
noctalia msg plugin augussst/notes-md:panel all list
```

**Notes MD preview logic.** The Markdown parsing in `notes-md/preview.luau`
has tests that run without Noctalia:

```sh
lua tests/notes_md_preview.lua
```

They should print `ALL PASS`. Keep `preview.luau` in the Lua/Luau common
subset (no `+=`, no `continue`, no string interpolation) so these keep working;
the other `.luau` files can use full Luau.

**Camera plugin.** The widget reads one EC byte. Check it by hand:

```sh
od -An -tu1 -j31 -N1 /sys/kernel/debug/ec/ec0/io   # 98 = on, 34 = off (LOQ 15IRX9)
```

## The catalog

`catalog.toml` is rebuilt from the manifests, so you only ever edit
`plugin.toml`:

- On every push to `main`, the GitHub Action regenerates it and commits it if
  it changed. When that happens your local copy is one commit behind: run
  `git pull` before your next push.
- To avoid that, run `python3 tools/update_catalog.py` before committing; the
  Action then finds nothing to change.
- `updated_at` is the date the current `version` first appeared, so it only
  moves when you bump the version. `added_at` is the plugin's first commit.
- The generator refuses manifests that miss a required field (`id`, `name`,
  `version`, `author`, `plugin_api`, `tags`) or whose folder name does not
  match the id.

## Adding a new plugin

1. Create a folder named after the plugin, e.g. `my-plugin/`.
2. Add `plugin.toml` with `id = "augussst/my-plugin"`, a `version`, the lowest
   `plugin_api` it needs, `tags`, and its entries.
3. Add the `.luau` entry files, `translations/en.json`, a `README.md` and a
   `thumbnail.webp` (960×540).
4. Add it to the table in the main `README.md`.
5. Test it with the dev source above, then push. The catalog picks it up
   automatically; users enable it with
   `noctalia msg plugins enable augussst/my-plugin`.

## References

- Noctalia plugin docs: <https://docs.noctalia.dev/noctalia/plugins/>
- API levels per feature: `docs/plugin-api.json` in
  [noctalia-dev/noctalia](https://github.com/noctalia-dev/noctalia)
- Examples, including drag and drop: `example/` in
  [noctalia-dev/official-plugins](https://github.com/noctalia-dev/official-plugins)
- UI component properties (the authoritative list): `knownProps` in
  `src/ui/ui_tree_reconciler.cpp` in the Noctalia repo
