#!/usr/bin/env bash
#
# update-images.sh — check for newer Docker image releases across all stacks,
# and optionally update pins, restart containers, and remove old images.
#
# Usage:
#   update-images.sh                   Check all stacks, interactive prompts.
#   update-images.sh --check           Check only, no changes (CI-friendly).
#   update-images.sh --auto            Update all without prompting.
#   update-images.sh <stack>           Check a single stack.
#
# Requires: docker with buildx, sed, grep, awk.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_ROOT="$REPO_ROOT/docker-compose"

MODE="interactive"  # interactive | check | auto
TARGET=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --auto)  MODE="auto" ;;
    --bump)  MODE="bump" ;;
    -h|--help)
      cat <<'EOF'
Usage: update-images.sh [OPTIONS] [<stack>]

Options:
  --check    Check for updates only, no modifications (exit 1 if updates found).
  --auto     Apply all digest updates without prompting.
  --bump     Interactively change the version tag for a stack's image(s).
  -h, --help Show this help.

Without options, runs interactively. For each outdated image the script offers:
  [u] Update digest — same tag, new digest (rebuild of same version).
  [v] Version bump  — enter a new tag, script resolves its digest and updates.
  [s] Skip.
EOF
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *)  TARGET="$1" ;;
  esac
  shift
done

# Colors (if terminal supports them)
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; NC=''
fi

# ---------------------------------------------------------------------------
# Extract image references from compose files.
# Returns lines: <stack> <compose_file> <full_image_ref>
# ---------------------------------------------------------------------------
find_images() {
  local search_path="$COMPOSE_ROOT"
  if [ -n "$TARGET" ]; then
    search_path="$COMPOSE_ROOT/$TARGET"
    if [ ! -d "$search_path" ]; then
      echo "ERROR: stack '$TARGET' not found." >&2
      exit 1
    fi
  fi

  find "$search_path" -name 'compose.yaml' -o -name 'compose.yml' \
    -o -name 'docker-compose.yaml' -o -name 'docker-compose.yml' | sort | while read -r f; do
    stack="$(basename "$(dirname "$f")")"
    # Extract image lines, skip commented ones
    grep -E '^\s+image:' "$f" | grep -v '^\s*#' | while read -r line; do
      img="$(echo "$line" | sed 's/.*image:\s*//' | tr -d '"' | tr -d "'")"
      # Skip images with variable interpolation (e.g. ${IMMICH_VERSION})
      echo "$img" | grep -q '\$' && continue
      echo "$stack $f $img"
    done
  done
}

# ---------------------------------------------------------------------------
# Parse an image reference into components.
# Input:  registry/repo:tag@sha256:digest
# Output: Sets global vars: IMG_NAME, IMG_TAG, IMG_DIGEST
# ---------------------------------------------------------------------------
parse_image() {
  local ref="$1"
  IMG_DIGEST=""
  IMG_TAG=""

  if echo "$ref" | grep -q '@'; then
    IMG_DIGEST="${ref#*@}"
    ref="${ref%%@*}"
  fi

  if echo "$ref" | grep -q ':'; then
    IMG_TAG="${ref##*:}"
    IMG_NAME="${ref%:*}"
  else
    IMG_TAG="latest"
    IMG_NAME="$ref"
  fi
}

