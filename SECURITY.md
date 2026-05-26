# Security

This repository contains the Docker Compose stacks I run on a single homelab
host. It is published **for transparency**, not as a turnkey product.

## What you should assume about this repo

- Every file here is meant to be read by anyone on the internet.
- No real secret, API key, token, password, hash, hostname, LAN IP, email
  address, or DuckDNS subdomain is committed.
- All `.env`, `secrets/*`, certificate, and key files are git-ignored. The
  committed `*.example` files describe the shape of the data; the real
  values live only on the host that runs the stack.
- Image versions are pinned. Pinning enables reproducible deploys, it does
  not imply the pinned versions are evergreen — track upstream advisories.

## Before you deploy any stack from this repo

1. **Rotate every credential.** Treat any value resembling a secret in any
   file (committed or not) as a placeholder. Generate fresh ones.
2. **Audit Docker socket exposure.** Some stacks (Portainer, Dozzle, Diun,
   Homepage, Kuma) need access to the Docker socket and therefore inherit
   full host privileges. Front them with `docker-socket-proxy` or accept
   that exposing them is equivalent to exposing root on the host.
3. **Decide how each service is reachable.** The defaults bind ports to all
   interfaces in the 17400–17430 range and assume the host is on a trusted
   LAN. Anything you publish via Nginx Proxy Manager must sit behind
   authentication and TLS, with rate limiting where appropriate.
4. **Back up data, not containers.** Most stacks store data in named
   volumes; some bind-mount external host paths. The included
   `scripts/docker-backup.sh` only handles named volumes — bind-mounted
   data needs its own backup path (Time Machine, `restic`, `rsync`, etc.).
5. **Subscribe to upstream releases.** Use Diun (included) or Renovate /
   Dependabot to be notified about new image versions.

## Threat model in scope

- Accidental commit of secrets to the repository.
- Default credentials shipped by upstream images (Photoprism, Nextcloud,
  Filebrowser, NPM all have well-known defaults).
- Docker socket abuse via web dashboards.
- Container escape risk from over-permissive `cap_add` / `privileged`
  flags — none of the committed stacks use them.

## Out of scope

- Multi-host or Swarm/Kubernetes deployments. Everything assumes a single
  Docker Engine on one host.
- High availability, replication, or geo-redundancy.
- Compliance with any specific framework (PCI, HIPAA, GDPR, etc.). If you
  need compliance, build for it explicitly; do not rely on this repo.

## Reporting a configuration issue

This is a personal repository, not a maintained product. If you spot a
configuration mistake here that could mislead a reader, please open an
issue against the repo. If you discover a vulnerability in one of the
*upstream* projects (Vaultwarden, Immich, etc.), report it directly to that
project — this repo only references their published images.
