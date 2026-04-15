---
name: omv-troubleshooting
description: Troubleshoot OpenMediaVault and Raspberry Pi NAS issues using a structured triage flow. Use when shares fail, disks disappear, services break, or performance degrades.
---

# OMV Troubleshooting

## Triage flow

1. Collect baseline status: `uptime`, `free -h`, `df -h`, `lsblk`, `ip a`.
2. Inspect logs: `journalctl -p warning..alert -b` and kernel output.
3. Isolate the failing area: network, storage, filesystem, permissions, or app layer.
4. Apply the smallest safe change first.
5. Re-test from a client perspective.

## Validation

- Original symptom is no longer reproducible.
- No new critical warnings appear after the fix.
- A short root-cause note and remediation note are captured.

## References

- `references/omv-troubleshooting-links.md`
