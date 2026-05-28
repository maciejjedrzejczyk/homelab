# homelab

Self-hosted services running on a single Docker host.
This repository contains the Docker Compose definitions, operational scripts,
and documentation for all stacks.

## Repository structure

```
.
├── docker-compose/          All Docker Compose stacks (one folder each)
├── scripts/                 Operational tooling
│   ├── homelab.sh           Stack lifecycle manager (start/stop/restart/etc.)
│   ├── backup/              Backup & restore scripts
│   ├── update-images/       Image version checker & updater
│   └── homepage-sync/       Homepage ↔ running containers sync
├── apps/                    Custom applications
│   └── docker-map/          Docker port/service visualization tool
├── .githooks/pre-commit     Secret leak prevention hook
├── .env.example             Global configuration template
├── SECURITY.md              Publication disclaimer & threat model
└── LICENSE
```

## Docker Compose stacks

Each stack lives in `docker-compose/<name>/` with a `compose.yaml`, `.env.example`,
and README. See [`docker-compose/README.md`](docker-compose/README.md) for
conventions, secrets management, and the full catalog.

| Stack | Description | Port |
| --- | --- | --- |
| [audiobookshelf](docker-compose/audiobookshelf/) | Audiobook & podcast server | 17401 |
| [dozzle](docker-compose/dozzle/) | Docker log viewer + alerting | 17404 |
| [duckdns](docker-compose/duckdns/) | Dynamic DNS updater | — |
| [freshrss](docker-compose/freshrss/) | RSS feed reader | 17406 |
| [homepage](docker-compose/homepage/) | Self-hosted dashboard | 17409 |
| [icloudpd](docker-compose/icloudpd/) | iCloud Photos downloader | — |
| [immich](docker-compose/immich/) | Photo & video library with ML | 17426 |
| [kuma](docker-compose/kuma/) | Uptime monitoring | 17410 |
| [nextcloud](docker-compose/nextcloud/) | File sync & collaboration platform | 17411 |
| [nginx-proxy-manager](docker-compose/nginx-proxy-manager/) | Reverse proxy + Let's Encrypt | 80/443/17413 |
| [pihole-unbound](docker-compose/pihole-unbound/) | DNS ad-blocking + recursive resolver | 53/17418 |
| [portainer](docker-compose/portainer/) | Docker management UI | 17402 |
| [privatebin](docker-compose/privatebin/) | Encrypted pastebin | 17420 |
| [signal-cli](docker-compose/signal-cli/) | Signal REST API gateway | 17424 |
| [vaultwarden](docker-compose/vaultwarden/) | Bitwarden-compatible password vault | 17421 |
| [vscode](docker-compose/vscode/) | VS Code in the browser (code-server) | 17425 |

## Scripts

| Script | Purpose |
| --- | --- |
| [`scripts/homelab.sh`](scripts/homelab.sh) | Start, stop, restart, delete, destroy stacks. Interactive menu or CLI. |
| [`scripts/backup/`](scripts/backup/) | Per-stack volume + config backup and restore with checksums. |
| [`scripts/proxy-manager/`](scripts/proxy-manager/) | Map containers to NPM proxy hosts, check cert expiry, create new hosts. |
| [`scripts/service-inventory/`](scripts/service-inventory/) | Generate full-stack service report (containers, proxies, DNS). |
| [`scripts/update-images/`](scripts/update-images/) | Check for upstream image updates, bump versions, pull + restart. |
| [`scripts/homepage-sync/`](scripts/homepage-sync/) | Compare running containers with Homepage config, add/remove entries. |

## Quick start

```sh
# 1. Clone the repo
git clone https://github.com/maciejjedrzejczyk/homelab
cd homelab

# 2. Activate the pre-commit hook (blocks accidental secret commits)
git config core.hooksPath .githooks

# 3. Copy and edit global config
cp .env.example .env

# 4. For each stack you want to run:
cd docker-compose/<stack>
cp .env.example .env
# Edit .env with your values, create secrets/ files as needed
cd ../..

# 5. Start a stack
scripts/homelab.sh start <stack>

# 6. Check status
scripts/homelab.sh status all
```

## Security

See [SECURITY.md](SECURITY.md) for the full threat model and pre-deploy
checklist. Key points:

- No real secrets are committed — all `.env` and `secrets/*` files are git-ignored.
- A pre-commit hook scans for credential patterns and personal identifiers.
- Every image is pinned by version tag + digest for reproducibility.
- Stacks are hardened with `cap_drop: [ALL]`, selective `cap_add`, and
  `no-new-privileges` where the image allows it.

## License

[MIT](LICENSE)
