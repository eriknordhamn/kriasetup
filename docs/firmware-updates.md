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
- If both slots are bad, use the **Image Recovery tool** that lives in the QSPI Recovery Image.
  It is started with a button on the carrier board at power-on and is run from a browser over Ethernet.
  Look up the exact button and IP in AMD's Kria boot firmware documentation before you need it.
  This hasn't been tested on this board.

### Precautions
- Don't cut power during step 2.
- Record the before and after `xmutil bootfw_status` output in `docs/changelog.md`.

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
