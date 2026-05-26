# Vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) is a lightweight
Rust reimplementation of the Bitwarden server, compatible with the official
Bitwarden client apps and browser extensions.

This stack is the **reference** for the rest of the repo: it shows the full
hardening, secrets, and operational pattern that every other migrated stack
will follow.

## At a glance

| Property             | Value                                              |
| -------------------- | -------------------------------------------------- |
| Image                | `vaultwarden/server:1.35.7` (pinned by digest)     |
| Host port (default)  | `17421` → container `80` (override in `.env`)      |
| Data location        | Named volume `vaultwarden-data`                    |
| Secrets              | `secrets/admin_token` (Argon2id hash)              |
| Healthcheck          | `wget /alive` every 30 s                           |
| Hardened with        | `cap_drop: [ALL]`, `no-new-privileges`, read-only  |
| External network     | None (per-stack bridge); add `proxy` for NPM later |

## First-time setup

1. **Copy the example files**
   ```sh
   cp .env.example .env
   cp secrets/admin_token.example secrets/admin_token
   ```

2. **Generate an admin token hash** and write it (single line, no trailing
   newline) into `secrets/admin_token`:
   ```sh
   docker run --rm -it vaultwarden/server:1.35.7 /vaultwarden hash
   ```
   Save the cleartext token in your password manager — you will need it
   to log into the `/admin` panel.

3. **Edit `.env`**, in particular `DOMAIN` (the public URL clients connect
   to) and `IP_HEADER` (match the header your reverse proxy sets, if any).

4. **Start the stack** from the repository root:
   ```sh
   scripts/homelab.sh start vaultwarden
   # equivalent to:
   docker compose -f docker-compose/vaultwarden/compose.yaml up -d
   ```

5. **Create your account.** Visit
   `http://<host>:${VAULTWARDEN_HOST_PORT}` (default port 17421) and
   register your personal account.

6. **Disable signups** by setting `SIGNUPS_ALLOWED=false` and
   `INVITATIONS_ALLOWED=false` in `.env` (already the default in the
   template). Recreate the container:
   ```sh
   scripts/homelab.sh restart vaultwarden
   ```

7. **Visit `/admin`** with the cleartext admin token to verify access, then
   log out.

## Lifecycle

| Action                                  | Effect                                                    |
| --------------------------------------- | --------------------------------------------------------- |
| `scripts/homelab.sh start vaultwarden`  | `docker compose up -d`                                    |
| `scripts/homelab.sh stop vaultwarden`   | `docker compose stop`                                     |
| `scripts/homelab.sh restart vaultwarden`| `docker compose restart`                                  |
| `scripts/homelab.sh delete vaultwarden` | `docker compose down --remove-orphans` (keeps the volume) |
| `scripts/homelab.sh destroy vaultwarden`| `docker compose down --volumes` — **deletes vault data**  |
| `scripts/homelab.sh logs vaultwarden`   | Tail logs                                                 |
| `scripts/homelab.sh status vaultwarden` | `docker compose ps`                                       |

## Backup

The entire vault — accounts, passwords, attachments — lives in the
`vaultwarden-data` named volume. Back up the volume regularly. Example
using the included script:

```sh
scripts/docker-backup.sh -t /path/to/backup-target
```

For point-in-time exports, log into the `/admin` panel and use the built-in
backup feature (writes a tarball to `/data/backups/`, which is inside the
volume).

## Updating the image

The image in `compose.yaml` is pinned both by tag *and* by the multi-arch
OCI index digest (`tag@sha256:...`). Pinning by digest guarantees a byte-for-byte
identical image across every host, even if the same tag is later overwritten
upstream.

To update to a newer Vaultwarden release:

```sh
# 1. Pick the new tag from https://github.com/dani-garcia/vaultwarden/releases
# 2. Resolve the multi-arch digest:
docker buildx imagetools inspect vaultwarden/server:<new-tag>
# 3. Copy the top-level `Digest: sha256:...` line into compose.yaml.
# 4. Pull, recreate, verify:
scripts/homelab.sh restart vaultwarden
scripts/homelab.sh status  vaultwarden
scripts/homelab.sh logs    vaultwarden    # ctrl-c when satisfied
```

If you also automate updates, Renovate and Dependabot both understand the
`name:tag@sha256:digest` format and will open PRs that bump both halves
together.

## Reverse proxy notes

When fronted by Nginx Proxy Manager (or any other reverse proxy):

- Set `DOMAIN=https://vault.example.com` in `.env` and recreate.
- The proxy must forward WebSocket connections (Vaultwarden uses them for
  client ↔ server live sync).
- Match `IP_HEADER` to whatever header your proxy actually sets
  (`X-Real-IP` for Nginx, `CF-Connecting-IP` behind Cloudflare, etc.).
- To put Vaultwarden on a shared `proxy` network, add the network at the
  end of `compose.yaml`:
  ```yaml
  networks:
    vaultwarden:
      name: vaultwarden
    proxy:
      external: true
  ```
  and reference both from the service.

## Security considerations

- The `read_only: true` setting forbids writes anywhere except `/data` and
  `/tmp`. If a future Vaultwarden release introduces writes elsewhere, the
  container will fail to start with a clear permission error; comment out
  `read_only: true` and file an upstream issue.
- The container runs as root inside its own namespace (the upstream image
  default). Capabilities are dropped to `ALL`, so root inside the
  container has only the bare minimum needed to bind to port 80.
- Argon2id parameters used by `/vaultwarden hash` (m=64 MiB, t=3, p=4) are
  CPU- and RAM-intensive on purpose. Keep them.
