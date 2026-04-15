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

## Important notes

- Run on a clean OS install to avoid conflicts.
- Use externally powered USB/SATA storage when possible.
- Prefer a UPS if you run RAID or store critical data.
- Back up first, then experiment.

## Next steps

See `docs/setup-checklist.md` for the full order from image flashing to a working NAS.

For agent-driven operations and reusable runbooks, see `.agents/README.md`.
