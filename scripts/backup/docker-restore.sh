#!/usr/bin/env bash
#
# docker-restore.sh — restore Docker Compose stack volumes + config from backup.
#
# Usage:
#   docker-restore.sh backups [<stack>]          List available backup archives.
#   docker-restore.sh list    <archive>          List contents of a backup.
#   docker-restore.sh verify  <archive>          Verify archive integrity.
#   docker-restore.sh restore <archive> [<stack>] Restore volumes + config.
#
# Options:
#   --force            Overwrite existing volumes without prompting.
#   --config-only      Restore only .env and secrets/, not volumes.
#   --volumes-only     Restore only volumes, not config files.
#   --prefix <name>    Prefix volume names on restore (e.g. --prefix test
#                      restores 'vaultwarden' as 'test-vaultwarden'). Enables
#                      testing a backup alongside the live stack.
#   --backup-dir <dir> Directory to scan for backups (default: <repo>/backups).
#   -h, --help         Show help.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_ROOT="$REPO_ROOT/docker-compose"

FORCE=false
CONFIG_ONLY=false
VOLUMES_ONLY=false
VOL_PREFIX=""
BACKUP_DIR="$REPO_ROOT/backups"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
ACTION=""
ARCHIVE=""
TARGET_STACK=""

usage() {
  sed -n '3,19p' "$0" | sed 's/^#//' | sed 's/^ //'
  exit "${1:-0}"
}

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force)        FORCE=true ;;
    --config-only)  CONFIG_ONLY=true ;;
    --volumes-only) VOLUMES_ONLY=true ;;
    --prefix)       VOL_PREFIX="$2"; shift ;;
    --backup-dir)   BACKUP_DIR="$2"; shift ;;
    -h|--help)      usage 0 ;;
    -*)             echo "Unknown option: $1" >&2; usage 2 ;;
    *)              args+=("$1") ;;
  esac
  shift
done

