# PrivateBin

Encrypted pastebin with zero-knowledge architecture and burn-after-reading.

**Project**: https://github.com/PrivateBin/PrivateBin

## At a Glance

| Property | Value |
|----------|-------|
| Image | `privatebin/nginx-fpm-alpine:2.0.4` (digest pinned) |
| Port | 17420 |
| Volumes | `privatebin` (data) |
| Healthcheck | `pgrep php-fpm` master process |
| Security | `cap_drop: ALL` + selective `cap_add` |

## Updating

1. Check for new releases at https://github.com/PrivateBin/PrivateBin/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify health: `docker compose ps` and check http://localhost:17420
