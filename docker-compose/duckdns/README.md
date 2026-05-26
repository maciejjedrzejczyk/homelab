# DuckDNS

Dynamic DNS updater for DuckDNS service.

**Project**: https://github.com/linuxserver/docker-duckdns

## At a Glance

| Property | Value |
|----------|-------|
| Image | `lscr.io/linuxserver/duckdns:latest` (digest pinned) |
| Port | None (daemon service) |
| Volumes | `duckdns` (config) |
| Healthcheck | None (daemon, no HTTP endpoint) |
| Security | `cap_drop: ALL` + `CHOWN`, `DAC_OVERRIDE`, `SETGID`, `SETUID` |

## Updating

1. Check for updates at https://github.com/linuxserver/docker-duckdns
2. Update digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify logs: `docker compose logs duckdns`
