#!/bin/bash
# Deploys the committed state to the Sprite. Run on the Mac: bash ops/deploy.sh
# Stops at the first failure; ops/deploy-in-sprite.sh holds the gates inside the Sprite.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -z "$(git status --porcelain)" ] || { echo "There are changes or new files without a commit."; exit 1; }
work=$(mktemp -d)
done_() {
  c=$?; rm -rf "$work"
  sprite exec -s builddoctor --no-stdin -- sprite-env curl -s -X DELETE /v1/tasks/deploy >/dev/null || true
  t=$(ops/network.sh tight || true); echo "network tight: $t"
  [ "$t" = 204 ] || { echo "WARNING: the network rules are still wide; run ops/network.sh tight"; c=1; }
  exit $c
}
trap done_ EXIT
bash ops/audit.sh
(cd app && mix format --check-formatted) || { echo "not formatted, not deployed"; exit 1; }
(cd agent && go vet ./... && go test ./... -count=1 >/dev/null && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$work/doctor.new" ./cmd/doctor)
(cd app && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$work/app.tgz" lib test config priv/repo priv/resource_snapshots assets mix.exs mix.lock .formatter.exs priv/static/robots.txt priv/static/fonts priv/static/images)
app=$(shasum -a 256 "$work/app.tgz" | cut -c1-64); agent=$(shasum -a 256 "$work/doctor.new" | cut -c1-64)
echo "local app ${app:0:16}, agent ${agent:0:16}"
bash ops/wake.sh
net=$(ops/network.sh deploy); echo "network deploy: $net"; [ "$net" = 204 ] || { echo "network rules not set"; exit 1; }
sprite exec -s builddoctor --no-stdin --file "$work/app.tgz:/home/sprite/app.tgz" --file "$work/doctor.new:/home/sprite/doctor.new" --file ops/deploy-in-sprite.sh:/home/sprite/prod.sh -- bash -c '
  set -uo pipefail
  sprite-env curl -s -f -X PUT /v1/tasks/deploy -d "{\"expire\":\"20m\"}" >/dev/null || { echo "no deploy task, not deployed"; exit 1; }
  [ "$(sha256sum /home/sprite/app.tgz | cut -c1-64)" = "'"$app"'" ] && [ "$(sha256sum /home/sprite/doctor.new | cut -c1-64)" = "'"$agent"'" ] || { echo "upload differs, not deployed"; exit 1; }
  echo "uploads match"
  bash /home/sprite/prod.sh > /home/sprite/deploy.log 2>&1; c=$?; tail -40 /home/sprite/deploy.log; exit $c'
