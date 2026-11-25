#!/bin/bash
# What visitors see. Run on the Mac: ops/mode.sh full | reduced | show
#   reduced: only our own measured project; nobody but the requester starts an examination
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  full|reduced) sprite exec -s builddoctor --no-stdin --file set-mode.sh:/home/sprite/set-mode.sh -- bash /home/sprite/set-mode.sh "$1" ;;
  show) sprite exec -s builddoctor --no-stdin -- bash -c 'cat /home/sprite/public_mode 2>/dev/null || echo full' ;;
  *) echo "Usage: ops/mode.sh full | reduced | show"; exit 2 ;;
esac
