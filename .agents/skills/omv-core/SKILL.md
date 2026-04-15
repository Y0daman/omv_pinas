---
name: omv-core
description: Install and baseline OpenMediaVault on Raspberry Pi 5. Use when setting up a fresh OMV host, configuring shares, or standardizing core NAS settings.
---

# OMV Core

## Procedure

1. Run `scripts/00-preflight.sh`.
2. Run `scripts/10-install-omv.sh`.
3. Run `scripts/20-install-omv-extras.sh`.
4. In OMV GUI, configure admin password, time/NTP, storage, shares, and SMB/NFS.
5. Enable SMART, scrub/self-tests, and notifications.

## Validation

- OMV GUI reachable at `http://<pi-ip>/`.
- Filesystems are mounted and shares accessible from a client.
- SMART + notifications are configured.

## References

- `references/omv-links.md`
