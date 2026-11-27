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
