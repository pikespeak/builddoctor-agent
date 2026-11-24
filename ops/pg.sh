#!/bin/bash
# Starts Postgres. After a hard stop of the Sprite its lock file can name a process that is now
# something else, and Postgres refuses to start. The lock is removed only if that process is no
# Postgres and no Postgres of this data folder runs; otherwise nothing is touched.
D=/home/sprite/pgdata
for lock in "$D/postmaster.pid" /tmp/.s.PGSQL.5432.lock; do
  [ -f "$lock" ] || continue
  pid=$(head -1 "$lock")
  if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" != postgres ] && ! pgrep -x postgres >/dev/null; then
    echo "removing $lock of process $pid, which is $(cat "/proc/$pid/comm" 2>/dev/null || echo gone)"
    rm -f "$lock"
  fi
done
exec /usr/lib/postgresql/18/bin/postgres -D "$D" -k /tmp -c listen_addresses=127.0.0.1
