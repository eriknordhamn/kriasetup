# KR260 firmware and software updates

The KR260 has four layers that are updated separately. Checked on this board on 2026-11-26
(Ubuntu 22.04.5 LTS, kernel `5.15.0-1080-xilinx-zynqmp`).

| Layer | What it is | Where it lives | How it's updated |
|---|---|---|---|
| 1. Boot firmware | FSBL, PMU firmware, ATF, U-Boot (`BOOT.BIN`) | QSPI flash on the SOM, A/B slots | Manually with `xmutil bootfw_update` |
| 2. OS boot files | Kernel + device tree FIT image, boot script | `/boot/firmware/` (`image.fit`, `boot.scr.uimg`) | Automatically by `flash-kernel` during apt kernel upgrades |
| 3. Kernel and packages | Ubuntu + Xilinx packages | SD card root fs | `apt` |
| 4. PL (FPGA) apps | Bitstreams + device-tree overlays | `xlnx-firmware-kr260-*` packages | `apt`, loaded with `xmutil loadapp` |

`fwupd` is installed but finds **no devices** on this board (`fwupdmgr get-devices` → "No detected
devices", no UEFI ESP), so it is not used for firmware here.

---

## 1. Boot firmware (QSPI, A/B)

The QSPI holds two boot images, **Image A** and **Image B**, plus an Image Selector that picks
which one boots. There is also a separate Recovery Image. (`cat /proc/mtd` shows the partitions.)
An update is written to the **inactive** slot. The new slot boots once on trial and must be marked good,
or the board falls back to the old slot. That makes a bad update recoverable.

### State on this board (2026-11-26)
```
Image A: Bootable
Image B: Bootable
Requested Boot Image: Image A
Last Booted Image: Image A
XilinxSom_QspiImage-k26-v2.1-06140636
ImageA Revision Info: k26-smk-kr-sdt-v1.08-20261107132709
ImageB Revision Info: k26-smk-v1.04-20250410071436
```
- **Image A** is active and validated: v1.08, KR260-specific (`smk-kr`), built 2026-11-07.
- **Image B** is the fallback: older v1.04 (2025-04-10), generic K26 starter kit build.
- The next `bootfw_update -i` writes to **Image B**, the inactive slot, replacing v1.04. A stays as the fallback.
  v1.04 is the last image known to run PYNQ buffer allocation on this board, so don't overwrite it
  yet. See "Which firmware for Ubuntu 22.04 + PYNQ" below.

### Check the current state
```sh
sudo xmutil bootfw_status      # QSPI MFG version/date, active image, requested image, A/B bootable flags
```
Needs root: without it, it fails with `Open Qspi MTD partition failed`.

### Update procedure
1. Download the `BOOT.BIN` for the **KR260** from AMD's Kria SOM boot firmware page on the
   AMD/Xilinx wiki. Check that it is the KR260 starter-kit image and is compatible
   with Ubuntu 22.04, and verify its checksum if one is published.
2. Write it to the inactive slot:
   ```sh
   sudo xmutil bootfw_update -i /path/to/BOOT.BIN
   sudo xmutil bootfw_status          # the requested image should now be the other slot
   ```
3. Reboot: `sudo reboot`
4. After it boots back into Ubuntu, **mark the new image as good**:
   ```sh
   sudo xmutil bootfw_update -v
   sudo xmutil bootfw_status          # the new slot should now be active and bootable
   ```
   Without `-v` the board boots the old slot again on the next reboot.

`image_update` is the same tool (`image_update -i/-p/-v`); `-p` prints the persistent state registers.

> **Command names:** it's `boot`fw, not `board`fw. On this board (`xmutil 1:1.2ubuntu1`),
> `xmutil boardfw_status` and `xmutil boardfw_update` fail with `invalid choice`. If a guide
> uses the `boardfw_*` names, use `bootfw_status` / `bootfw_update` instead
> (`xmutil -h` lists the valid commands).

### If the board won't boot
- If the trial image fails, rebooting falls back to the previous slot. Power-cycle it.
- If both slots are bad, use the **Boot Image Recovery Tool** (next section).

### Boot Image Recovery Tool
A web app stored in QSPI, separate from slots A and B. It can upload a `BOOT.BIN` into either
slot, set each slot's Bootable flag, and choose the **Requested Boot Image**. That last option
switches slots without flashing anything. Source: AMD wiki snapshot in `references/`, p. 27–28.
Reached on this board 2026-11-27 (J10C, Windows PC, 100 Mbps forced on the PC side).

1. Connect the PC to the KR260's **J10C** Ethernet port (GEM1). The other three ports don't work
   for recovery.
2. Give the PC a static address on 192.168.0.x/24, anything except `.111`. No gateway.
   **Set the PC adapter to 100 Mbps Full Duplex.** With auto-negotiation (and 1 Gbps), the
   tool printed an auto-negotiation error on the UART and the link never came up. On Windows:
   Device Manager → Network adapters → adapter → Properties → Advanced → Speed & Duplex.
   Set it back to Auto Negotiation afterwards.
3. Open the serial console (micro-USB UART, 115200 8N1, usually the second of the new COM
   ports; Windows needs PuTTY or Tera Term). The tool prints its IP and link errors there.
4. With the board off, hold the **FWUEN** (firmware update) button and power on.
5. In a browser, open `http://192.168.0.111`. **Boot Image Status** shows the same A/B
   information as `bootfw_status`.
6. To **switch slots**: under **Requested Boot Image**, select the slot you want, leave both
   images Bootable, and click **Configure**.
   To **flash**: under **Recover Image**, pick the slot, choose the `BOOT.BIN`, and click
   **Upload**. That overwrites the slot and marks it Bootable.
7. Power-cycle without holding the button and let Ubuntu boot.
8. Check with `sudo xmutil bootfw_status`. The FSBL console line also shows which slot booted:
   `MultiBootOffset: 0x40` = Image A, `0x1F0` = Image B.

The trial-boot rule (mark good with `bootfw_update -v`) is for images flashed with `xmutil`.
A slot chosen with **Configure** is expected to stay selected without it. Confirm this with
`bootfw_status` after a second reboot.

### Precautions
- Don't cut power during step 2.
- Record the before and after `xmutil bootfw_status` output in `docs/changelog.md`.

### Which firmware for Ubuntu 22.04 + PYNQ
Source: AMD's "Kria SOMs & Starter Kits" wiki, snapshot 2026-11-27 in
`references/Kria_SOMs_Starter_Kits-271126-155240.pdf`.

**Problem seen here:** on v1.08 (Image A), `pynq.allocate()` fails, so `kr260intro` step 05
no longer runs. The same Ubuntu 22.04 Desktop install ran step 05 fine on v1.04.
Root cause not confirmed yet (see "Likely mechanism" below).

**What AMD's page says:**
| Version | Code base / flow | Notes |
|---|---|---|
| 2022.1, 2022.2 | PetaLinux, legacy versioning | 2022.1 is the minimum for Ubuntu 22.04 (KR260 USB2.0 on U46, PS Ethernet J10C) |
| 1.01, 1.02 | Yocto, 2023.2 | Last versions listed for Ubuntu 22.04 Desktop with no caveat |
| 1.04 | Yocto, 2024.2 | Excluded for Ubuntu 22.04 Desktop ("2022.1 or later, except bootfw 1.04"). Listed issue is DP only: no DP on first boot under 22.04 (fixed by updating packages) and with EDF 2025.1 images |
| 1.05, 1.06 | SDT flow, EDF distro, 2025.1–2025.2 | No statement on Ubuntu 22.04 |
| 1.07, 1.08 | SDT, EDF, 2026.x "flat" | One fixed image per kit (`smk-kr` = KR260). AMD's 2026.1 WIC images *require* these |

Ubuntu Server 24.04 is listed as working with 1.02 or later.

**Background (why the new builds differ):**
- 2024.2 added the SDT (system device tree) build flow next to XSCT; from 2025.1 SDT is the
  only flow. That's the `sdt` in `k26-smk-kr-sdt-v1.08-…`.
- From 1.06 the firmware is built with AMD's EDF Yocto distro (AMD images log in as `amd-edf`
  instead of `petalinux`).
