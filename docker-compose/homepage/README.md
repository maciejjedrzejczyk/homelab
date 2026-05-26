# Homepage

Self-hosted application dashboard with service integrations and Docker widgets.

**Project**: https://github.com/gethomepage/homepage

## At a Glance

| Property | Value |
|----------|-------|
| Image | `ghcr.io/gethomepage/homepage:v1.13.1` (digest pinned) |
| Port | 17409 |
| Volumes | `homepage` (config) |
| Healthcheck | `wget /` every 30s |
| Security | `cap_drop: ALL`, `no-new-privileges`, `init: true` |
| Note | `docker.sock` mounted read-only for container widgets |

## Updating

1. Check for new releases at https://github.com/gethomepage/homepage/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify health: `docker compose ps` and check http://localhost:17409
