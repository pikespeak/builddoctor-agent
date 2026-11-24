#!/bin/bash
# The outbound rules of the Sprite. Run on the Mac: ops/network.sh tight | deploy | open | show
#   tight   only what the running app needs      deploy  also the package hosts
#   open    no rules (the way back)
set -e -o pipefail
send() { sprite api -s builddoctor /policy/network -- -s -X POST -H 'Content-Type: application/json' -d "$1" -w '\n%{http_code}\n' 2>/dev/null | tail -1; }
allow() { printf '{"rules":['; first=1; for d in "$@"; do [ $first = 1 ] || printf ','; first=0; printf '{"action":"allow","domain":"%s"}' "$d"; done; printf ']}'; }
run=(api.github.com api.sprites.dev fly.storage.tigris.dev '*.fly.storage.tigris.dev')
build=(hex.pm repo.hex.pm builds.hex.pm github.com codeload.github.com objects.githubusercontent.com release-assets.githubusercontent.com registry.npmjs.org)
case "$1" in
  tight) send "$(allow "${run[@]}")" ;;
  deploy) send "$(allow "${run[@]}" "${build[@]}")" ;;
  open) send '{"rules":[]}' ;;
  show) sprite api -s builddoctor /policy/network -- -s 2>/dev/null | tail -5 ;;
  *) echo "Usage: ops/network.sh tight | deploy | open | show"; exit 2 ;;
esac
