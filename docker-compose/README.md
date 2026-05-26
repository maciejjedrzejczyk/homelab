# Docker Compose stacks

Each subdirectory of `docker-compose/` is a self-contained stack: one
`compose.yaml`, an optional `.env`, and an optional `secrets/` directory.
Stacks are independent — there is no top-level Compose file aggregating
them.

## Layout convention

```
docker-compose/
├── README.md                this file
└── <stack-name>/
    ├── compose.yaml         the only required file
    ├── .env                 host-specific values (git-ignored)
    ├── .env.example         committed template, copy to .env
    ├── README.md            stack-specific notes
    └── secrets/             Docker Compose `secrets:` files (git-ignored)
        ├── .gitkeep
        └── <name>.example   committed placeholder
```

A new stack is added by creating a new folder under `docker-compose/` with
at minimum a `compose.yaml`. The wrapper script
[`scripts/homelab.sh`](../scripts/homelab.sh) discovers stacks
automatically.

## Running stacks

The intended workflow is `docker compose` per stack. From the repository
root:

```sh
# Start one stack
docker compose -f docker-compose/vaultwarden/compose.yaml up -d

# Or, more conveniently, use the wrapper:
scripts/homelab.sh start vaultwarden
scripts/homelab.sh stop  vaultwarden
scripts/homelab.sh restart all
scripts/homelab.sh status running
scripts/homelab.sh logs vaultwarden
```

The wrapper exposes:

| Action    | Effect                                                         |
| --------- | -------------------------------------------------------------- |
| `start`   | `docker compose up -d`                                         |
| `stop`    | `docker compose stop`                                          |
| `restart` | `docker compose restart`                                       |
| `delete`  | `docker compose down --remove-orphans` *(named volumes kept)*  |
| `destroy` | `docker compose down --volumes --remove-orphans` *(data lost)* |
| `status`  | `docker compose ps`                                            |
| `logs`    | `docker compose logs --tail=200 -f`                            |
| `list`    | List all stacks discovered under `docker-compose/`             |

`destroy` requires you to type the stack name to confirm.

Run `scripts/homelab.sh` with no arguments for an interactive menu.

## Conventions every stack follows

- **`name:` is set explicitly** at the top of `compose.yaml`, matching the
  folder name. The Compose project name is therefore deterministic.
- **Image tags are pinned** (version tag at minimum, digest where
  practical). No `:latest`.
- **Restart policy is `unless-stopped`** unless the service is a one-shot
  job.
- **Each service has a `healthcheck`**, either inherited from the image or
  declared explicitly.
- **Logging is capped** to prevent unbounded `json-file` log growth.
- **Resource limits** (`deploy.resources.limits`) are set conservatively so
  one misbehaving container cannot starve the host.
- **Defaults are hardened**: `init: true`, `cap_drop: [ALL]`,
  `security_opt: [no-new-privileges:true]`, and `read_only: true` with a
  small `tmpfs` where the image allows it. Services that legitimately need
  capabilities back add them explicitly with `cap_add`.
- **No `container_name:` or `hostname:`** unless another container needs to
  resolve a fixed DNS name on a shared network. This lets you run a
  second copy of a stack side by side.
- **Per-stack bridge network** named after the stack. A shared external
  network (`proxy`) is used by stacks reachable through Nginx Proxy
  Manager.

## Secrets convention

Three places where sensitive values can live, in increasing order of
preference:

1. **In the YAML** — never. The committed `compose.yaml` contains no real
   secrets.
2. **In `<stack>/.env`** — for non-sensitive configuration and for values
   that the upstream image expects as plain environment variables. The
   `.env` file is git-ignored; `.env.example` is committed.
3. **In `<stack>/secrets/<name>`**, mounted via Docker Compose
   [`secrets:`](https://docs.docker.com/reference/compose-file/secrets/)
   and read by the application via the `<VAR>_FILE` indirection upstream
   images support (Postgres, MariaDB, Vaultwarden, Firefly III, and many
   more all honour `*_FILE` environment variables). The `secrets/`
   directory is git-ignored except for `.gitkeep` and `*.example` files.

Pre-publish checks (always run before `git push`):

```sh
git diff --cached | grep -E '^\+.*(password|secret|token|key)=' || true
gitleaks detect --no-git -v             # if installed
```

## Stack catalog

| Stack                 | Purpose                                  | Status   |
| --------------------- | ---------------------------------------- | -------- |
| `vaultwarden`         | Self-hosted Bitwarden-compatible vault   | migrated |
| `audiobookshelf`      | Audiobook & podcast server               | planned  |
| `clipcascade`         | Cross-device clipboard sync              | planned  |
| `dozzle`              | Web-based Docker log viewer              | planned  |
| `diun-gotify`         | Image-update notifier + push gateway     | planned  |
| `duckdns`             | Dynamic DNS updater                      | planned  |
| `feedtube`            | YouTube/Twitch → podcast feed bridge     | planned  |
| `filebrowser`         | Web file manager                         | planned  |
| `freshrss`            | RSS reader                               | planned  |
| `ghostfolio`          | Personal portfolio tracker               | planned  |
| `homepage`            | Self-hosted dashboard                    | planned  |
| `icloudpd`            | iCloud Photos backup tool                | planned  |
| `immich`              | Photo & video library with ML            | planned  |
| `kuma`                | Uptime monitoring                        | planned  |
| `nextcloud`           | File sync, calendars, contacts           | planned  |
| `nginx-proxy-manager` | Reverse proxy + Let's Encrypt management | planned  |
| `open-webui-ollama`   | LLM chat UI + Ollama runtime             | planned  |
| `photoprism`          | Photo management with face recognition   | planned  |
| `pihole-unbound`      | DNS sinkhole + recursive resolver        | planned  |
| `pinchflat`           | YouTube channel archiver                 | planned  |
| `portainer`           | Docker management UI                     | planned  |
| `privatebin`          | Encrypted pastebin                       | planned  |
| `signal-cli`          | Signal REST gateway                      | planned  |
| `vikunja`             | Task & project management                | planned  |
| `vscode`              | Browser-based code editor                | planned  |

The "planned" rows will be filled in stack by stack as each is migrated
from the legacy `compose/` tree, sanitized, and validated.

## Port allocation

Stacks bind to host ports in the **17400–17430** range so they don't
collide with common system services. Each stack's README documents its
port. The table will be filled in as stacks are migrated.

## Adding a new stack

1. Create `docker-compose/<stack>/compose.yaml` using
   [`vaultwarden/`](./vaultwarden/) as the template.
2. Add `<stack>/.env.example` with placeholder values for everything in
   `compose.yaml` that uses `${...}` interpolation.
3. If the service needs material that should never be exported as a plain
   environment variable, add a `secrets/<name>.example` and mount it via
   `secrets:` + the upstream `_FILE` indirection.
4. Document the stack in a `<stack>/README.md`: image source, port,
   first-time setup, what data is in volumes vs bind mounts.
5. Validate locally: `docker compose -f docker-compose/<stack>/compose.yaml config -q`.
6. Add the stack to the catalog table above.
