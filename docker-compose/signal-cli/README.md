# Signal-CLI REST API

Signal messaging gateway with REST API for sending and receiving messages.

**Project**: https://github.com/bbernhard/signal-cli-rest-api

## At a Glance

| Property | Value |
|----------|-------|
| Image | `bbernhard/signal-cli-rest-api:0.99` (digest pinned) |
| Port | 17424 |
| Volumes | `signal-cli` (registration data) |
| Healthcheck | `curl /v1/about` every 30s |
| Security | `cap_drop: ALL` + selective `cap_add`, `no-new-privileges`, `init: true` |

## Updating

1. Check for new releases at https://github.com/bbernhard/signal-cli-rest-api/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify health: `docker compose ps` and check http://localhost:17424/v1/about
