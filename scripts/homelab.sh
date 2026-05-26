#!/usr/bin/env bash
#
# homelab.sh — manage Docker Compose stacks under docker-compose/<stack>/.
#
# Usage:
#   homelab.sh                        Interactive menu.
#   homelab.sh list                   List discovered stacks.
#   homelab.sh status  [<stack>...]   docker compose ps. Defaults to all.
#   homelab.sh start    <stack>...    docker compose up -d.
#   homelab.sh stop     <stack>...    docker compose stop.
#   homelab.sh restart  <stack>...    docker compose restart.
#   homelab.sh delete   <stack>...    docker compose down --remove-orphans.
#                                       (named volumes are KEPT)
#   homelab.sh destroy  <stack>...    docker compose down --volumes
#                                       --remove-orphans. DESTRUCTIVE; per-stack
#                                       typed confirmation required.
#   homelab.sh logs     <stack>       docker compose logs --tail=200 -f.
#                                       Single stack only.
#
# Selectors usable in place of any <stack>:
#   all       Every stack discovered under docker-compose/.
#   running   Currently-running stacks (per `docker compose ls`).
#
# Exit status:
#   0 on success, 2 on usage error, 127 on missing dependencies, otherwise
#   the highest exit status returned by an underlying docker compose call.
#
# Compatibility: written for bash 3.2+ so it works with the stock
# /bin/bash on macOS. Avoids `mapfile`, lower-case parameter expansion, and
# other bash 4+ features.

set -euo pipefail

# ----------------------------------------------------------------------------
# Locate repo root (assumes this script lives in <repo>/scripts/).
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_ROOT="$REPO_ROOT/docker-compose"

if [ ! -d "$COMPOSE_ROOT" ]; then
  echo "ERROR: compose root not found: $COMPOSE_ROOT" >&2
  exit 127
fi

# ----------------------------------------------------------------------------
# Detect the docker compose CLI form. Prefer the v2 plugin form.
# ----------------------------------------------------------------------------
DC_CMD=""
if docker compose version >/dev/null 2>&1; then
  DC_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC_CMD="docker-compose"
else
  echo "ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
  exit 127
fi

# Run docker compose against a stack directory.
dc() {
  # shellcheck disable=SC2086
  ( cd "$1" && shift && $DC_CMD "$@" )
}

# ----------------------------------------------------------------------------
# Discovery helpers.
# ----------------------------------------------------------------------------

# Echo the path to the stack's compose file, or return non-zero.
stack_file() {
  stack="$1"
  d="$COMPOSE_ROOT/$stack"
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "$d/$f" ]; then
      echo "$d/$f"
      return 0
    fi
  done
  return 1
}

# Print every stack name (one per line, sorted, deduped).
list_stacks() {
  find "$COMPOSE_ROOT" -mindepth 2 -maxdepth 2 -type f \
    \( -name 'compose.yaml' -o -name 'compose.yml' \
    -o -name 'docker-compose.yaml' -o -name 'docker-compose.yml' \) \
    -print 2>/dev/null \
    | awk -F/ '{print $(NF-1)}' \
    | sort -u
}

# Print the names of currently-running stacks (one per line).
# Uses `docker compose ls` so it covers any project Docker knows about,
# then intersects with our discovered stacks.
list_running_stacks() {
  running="$($DC_CMD ls --quiet 2>/dev/null || true)"
  [ -n "$running" ] || return 0
  ours="$(list_stacks)"
  echo "$running" | while IFS= read -r name; do
    [ -z "$name" ] && continue
    if echo "$ours" | grep -Fxq "$name"; then
      echo "$name"
    fi
  done
}

# Resolve user-supplied stack arguments, expanding 'all' and 'running'.
# Echoes the resolved names, one per line.
resolve_stacks() {
  for s in "$@"; do
    case "$s" in
      all)     list_stacks ;;
      running) list_running_stacks ;;
      *)       echo "$s" ;;
    esac
  done
}

# ----------------------------------------------------------------------------
# Per-action implementations.
# Each function takes a single stack name.
# ----------------------------------------------------------------------------

act_start() {
  d="$(dirname "$(stack_file "$1")")"
  dc "$d" up -d
}

act_stop() {
  d="$(dirname "$(stack_file "$1")")"
  dc "$d" stop
}

act_restart() {
  d="$(dirname "$(stack_file "$1")")"
  dc "$d" restart
}

act_delete() {
  d="$(dirname "$(stack_file "$1")")"
  dc "$d" down --remove-orphans
}

act_destroy() {
  stack="$1"
  d="$(dirname "$(stack_file "$stack")")"
  echo
  echo "WARNING: 'destroy' will remove containers, networks AND named volumes"
  echo "         for stack '$stack'. Bind-mounted host data is NOT touched,"
  echo "         but anything stored in a named volume will be permanently"
  echo "         lost."
  printf "Type the stack name '%s' to confirm: " "$stack"
  read -r confirm
  if [ "$confirm" != "$stack" ]; then
    echo "Confirmation mismatch, skipping '$stack'." >&2
    return 1
  fi
  dc "$d" down --volumes --remove-orphans
}

act_status() {
  d="$(dirname "$(stack_file "$1")")"
  dc "$d" ps
}

act_logs() {
  d="$(dirname "$(stack_file "$1")")"
  dc "$d" logs --tail=200 -f
}

# ----------------------------------------------------------------------------
# Help text.
# ----------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: homelab.sh <action> [<stack>|all|running ...]

