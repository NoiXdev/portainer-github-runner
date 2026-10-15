#!/usr/bin/env sh
# Reset a self-hosted runner host, or just look at what is filling it up.
#
# Run it ON THE HOST, not inside the runner container.
#
# It reports by default and changes nothing. Every destructive scope is an
# explicit flag, because this script cannot tell a job's leftovers from another
# stack's data — only you can.
#
#   ./cleanup.sh                     what is using disk, and what each flag would remove
#   ./cleanup.sh --containers        remove stopped containers
#   ./cleanup.sh --images            remove unused images and build cache
#   ./cleanup.sh --work /srv/x/_work clear a work root, keeping _tool and _actions
#   ./cleanup.sh --volumes           remove unused volumes  ⚠ see the warning below
#   ./cleanup.sh --all --work /srv/x/_work   everything except volumes
#
# Add --yes to skip the confirmation (for cron; think before you do).

set -eu

KEEP="${KEEP:-}"            # e.g. KEEP=24h to spare anything younger
WORK=""
DO_CONTAINERS=0
DO_IMAGES=0
DO_VOLUMES=0
ASSUME_YES=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --containers) DO_CONTAINERS=1 ;;
    --images)     DO_IMAGES=1 ;;
    --volumes)    DO_VOLUMES=1 ;;
    --all)        DO_CONTAINERS=1; DO_IMAGES=1 ;;
    --work)       shift; WORK="${1:?--work needs a path}" ;;
    --yes|-y)     ASSUME_YES=1 ;;
    -h|--help)    usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done

filter=""
[ -n "$KEEP" ] && filter="--filter until=$KEEP"

echo "── Disk ──────────────────────────────────────────────────────────────"
docker system df
echo
echo "── Stopped containers ────────────────────────────────────────────────"
docker ps -a --filter status=exited --filter status=created \
  --format '  {{.Names}}  ({{.Image}}, {{.Status}})' || true
echo
if [ -n "$WORK" ]; then
  echo "── Work root: $WORK ──────────────────────────────────────────────────"
  if [ -d "$WORK" ]; then
    du -sh "$WORK" 2>/dev/null || true
    for d in "$WORK"/*; do
      [ -e "$d" ] || continue
      case "$(basename "$d")" in
        _tool|_actions) echo "  $(du -sh "$d" 2>/dev/null | cut -f1)  $(basename "$d")  (cache — kept)" ;;
        *)              echo "  $(du -sh "$d" 2>/dev/null | cut -f1)  $(basename "$d")" ;;
      esac
    done
  else
    echo "  does not exist"
  fi
  echo
fi

if [ "$DO_CONTAINERS" -eq 0 ] && [ "$DO_IMAGES" -eq 0 ] && [ "$DO_VOLUMES" -eq 0 ] && [ -z "$WORK" ]; then
  cat <<'TXT'
Nothing was changed. To act, name a scope:

  --containers   stopped containers
  --images       unused images and build cache
  --work PATH    a work root, keeping _tool and _actions
  --volumes      unused volumes  ⚠ on a shared host this destroys other stacks'
                 data: a volume whose container was removed counts as unused.
                 Only on a host that runs nothing but runners.

  KEEP=24h ./cleanup.sh --all   spares anything younger than 24h
TXT
  exit 0
fi

echo "── Would remove ──────────────────────────────────────────────────────"
[ "$DO_CONTAINERS" -eq 1 ] && echo "  stopped containers${KEEP:+ older than $KEEP}"
[ "$DO_IMAGES" -eq 1 ]     && echo "  unused images and build cache${KEEP:+ older than $KEEP}"
[ -n "$WORK" ]             && echo "  everything in $WORK except _tool and _actions"
[ "$DO_VOLUMES" -eq 1 ]    && echo "  UNUSED VOLUMES — including other stacks' data if any container was removed"
echo

if [ "$ASSUME_YES" -eq 0 ]; then
  printf 'Proceed? [y/N] '
  read -r answer
  case "$answer" in y|Y|yes) ;; *) echo "aborted"; exit 0 ;; esac
fi

# shellcheck disable=SC2086
[ "$DO_CONTAINERS" -eq 1 ] && docker container prune -f $filter
# shellcheck disable=SC2086
[ "$DO_IMAGES" -eq 1 ] && { docker image prune -af $filter; docker builder prune -af ${KEEP:+--filter unused-for=$KEEP}; }
[ "$DO_VOLUMES" -eq 1 ] && docker volume prune -af

if [ -n "$WORK" ] && [ -d "$WORK" ]; then
  for d in "$WORK"/*; do
    [ -e "$d" ] || continue
    case "$(basename "$d")" in
      _tool|_actions) ;;
      *) rm -rf -- "$d" ;;
    esac
  done
  echo "cleared $WORK (kept _tool, _actions)"
fi

echo
echo "── After ─────────────────────────────────────────────────────────────"
docker system df
