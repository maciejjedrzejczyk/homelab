# Nginx Proxy Manager

[Nginx Proxy Manager](https://nginxproxymanager.com/) provides a web-based
UI for managing Nginx reverse-proxy hosts, SSL certificates (Let's Encrypt),
redirections, and streams.

## At a glance

| Property            | Value                                                      |
| ------------------- | ---------------------------------------------------------- |
| Image               | `jc21/nginx-proxy-manager:2.14.0` (pinned by digest)      |
| Host ports          | `80` (HTTP), `443` (HTTPS), `17413` (admin UI)            |
| Data volumes        | `nginx-proxy-manager-data`, `nginx-proxy-manager-letsencrypt` |
| Healthcheck         | `curl /api/` on admin port every 30 s                      |
| Hardened with       | `cap_drop: [ALL]` + selective `cap_add`, `no-new-privileges` |

## First-time setup

1. Copy `.env.example` to `.env` (already done if migrating from the old stack).
2. Start the stack:
   ```sh
   scripts/homelab.sh start nginx-proxy-manager
   ```
3. Visit `http://<host>:17413` and log in with the default credentials:
   - Email: `admin@example.com`
   - Password: `changeme`
4. **Change the default credentials immediately.**

## Security notes

- NPM cannot run fully read-only because it writes an SQLite database,
  generated Nginx configs, and Let's Encrypt certificates to its volumes.
- `cap_drop: [ALL]` removes all capabilities; only `NET_BIND_SERVICE`
  (bind ports < 1024), `CHOWN`, `DAC_OVERRIDE`, `SETGID`, `SETUID` are
  added back (minimum required for Nginx worker processes).
- The admin UI (port 17413) should **never** be exposed to the internet.
  Keep it LAN-only or behind an authenticated proxy host within NPM itself.

## Updating

```sh
docker buildx imagetools inspect jc21/nginx-proxy-manager:<new-tag>
# Update the tag + digest in compose.yaml, then:
scripts/homelab.sh restart nginx-proxy-manager
```