# ---------------------------------------------------------------------------
# Check if a newer version exists for a given image.
# Uses `docker buildx imagetools inspect` to get the current upstream digest.
# Returns 0 if update available, 1 if up-to-date, 2 on error.
# Sets: UPSTREAM_DIGEST
# ---------------------------------------------------------------------------
check_upstream() {
  local name="$1" tag="$2" current_digest="$3"

  local ref="${name}:${tag}"
  local output
  output="$(docker buildx imagetools inspect "$ref" 2>&1)" || return 2

  UPSTREAM_DIGEST="$(echo "$output" | grep '^Digest:' | head -1 | awk '{print $2}')"
  [ -z "$UPSTREAM_DIGEST" ] && return 2

  if [ -n "$current_digest" ]; then
    if [ "$UPSTREAM_DIGEST" = "$current_digest" ]; then
      return 1  # up to date
    else
      return 0  # update available
    fi
  else
    # No digest pinned — always suggest pinning
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Update the image reference in a compose file.
# ---------------------------------------------------------------------------
update_compose_file() {
  local file="$1" old_ref="$2" new_ref="$3"

  # Escape special chars for sed
  local old_escaped new_escaped
  old_escaped="$(echo "$old_ref" | sed 's/[&/\$]/\\&/g')"
  new_escaped="$(echo "$new_ref" | sed 's/[&/\$]/\\&/g')"

  sed -i.bak "s|${old_escaped}|${new_escaped}|g" "$file"
  rm -f "${file}.bak"
}

# ---------------------------------------------------------------------------
# Main logic.
# ---------------------------------------------------------------------------
UPDATES_FOUND=0
UPDATES_APPLIED=0

# Bump mode: show all images and prompt for new version regardless of status.
if [ "$MODE" = "bump" ]; then
  printf "${YELLOW}Version bump mode — enter new tags for images to update.${NC}\n\n"

  find_images | while IFS=' ' read -r stack file img; do
    parse_image "$img"
    printf "  %-20s %s:%s\n" "$stack" "$IMG_NAME" "$IMG_TAG"
    printf "    New version tag (enter to skip): "
    read -r new_tag
    [ -z "$new_tag" ] && { echo "    Skipped."; echo; continue; }

    echo "    Resolving digest for ${IMG_NAME}:${new_tag}..."
    bump_output="$(docker buildx imagetools inspect "${IMG_NAME}:${new_tag}" 2>&1)"
    bump_digest="$(echo "$bump_output" | grep '^Digest:' | head -1 | awk '{print $2}')"

    if [ -z "$bump_digest" ]; then
      printf "    ${RED}Tag '${new_tag}' not found. Skipping.${NC}\n\n"
      continue
    fi

    BUMP_REF="${IMG_NAME}:${new_tag}@${bump_digest}"
    printf "    → %s\n" "$BUMP_REF"
    echo "    Updating compose file..."
    update_compose_file "$file" "$img" "$BUMP_REF"

    echo "    Pulling and recreating..."
    ( cd "$(dirname "$file")" && docker compose up -d --force-recreate --pull always ) 2>&1 \
      | grep -E '(Pulled|Recreat|Start)' | sed 's/^/    /'

    echo "    Pruning old images..."
    docker image prune -f 2>&1 | grep -v "^$" | sed 's/^/    /'

    UPDATES_APPLIED=$((UPDATES_APPLIED + 1))
    printf "    ${GREEN}Done. Pinned to ${new_tag}.${NC}\n\n"
  done

  exit 0
fi

printf "${YELLOW}Checking images for updates...${NC}\n\n"

find_images | while IFS=' ' read -r stack file img; do
  parse_image "$img"

  printf "  %-20s %-50s " "$stack" "${IMG_NAME}:${IMG_TAG}"

  if ! check_upstream "$IMG_NAME" "$IMG_TAG" "$IMG_DIGEST"; then
    rc=$?
    if [ $rc -eq 2 ]; then
      printf "${RED}error (could not inspect upstream)${NC}\n"
      continue
    fi
  fi

  # check_upstream returns 1 = up to date, 0 = update available
  # We need to re-run to capture the return code properly
  check_upstream "$IMG_NAME" "$IMG_TAG" "$IMG_DIGEST"
  rc=$?

  if [ $rc -eq 1 ]; then
    printf "${GREEN}up to date${NC}\n"
    continue
  elif [ $rc -eq 2 ]; then
    printf "${RED}error${NC}\n"
    continue
  fi

  # Update available
  UPDATES_FOUND=$((UPDATES_FOUND + 1))
  NEW_REF="${IMG_NAME}:${IMG_TAG}@${UPSTREAM_DIGEST}"

  if [ -n "$IMG_DIGEST" ]; then
    printf "${YELLOW}update available${NC}\n"
    printf "    Current: %s\n" "$IMG_DIGEST"
    printf "    New:     %s\n" "$UPSTREAM_DIGEST"
  else
    printf "${YELLOW}not pinned by digest${NC}\n"
    printf "    Suggest: %s\n" "$NEW_REF"
  fi

  if [ "$MODE" = "check" ]; then
    continue
  fi

  # Prompt or auto-apply
  apply="n"
  if [ "$MODE" = "auto" ]; then
    apply="y"
  else
    printf "    [u]pdate digest / [v]ersion bump / [s]kip? [u/v/s] "
    read -r apply
  fi

  case "$apply" in
    u|U|y|Y)
      echo "    Updating compose file (same tag, new digest)..."
      update_compose_file "$file" "$img" "$NEW_REF"

      echo "    Pulling and recreating..."
      ( cd "$(dirname "$file")" && docker compose up -d --force-recreate --pull always ) 2>&1 \
        | grep -E '(Pulled|Recreat|Start)' | sed 's/^/    /'

      echo "    Pruning old images..."
      docker image prune -f 2>&1 | grep -v "^$" | sed 's/^/    /'

      UPDATES_APPLIED=$((UPDATES_APPLIED + 1))
      printf "    ${GREEN}Done.${NC}\n"
      ;;
    v|V)
      printf "    New version tag (e.g. v2.0.0): "
      read -r new_tag
      if [ -z "$new_tag" ]; then
        echo "    No tag entered, skipping."
      else
        # Resolve the digest for the new tag
        echo "    Resolving digest for ${IMG_NAME}:${new_tag}..."
        local_upstream=""
        bump_output="$(docker buildx imagetools inspect "${IMG_NAME}:${new_tag}" 2>&1)"
        bump_digest="$(echo "$bump_output" | grep '^Digest:' | head -1 | awk '{print $2}')"

        if [ -z "$bump_digest" ]; then
          printf "    ${RED}Tag '${new_tag}' not found for ${IMG_NAME}. Skipping.${NC}\n"
        else
          BUMP_REF="${IMG_NAME}:${new_tag}@${bump_digest}"
          printf "    New ref: %s\n" "$BUMP_REF"
          echo "    Updating compose file..."
          update_compose_file "$file" "$img" "$BUMP_REF"

          echo "    Pulling and recreating..."
          ( cd "$(dirname "$file")" && docker compose up -d --force-recreate --pull always ) 2>&1 \
            | grep -E '(Pulled|Recreat|Start)' | sed 's/^/    /'

          echo "    Pruning old images..."
          docker image prune -f 2>&1 | grep -v "^$" | sed 's/^/    /'

          UPDATES_APPLIED=$((UPDATES_APPLIED + 1))
          printf "    ${GREEN}Done. Pinned to ${new_tag}.${NC}\n"
        fi
      fi
      ;;
    *)
      echo "    Skipped."
      ;;
  esac
  echo
done

echo
if [ "$MODE" = "check" ] && [ $UPDATES_FOUND -gt 0 ]; then
  printf "${YELLOW}%d update(s) available.${NC}\n" "$UPDATES_FOUND"
  exit 1
elif [ $UPDATES_FOUND -eq 0 ]; then
  printf "${GREEN}All images are up to date.${NC}\n"
fi
