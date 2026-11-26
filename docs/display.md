# KR260 display setup

Board: AMD/Xilinx Kria KR260, Ubuntu (kernel 5.15.0-xilinx-zynqmp), GNOME on X11 (`DISPLAY=:1`).
Monitor: Dell P2317H (1920x1080@60 native, accepts 56–76 Hz vertical) on DisplayPort `DP-1`.

## Resolution is capped at 1024x768 (hardware limit)

- The EDID is read correctly; the monitor advertises 1920x1080.
- The device tree (`/proc/device-tree/axi/display@fd4a0000/phys`) wires **one** PS-GTR
  lane to DisplayPort (`dp-phy0` only).
- 1 lane × 2.7 Gbps at 24 bpp ⇒ max pixel clock ≈ **90 MHz**. The `zynqmp_dp` driver
  drops every mode above that. 1080p60 needs 148.5 MHz, so it cannot work on this port.
- Real 1080p requires a PL (FPGA) HDMI/DP output or a USB display adapter.

### Custom modes tested (2026-11-26)

| Mode | Pixel clock | Result |
|---|---|---|
| 1600x900 @57.5 Hz, tight reduced blanking | 89.50 MHz | No confirmed result |
| 1368x768 @60 (CVT) | 85.25 MHz | Shaky / unstable picture |
| 1280x720 @60 (CEA) | 74.25 MHz | Stable; image looked stretched (taller than wide), probably the monitor's Aspect Ratio setting. Not adopted |

**Current state: original 1024x768@60 restored, no custom modes installed.**

To try 1280x720 again:
```sh
xrandr --newmode "1280x720_60" 74.25 1280 1390 1430 1650 720 725 730 750 +hsync +vsync
xrandr --addmode DP-1 1280x720_60
xrandr --output DP-1 --mode 1280x720_60
# then on the monitor: Menu → Display → Aspect Ratio → Wide 16:9
```

Restore:
```sh
xrandr --output DP-1 --mode 1024x768 --rate 60
xrandr --delmode DP-1 1280x720_60; xrandr --rmmode 1280x720_60
```

## No signal after screen blank / idle (fixed)

Cause: GNOME blanked the display (DPMS off) after 5 min and suspended the board when idle.
The monitor went into deep sleep and the DP link did not recover on wake.
Evidence (2026-11-26): on wake the kernel logged
`zynqmp-display fd4a0000.display: failed to configure link values` /
`failed to train the DP link`. The signal only came back after a monitor hotplug
(Xorg `hotplug=1`). Check with: `journalctl -b | grep -i "train the DP link"`.

Root cause: on DPMS wake `zynqmp_dp` trains the link once; the monitor is still in
deep sleep, training fails, and the driver never retries. The Dell P2317H menu has no deep-sleep
setting. A proper fix would patch the driver to retry with a delay.

Current fix (workaround), installed 2026-11-26:
- `~/.local/bin/dp-wake-fix` watches `journalctl -k` for `failed to train the DP link`
  and cycles `xrandr --output DP-1 --off` and back to the current mode, up to 3 tries with a 10 s cooldown.
- User service `~/.config/systemd/user/dp-wake-fix.service` (enabled, starts with the
  graphical session). Logs: `journalctl --user -u dp-wake-fix`.
- Tested: forced DPMS off for 25 s then woke it; recovered on the first attempt about 5 s after wake.
- Limits: it depends on the kernel's error text; there is a brief flicker; it does not cover the GDM login screen
  (it runs only inside the user session).

Settings:
```sh
gsettings set org.gnome.desktop.session idle-delay 300            # blanking kept (default)
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'  # idle suspend off (was 'suspend')
```

Remove the workaround:
```sh
systemctl --user disable --now dp-wake-fix.service
rm ~/.config/systemd/user/dp-wake-fix.service ~/.local/bin/dp-wake-fix
```

If the screen is ever stuck with no signal (run over SSH or a serial console):
```sh
DISPLAY=:1 xrandr --output DP-1 --off && DISPLAY=:1 xrandr --output DP-1 --auto
```
