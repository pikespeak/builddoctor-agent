#!/bin/bash
# Agent as a service; the Sprite is held awake only while there is work.
trap 'kill $a 2>/dev/null' EXIT
/home/sprite/agent.sh & a=$!
while kill -0 $a 2>/dev/null; do
  n=$(PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres builddoctor_dev -Atc "select count(*) from audits where state in ('examining','measuring') or (state='awaiting_approval' and not council_done)" 2>/dev/null || echo 0)
  if [ "$n" != 0 ]; then sprite-env curl -s -X PUT /v1/tasks/doctor -d '{"expire":"3m"}' >/dev/null 2>&1; held=1
  elif [ "${held:-0}" = 1 ]; then sprite-env curl -s -X DELETE /v1/tasks/doctor >/dev/null 2>&1; held=0; fi
  sleep 15
done
