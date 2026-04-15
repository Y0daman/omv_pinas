---
name: wf-incident-recovery
description: Recover OMV NAS service after incidents using a repeatable triage and remediation workflow. Use when alerts trigger, users report outages, or data/service risk is detected.
---

# Workflow: Incident recovery

## Ordered steps

1. Classify impact and urgency.
2. Run `omv-troubleshooting` triage.
3. Apply short-term stabilization (workaround or rollback).
4. Identify root cause.
5. Implement permanent fix.
6. Capture post-incident notes and update related skills.

## Decision points

- If data integrity is at risk: pause writes and secure backup first.
- If service is business-critical: restore service first, then deepen RCA.

## Definition of done

- Service is restored to acceptable SLO.
- Root cause and corrective action are documented.
- Skill or workflow improvements are committed.