[ ${#args[@]} -lt 1 ] && usage 2

ACTION="${args[0]}"

# 'backups' action only needs an optional stack filter
if [ "$ACTION" = "backups" ]; then
  TARGET_STACK="${args[1]:-}"
else
  [ ${#args[@]} -lt 2 ] && { echo "ERROR: <archive> argument required." >&2; usage 2; }
  ARCHIVE="${args[1]}"
  TARGET_STACK="${args[2]:-}"
  if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: archive not found: $ARCHIVE" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "[%s] WARNING: %s\n" "$(date +%H:%M:%S)" "$*" >&2; }

# Apply prefix to a volume name
prefixed_vol() {
  if [ -n "$VOL_PREFIX" ]; then
    echo "${VOL_PREFIX}-${1}"
  else
    echo "$1"
  fi
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

do_backups() {
  if [ ! -d "$BACKUP_DIR" ]; then
    echo "No backups directory found at: $BACKUP_DIR"
    echo "Run docker-backup.sh first, or use --backup-dir to point elsewhere."
    exit 1
  fi

  local filter="*.tar.gz"
  if [ -n "$TARGET_STACK" ]; then
    filter="${TARGET_STACK}-*.tar.gz"
  fi

  local count=0
  local current_stack=""

  find "$BACKUP_DIR" -name "$filter" -type f | sort | while read -r f; do
    local base
    base="$(basename "$f")"
    local stack
    stack="$(echo "$base" | sed 's/-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]\.tar\.gz$//')"
    local ts
    ts="$(echo "$base" | sed 's/.*-\([0-9]\{8\}\)-\([0-9]\{6\}\)\.tar\.gz/\1-\2/' | sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/')"
    local size
    size="$(du -h "$f" | awk '{print $1}')"
    local checksum_status="no checksum"
    [ -f "${f%.tar.gz}.sha256" ] && checksum_status="sha256 ✓"

    if [ "$stack" != "$current_stack" ]; then
      [ -n "$current_stack" ] && echo
      printf "  %s\n" "$stack"
      printf "  %s\n" "$(printf '%*s' ${#stack} | tr ' ' '─')"
      current_stack="$stack"
    fi

    printf "    %-24s  %6s  %s\n" "$ts" "$size" "$checksum_status"
    printf "    %s\n" "$f"
    count=$((count + 1))
  done

  if [ $count -eq 0 ]; then
    echo "No backups found."
    [ -n "$TARGET_STACK" ] && echo "Filter: $TARGET_STACK"
  fi
}

do_list() {
  log "Contents of $(basename "$ARCHIVE"):"
  echo
  tar tzf "$ARCHIVE" | sed 's|^\./||' | grep -v '^$' | sort | while read -r entry; do
    case "$entry" in
      volumes/*.tar) printf "  [volume]  %s\n" "$(basename "$entry" .tar)" ;;
      config/.env)   printf "  [config]  .env\n" ;;
      config/secrets/*) printf "  [secret]  %s\n" "$(basename "$entry")" ;;
      *) printf "  [file]    %s\n" "$entry" ;;
    esac
  done
}

do_verify() {
  local checksum_file="${ARCHIVE%.tar.gz}.sha256"
  if [ ! -f "$checksum_file" ]; then
    warn "No .sha256 file found alongside the archive."
    log "Testing archive integrity only..."
  else
    local expected
    expected="$(cat "$checksum_file")"
    local actual
    if command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    else
      actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
    fi
    if [ "$expected" = "$actual" ]; then
      log "Checksum OK: $actual"
    else
      log "CHECKSUM MISMATCH!"
      log "  Expected: $expected"
      log "  Actual:   $actual"
      exit 1
    fi
  fi

  if tar tzf "$ARCHIVE" >/dev/null 2>&1; then
    log "Archive integrity OK."
  else
    log "Archive is CORRUPT — tar cannot read it."
    exit 1
  fi
}

do_restore() {
  # Determine target stack from archive name if not specified
  if [ -z "$TARGET_STACK" ]; then
    TARGET_STACK="$(basename "$ARCHIVE" | sed 's/-[0-9].*$//')"
    log "Auto-detected stack: $TARGET_STACK"
  fi

  local stack_dir="$COMPOSE_ROOT/$TARGET_STACK"

  if [ -n "$VOL_PREFIX" ]; then
    log "Volume prefix: '$VOL_PREFIX' (volumes will be named ${VOL_PREFIX}-<original>)"
  fi

  # Skip config restore when using a prefix (it's a test, not a real restore)
  if [ -n "$VOL_PREFIX" ]; then
    VOLUMES_ONLY=true
    log "Config restore skipped (prefix mode = test restore)."
  fi

  if [ ! -d "$stack_dir" ] && ! $VOLUMES_ONLY; then
    warn "Stack directory not found: $stack_dir"
    warn "Config files will not be restored."
  fi

  # Verify first
  do_verify
  echo

  # Extract to temp
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" EXIT
  tar xzf "$ARCHIVE" -C "$tmp_dir"

  # --- Restore volumes ---
  if ! $CONFIG_ONLY; then
    local vol_dir="$tmp_dir/volumes"
    if [ -d "$vol_dir" ]; then
      for vol_tar in "$vol_dir"/*.tar; do
        [ -f "$vol_tar" ] || continue
        local vol_name
        vol_name="$(basename "$vol_tar" .tar)"
        local target_vol
        target_vol="$(prefixed_vol "$vol_name")"

        if docker volume inspect "$target_vol" >/dev/null 2>&1; then
          if ! $FORCE; then
            printf "  Volume '%s' already exists. Overwrite? [y/N] " "$target_vol"
            read -r confirm
            case "$confirm" in
              y|Y) ;;
              *) log "  Skipping $target_vol."; continue ;;
            esac
          fi
          log "  Restoring volume: $target_vol (overwriting)"
        else
          log "  Creating and restoring volume: $target_vol"
          docker volume create "$target_vol" >/dev/null
        fi

        docker run --rm \
          -v "${target_vol}:/target" \
          -v "${vol_tar}:/backup.tar:ro" \
          alpine sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar xf /backup.tar -C /target" || {
            warn "Failed to restore volume $target_vol"
          }
      done
    else
      log "  No volumes in archive."
    fi
  fi

  # --- Restore config ---
  if ! $VOLUMES_ONLY && [ -d "$stack_dir" ]; then
    local conf_dir="$tmp_dir/config"
    if [ -d "$conf_dir" ]; then
      if [ -f "$conf_dir/.env" ]; then
        if [ -f "$stack_dir/.env" ] && ! $FORCE; then
          printf "  .env already exists. Overwrite? [y/N] "
          read -r confirm
          case "$confirm" in
            y|Y) cp "$conf_dir/.env" "$stack_dir/.env"; log "  Restored .env" ;;
            *) log "  Skipping .env" ;;
          esac
        else
          cp "$conf_dir/.env" "$stack_dir/.env"
          log "  Restored .env"
        fi
      fi

      if [ -d "$conf_dir/secrets" ]; then
        mkdir -p "$stack_dir/secrets"
        for secret_file in "$conf_dir/secrets"/*; do
          [ -f "$secret_file" ] || continue
          local fname
          fname="$(basename "$secret_file")"
          [ "$fname" = ".gitkeep" ] && continue
          if [ -f "$stack_dir/secrets/$fname" ] && ! $FORCE; then
            printf "  Secret '%s' exists. Overwrite? [y/N] " "$fname"
            read -r confirm
            case "$confirm" in
              y|Y) cp "$secret_file" "$stack_dir/secrets/$fname"; log "  Restored secret: $fname" ;;
              *) log "  Skipping $fname" ;;
            esac
          else
            cp "$secret_file" "$stack_dir/secrets/$fname"
            log "  Restored secret: $fname"
          fi
        done
      fi
    fi
  fi

  echo
  log "Restore complete for '$TARGET_STACK'."
  if [ -n "$VOL_PREFIX" ]; then
    log "Test volumes created with prefix '${VOL_PREFIX}-'. Clean up with:"
    log "  docker volume rm \$(docker volume ls -q | grep '^${VOL_PREFIX}-')"
    echo
    printf "  Launch stack against test data? [y/N] "
    read -r launch
    case "$launch" in
      y|Y) do_test_launch ;;
    esac
  else
    log "Start the stack with: scripts/homelab.sh start $TARGET_STACK"
  fi
}

# ---------------------------------------------------------------------------
# Test launch — run the stack against prefixed volumes on a custom port.
# ---------------------------------------------------------------------------
do_test_launch() {
  local stack_dir="$COMPOSE_ROOT/$TARGET_STACK"
  local compose_src
  compose_src="$(find "$stack_dir" -maxdepth 1 \( -name 'compose.yaml' -o -name 'compose.yml' \
    -o -name 'docker-compose.yaml' -o -name 'docker-compose.yml' \) -print -quit)"

  if [ -z "$compose_src" ]; then
    warn "No compose file found for '$TARGET_STACK'. Cannot launch."
    return 1
  fi

  # Ask for a custom port
  local orig_port
  orig_port="$(cd "$stack_dir" && docker compose config 2>/dev/null \
    | awk '/published:/{gsub(/"/,"",$2); print $2; exit}')"

  local test_port
  if [ -n "$orig_port" ]; then
    local suggested=$((orig_port + 1000))
    printf "  Port for test instance [default: %d]: " "$suggested"
    read -r test_port
    [ -z "$test_port" ] && test_port="$suggested"
  else
    printf "  Host port for test instance: "
    read -r test_port
    [ -z "$test_port" ] && { warn "No port specified, aborting."; return 1; }
  fi

  local project_name="${VOL_PREFIX}-${TARGET_STACK}"
  local test_dir
  test_dir="$(mktemp -d)"
  local override_file="$test_dir/compose.yaml"

  log "Generating test compose at: $override_file"
  log "Project name: $project_name"

  # Read the original compose and rewrite volume references + port + project name
  # Strategy: use the original compose with an override that remaps volumes and ports
  # Build the override: remap each volume to the prefixed version

  # Get service name(s)
  local services
  services="$(cd "$stack_dir" && docker compose config --services 2>/dev/null)"

  # Start building override
  {
    echo "name: ${project_name}"
    echo ""
    echo "services:"

    for svc in $services; do
      echo "  ${svc}:"
      # Remap port: replace the first published port with test_port
      echo "    ports: !override"
      local container_port
      container_port="$(cd "$stack_dir" && docker compose config 2>/dev/null \
        | awk "/^  ${svc}:/{found=1} found && /target:/{print \$2; exit}")"
      [ -z "$container_port" ] && container_port="80"
      echo "      - \"${test_port}:${container_port}\""
      echo ""
    done

    # Remap volumes to prefixed versions
    echo "volumes:"
    local vol_names
    vol_names="$(cd "$stack_dir" && docker compose config 2>/dev/null \
      | awk '/^volumes:/{found=1; next} found && /^[^ ]/{exit} found && /name:/{print $2}' \
      | tr -d '"' | tr -d "'")"
    for vol in $vol_names; do
      local prefixed="${VOL_PREFIX}-${vol}"
      # Use the compose key (derive from the config)
      local vol_key
      vol_key="$(cd "$stack_dir" && docker compose config 2>/dev/null \
        | awk -v name="$vol" '/^volumes:/{found=1; next} found && /^[^ ]/{exit} found && /^  [a-z]/{key=$1} found && /name:/ && $2==name{gsub(/:$/,"",key); print key}' \
        | tr -d '"')"
      [ -z "$vol_key" ] && vol_key="$vol"
      echo "  ${vol_key}:"
      echo "    name: ${prefixed}"
      echo "    external: true"
    done

    # Network — create a dedicated test network
    echo ""
    echo "networks:"
    local net_names
    net_names="$(cd "$stack_dir" && docker compose config 2>/dev/null \
      | awk '/^networks:/{found=1; next} found && /^[^ ]/{exit} found && /^  [a-z]/{gsub(/:$/,""); print $1}')"
    for net in $net_names; do
      echo "  ${net}:"
      echo "    name: ${project_name}"
    done
  } > "$override_file"

  log "Starting test instance on port $test_port..."
  docker network create "$project_name" 2>/dev/null || true
  docker compose -f "$compose_src" -f "$override_file" -p "$project_name" up -d 2>&1 | sed 's/^/  /'

  echo
  log "Test instance running:"
  log "  URL:     http://localhost:${test_port}"
  log "  Project: $project_name"
  log ""
  log "To view status:"
  log "  docker compose -p ${project_name} ps"
  log ""
  log "To stop and clean up:"
  log "  docker compose -p ${project_name} down"
  log "  docker network rm ${project_name} 2>/dev/null"
  log "  docker volume rm \$(docker volume ls -q | grep '^${VOL_PREFIX}-')"
  log "  rm -rf $test_dir"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$ACTION" in
  backups) do_backups ;;
  list)    do_list ;;
  verify)  do_verify ;;
  restore) do_restore ;;
  *) echo "Unknown action: $ACTION" >&2; usage 2 ;;
esac
