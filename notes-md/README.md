# Notes MD

Markdown notes in a side panel, with an **interactive preview**: tick tasks,
open links, jump between notes and copy code without switching to edit mode.
A fork of Noctalia's official Notes plugin.

> **⚠️ Disclaimer: the Markdown features are fully vibe-coded.**
> They were written with Claude Code, and the author does not claim to
> understand every line. Tested on one machine (Noctalia 5.4.0, niri). Your
> notes are plain `.md` files and stay readable without this plugin, but keep
> a backup if they matter to you.

## Plugin

| Field | Value |
| --- | --- |
| ID | `augussst/notes-md` |
| Entries | Bar widget: `notes`; panel: `panel`; launcher provider: `launcher` |
| Launcher Prefix | `/nt` |

## Requirements

`xdg-open` (xdg-utils) on `PATH`, used to open links and images.

## Usage

Add the **Notes MD → notes** widget to your bar, or open the panel directly:

```sh
noctalia msg panel-toggle augussst/notes-md:panel
```

Notes with content open in the **preview**; empty notes open in the
**editor**. The pencil / eye button in the note header switches between them.

In the preview:

| Markdown | What you can do |
| --- | --- |
| `- [ ] task`, `1. [x] task` | Click the box to tick or untick it; the file is saved. |
| `[text](https://…)`, bare `https://…` | A line with one link becomes clickable: accent-colored, with a link icon. Click it to open the link. |
| `[text](other-note.md)`, `[text](~/file.pdf)` | Note links open in the panel; other files open in their app. |
| `[[Note name]]`, `[[Note name\|shown text]]` | Opens that note, same as above with a note icon. Links to notes that do not exist stay plain text, so typos stand out. |
| Several links on one line, links in tables or quotes | Each link gets a small chip under its paragraph. |
| `![alt](~/Pictures/x.png)` | Shows the image (local files; relative paths are from the notes folder). Click to open it. |
| ```` ``` ```` code blocks | A copy button above the block. |
| `> quote` | Shown as an indented block with a bar. |

Headings, bold, italic, strikethrough, inline code, lists, tables and rules
are rendered by Noctalia's built-in Markdown view.

Line breaks and empty lines show in the preview the way you typed them, like
in a notes app: Enter starts a new line, and each blank line is an empty line
(standard Markdown would join lines and collapse blank lines). Blank lines
right after a heading are skipped, since headings already have space.

In the editor:

- Pressing Enter at the end of a list item starts the next item (bullets,
  numbers and task boxes); Enter on an empty item ends the list.
- Typing `[[` lists matching notes under the editor; click one to complete the
  link.

In the note list, drag a note by its grip (≡) to reorder. Pinned notes stay on
top and are not draggable (they show a pin instead of the grip). The order is saved
in `.order.json` in the notes folder. The sort button cycles between your
order, by name and by last change.

To open a note from a script or keybinding (the panel must be open):

```sh
noctalia msg plugin augussst/notes-md:panel all open "Note name"
noctalia msg plugin augussst/notes-md:panel all list
```

The launcher works like the original: type `/nt` to search notes, create a
note, or add to the scratchpad.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `notes_dir` | `folder` | `$XDG_DOCUMENTS_DIR/Notes` | Where note files are stored. |
| `extension` | `string` | `md` | File extension of notes (without the dot). |
| `glyph` (widget) | `glyph` | `notes` | Icon shown on the bar. |

## Notes

- **Spawned processes:** `xdg-open`, only when you click a link or image.
- **Network access:** none. Web images are not downloaded; they show as a link
  chip that opens in the browser.
- **Files written:** notes in the notes folder (on save and task toggles), plus
  the hidden `.pinned.json` and `.order.json` next to them. Notes are renamed
  or deleted only when you do so in the panel. Links never create notes.
- **Clipboard:** the copy button on a code block copies its text.
- **Limits:**
  - A link cannot be clicked on its own inside a sentence (Noctalia's
    Markdown view does not support it): the whole line is the link, or a line
    with several links gets chips.
  - Noctalia 5.4's Markdown view does not show bold, italic, strikethrough or
    link underlines (headings, lists, code and tables are fine).
  - List continuation and `[[` suggestions only work at the end of the note:
    plugins cannot see the editor's cursor.
  - No syntax highlighting while editing.
  - Images are shown at a fixed size (360×220, scaled to fit).
- **Same notes as the official plugin:** it uses the same folder and settings
  names, so you can switch between them. Disable the official Notes plugin to
  avoid two `/nt` launcher entries.

## Credits

Based on the official [Notes](https://github.com/noctalia-dev/official-plugins)
plugin by the Noctalia contributors (MIT). The thumbnail is from the original
plugin.
