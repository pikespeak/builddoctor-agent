#!/bin/bash
# Runs in the Sprite. "once": dump, upload to Tigris, download, restore and compare.
# "serve": the same once per 20 hours while the Sprite is awake.
set -eu
umask 077
export PGPASSWORD=postgres
P="-h 127.0.0.1 -U postgres"
DIR=/home/sprite/backups
mkdir -p "$DIR"

s3() { # method, key, extra curl options; the secret goes through stdin, never through arguments
  local method=$1 key=$2; shift 2
  (
    . /home/sprite/tigris.env
    [[ $BUCKET_NAME =~ ^[a-z0-9.-]+$ && $AWS_ENDPOINT_URL_S3 =~ ^https:// ]] || { echo "tigris.env is not valid" >&2; exit 1; }
    printf 'user = "%s:%s"\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" |
      curl -sS --fail -K - --max-time 120 --aws-sigv4 "aws:amz:auto:s3" -X "$method" "$@" "$AWS_ENDPOINT_URL_S3/$BUCKET_NAME/$key"
  )
}

once() {
  local name file back test=builddoctor_restore_test
  name=builddoctor_dev-$(date -u +%Y%m%dT%H%M%SZ).dump
  file=$DIR/$name back=$DIR/check.dump
  pg_dump $P -Fc builddoctor_dev -f "$file"
  for k in agent.secret requester.key; do
    if pg_restore -f - "$file" | grep -qF -f "/home/sprite/$k"; then echo "a secret is in the export, not uploaded"; rm -f "$file"; return 1; fi
  done
  sum=$(sha256sum <"$file" | cut -d' ' -f1)
  s3 PUT "db/$name" -T "$file" -H "x-amz-content-sha256: $sum" >/dev/null
  s3 GET "db/$name" -o "$back"
  cmp "$file" "$back"
  psql $P -qc "drop database if exists $test" -c "create database $test" 2>/dev/null
  pg_restore $P -d $test --exit-on-error "$back"
  psql $P -qc "drop database $test"
  rm -f "$back"
  ls -1t "$DIR"/builddoctor_dev-*.dump | tail -n +8 | xargs -r rm -f # the Sprite keeps 7
  date -u +%s >"$DIR/last"
  sync
  echo "$(date -u +%FT%TZ) stored db/$name, $(stat -c %s "$file") bytes, read back and restored"
}

# Whether the moment in a name is more than 30 days before another one (seconds).
older() {
  local at
  [[ $1 =~ builddoctor_dev-([0-9]{8})T([0-9]{2})([0-9]{2})([0-9]{2})Z\.dump$ ]] || return 1
  at=$(date -u -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s) || return 1
  [ $(( $2 - at )) -gt 2592000 ]
}

# Removes backups older than 30 days; the three newest of both places always stay.
expire() {
  local now list n
  now=$(date -u +%s)
  list=$(ls -1 "$DIR" | grep -E '^builddoctor_dev-.*\.dump$' | sort -r | tail -n +4 || true)
  for n in $list; do if older "$n" "$now"; then rm -f "$DIR/$n"; echo "expired $n"; fi; done
  list=$(s3 GET "?list-type=2&prefix=db/") || { echo "the list of backups could not be read"; return 1; }
  case "$list" in *"<IsTruncated>true"*) echo "the list of backups is not complete"; return 1 ;; esac
  list=$(echo "$list" | grep -oE '<Key>[^<]+' | sed 's/<Key>//' | sort -r | tail -n +4 || true)
  for n in $list; do if older "$n" "$now"; then s3 DELETE "$n" >/dev/null || return 1; echo "expired $n"; fi; done
}

case "${1:-once}" in
expire) expire ;;
once) once ;;
serve)
  while true; do
    last=$(cat "$DIR/last" 2>/dev/null || echo 0)
    # A subshell of its own, so that set -e works inside and a failure never ends the service.
    if [ $(($(date -u +%s) - last)) -gt 72000 ]; then "$0" expire || echo "expiry failed"; "$0" once || { echo "backup failed, next try in 10 minutes"; sleep 540; }; fi
    sleep 60
  done ;;
esac
