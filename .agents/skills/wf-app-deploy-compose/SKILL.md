---
name: wf-app-deploy-compose
description: Deploy and maintain containerized apps on OMV using Docker Compose. Use when introducing a new app, updating an app stack, or standardizing app deployment steps.
---

# Workflow: App deploy with Compose

## Ordered steps

1. Verify storage paths and permissions in OMV.
2. Create or update `apps/compose/<app>/docker-compose.yml`.
3. Keep secrets in local `.env` files only.
4. Deploy with OMV Compose plugin or `docker compose up -d`.
5. Validate endpoint, persistence, and restart behavior.

## Decision points

- If public access is needed, define reverse proxy/TLS first.
- If a database is required, separate data volumes and backup policy.

## Definition of done

- App endpoint is reachable.
- Data survives container restart.
- Backup and rollback notes exist.
