#!/bin/bash
# Wakes the Sprite and waits until the page and the agent answer. Run on the Mac: ops/wake.sh
# One request at a time; parallel ones only pile up while it starts.
start=$(date +%s)
for try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  out=$(sprite exec -s builddoctor --no-stdin -- bash -c '
    for i in $(seq 1 30); do c=$(curl -s -o /dev/null -w "%{http_code}" localhost:4000/); [ "$c" = 200 ] && pgrep -x doctor >/dev/null && { echo ready; exit 0; }; sleep 1; done; echo "page $c"; exit 1' 2>&1)
  now=$(( $(date +%s) - start ))
  case "$out" in *ready*) echo "Ready after $now s: https://builddoctor.app"; exit 0 ;; esac
  echo "Try $try, $now s: $(echo "$out" | tail -1 | cut -c1-120)"
  sleep 5
done
echo "Not awake after $now s. Status: $(sprite info -s builddoctor | awk '/^Status/{print $2}'). Contact https://fly.io/dashboard/support"
exit 1
