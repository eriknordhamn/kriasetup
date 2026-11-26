# Changelog: changes made to this KR260

Every change made to the system, why it was made, and how to undo it. Newest first.
Details and background: `docs/display.md`.

---

## 2026-11-26: Boot firmware baseline recorded (no change)

`sudo xmutil bootfw_status`: QSPI `XilinxSom_QspiImage-k26-v2.1-06140636`.
Booting **Image A** `k26-smk-kr-sdt-v1.08-20261107132709` (both slots bootable);
Image B `k26-smk-v1.04-20250410071436`. Display issues and the `dp-wake-fix` workaround were
observed on Image A v1.08. Details: `docs/firmware-updates.md`.

---

## 2026-11-26: DP wake-fix service (workaround)

**Problem:** after the screen blanks (GNOME idle → DPMS off), moving the mouse did not
bring the picture back; the monitor showed "no signal" until it was replugged.

**Why:** on wake the `zynqmp_dp` kernel driver trains the DisplayPort link once. The
Dell P2317H is still in deep sleep, so training fails
(`zynqmp-display fd4a0000.display: failed to train the DP link`) and the driver never
retries. The monitor has no setting to disable deep sleep. Reproduced on purpose with
`xset dpms force off`, then `xset dpms force on`.

**What was added:**
| File | Purpose |
|---|---|
| `~/.local/bin/dp-wake-fix` | Watches `journalctl -k` for the training error and cycles `xrandr --output DP-1 --off` then back to the current mode (up to 3 tries, 10 s cooldown) |
| `~/.config/systemd/user/dp-wake-fix.service` | User service, enabled, starts with the graphical session |
| `~/.config/systemd/user/graphical-session.target.wants/dp-wake-fix.service` | Symlink created by `systemctl --user enable` |

Source copies and installer: `files/dp-wake-fix/` (`install.sh` reinstalls and enables it).

**Verified:** forced DPMS off for 25 s then woke it; the service recovered the picture on the first attempt about 5 s after wake.
Confirmed in real use: after a normal idle blank, moving the mouse woke the display
(service log at 19:01:55, retrained on attempt 1).

### Is it still needed?
The service is a workaround for a driver bug. Check it again after a kernel or firmware update
(`uname -r` was `5.15.0-1080-xilinx-zynqmp`) or after changing the monitor.

1. See whether it has been doing anything:
   ```sh
   journalctl --user -u dp-wake-fix --no-pager | grep retrain
   ```
   No "retraining" lines over a long period means it is not being used.
2. Test without it:
   ```sh
   systemctl --user stop dp-wake-fix.service
   DISPLAY=:1 xset dpms force off; sleep 25; DISPLAY=:1 xset dpms force on
   journalctl -k --since "-1min" | grep "train the DP link"
   ```
   If the picture comes back **and** there is no training error, the service is no longer needed.
   If the screen stays black, recover with
   `DISPLAY=:1 xrandr --output DP-1 --off && DISPLAY=:1 xrandr --output DP-1 --mode 1024x768`
   (run over SSH if needed) and start the service again: `systemctl --user start dp-wake-fix.service`.

### Remove it
```sh
systemctl --user disable --now dp-wake-fix.service
rm ~/.config/systemd/user/dp-wake-fix.service ~/.local/bin/dp-wake-fix
systemctl --user daemon-reload
```

---

## 2026-11-26: GNOME idle settings

| Setting | Original | Now | Why |
|---|---|---|---|
| `org.gnome.desktop.session idle-delay` | `300` | `300` | Briefly set to `0` to prevent the blank. Restored once the wake-fix service handled recovery |
| `org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type` | `'suspend'` | `'nothing'` | Idle suspend of the whole board risks the same DP/resume failures; the wake-fix service only covers screen blanking |

Revert idle suspend: `gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'`

---

## 2026-11-26: Resolution experiments (no lasting change)

Tried custom xrandr modes to get past 1024x768 (the single DP lane caps the pixel clock at ~90 MHz).
All were removed; the system is on the original 1024x768@60. Nothing persistent was
installed. See `docs/display.md`.
