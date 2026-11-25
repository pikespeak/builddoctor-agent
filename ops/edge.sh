#!/bin/bash
# Sets up the door in front of the Sprite. Run on the Mac: ops/edge.sh secret | machine
#   secret   a new secret for the Sprite and the machine (restart the app afterwards)
#   machine  the nginx configuration of ops/edge.conf; the machine then stays awake
set -e -o pipefail
cd "$(dirname "$0")/.."
app=buoyant-moonbeam-847
case "$1" in
  secret)
    umask 077; f=$(mktemp); trap 'rm -f "$f"' EXIT
    openssl rand -hex 32 | tr -d '\n' > "$f"
    sprite exec -s builddoctor --no-stdin --file "$f:/home/sprite/edge.secret" -- chmod 600 /home/sprite/edge.secret
    printf 'EDGE_SECRET=%s\n' "$(cat "$f")" | fly secrets import --stage -a "$app" ;;
  machine)
    id=$(fly machines list -a "$app" --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')
    fly machine update "$id" -a "$app" --yes --autostop=off --restart always \
      --file-local /etc/nginx/templates/default.conf.template=ops/edge.conf ;;
  *) echo "Usage: ops/edge.sh secret | machine"; exit 2 ;;
esac
