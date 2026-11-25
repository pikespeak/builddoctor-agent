#!/bin/bash
# Runs in the Sprite: sets the mode, starts the app anew (the agent depends on it) and checks the result.
set -euo pipefail
mode=$1; [ "$mode" = full ] || [ "$mode" = reduced ]
n=$(PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres builddoctor_dev -Atc "select count(*) from audits where state in ('examining','measuring')")
[ "$n" = 0 ] || { echo "busy, nothing changed"; exit 1; }
echo "$mode" > /home/sprite/public_mode
for s in agent app; do sprite-env services delete $s >/dev/null 2>&1 || true; done; sleep 2
sprite-env services create app --cmd /home/sprite/serve-prod.sh --needs postgres --http-port 4000 --no-stream >/dev/null
for i in $(seq 1 60); do c=$(curl -s -o /tmp/mode.html -w '%{http_code}' localhost:4000/ || true); [ "$c" = 200 ] && break; sleep 1; done
sprite-env services create agent --cmd /home/sprite/crew.sh --needs app --no-stream >/dev/null; sleep 4
[ "$c" = 200 ] && pgrep -x doctor >/dev/null
seen=full; grep -q 'id="reduced"' /tmp/mode.html && seen=reduced
echo "wanted $mode, the page shows $seen"; [ "$seen" = "$mode" ]
