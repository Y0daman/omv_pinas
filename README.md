# OMV Pi NAS (Raspberry Pi 5)

This repo contains reusable scripts, app definitions, and Agent Skills for building a Raspberry Pi 5 NAS with OpenMediaVault (OMV).

## Target setup

- Base OS: Debian 13 (Trixie) / Raspberry Pi OS based on Debian 13
- NAS layer: OpenMediaVault
- Add-ons: OMV-Extras (Compose, additional plugins)
- Apps: Docker Compose files in `apps/`

## Quick start

Run this on a freshly installed Pi (SSH as a sudo-enabled user):

```bash
git clone https://github.com/Y0daman/omv_pinas.git
cd omv_pinas
chmod +x scripts/*.sh

./scripts/00-preflight.sh
./scripts/01-hw-preflight.sh
./scripts/05-preinstall-flash.sh
sudo reboot
./scripts/10-install-omv.sh
./scripts/20-install-omv-extras.sh
```

Notes:

- `scripts/10-install-omv.sh` uses the official installer (`https://get.openmediavault.io`).
- `scripts/05-preinstall-flash.sh` applies SD-write reduction defaults.
- `scripts/20-install-omv-extras.sh` attempts to install `openmediavault-writecache`.

After installation:

1. Log in to the OMV web UI: `http://<PI-IP>/`
2. Set a static IP (recommended)
3. Add disks, create filesystems, mount
4. Create shares (SMB/NFS) and users
5. Enable SMART, scrub, and notifications

## Repository structure

- `scripts/` - install and baseline automation
- `apps/` - Compose apps runnable via OMV Compose plugin or Docker CLI
- `docs/` - manuals and checklists
- `.agents/skills/` - Agent Skills following the agentskills.io specification

## Freenove hardware controls

If you use the Freenove FNK0107 case board, this repo includes grouped control scripts:

- `scripts/fan_control/set_fan_percent.sh`
- `scripts/led_control/led_control.sh`
- `scripts/oled_control/oled_control.sh`
- `scripts/screen_control/screen_control.sh`

Fan control modes:

```bash
# Manual fixed speed
./scripts/fan_control/set_fan_percent.sh manual 60

# Follow case temperature
./scripts/fan_control/set_fan_percent.sh follow-case --low-temp 30 --high-temp 50 --low-speed 30 --mid-speed 50 --high-speed 70

# Follow Raspberry Pi PWM
./scripts/fan_control/set_fan_percent.sh follow-rpi --min-speed 20 --max-speed 100

# Keep target temperature (active loop)
./scripts/fan_control/set_fan_percent.sh target-temp 55 --sensor cpu --min-speed 20 --max-speed 100 --gain 4 --interval 2

# Config vs hardware readback
./scripts/fan_control/set_fan_percent.sh get
./scripts/fan_control/set_fan_percent.sh read
```

LED modes include presets and temperature-follow:

```bash
# Preset colors
./scripts/led_control/led_control.sh preset blue
./scripts/led_control/led_control.sh preset orange
./scripts/led_control/led_control.sh list-presets

# Config vs hardware readback
./scripts/led_control/led_control.sh get
./scripts/led_control/led_control.sh read

# Dynamic temperature color (blue -> red)
./scripts/led_control/led_control.sh temp-follow --sensor cpu --cold 35 --hot 75 --interval 1
```

OLED page control:

```bash
./scripts/oled_control/oled_control.sh list
./scripts/oled_control/oled_control.sh get
./scripts/oled_control/oled_control.sh read
./scripts/oled_control/oled_control.sh show usage
```

Large screen dashboard:

```bash
./scripts/screen_control/screen_control.sh info
./scripts/screen_control/screen_control.sh get
./scripts/screen_control/screen_control.sh read
./scripts/screen_control/screen_control.sh run-dashboard --backend auto
```

Hardware status scripts:

```bash
./scripts/hw/read_temp.sh
./scripts/hw/read_all_status.sh
```

## Important notes

- Run on a clean OS install to avoid conflicts.
- Use externally powered USB/SATA storage when possible.
- Prefer a UPS if you run RAID or store critical data.
- Back up first, then experiment.

## Next steps

See `docs/setup-checklist.md` for the full order from image flashing to a working NAS.

For Freenove hardware controls (fan/LED/OLED/screen), see `docs/hardware/freenove-controls.md`.

For agent-driven operations and reusable runbooks, see `.agents/README.md`.
