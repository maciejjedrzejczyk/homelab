# Uptime Kuma

Self-hosted uptime monitoring with notifications and status pages.

**Project**: https://github.com/louislam/uptime-kuma

## At a Glance

| Property | Value |
|----------|-------|
| Image | `louislam/uptime-kuma:2.3.2` (digest pinned) |
| Port | 17410 |
| Volumes | `kuma` (data) |
| Healthcheck | `curl /` every 30s |
| Security | `no-new-privileges`, `init: true` |
| Note | `docker.sock` mounted read-only for container monitoring |

## Updating

1. Check for new releases at https://github.com/louislam/uptime-kuma/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify health: `docker compose ps` and check http://localhost:17410
