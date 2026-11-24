#!/bin/bash
# Asks for the Tigris values (hidden input) and stores them in the macOS keychain and in the Sprite.
# Nothing is printed and nothing is written to this repository.
set -eu
file=${1:-/home/sprite/tigris.env}
out=""
for k in BUCKET_NAME AWS_ENDPOINT_URL_S3 AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  IFS= read -rsp "$k (paste, then Enter): " v; echo
  [[ $v =~ ^[A-Za-z0-9_:/.+=-]+$ ]] || { echo "$k is empty or has unexpected characters. Nothing was stored."; exit 1; }
  out+="$k=$v"$'\n'
done
printf '%s' "$out" | sprite exec -s builddoctor --stdin -- bash -c "umask 077; cat > $file; sync" >/dev/null 2>&1
n=$(sprite exec -s builddoctor --no-stdin -- bash -c "grep -c = $file" 2>/dev/null | tr -dc 0-9)
[ "$n" = 4 ] || { echo "The Sprite did not get all values ($n of 4)."; exit 1; }
[ "${2:-}" = no-keychain ] || printf 'add-generic-password -U -a builddoctor -s builddoctor-tigris -w "%s"\n' "$(printf '%s' "$out" | base64 | tr -d '\n')" | security -i
echo "Done: 4 values stored."
