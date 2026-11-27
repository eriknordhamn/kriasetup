# kriasetup

Fixes, setup notes and maintenance procedures for an AMD/Xilinx **Kria KR260** robotics starter kit
running Ubuntu 22.04 (kernel `xilinx-zynqmp`, GNOME on X11).

## Contents

| Doc | Topic |
|---|---|
| [docs/changelog.md](docs/changelog.md) | **Every change made to the board**: what, why, how to check it's still needed, how to remove it |
| [docs/display.md](docs/display.md) | DisplayPort: 1024x768 limit (single lane), no signal after screen blank |
| [docs/firmware-updates.md](docs/firmware-updates.md) | How boot firmware, OS boot files, kernel/packages and PL apps are updated |
| [docs/cma.md](docs/cma.md) | CMA pool for PYNQ buffers: what uses it, how to enlarge it (`cma=` boot arg), why there is none on boot FW v1.08 |
| [references/Kria_SOMs_Starter_Kits-271126-155240.pdf](references/Kria_SOMs_Starter_Kits-271126-155240.pdf) | Snapshot of AMD's "Kria SOMs & Starter Kits" wiki page, 2026-11-27: boot FW versions, Ubuntu compatibility, QSPI map |

## Installed on the board

| What | Where | Why |
|---|---|---|
| `dp-wake-fix` user service | `~/.local/bin/dp-wake-fix`, `~/.config/systemd/user/dp-wake-fix.service` | Restores the picture after the screen blanks |
| gsettings: idle suspend off | `org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'` | Avoid suspend and resume failures |

Copies of installed files are kept in `files/` (one folder per fix, each with an `install.sh`).
Reinstall after an OS reinstall, e.g. `files/dp-wake-fix/install.sh`.
If you edit an installed file on the board, copy it back into `files/` and commit.

## After a kernel or firmware update
1. Check `docs/changelog.md` → each workaround's "Is it still needed?" section.
2. Record the update in `docs/changelog.md`.
