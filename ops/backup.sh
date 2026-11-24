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
  ls -1t "$DIR"/builddoctor_dev-*.dump | tail -n +8 | xargs -r rm -f # the Sprite keeps 7, Tigris keeps all
  date -u +%s >"$DIR/last"
  sync
  echo "$(date -u +%FT%TZ) stored db/$name, $(stat -c %s "$file") bytes, read back and restored"
}

case "${1:-once}" in
once) once ;;
serve)
  while true; do
    last=$(cat "$DIR/last" 2>/dev/null || echo 0)
    # A subshell of its own, so that set -e works inside and a failure never ends the service.
    if [ $(($(date -u +%s) - last)) -gt 72000 ]; then "$0" once || { echo "backup failed, next try in 10 minutes"; sleep 540; }; fi
    sleep 60
  done ;;
esac
