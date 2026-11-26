#!/bin/bash
# Runs in the Sprite as /home/sprite/prod.sh, after ops/deploy.sh uploaded app.tgz (and doctor.new).
# Every gate stops the script; the running services are replaced only after tests, format, backup,
# build and migration passed (Codex peer review, 2026-11-26: no pipefail, migration errors swallowed).
set -euo pipefail
fail() { echo "NOT DEPLOYED: $*"; exit 1; }
show() { tail -"${2:-20}" "$1" || true; }

# Tests run in the copy ~/app-test. tt.sh filters its output, so its exit code says little: the gate is
# the result line, and any compile failure or missed coverage threshold in the log stops the deployment.
# The format is checked on the Mac by ops/deploy.sh, before tt.sh formats its copy.
bash /home/sprite/tt.sh > /home/sprite/test.log 2>&1 || true
grep -E "passed|failed|Failed|Total|^ +[0-9]+\)" /home/sprite/test.log || true
grep -qE "^Result: [0-9]+ passed$" /home/sprite/test.log || fail "tests not green"
! grep -qE "Compilation failed|threshold not met" /home/sprite/test.log || fail "compile warnings or coverage below the threshold"

export PGPASSWORD=postgres
s=$(psql -h 127.0.0.1 -U postgres builddoctor_dev -Atc "select count(*) from audits where state in ('measuring','examining')") || fail "database not readable"
[ "$s" = 0 ] || { echo "NOT DEPLOYED: busy, $s examinations running; try again in a minute"; exit 3; }
/home/sprite/backup.sh once || fail "backup"

umask 077; [ -f /home/sprite/secret_key_base ] || head -c 64 /dev/urandom | base64 -w0 > /home/sprite/secret_key_base
for f in db.url secret_key_base agent.secret requester.key; do [ -s "/home/sprite/$f" ] || fail "/home/sprite/$f is missing or empty"; done
cd /home/sprite/app; rm -rf lib test config priv/repo; tar xzf /home/sprite/app.tgz; umask 022
export MIX_ENV=prod DATABASE_URL="$(cat /home/sprite/db.url)" SECRET_KEY_BASE="$(cat /home/sprite/secret_key_base)" PHX_HOST=builddoctor.app AGENT_TOKEN="$(cat /home/sprite/agent.secret)" REQUESTER_KEY="$(cat /home/sprite/requester.key)"
mix deps.get --only prod > /home/sprite/deps.log 2>&1 || { show /home/sprite/deps.log; fail "deps.get"; }
mix deps.compile >> /home/sprite/deps.log 2>&1 || { show /home/sprite/deps.log; fail "deps.compile"; }
mix compile > /home/sprite/compile.log 2>&1 || { show /home/sprite/compile.log; fail "compile"; }
show /home/sprite/compile.log 2
mix assets.deploy > /home/sprite/assets.log 2>&1 || { show /home/sprite/assets.log; fail "assets"; }
show /home/sprite/assets.log 2
mix ecto.migrate > /home/sprite/migrate.log 2>&1 || { show /home/sprite/migrate.log; fail "migration"; }
grep -E "Migrated|already" /home/sprite/migrate.log || true

cat > /home/sprite/serve-prod.sh <<'Y'
#!/bin/bash
cd /home/sprite/app
export MIX_ENV=prod DATABASE_URL="$(cat /home/sprite/db.url)" PHX_HOST=builddoctor.app PHX_SERVER=true IMPRINT_FILE=/home/sprite/imprint.json POSTHOG_HOST=https://r.builddoctor.app POSTHOG_KEY="$(cat /home/sprite/posthog.key 2>/dev/null)" PUBLIC_MODE="$(cat /home/sprite/public_mode 2>/dev/null || echo full)"
export SECRET_KEY_BASE="$(cat /home/sprite/secret_key_base)" REQUESTER_KEY="$(cat /home/sprite/requester.key)" AGENT_TOKEN="$(cat /home/sprite/agent.secret)" EDGE_SECRET="$(cat /home/sprite/edge.secret 2>/dev/null)" OTHER_HOSTS="$(cat /home/sprite/other_hosts 2>/dev/null)"
export RESEND_GATEWAY="$(cat /home/sprite/resend.gateway 2>/dev/null)" NOTICE_TO="$(cat /home/sprite/notice.to 2>/dev/null)" NOTICE_FROM="$(cat /home/sprite/notice.from 2>/dev/null)"
exec mix phx.server --no-compile
Y
chmod 700 /home/sprite/serve-prod.sh

# The new agent replaces the old one only now, after every gate; the old one stays as doctor.prev.
if [ -f /home/sprite/doctor.new ]; then
  chmod 755 /home/sprite/doctor.new
  cp -p /home/sprite/doctor /home/sprite/doctor.prev
  mv /home/sprite/doctor.new /home/sprite/doctor
fi
echo "agent $(sha256sum /home/sprite/doctor | cut -c1-16)"

sprite-env services delete agent >/dev/null 2>&1 || true; sprite-env services delete app >/dev/null 2>&1 || true; sleep 2
sprite-env services create app --cmd /home/sprite/serve-prod.sh --needs postgres --http-port 4000 --no-stream >/dev/null
c=000; for i in $(seq 1 60); do c=$(curl -s -o /home/sprite/p.html -w '%{http_code}' localhost:4000/ || true); [ "$c" = 200 ] && break; sleep 1; done
echo "page $c"; [ "$c" = 200 ] || fail "page answers $c after the restart; the agent was not started"
grep -o "[0-9]* of 100 pages printed" /home/sprite/p.html || true
sprite-env services create agent --cmd /home/sprite/crew.sh --needs app --no-stream >/dev/null; sleep 4
pgrep -x doctor >/dev/null || fail "agent not running"
echo "agent running"
for p in /dev/dashboard /api/json/audits/open /phoenix/live_reload/frame /assets/css/app.css /requester; do echo "$p $(curl -s -o /dev/null -w '%{http_code}' localhost:4000$p || true)"; done
curl -sI -H 'x-forwarded-proto: https' -H 'host: builddoctor-b6tq7.sprites.app' localhost:4000/ | grep -iE "HTTP|strict|content-sec|x-frame|set-cookie" | cut -c1-120 || true
tail -3 /.sprite/logs/services/app.log | cut -c1-200 || true
sync
echo DEPLOYED
