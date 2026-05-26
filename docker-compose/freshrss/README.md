# FreshRSS

[FreshRSS](https://freshrss.org/) is a self-hosted RSS/Atom feed reader with
a clean web interface, API support (Google Reader / Fever), and extensions.

## At a glance

| Property            | Value                                                 |
| ------------------- | ----------------------------------------------------- |
| Image               | `lscr.io/linuxserver/freshrss:1.28.0` (pinned by digest) |
| Host port (default) | `17406` → container `80`                              |
| Data volume         | `freshrss` (config + SQLite DB)                       |
| Healthcheck         | `curl /i/` every 30 s                                 |
| Hardened with       | `cap_drop: [ALL]` + selective `cap_add`, `no-new-privileges` |

## First-time setup

1. `cp .env.example .env`
2. `scripts/homelab.sh start freshrss`
3. Visit `http://<host>:17406` and complete the installation wizard.

## Updating

```sh
docker buildx imagetools inspect lscr.io/linuxserver/freshrss:<new-tag>
# Update tag + digest in compose.yaml, then:
scripts/homelab.sh restart freshrss
```
