# CMA pool (PYNQ buffer memory)

`pynq.allocate()` gets its buffers through XRT and `zocl` from the kernel's CMA pool, so
the pool's free space limits how much you can allocate. Status: measured once, nothing
changed yet.

## State on this board (2026-11-27, boot FW v1.04 / Image B)
```
$ cat /proc/cmdline
 root=LABEL=writable rootwait earlycon console=ttyPS1,115200 console=tty1 clk_ignore_unused uio_pdrv_genirq.of_id=generic-uio xilinx_tsn_ep.st_pcp=4 cma=1000M
$ grep -i cma /proc/meminfo
CmaTotal:        1024000 kB
CmaFree:          140828 kB      (117792–140828 kB across three reads)
```
About 880 MB of the 1000 MB pool is in use before PYNQ allocates anything. That's enough for
`kr260intro` step 05, but not for large buffers.

## No pool at all on boot FW v1.08 (Image A)
On v1.08 the kernel logs `cma: Failed to reserve 1000 MiB` and `/proc/meminfo` shows `CmaTotal: 0 kB`, with the same
kernel and command line. Booting Image B (v1.04) brings the pool back, which confirms the firmware as the cause
(`docs/changelog.md`, 2026-11-27). How it was first traced to the firmware (`psci: SMC Calling Convention v1.4` →
`v1.5`): `docs/display.md` → "Blocker: no CMA". **If Image A is booted again, all of the following comes back.**

Without CMA the kernel can only hand out physically contiguous memory from the buddy allocator. That is at most
4 MiB in one piece, and less once memory is fragmented. `/proc/buddyinfo` at 14:59 on 2026-11-27 (29 min of uptime,
v1.08) had no free block larger than 2 MiB.

### Loading a PL bitstream (FPGA) fails
Running kr260intro step 05 (`linear_layer_test.py` via `run_pynq.sh`) on v1.08 failed at 14:55:55 while loading
the overlay, before any `pynq.allocate()`:
```
fpga_manager fpga0: writing linear_layer_accel.bin to Xilinx ZynqMP FPGA Manager
WARNING: CPU: 0 PID: 9377 at mm/page_alloc.c:5476 __alloc_pages+0x2c4/0x31c
  ... dma_alloc_attrs <- zynqmp_fpga_ops_write <- fpga_mgr_firmware_load
fpga_manager fpga0: Error while writing image data to FPGA
```
`zynqmp_fpga_ops_write` copies the whole bitstream into one DMA-coherent buffer. The request was 0x770000 bytes
(7.4 MiB, an order-11 allocation). That is bigger than anything the buddy allocator can give, so the kernel warned
and failed. Every full ZU5EV bitstream is about this size, so **no PL design can be loaded** while CMA is missing.
`pynq.allocate()` buffers come from the same place, so they fail too once they're larger than a few MiB.

### The GUI crashes at the same time
At the same second X failed to allocate small buffers (`_CREATE_GEM 722x434 ... errno 12`, then 1024x768).
gnome-terminal got `BadAlloc` and crashed (`gnome-terminal-server.service: code=dumped, status=5/TRAP`).
That killed every shell running in it, including the Claude Code session that started the test.
**Whenever CMA is missing, run PL tests from SSH or the serial console, not from a GNOME terminal.**
Display modes above 1024x768 fail for the same reason (`docs/display.md`).

### Check
```sh
grep Cma /proc/meminfo                         # CmaTotal 0 kB = no pool
journalctl -k -b | grep -i cma                 # "Failed to reserve" vs "Reserved"
cat /proc/buddyinfo                            # rightmost non-zero column = largest free block (col 0 = 4 KiB)
journalctl -k -b | grep -A3 "writing .* to Xilinx ZynqMP FPGA Manager"
```

