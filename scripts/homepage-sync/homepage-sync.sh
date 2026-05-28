#!/usr/bin/env bash
#
# homepage-sync.sh — compare running containers with Homepage services.yaml
# and offer to add missing or remove stale entries.
#
# Usage:
#   homepage-sync.sh           Interactive: show diff, offer changes.
#   homepage-sync.sh --check   Report only, no changes.

set -uo pipefail

HOMEPAGE_CONTAINER="homepage-homepage-1"
MODE="interactive"
[ "${1:-}" = "--check" ] && MODE="check"

# Helper: copy file into homepage config volume with correct permissions
copy_to_homepage() {
  local src="$1"
  docker run --rm -v homepage:/config -v "${src}:/tmp/services.yaml:ro" \
    alpine sh -c "cp /tmp/services.yaml /config/services.yaml && chmod 664 /config/services.yaml && chown root:root /config/services.yaml"
}

# Get services.yaml
SERVICES_YAML="$(docker exec "$HOMEPAGE_CONTAINER" cat /app/config/services.yaml 2>/dev/null)" || {
  echo "ERROR: cannot read services.yaml from $HOMEPAGE_CONTAINER" >&2
  exit 1
}

# Extract active container names from services.yaml
HOMEPAGE_CONTAINERS="$(echo "$SERVICES_YAML" \
  | grep -E '^\s+container:' \
  | sed 's/.*container:[[:space:]]*//' \
  | tr -d '"' | tr -d "'" \
  | sed 's/^[[:space:]]*//' \
  | sort -u)"

# Running container names
RUNNING="$(docker ps --format '{{.Names}}' | sort -u)"

# --- In Homepage but not running ---
echo "━━━ In Homepage but NOT running ━━━"
STALE=""
while IFS= read -r c; do
  [ -z "$c" ] && continue
  if ! echo "$RUNNING" | grep -Fxq "$c"; then
    printf "  ✗ %s\n" "$c"
    STALE="${STALE}${c}\n"
  fi
done <<EOF
$HOMEPAGE_CONTAINERS
EOF
[ -z "$STALE" ] && echo "  (none)"

# --- Running but not in Homepage ---
echo
echo "━━━ Running but NOT in Homepage ━━━"
MISSING=""
while IFS= read -r c; do
  [ -z "$c" ] && continue
  if ! echo "$HOMEPAGE_CONTAINERS" | grep -Fxq "$c"; then
    info="$(docker inspect "$c" --format '{{.Config.Image}}' 2>/dev/null | sed 's/@sha256:.*//')"
    port="$(docker port "$c" 2>/dev/null | head -1 | grep -oE '[0-9]+$')"
    printf "  + %-45s %s %s\n" "$c" "${info:-}" "${port:+:$port}"
    MISSING="${MISSING}${c}\n"
  fi
done <<EOF
$RUNNING
EOF
[ -z "$MISSING" ] && echo "  (none)"

echo
echo "━━━ Summary ━━━"
echo "  Homepage references: $(echo "$HOMEPAGE_CONTAINERS" | grep -c . || echo 0)"
echo "  Running containers:  $(echo "$RUNNING" | grep -c . || echo 0)"

[ "$MODE" = "check" ] && exit 0

# --- Offer to remove stale entries ---
if [ -n "$STALE" ]; then
  echo
  printf "Comment out stale entries from services.yaml? [y/N] "
  read -r ans < /dev/tty
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    TMP="$(mktemp)"
    docker exec "$HOMEPAGE_CONTAINER" cat /app/config/services.yaml > "$TMP"
    printf '%b' "$STALE" | while IFS= read -r c; do
      [ -z "$c" ] && continue
      # Comment out lines containing this container reference + surrounding service block
      sed -i.bak "/container: ${c}$/s/^/# /" "$TMP"
      echo "  Commented: $c"
    done
    rm -f "${TMP}.bak"
    copy_to_homepage "$TMP"
    rm -f "$TMP"
    echo "  Done. Homepage will reload automatically."
  fi
fi

# --- Offer to add missing containers ---
if [ -n "$MISSING" ]; then
  echo
  echo "Add running containers to Homepage?"
  printf '%b' "$MISSING" | while IFS= read -r c; do
    [ -z "$c" ] && continue
    port="$(docker port "$c" 2>/dev/null | head -1 | grep -oE '[0-9]+$')"
    # Skip containers with no exposed port (internal services)
    [ -z "$port" ] && { printf "  Skip %s (no exposed port)\n" "$c"; continue; }

    printf "  Add '%s' (port %s)? [y/N] " "$c" "$port"
    read -r ans < /dev/tty
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      # Derive a display name from compose service label, fallback to container name
      svc_label="$(docker inspect "$c" --format '{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null)"
      display="$(echo "${svc_label:-$c}" | sed 's/-[0-9]*$//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')"
      # Ask for section
      printf "    Section name (press Enter for 'Intranet'): "
      read -r section < /dev/tty
      [ -z "$section" ] && section="Intranet"

      # Build the YAML snippet
      SNIPPET="    - ${display}:
        href: http://\${HOST_IP:-127.0.0.1}:${port}
        description: ${display}
        server: my-docker
        container: ${c}
        siteMonitor: http://\${HOST_IP:-127.0.0.1}:${port}
        icon: docker.svg"

      # Append under the matching section
      TMP="$(mktemp)"
      docker exec "$HOMEPAGE_CONTAINER" cat /app/config/services.yaml > "$TMP"
      # Find the section and insert snippet after it
      if grep -qn "^- ${section}:" "$TMP"; then
        LINE=$(grep -n "^- ${section}:" "$TMP" | head -1 | cut -d: -f1)
        { head -n "$LINE" "$TMP"; echo "$SNIPPET"; tail -n +"$((LINE + 1))" "$TMP"; } > "${TMP}.new"
        mv "${TMP}.new" "$TMP"
      else
        # Section doesn't exist, append at end
        printf "\n- %s:\n%s\n" "$section" "$SNIPPET" >> "$TMP"
      fi
      copy_to_homepage "$TMP"
      rm -f "$TMP"
      echo "    Added."
    fi
  done
fi
