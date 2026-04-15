# Setup checklist: Raspberry Pi 5 + OMV

## 1) Preparation

- Flash Raspberry Pi OS Lite 64-bit (Bookworm)
- Enable SSH in Raspberry Pi Imager
- Set hostname (for example `omv-pi`)
- Boot the Pi and connect via SSH

## 2) Base installation

Run in this order:

```bash
./scripts/00-preflight.sh
./scripts/01-hw-preflight.sh
sudo reboot
./scripts/10-install-omv.sh
./scripts/20-install-omv-extras.sh
```

## 3) OMV web UI

- Go to `http://<PI-IP>/`
- Change the admin password
- Verify timezone/NTP

## 4) Disks and filesystems

- Storage -> Disks: verify all drives are visible
- Storage -> File Systems: create filesystems (ext4 recommended)
- Mount filesystems
- Create shared folders

## 5) Sharing and users

- Users -> create user accounts
- Services -> SMB/CIFS -> enable and create shares
- (Optional) NFS for Linux clients

## 6) Health and backup

- Storage -> SMART -> enable monitoring
- Scheduled Jobs -> scrub and SMART self-tests
- Configure notifications via email/SMTP
- Back up critical data to an external disk or another node

## 7) Apps (optional)

- Install the Compose plugin via OMV-Extras
- Run apps from `apps/compose/`

## 8) Operational knowledge and runbooks

- Hardware notes: `docs/hardware/fnk0107-notes.md`
- GitHub auth/credentials: `docs/github/credentials-and-auth.md`
- Agent Skills: `.agents/skills/`
