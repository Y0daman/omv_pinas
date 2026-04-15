---
name: wf-four-nvme-storage-layout
description: Design and validate storage layout decisions for a 4x NVMe Raspberry Pi NAS. Use when choosing RAID or pooled configurations and defining data protection strategy.
---

# Workflow: 4x NVMe storage layout

## Ordered steps

1. Confirm all four drives are stable with `hw-fnk0107-quad-nvme`.
2. Pick layout based on goal:
   - RAID0 for maximum performance (no redundancy)
   - RAID10 for balanced performance and resilience
   - RAID5/6 for capacity with redundancy
   - mergerfs + snapraid for flexible media/archive scenarios
3. Create filesystems and mount points in OMV.
4. Configure shares and permissions.
5. Define backup outside the same chassis/node.

## Decision points

- Primary priority: performance, capacity, or recovery behavior?
- Need snapshots/checksumming? If yes, evaluate alternative storage stacks.

## Definition of done

- Chosen layout is documented with rationale.
- Read/write and recovery expectations are tested.
- Backup job exists and has a verified restore path.