Still unknown: *why* v1.08 leaves no room for 1000 MiB. The device tree reserves only `pmu@7ff00000` (1 MiB).
`sudo cat /proc/iomem` on v1.08 would show where the kernel, initrd and other reservations sit. If v1.08 is needed
later, also try a smaller `cma=` there (see section 2), or report it to AMD with the SMC v1.4 → v1.5 and
`Failed to reserve` evidence.

## 1. Find what's using it (no persistent change)
Suspects, not yet confirmed: the GNOME desktop on DisplayPort (display buffers come from CMA)
and `jupyter.service` from Kria-PYNQ. Measure after removing each one:
```sh
grep -i cmafree /proc/meminfo
sudo systemctl stop jupyter        # undo: sudo systemctl start jupyter
grep -i cmafree /proc/meminfo
sudo xmutil desktop_disable        # undo: sudo xmutil desktop_enable
grep -i cmafree /proc/meminfo
```
If the desktop accounts for most of it, the cheapest fix is to run without the desktop when
you need big buffers.

### Experiment: how much CMA does the desktop use? (planned, not run yet)
**Question:** would `pynq.allocate()` get noticeably more buffer with the desktop and GUI off?

**Why it's likely (2026-11-27, Image B / v1.04):**
- X uses the `armsoc` driver (`Xorg.1.log`). It allocates scanout and per-window buffers as GEM
  objects from the zynqmp DRM device, and on this board those come from CMA. The v1.08 failure log showed
  X asking for window-sized buffers (`_CREATE_GEM 722x434`).
- `CmaFree` changes a lot with the same 1000 MB pool and no PYNQ allocations, which fits per-window buffers:

  | When (2026-11-27) | CmaFree |
  |---|---|
  | Readings above (desktop + jupyter) | 118–141 MB |
  | ~17:15 | 645 MB |
  | ~17:40 | 581 MB |

- `jupyter.service` (Kria-PYNQ) was active during all of these readings, so it's the other suspect.

**How to run it:**
1. Run from **SSH or the serial console**. Disabling the desktop kills every GNOME terminal, including a
   Claude Code session running in one.
2. Optional first step (no sudo): note `CmaFree`, close the browser, VS Code and other windows, then read it again.
3. Run the steps above (stop jupyter, then `xmutil desktop_disable`) and read `CmaFree` after each one.
4. Optionally, with the desktop off, run step 05 or a large `pynq.allocate()` to confirm the gain is usable.
5. Restore: `sudo xmutil desktop_enable`, `sudo systemctl start jupyter`.

Nothing here persists across a reboot. Record the readings here:

| State | CmaFree |
|---|---|
| Desktop + jupyter | |
| Windows closed | |
| jupyter stopped | |
| Desktop disabled | |

## 2. Make the pool bigger (boot command line: confirm before doing)
The size is set by `cma=1000M` on the kernel command line. On Kria Ubuntu, `flash-kernel`
builds that into `/boot/firmware/boot.scr.uimg` and regenerates it on every kernel update.
So change the config file it reads, never the generated script.

1. Find where the value is set:
   ```sh
   grep -rn cma /etc/default/flash-kernel /etc/flash-kernel/ 2>/dev/null
   ```
2. Change it there (e.g. `cma=1500M`) and run `sudo flash-kernel`. The old script is kept as
   `boot.scr.uimg.bak`.
3. Reboot and check `CmaTotal` in `/proc/meminfo`.

Limits:
- **Size:** the pool must fit in the low 2 GB of RAM along with the kernel, so about 1.5 GB
  is a sensible ceiling on the 4 GB K26. If the value is too big, CMA reservation fails at
  boot and you end up with no pool. Check `CmaTotal` after rebooting.
- **Kernel updates:** the change survives them only because it's in `flash-kernel`'s config.

Revert:
- Set the old value back and run `sudo flash-kernel`.
- If the board won't boot: put the SD card in a PC and, on the `system-boot` partition, copy
  `boot.scr.uimg.bak` over `boot.scr.uimg`.

Log any change in `docs/changelog.md`.
