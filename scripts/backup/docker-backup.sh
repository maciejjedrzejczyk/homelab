#!/usr/bin/env bash
#
# docker-backup.sh — back up Docker Compose stack volumes + config files.
#
# Usage:
#   docker-backup.sh [OPTIONS] [<stack>...]
#
# Options:
#   -t, --target <path>     Target directory for backup archives (default: ./backups)
#   -r, --retain <days>     Delete backups older than N days (default: 30, 0=disable)
#   -n, --dry-run           Show what would be backed up without doing it.
#   -a, --all               Back up all stacks.
#   --no-stop               Back up without stopping containers (risk of inconsistency).
#   -h, --help              Show help.
#
# Each stack backup produces:
#   <target>/<stack>-<timestamp>.tar.gz       the archive
#   <target>/<stack>-<timestamp>.sha256       checksum for verification

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_ROOT="$REPO_ROOT/docker-compose"

TARGET_DIR="$REPO_ROOT/backups"
RETAIN_DAYS=30
DRY_RUN=false
NO_STOP=false
STACKS=()

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--target)  TARGET_DIR="$2"; shift ;;
    -r|--retain)  RETAIN_DAYS="$2"; shift ;;
    -n|--dry-run) DRY_RUN=true ;;
    --no-stop)    NO_STOP=true ;;
    -a|--all)     STACKS=("ALL") ;;
    -h|--help)
      sed -n '3,16p' "$0" | sed 's/^#//' | sed 's/^ //'
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *)  STACKS+=("$1") ;;
  esac
  shift
done