- From 2026.1 boot firmware is "flat": a fixed image per starter kit instead of one image per
  SOM that detects the carrier board at boot.

**Likely mechanism (inference, not verified):** Ubuntu 22.04's boot scripts and PYNQ's
device-tree overlay (`insert_dtbo.py`) were made for what the older firmware hands to Linux.
The flat SDT image may hand over a different reserved-memory/CMA layout or `zocl` setup, so the PL
loads but buffer allocation fails. To check, compare on both firmwares:
```sh
cat /proc/cmdline
grep -i cma /proc/meminfo
lsmod | grep zocl
ls /sys/kernel/config/device-tree/overlays/
sudo dmesg | grep -i -e cma -e zocl -e "reserved mem"
```

**Recommendation:** use a firmware from before the SDT change. In practice that's v1.04, which is
proven on this board. If you want a version AMD lists for 22.04 with no caveat, use v1.02.
1. Don't run `bootfw_update -i` while A (v1.08) is active: it writes to B and destroys v1.04.
2. Boot Image B (v1.04). `xmutil` has no slot-select command, so use the Boot Image Recovery
   Tool's **Requested Boot Image → Image B → Configure** (see that section above).
   Check that a second reboot still boots B.
3. Rerun step 05. If it passes, the firmware is confirmed as the cause.
4. Optional: flash v1.02 with `bootfw_update -i`. It goes into A and overwrites v1.08, leaving
   two pre-SDT images.
