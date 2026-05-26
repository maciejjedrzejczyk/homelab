# Portainer CE

Docker and Kubernetes management UI with RBAC and multi-environment support.

**Project**: https://github.com/portainer/portainer

## At a Glance

| Property | Value |
|----------|-------|
| Image | `portainer/portainer-ce:2.42.0` (digest pinned) |
| Port | 17402 (HTTPS) |
| Volumes | `portainer` (data) |
| Healthcheck | None (minimal image, no shell) |
| Security | `no-new-privileges` |
| Note | `docker.sock` mounted read-write (required for management) |

## Updating

1. Check for new releases at https://github.com/portainer/portainer/releases
2. Update image tag and digest in `docker-compose.yml`
3. Run `docker compose pull && docker compose up -d`
4. Verify access: https://localhost:17402
