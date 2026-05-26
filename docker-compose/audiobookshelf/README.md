# Audiobookshelf

Self-hosted audiobook and podcast server with web player and mobile apps.

**Project**: https://github.com/advplyr/audiobookshelf

## At a Glance

| Property | Value |
|----------|-------|
| Image | `ghcr.io/advplyr/audiobookshelf:2.35.0` (digest pinned) |
| Port | 17401 |
| Volumes | `audiobookshelf` (config), `audiobookshelf-metadata` |
| Healthcheck | Node-based `/healthcheck` |
| Security | `cap_drop: ALL`, `no-new-privileges`, `init: true` |

## Updating

1. Check for new releases at https://github.com/advplyr/audiobookshelf/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify health: `docker compose ps` and check http://localhost:17401
