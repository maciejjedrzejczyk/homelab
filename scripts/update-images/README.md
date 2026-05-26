# update-images

A helper script that inspects all Docker Compose stacks for pinned images,
checks upstream registries for newer releases, and optionally updates the
pins, restarts containers, and removes old images.

## Requirements

- Docker Engine with the `buildx` plugin (ships by default with Docker
  Desktop and modern Docker CE installs).
- Bash 3.2+ (macOS stock shell is fine).

## Usage

```sh
# From the repository root:
scripts/update-images/update-images.sh [OPTIONS] [<stack>]
```

### Modes

| Flag | Behaviour |
| --- | --- |
| *(none)* | **Interactive** — shows each available update and asks whether to apply it. |
| `--check` | **Read-only** — lists outdated images and exits with code `1` if any updates are found. Useful in CI or cron. |
| `--auto` | **Unattended** — applies every available update without prompting: updates `compose.yaml`, pulls the new image, recreates the container, and prunes the old image. |
| `<stack>` | Restrict the check to a single stack (e.g. `vaultwarden`). Can be combined with `--check` or `--auto`. |

### Examples

```sh
# Check all stacks, no changes:
scripts/update-images/update-images.sh --check

# Interactively update one stack:
scripts/update-images/update-images.sh vaultwarden

# Auto-update everything (suitable for a cron job):
scripts/update-images/update-images.sh --auto
```

## What it does

For each `compose.yaml` discovered under `docker-compose/<stack>/`:

1. **Parses** the `image:` line to extract the registry, name, tag, and
   (if present) the `@sha256:` digest pin.
2. **Inspects** the upstream registry via `docker buildx imagetools
   inspect <name>:<tag>` to get the current digest for that tag.
3. **Compares** the upstream digest to the local pin:
   - If they match → reports "up to date".
   - If they differ → reports "update available" and shows both digests.
   - If no digest is pinned → suggests adding one.
4. Depending on the mode, either prompts or auto-applies:
   - Rewrites the `image:` line in `compose.yaml` with the new digest.
   - Runs `docker compose up -d --force-recreate --pull always` to
     pull and restart.
   - Runs `docker image prune -f` to remove dangling layers.

## Limitations

- Skips images that use Compose variable interpolation (e.g.
  `${IMMICH_VERSION:-release}`). Those must be updated manually.
- Only checks whether the *digest* behind a tag has changed. It does not
  discover newer *tags* (e.g. it won't tell you that `1.36.0` exists if
  you're pinned to `1.35.7`). For tag-level discovery, use
  [Diun](https://crazymax.dev/diun/) or Renovate/Dependabot.
- The `--auto` mode trusts upstream completely. If you prefer reviewing
  changes before applying, use the default interactive mode or
  `--check` in CI combined with manual approval.

## Scheduling (optional)

To receive a daily summary of available updates without auto-applying:

```sh
# crontab -e
0 8 * * * /path/to/homelab/scripts/update-images/update-images.sh --check 2>&1 | logger -t homelab-updates
```

Or combine with Gotify/ntfy for push notifications on the result.