if [ ${#STACKS[@]} -eq 0 ]; then
  echo "ERROR: specify one or more stacks, or use --all." >&2
  echo "Run with --help for usage." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Discover stacks
# ---------------------------------------------------------------------------
list_all_stacks() {
  find "$COMPOSE_ROOT" -mindepth 2 -maxdepth 2 -type f \
    \( -name 'compose.yaml' -o -name 'compose.yml' \
    -o -name 'docker-compose.yaml' -o -name 'docker-compose.yml' \) \
    | awk -F/ '{print $(NF-1)}' | sort -u
}

if [ "${STACKS[0]}" = "ALL" ]; then
  STACKS=()
  while IFS= read -r s; do
    STACKS+=("$s")
  done < <(list_all_stacks)
fi

# Validate stacks exist
for stack in "${STACKS[@]}"; do
  if [ ! -d "$COMPOSE_ROOT/$stack" ]; then
    echo "ERROR: stack '$stack' not found under $COMPOSE_ROOT" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FAILED=0

log()  { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "[%s] WARNING: %s\n" "$(date +%H:%M:%S)" "$*" >&2; }

# Find the compose file for a stack
compose_file() {
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    [ -f "$COMPOSE_ROOT/$1/$f" ] && echo "$COMPOSE_ROOT/$1/$f" && return
  done
}

# Get actual Docker volume names used by a stack.
# Parses `docker compose config` to resolve the `name:` field of each volume.
stack_volumes() {
  local dir="$COMPOSE_ROOT/$1"
  ( cd "$dir" && docker compose config 2>/dev/null ) \
    | awk '/^volumes:/{found=1; next} found && /^[^ ]/{exit} found && /name:/{print $2}' \
    | tr -d '"' | tr -d "'"
}

# ---------------------------------------------------------------------------
# Backup one stack
# ---------------------------------------------------------------------------
backup_stack() {
  local stack="$1"
  local stack_dir="$COMPOSE_ROOT/$stack"
  local archive="${TARGET_DIR}/${stack}-${TIMESTAMP}.tar.gz"
  local checksum="${TARGET_DIR}/${stack}-${TIMESTAMP}.sha256"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  # Trap to clean temp dir
  trap "rm -rf '$tmp_dir'" RETURN

  log "━━━ $stack ━━━"

  # Collect volumes
  local volumes
  volumes="$(stack_volumes "$stack")"

  if $DRY_RUN; then
    log "[DRY-RUN] Would back up:"
    log "  Volumes: ${volumes:-<none>}"
    log "  Config:  .env, secrets/"
    log "  Target:  $archive"
    return 0
  fi

  mkdir -p "$TARGET_DIR"

  # --- Stop the stack for consistency (unless --no-stop) ---
  local was_running=false
  if ! $NO_STOP; then
    if docker compose -f "$(compose_file "$stack")" ps -q 2>/dev/null | grep -q .; then
      was_running=true
      log "Stopping $stack..."
      ( cd "$stack_dir" && docker compose stop ) 2>&1 | sed 's/^/  /'
    fi
  fi

  # --- Back up volumes ---
  local vol_dir="$tmp_dir/volumes"
  mkdir -p "$vol_dir"

  if [ -n "$volumes" ]; then
    for vol in $volumes; do
      # Resolve actual volume name (compose may prefix with project name)
      # Try the literal name first, then the project-prefixed name
      local real_vol="$vol"
      if ! docker volume inspect "$vol" >/dev/null 2>&1; then
        real_vol="${stack}_${vol}"
        if ! docker volume inspect "$real_vol" >/dev/null 2>&1; then
          warn "Volume '$vol' not found, skipping."
          continue
        fi
      fi
      log "  Backing up volume: $real_vol"
      docker run --rm \
        -v "${real_vol}:/source:ro" \
        -v "${vol_dir}:/backup" \
        alpine tar cf "/backup/${real_vol}.tar" -C /source . 2>&1 || {
          warn "Failed to back up volume $real_vol"
          FAILED=$((FAILED + 1))
        }
    done
  fi

  # --- Back up .env and secrets/ ---
  local conf_dir="$tmp_dir/config"
  mkdir -p "$conf_dir"
  [ -f "$stack_dir/.env" ] && cp "$stack_dir/.env" "$conf_dir/.env"
  if [ -d "$stack_dir/secrets" ]; then
    cp -r "$stack_dir/secrets" "$conf_dir/secrets"
  fi

  # --- Create archive (single-pass gzip) ---
  log "  Compressing → $(basename "$archive")"
  tar czf "$archive" -C "$tmp_dir" . 2>&1 || {
    warn "Failed to create archive for $stack"
    FAILED=$((FAILED + 1))
  }

  # --- Checksum ---
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$archive" | awk '{print $1}' > "$checksum"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$archive" | awk '{print $1}' > "$checksum"
  fi
  log "  Checksum: $(cat "$checksum" 2>/dev/null || echo 'N/A')"

  # --- Restart if we stopped it ---
  if $was_running && ! $NO_STOP; then
    log "  Restarting $stack..."
    ( cd "$stack_dir" && docker compose start ) 2>&1 | sed 's/^/  /'
  fi

  local size
  size="$(du -h "$archive" | awk '{print $1}')"
  log "  Done. Archive: $size"
}

# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------
apply_retention() {
  [ "$RETAIN_DAYS" -eq 0 ] && return
  log "Applying retention: removing backups older than $RETAIN_DAYS days..."
  find "$TARGET_DIR" -name '*.tar.gz' -mtime +"$RETAIN_DAYS" -print -delete 2>/dev/null | while read -r f; do
    log "  Removed: $(basename "$f")"
    rm -f "${f%.tar.gz}.sha256"
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Backup starting: ${#STACKS[@]} stack(s) → $TARGET_DIR"
echo

for stack in "${STACKS[@]}"; do
  backup_stack "$stack"
  echo
done

if [ "$RETAIN_DAYS" -gt 0 ] && [ -d "$TARGET_DIR" ] && ! $DRY_RUN; then
  apply_retention
fi

if [ $FAILED -gt 0 ]; then
  warn "$FAILED error(s) occurred during backup."
  exit 1
fi

log "Backup complete."
