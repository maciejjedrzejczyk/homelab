# Dozzle

Real-time Docker log viewer with alerting and multi-host support.

**Project**: https://github.com/amir20/dozzle

## At a Glance

| Property | Value |
|----------|-------|
| Image | `amir20/dozzle:v10.6.0` (digest pinned) |
| Port | 17404 |
| Volumes | `dozzle-data` (alert config persistence) |
| Healthcheck | Built-in `/dozzle` healthcheck |
| Security | `cap_drop: ALL`, `no-new-privileges`, `init: true` |

## Updating

1. Check for new releases at https://github.com/amir20/dozzle/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify health: `docker compose ps` and check http://localhost:17404
