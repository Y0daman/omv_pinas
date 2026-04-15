---
name: hw-fnk0107-quad-nvme
description: Validate Raspberry Pi 5 hardware with Freenove FNK0107 and up to 4 NVMe drives. Use when disks are missing, PCIe looks unstable, or before storage setup.
---

# HW: FNK0107 + 4x NVMe

## Preconditions

- Raspberry Pi 5 with Freenove FNK0107 build.
- Stable PSU, ideally 5.1V/5A.
- SSH access.

## Procedure

1. Run `scripts/01-hw-preflight.sh`.
2. Confirm expected NVMe count in `lsblk`.
3. Check kernel messages for recurring PCIe/NVMe errors.
4. If instability appears, verify power and cabling before changing software.

## Validation

- All expected `/dev/nvme*n1` devices are visible.
- No repeated link resets/AER/I/O errors.
- Thermals are acceptable under load.

## Gotchas

- On Pi 5, NVMe bandwidth is shared and limited by upstream PCIe design.
- Power insufficiency often appears as intermittent disk disappearance.

## References

- `references/fnk0107-notes.md`
