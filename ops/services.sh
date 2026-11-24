#!/bin/bash
# Builds all services of the Sprite anew, in the order of their needs. Run in the Sprite.
set -euo pipefail
cd /home/sprite
for s in agent backup app postgres; do sprite-env services delete $s >/dev/null 2>&1 || true; done
sleep 3
mk() { sprite-env services create "$@" --no-stream >/dev/null; }
mk postgres --cmd /home/sprite/pg.sh
up=no; for i in $(seq 1 40); do /usr/lib/postgresql/18/bin/pg_isready -h 127.0.0.1 -q && { up=yes; break; }; sleep 1; done
echo "postgres ready: $up"; [ $up = yes ]
mk app --cmd /home/sprite/serve-prod.sh --needs postgres --http-port 4000
for i in $(seq 1 60); do c=$(curl -s -o /dev/null -w '%{http_code}' localhost:4000/ || true); [ "$c" = 200 ] && break; sleep 1; done
echo "page $c"
mk backup --cmd /home/sprite/backup.sh --args serve --needs postgres
mk agent --cmd /home/sprite/crew.sh --needs app
sleep 4; pgrep -x doctor >/dev/null && echo "agent running"
