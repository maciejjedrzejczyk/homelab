# homepage-sync

Compares running Docker containers with the Homepage `services.yaml`
configuration and offers to add missing services or remove stale ones.

## Quick start

```sh
# Check only (no changes):
scripts/homepage-sync/homepage-sync.sh --check

# Interactive — review and apply changes:
scripts/homepage-sync/homepage-sync.sh
```

## What it does

1. Reads `services.yaml` from the running Homepage container.
2. Extracts all `container:` references.
3. Compares against `docker ps` output.
4. Reports:
   - **Stale** — in Homepage but container not running.
   - **Missing** — running but not in Homepage.
5. In interactive mode, offers to:
   - Comment out stale entries.
   - Add missing containers (prompts for section name, generates a
     service block with href/siteMonitor/icon).

Containers with no exposed port (internal services like databases,
caches, background workers) are skipped automatically.

## Requirements

- The Homepage container must be running as `homepage-homepage-1`.
- Docker socket access (to list containers and `docker exec`/`docker cp`).