Actions:
  list                       List every stack discovered under docker-compose/.
  status   [<stack>...]      docker compose ps. Defaults to 'all'.
  start    <stack>...        docker compose up -d.
  stop     <stack>...        docker compose stop.
  restart  <stack>...        docker compose restart.
  delete   <stack>...        docker compose down --remove-orphans.
                             Named volumes are kept.
  destroy  <stack>...        docker compose down --volumes --remove-orphans.
                             DESTRUCTIVE; typed confirmation per stack.
  logs     <stack>           Follow logs for a single stack.

Selectors:
  all       Resolves to every discovered stack.
  running   Resolves to currently-running stacks.

With no arguments, an interactive menu is shown.

Examples:
  homelab.sh start vaultwarden
  homelab.sh restart all
  homelab.sh stop running
  homelab.sh destroy vaultwarden       # asks for confirmation
EOF
}

# ----------------------------------------------------------------------------
# Interactive menu.
# ----------------------------------------------------------------------------

interactive() {
  echo "Homelab stack manager"
  echo "Compose root : $COMPOSE_ROOT"
  echo "Compose CLI  : $DC_CMD"
  echo

  stacks_str="$(list_stacks)"
  if [ -z "$stacks_str" ]; then
    echo "No stacks found under $COMPOSE_ROOT" >&2
    return 1
  fi

  # Build a numbered list with 'all' appended.
  echo "Available stacks:"
  i=0
  options=""
  while IFS= read -r s; do
    i=$((i + 1))
    printf "  %2d) %s\n" "$i" "$s"
    options="$options $s"
  done <<EOF
$stacks_str
EOF
  i=$((i + 1))
  printf "  %2d) all\n" "$i"
  options="$options all"

  printf "\nSelect stack number (q to quit): "
  read -r n
  case "$n" in
    q|Q|"") echo "aborted."; return 0 ;;
    *[!0-9]*|"") echo "invalid choice." >&2; return 2 ;;
  esac
  if [ "$n" -lt 1 ] || [ "$n" -gt "$i" ]; then
    echo "out of range." >&2; return 2
  fi
  # shellcheck disable=SC2086
  set -- $options
  stack="$(eval echo "\${$n}")"

  echo
  echo "Available actions:"
  echo "   1) start"
  echo "   2) stop"
  echo "   3) restart"
  echo "   4) delete    (keep volumes)"
  echo "   5) destroy   (delete volumes — DESTRUCTIVE)"
  echo "   6) status"
  echo "   7) logs"
  printf "\nSelect action number (q to quit): "
  read -r a
  case "$a" in
    q|Q|"") echo "aborted."; return 0 ;;
    1) action=start   ;;
    2) action=stop    ;;
    3) action=restart ;;
    4) action=delete  ;;
    5) action=destroy ;;
    6) action=status  ;;
    7) action=logs    ;;
    *) echo "invalid choice." >&2; return 2 ;;
  esac

  if [ "$stack" = "all" ]; then
    if [ "$action" = "logs" ]; then
      echo "ERROR: 'logs' is not supported for 'all'. Pick a single stack." >&2
      return 2
    fi
    targets="$(list_stacks)"
  else
    targets="$stack"
  fi

  rc=0
  echo "$targets" | while IFS= read -r s; do
    [ -z "$s" ] && continue
    echo
    echo "==> $action $s"
    "act_${action}" "$s" || rc=$?
  done
  return $rc
}

# ----------------------------------------------------------------------------
# Argument dispatch.
# ----------------------------------------------------------------------------

if [ $# -eq 0 ]; then
  interactive
  exit $?
fi

action="$1"
shift || true

case "$action" in
  -h|--help|help)
    usage
    exit 0
    ;;

  list)
    list_stacks
    exit 0
    ;;

  status)
    if [ $# -eq 0 ]; then
      set -- all
    fi
    ;;

  start|stop|restart|delete|destroy|logs)
    if [ $# -eq 0 ]; then
      echo "ERROR: '$action' needs at least one stack name (or 'all'/'running')." >&2
      usage
      exit 2
    fi
    if [ "$action" = "logs" ] && [ $# -ne 1 ]; then
      echo "ERROR: 'logs' supports a single stack only." >&2
      exit 2
    fi
    ;;

  *)
    echo "ERROR: unknown action: $action" >&2
    usage
    exit 2
    ;;
esac

# Resolve selectors.
resolved="$(resolve_stacks "$@")"
if [ -z "$resolved" ]; then
  echo "No stacks resolved from arguments: $*" >&2
  exit 1
fi

# Validate every resolved stack actually exists before doing anything.
missing=""
echo "$resolved" | while IFS= read -r s; do
  [ -z "$s" ] && continue
  if ! stack_file "$s" >/dev/null 2>&1; then
    echo "ERROR: no compose file for stack '$s' under $COMPOSE_ROOT" >&2
    missing="$missing $s"
  fi
done
# Re-check using a separate pass so the subshell variable issue with `while`
# doesn't hide a missing stack.
bad=0
echo "$resolved" | while IFS= read -r s; do
  [ -z "$s" ] && continue
  stack_file "$s" >/dev/null 2>&1 || exit 1
done || bad=$?
if [ $bad -ne 0 ]; then
  exit 1
fi

# Run the action across resolved stacks.
final_rc=0
echo "$resolved" | (
  rc=0
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    echo
    echo "==> $action $s"
    "act_${action}" "$s" || rc=$?
  done
  exit $rc
) || final_rc=$?

exit $final_rc
