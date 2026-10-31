# Lenovo LOQ Camera Switch

A Noctalia bar widget that shows the state of the physical camera shutter
switch on Lenovo LOQ laptops, and shows Noctalia's native OSD when you flip it.

> **⚠️ Tested on one laptop only: the Lenovo LOQ 15IRX9.**
> It will probably not work on any other laptop without extra work. It reads a
> byte from the embedded controller (EC), and which byte and bit hold the switch
> differs between models, including other Lenovo models. I do not know of any
> other machine where it works. See [Finding your own values](#finding-your-own-values)
> if you want to try anyway.

> **⚠️ Disclaimer: this plugin is fully vibe-coded.**
> It was written with Claude Code, and the author does not claim to understand
> every line. Read the code before you trust it, and expect rough edges. It is
> provided as is, with no warranty. Issues and fixes are welcome.

## Plugin

| Field | Value |
| --- | --- |
| ID | `augussst/lenovo-loq-camera-switch` |
| Entries | Bar widget: `indicator` |

## Requirements

- Noctalia with `plugin_api` 39 or newer (`noctalia.osd.show`).
- `od` (GNU coreutils) on `PATH`. It is the only command the plugin runs.
- The `ec_sys` kernel module, and read access to the EC memory file. See
  [One-time setup](#one-time-setup).
- A laptop whose shutter state is stored in the embedded controller (EC). The
  defaults (byte 31, bit value 64) are for the Lenovo LOQ 15IRX9 and **will
  not be right for most other models**. See
  [Finding your own values](#finding-your-own-values).

### One-time setup

Reading the EC needs root once, to load a module and open permissions:

    echo ec_sys | sudo tee /etc/modules-load.d/ec_sys.conf
    printf 'z /sys/kernel/debug 0711 root root -\nz /sys/kernel/debug/ec/ec0/io 0444 root root -\n' | sudo tee /etc/tmpfiles.d/ec-camera.conf
    sudo modprobe ec_sys
    sudo systemd-tmpfiles --create /etc/tmpfiles.d/ec-camera.conf

**Security note:**
- The EC file is the **entire** EC memory (256 bytes), not just the camera
  switch. Besides the switch it holds things like fan, temperature, battery and
  other button states. This setup makes it readable by every user and program on
  the machine. Writing to the EC stays off.
- It also makes `/sys/kernel/debug` traversable (not listable) by everyone, so
  any other debugfs file that is world-readable becomes reachable too. On a
  single-user laptop that mostly means other programs running as you can read
  it; on a shared machine it is a weaker choice.
- Permissions cannot be limited to one byte. A stricter design is a small root
  service that reads the EC and publishes only "on" or "off" to a file. This
  plugin does not ship one.

If that is not acceptable to you, do not use this plugin.

Check that it worked; this should print a number:

    od -An -tu1 -j31 -N1 /sys/kernel/debug/ec/ec0/io

### Finding your own values

With the shutter closed, then open, run:

    sudo od -v -An -tu1 -w1 /sys/kernel/debug/ec/ec0/io | nl -v0 > off.txt   # shutter closed
    sudo od -v -An -tu1 -w1 /sys/kernel/debug/ec/ec0/io | nl -v0 > on.txt    # shutter open
    diff off.txt on.txt

Each line is one byte, numbered from 0, so the number on the line that
changes is the byte offset. The difference between the two values is the
mask, for example 98 - 34 = 64. If your laptop sets the bit when the camera is
OFF, enable **Invert state**.

## Usage

Add the **Lenovo LOQ Camera Switch → indicator** widget to your bar in
Noctalia's settings.

- The icon shows the camera when the shutter is open and a crossed-out camera
  (in the error color) when it is closed.
- Flipping the switch shows a popup, "Camera Enabled" or "Camera Disabled".
  There is no popup at login.
- Clicking the icon shows the current state as a popup.
- A dimmed icon means the state cannot be read. The tooltip says so. Check
  the setup above.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `ec_path` | `string` | `/sys/kernel/debug/ec/ec0/io` | File that exposes the EC memory. |
| `ec_offset` | `int` | `31` | Byte of the EC memory that holds the switch state (decimal, 0–255). |
| `ec_mask` | `int` | `64` | Single bit of that byte that is set when the camera is ON (1, 2, 4, 8, 16, 32, 64 or 128). |
| `ec_invert` | `bool` | `false` | Turn on if your laptop sets the bit when the camera is OFF. |
| `poll_ms` | `int` | `500` | How often the switch is read, in milliseconds (200–5000). Changing it needs a plugin reload. |
| `show_osd` | `bool` | `true` | Show Noctalia's OSD when the switch changes. |

## Notes

- **Spawned processes:** `od`, once every `poll_ms` (default 500 ms), to read
  one byte of the EC file. It is started directly, without a shell.
- **Network access:** none.
- **Files written:** none. The plugin only reads the EC file.
- **Known limits:** only the EC route is supported; laptops that expose the
  shutter as an input switch or a sysfs file are not covered. A wrong offset
  or mask shows a wrong state with no error. Tested on one model only.
- **Debugging:** run the check command above in a terminal. If it prints a
  number but the widget is dimmed, the problem is in the plugin; if it fails
  with "Permission denied", the one-time setup did not apply.
