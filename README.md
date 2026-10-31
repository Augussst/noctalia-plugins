# Augussst's Noctalia plugins

Plugins for the [Noctalia](https://github.com/noctalia-dev/noctalia) shell.

> **Vibe-coded.** These were written with Claude Code and tested on one
> machine (Lenovo LOQ 15IRX9, Noctalia 5.4.0, niri). Read the code before you
> trust it. Each plugin's README lists what it does, its limits, and what it
> reads, writes and runs.

| Plugin | What it does |
| --- | --- |
| [Notes MD](notes-md/README.md) | Markdown notes in a side panel with an interactive preview: tick tasks, open links and `[[note links]]`, copy code, see images, drag to reorder. A fork of the official Notes plugin. |
| [Lenovo LOQ Camera Switch](lenovo-loq-camera-switch/README.md) | Bar icon and OSD for the physical camera shutter switch. **Tested on the LOQ 15IRX9 only**; needs a one-time root setup. |

## Install

This repository is a Noctalia plugin source. Add it once:

    noctalia msg plugins source add augussst git https://github.com/Augussst/noctalia-plugins

Then enable the plugins you want:

    noctalia msg plugins enable augussst/notes-md
    noctalia msg plugins enable augussst/lenovo-loq-camera-switch

You can also add the source in **Settings → Plugins → Add source**. After
enabling, add the plugin's widget to your bar in Noctalia's settings, and read
the plugin's README for any setup it needs.

## Update

    noctalia msg plugins update augussst

## Uninstall

    noctalia msg plugins disable augussst/notes-md
    noctalia msg plugins disable augussst/lenovo-loq-camera-switch
    noctalia msg plugins source remove augussst

## Working on the plugins

See [DEVELOPING.md](DEVELOPING.md): repo layout, the edit/test/publish loop,
how to run a plugin straight from a local folder, tests, the generated
catalog, and adding a new plugin.

## License

MIT, see [LICENSE](LICENSE). Notes MD is based on the official Notes plugin by
the Noctalia contributors; see [notes-md/LICENSE](notes-md/LICENSE).
