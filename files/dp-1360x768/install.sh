#!/bin/bash
# Install the 1360x768 X mode for DP-1 (see docs/changelog.md). Needs sudo.
# Then log out and back in (or reboot) and pick 1360x768 in Settings → Displays.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
sudo install -Dm644 "$here/10-dp-1360x768.conf" /etc/X11/xorg.conf.d/10-dp-1360x768.conf
ls -l /etc/X11/xorg.conf.d/
