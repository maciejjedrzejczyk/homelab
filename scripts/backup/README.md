# Backup & Restore

Scripts for backing up and restoring Docker Compose stack data (named
volumes, `.env` files, and `secrets/`).

## Quick start

```sh
# Back up a single stack:
scripts/backup/docker-backup.sh vaultwarden

# Back up all stacks:
scripts/backup/docker-backup.sh --all

# Dry run (see what would be backed up):
scripts/backup/docker-backup.sh --dry-run --all

# Restore from an archive:
scripts/backup/docker-restore.sh restore backups/vaultwarden-20260525-120000.tar.gz
```

## Scripts

| Script | Purpose |
| --- | --- |
| `docker-backup.sh` | Back up stack volumes + config to a timestamped archive |
| `docker-restore.sh` | Verify, list, or restore from a backup archive |

---

## docker-backup.sh

### Usage

```
docker-backup.sh [OPTIONS] [<stack>...]
```

### Options

| Flag | Default | Description |
| --- | --- | --- |
| `-t, --target <path>` | `./backups` | Directory where archives are written |
| `-r, --retain <days>` | `30` | Auto-delete backups older than N days (0 = disable) |
| `-n, --dry-run` | — | Show what would be backed up, make no changes |
| `--no-stop` | — | Skip stopping containers (faster but risks inconsistent data) |
| `-a, --all` | — | Back up every stack under `docker-compose/` |

### What gets backed up

For each stack:

1. **Named volumes** — identified via `docker compose config --volumes`.
   Each volume is tar'd via a temporary Alpine container with read-only
   access.
2. **`.env`** — the runtime environment file (git-ignored, contains your
   host-specific config).
3. **`secrets/`** — the entire directory including real secret files
   (git-ignored).

### What does NOT get backed up

- **Compose files** (`compose.yaml`, `.env.example`, `README.md`) — these
  are in git. Push your repo to back them up.
- **Bind-mounted host paths** (e.g. `/Volumes/...`, iCloud Drive) — these
  need a separate backup tool (Time Machine, `restic`, `rsync`, `rclone`).
- **Docker images** — they can always be re-pulled.

### Output

Each backup produces two files:

```
backups/
├── vaultwarden-20260525-120000.tar.gz     # the archive
└── vaultwarden-20260525-120000.sha256     # SHA-256 checksum
```

### Process

1. Stops the stack (`docker compose stop`) for data consistency.
2. Mounts each volume read-only into a temporary Alpine container and
   creates a tar archive.
3. Copies `.env` and `secrets/` into the archive.
4. Compresses everything into a single `.tar.gz`.
5. Generates a SHA-256 checksum.
6. Restarts the stack.
7. Applies retention policy (deletes old archives).

Downtime per stack is typically seconds to a couple of minutes depending on
volume size.

### Scheduling

```sh
# Daily at 03:00, back up all stacks, keep 30 days:
0 3 * * * /path/to/homelab/scripts/backup/docker-backup.sh --all -t /path/to/backups 2>&1 | logger -t homelab-backup
```

---

## docker-restore.sh

### Usage

```
docker-restore.sh <action> <archive> [<stack>]
```

### Actions

| Action | Description |
| --- | --- |
| `list` | Show the contents of a backup archive |
| `verify` | Check SHA-256 checksum and archive integrity |
| `restore` | Restore volumes and/or config files |

### Options

| Flag | Description |
| --- | --- |
| `--force` | Overwrite existing volumes/files without prompting |
| `--config-only` | Restore only `.env` + `secrets/`, skip volumes |
| `--volumes-only` | Restore only volumes, skip config files |

### Restore process

1. Verifies archive checksum (if `.sha256` file exists alongside).
2. Tests archive integrity (`tar tzf`).
3. For each volume in the archive:
   - If the volume already exists, prompts to overwrite (unless `--force`).
   - Creates the volume if it doesn't exist.
   - Restores data via a temporary Alpine container.
4. Restores `.env` and `secrets/` to the stack directory.
5. Prints the command to start the stack.

### Examples

```sh
# See what's in a backup:
scripts/backup/docker-restore.sh list backups/vaultwarden-20260525-120000.tar.gz

# Verify integrity:
scripts/backup/docker-restore.sh verify backups/vaultwarden-20260525-120000.tar.gz

# Full restore (prompts before overwriting):
scripts/backup/docker-restore.sh restore backups/vaultwarden-20260525-120000.tar.gz

# Restore to a different stack name:
scripts/backup/docker-restore.sh restore backups/vaultwarden-20260525-120000.tar.gz vaultwarden-test

# Non-interactive restore:
scripts/backup/docker-restore.sh restore --force backups/vaultwarden-20260525-120000.tar.gz

# Restore only secrets (e.g. after migrating to a new host):
scripts/backup/docker-restore.sh restore --config-only backups/vaultwarden-20260525-120000.tar.gz
```

---

## Disaster recovery playbook

### Test restore (non-conflicting)

Verify a backup is usable without touching live data:

```sh
# 1. Restore volumes with a prefix (live stack is unaffected):
scripts/backup/docker-restore.sh restore --prefix test backups/audiobookshelf-20260525-140052.tar.gz

# 2. Inspect the restored data:
docker run --rm -v test-audiobookshelf:/data alpine ls /data

# 3. Clean up test volumes when satisfied:
docker volume rm $(docker volume ls -q | grep '^test-')
```

When `--prefix` is used:
- Volumes are created as `<prefix>-<original-name>` (e.g. `test-vaultwarden`).
- Config/secrets restore is automatically skipped (it's a test, not a real recovery).
- The live stack keeps running on its own volumes throughout.

Add `--force` to skip overwrite prompts if the test volumes already exist.

### Full restore on a fresh host

To restore a stack on a fresh host:

```sh
# 1. Clone the repo
git clone https://github.com/maciejjedrzejczyk/homelab
cd homelab

# 2. Restore config + volumes from backup
scripts/backup/docker-restore.sh restore --force /media/backup/vaultwarden-20260525-120000.tar.gz

# 3. Start the stack
scripts/homelab.sh start vaultwarden

# 4. Verify
scripts/homelab.sh status vaultwarden
```

For bind-mounted data (photos, media, etc.), restore from your separate
backup solution (Time Machine, restic, etc.) to the paths referenced in
each stack's `.env`.
