# kriasetup

Project for fixes, setup and maintenance of an AMD/Xilinx Kria KR260 running Ubuntu 22.04
(kernel 5.15.0-xilinx-zynqmp, GNOME on X11). This directory runs *on* the board.
Record findings and fixes in `docs/`, one file per topic (e.g. `docs/display.md`), and keep
the contents table and "Installed on the board" table in `README.md` up to date.
Read `docs/firmware-updates.md` before any update task.

## Environment facts
- X display is `:1` (set `DISPLAY=:1` when running from SSH or a serial console). Output is `DP-1`.
- No passwordless sudo: `dmesg`, `/sys/kernel/debug` are not readable. Gather info from
  `/sys/class/drm`, `/proc/device-tree`, `xrandr --verbose`, `gsettings`, or ask the user to run `! sudo …`.
- DisplayPort is **single-lane**, so the pixel clock is capped at ~90 MHz. Do not try to get
  1080p60 out of the PS DP port. See `docs/display.md` before touching display modes.

## How to work on this board
- Display changes can leave the user with a blank screen they can't see past. Always pair a
  mode switch with an auto-revert running in the background (e.g. 90 s), plus a way to keep the change
  (`touch .keep`). Tell the user exactly what to run to keep the change.
- Make runtime changes (`xrandr`) first and persist them only after the user confirms they
  work. Always give the revert command for anything persistent (gsettings, xorg.conf,
  device tree, boot args).
- Never `pkill -f` with a pattern that also appears in the same command line: it kills
  the invoking shell (this happened once and produced exit code 144).
- Changes to the device tree, boot command line, or bitstream/firmware are hard to undo on this board:
  confirm with the user first.
- Boot firmware (QSPI `BOOT.BIN`) updates: never run `xmutil bootfw_update -i` without the user's
  explicit go-ahead and a KR260-specific `BOOT.BIN` they provided or approved. Record
  `sudo xmutil bootfw_status` before and after. `fwupd` sees no devices here and isn't used.
- After any fix or experiment, update the relevant `docs/*.md` with the result and the revert steps.
- Log every system change (files installed, services, settings) in `docs/changelog.md`,
  newest first: what, why, how it was verified, how to check it's still needed, and how to remove it.
- Installed workarounds to review after kernel or firmware updates: `dp-wake-fix` user service
  (see `docs/changelog.md`).
