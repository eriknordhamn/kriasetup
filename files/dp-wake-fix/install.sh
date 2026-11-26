#!/bin/bash
# Install the dp-wake-fix user service (see docs/changelog.md for why it exists).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
install -Dm755 "$here/dp-wake-fix" ~/.local/bin/dp-wake-fix
install -Dm644 "$here/dp-wake-fix.service" ~/.config/systemd/user/dp-wake-fix.service
systemctl --user daemon-reload
systemctl --user enable --now dp-wake-fix.service
systemctl --user is-active dp-wake-fix.service
