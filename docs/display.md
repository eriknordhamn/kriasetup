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
| 1280x720 @60 (CEA) | 74.25 MHz | Stable; image looked stretched (taller than wide). Cause: the monitor was set to a 4:3 aspect ratio, not Wide 16:9. Not adopted |
| 1360x768 @60, CVT reduced blanking (2026-11-27) | 72.00 MHz | **Works**, with the monitor set to Wide 16:9. Runtime test only, so it reverted after 90 s |

**Current state: 1024x768@75 (78.75 MHz, the driver's default pick), no custom modes installed.**

Notes:
- The monitor's Aspect Ratio setting does not change the EDID, so it has no effect on which modes are detected. Keep it on **Wide 16:9**.
- Custom `xrandr` modes don't show up in GNOME Settings. Settings lists only the modes the driver builds from the EDID, and those are capped at about 90 MHz. A mode added at runtime also disappears on logout or reboot. To make one selectable and permanent, define it in `/etc/X11/xorg.conf.d/`.
  The config is ready in `files/dp-1360x768/` but **not installed yet**: run `files/dp-1360x768/install.sh` (uses sudo).
- What the monitor's EDID lists (128 bytes, no extension block). The pixel clocks are from the X log:
  1920x1080@60 (148.5 MHz, native), 1600x900@60 (119 MHz), 1280x1024@60/75 (108/135 MHz), 1152x864@75 (108 MHz),
  1024x768@60/75, 800x600@60/75, 640x480@60/75, 720x400@70. Every widescreen mode is above 90 MHz, so the driver
  keeps only 1024x768 and the smaller 4:3 modes. Range limits: V 56–76 Hz, H 30–83 kHz, up to 170 MHz.

### Blocker: no CMA, 1360x768 buffers fail to allocate (found 2026-11-27)

During the 1360x768 test the X log showed, at the switch (10:34:39) and again at the revert (10:36:10):
`_CREATE_GEM({height: 768, width: 1360, bpp: 32 ...}) failed. errno: 12 - Cannot allocate memory`.
The desktop-icons extension (DING) then crashed with `BadAlloc`. The picture itself worked: the X screen is 16 bpp,
so its 1360x768 buffer is only about 2 MB.

Cause: the kernel command line has `cma=1000M`, but at boot the kernel logs `cma: Failed to reserve 1000 MiB`, and
`/proc/meminfo` shows `CmaTotal: 0 kB`. With no CMA pool, display buffers need physically contiguous memory, and
the kernel can hand out at most 4 MiB in one piece. A 1360x768 32-bpp buffer is 4.18 MB before row alignment,
so it most likely goes over that limit. A 1024x768 one (3.1 MB) fits.
Check: `journalctl -k -b | grep -i cma`, `grep Cma /proc/meminfo`.

**It started with the v1.08 boot firmware.** The journal shows the CMA pool reserved correctly on every boot
from August through boot -3 (2026-11-26). It has failed on every boot since boot -2 (started 2026-11-26 19:16).
The kernel (5.15.0-1080), the command line and the memory map are the same in both. The only difference in the
early kernel log is `psci: SMC Calling Convention v1.4` → `v1.5`, which means the board is running a different
Trusted Firmware (part of `BOOT.BIN`). That fits the new QSPI image `k26-smk-kr-sdt-v1.08` (`bootfw_update` at
17:07, see `docs/firmware-updates.md`) becoming the running firmware at that boot.
Not yet known: *why* v1.08 leaves no room for 1000 MiB. A guess, not verified: its U-Boot places the
kernel, initrd or DTB differently in the low 2 GB, so no 1000 MiB gap is left.
Check per boot:
`for b in -5 -4 -3 -2 -1 0; do journalctl -k -b $b -o cat | grep -m1 -oE 'SMC Calling Convention v[0-9.]+|cma: (Failed to reserve|Reserved) [0-9]+ MiB' | tr '\n' ' '; echo; done`

Options (none applied): boot the old firmware slot to confirm; lower `cma=`; report it to AMD.
Possible fix: a smaller `cma=` value that the kernel can actually reserve (e.g. 256M). This is a boot command line
change, so confirm with the user first. Hold off on installing the xorg.conf below until this is fixed.

### Permanent 1360x768 (`files/dp-1360x768/`)

`/etc/X11/xorg.conf.d/10-dp-1360x768.conf` adds a `Monitor` section with `Identifier "DP-1"`. X matches it by
output name (the X log otherwise says "Output DP-1 has no monitor section"). The section holds the 1360x768R
modeline and sets it as `PreferredMode`. The `armsoc` driver and `xilinx-kria.conf` stay unchanged.

- Install: `files/dp-1360x768/install.sh`, then log out and back in, and pick 1360x768 in Settings → Displays.
  `~/.config/monitors.xml` still holds 1024x768@75, so GNOME keeps that until you change it in Settings.
- Check that it loaded: `grep -E "DP-1|1360x768" /var/log/Xorg.1.log` should show the monitor section and the mode.
- Remove: `sudo rm /etc/X11/xorg.conf.d/10-dp-1360x768.conf`, then log out and back in.
- If X fails to start: from SSH or the serial console run the same `rm`, then `sudo systemctl restart gdm3`.

To try 1360x768 again (recommended):
```sh
xrandr --newmode "1360x768R" 72.00 1360 1408 1440 1520 768 771 781 790 +hsync -vsync
xrandr --addmode DP-1 1360x768R
xrandr --output DP-1 --mode 1360x768R
```
Restore: `xrandr --output DP-1 --mode 1024x768 --rate 75; xrandr --delmode DP-1 1360x768R; xrandr --rmmode 1360x768R`

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