5. Before downloading from AMD, check the Ubuntu-packaged firmware:
   `sudo add-apt-repository ppa:ubuntu-xilinx/default && apt show kria-k26-bootfw`.
   The page doesn't say which version it is. Once installed, the images are in
   `/usr/lib/firmware/xilinx/bootfw/BOOT-<variation>.bin`.

Alternative: move to Ubuntu 24.04 (supported with 1.02 or later), at the cost of reinstalling
PYNQ and the workarounds in `docs/changelog.md`.

---

## 2. OS boot files (`/boot/firmware`)

`flash-kernel` regenerates `image.fit` (kernel + DTB + initrd) and `boot.scr.uimg` whenever a
new `linux-image-*-xilinx-zynqmp` is installed, keeping the old copy as `*.bak`.
No manual step is normally needed.

If a new kernel doesn't boot: put the SD card in another machine and restore the backups in the
`system-boot` partition:
`image.fit.bak` → `image.fit` and `boot.scr.uimg.bak` → `boot.scr.uimg`.

---

## 3. Kernel and packages (apt)

```sh
sudo apt update && sudo apt full-upgrade
```
Package sources on this board, beyond the Ubuntu archive:
- `ppa:ubuntu-xilinx/updates` and `ppa:ubuntu-xilinx/sdk`: Xilinx kernel, xmutil, dfx-mgr, etc.
- `oem.archive.canonical.com` `jammy-limerick`: the Kria OEM meta package (`oem-limerick-kria-meta`)
- `ppa:lely/ppa`: not Kria-specific, added by the user

**After a kernel update:** check the installed workarounds still work, starting with the `dp-wake-fix`
service (see `docs/changelog.md` for how to tell if it's still needed).

Old kernels pile up (`dpkg -l 'linux-image-*xilinx*'`); `sudo apt autoremove` cleans them.

---

## 4. PL (FPGA) application firmware

```sh
xmutil getpkgs                           # list firmware packages relevant to this board
sudo apt install xlnx-firmware-kr260-<app>
sudo xmutil listapps                     # installed apps; shows which one is active
sudo xmutil unloadapp
sudo xmutil loadapp kr260-<app>
```
These are ordinary apt packages and update with `apt full-upgrade`.
