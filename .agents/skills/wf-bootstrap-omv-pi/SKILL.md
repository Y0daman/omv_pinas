---
name: wf-bootstrap-omv-pi
description: Execute the end-to-end bootstrap workflow for a new Raspberry Pi OMV NAS. Use when provisioning a new node from a fresh OS image.
---

# Workflow: Bootstrap OMV on Pi 5

## Ordered steps

1. Run hardware preflight with `hw-fnk0107-quad-nvme`.
2. Run `scripts/00-preflight.sh`.
3. Run `scripts/05-preinstall-flash.sh`.
4. Reboot.
5. Run `scripts/10-install-omv.sh`.
6. Run `scripts/20-install-omv-extras.sh`.
7. Apply baseline configuration with `omv-core`.

## Decision points

- If NVMe drives are unstable, stop and resolve hardware/power first.
- If OMV UI is unreachable, verify IP, DNS, and OMV services before storage work.

## Definition of done

- OMV UI is reachable.
- At least one share works from a client.
- SMART and notifications are enabled.
