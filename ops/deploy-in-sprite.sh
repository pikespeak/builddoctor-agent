set -e
bash /home/sprite/tt.sh > /home/sprite/test.log 2>&1; grep -E "passed|failed|Failed|Total|^ +[0-9]+\)" /home/sprite/test.log
# Nothing is deployed without a green run.
grep -qE "^Result: [0-9]+ passed$" /home/sprite/test.log || { echo "tests not green, not deployed"; exit 1; }
cd /home/sprite/app-test
mix format --check-formatted || { echo "not formatted, not deployed"; exit 1; }
export PGPASSWORD=postgres; s=$(psql -h 127.0.0.1 -U postgres builddoctor_dev -Atc "select count(*) from audits where state in ('measuring','examining')"); [ "$s" = 0 ] || { echo "busy, not deployed"; exit 0; }
/home/sprite/backup.sh once
umask 077; [ -f /home/sprite/secret_key_base ] || head -c 64 /dev/urandom | base64 -w0 > /home/sprite/secret_key_base
cd /home/sprite/app; rm -rf lib test config priv/repo; tar xzf /home/sprite/app.tgz; umask 022
export MIX_ENV=prod DATABASE_URL="$(cat /home/sprite/db.url)" SECRET_KEY_BASE=$(cat /home/sprite/secret_key_base) PHX_HOST=builddoctor.app AGENT_TOKEN="$(cat /home/sprite/agent.secret)" REQUESTER_KEY="$(cat /home/sprite/requester.key)"
mix deps.get --only prod >/dev/null 2>&1; mix deps.compile >/home/sprite/deps.log 2>&1; mix compile 2>&1 | tail -2; mix assets.deploy 2>&1 | tail -2
mix ecto.migrate 2>&1 | grep -E "Migrated|already|rror" || true
cat > /home/sprite/serve-prod.sh <<'Y'
#!/bin/bash
cd /home/sprite/app
export MIX_ENV=prod DATABASE_URL="$(cat /home/sprite/db.url)" PHX_HOST=builddoctor.app PHX_SERVER=true IMPRINT_FILE=/home/sprite/imprint.json POSTHOG_HOST=https://r.builddoctor.app POSTHOG_KEY="$(cat /home/sprite/posthog.key 2>/dev/null)" PUBLIC_MODE="$(cat /home/sprite/public_mode 2>/dev/null || echo full)"
export SECRET_KEY_BASE="$(cat /home/sprite/secret_key_base)" REQUESTER_KEY="$(cat /home/sprite/requester.key)" AGENT_TOKEN="$(cat /home/sprite/agent.secret)" EDGE_SECRET="$(cat /home/sprite/edge.secret 2>/dev/null)" OTHER_HOSTS="$(cat /home/sprite/other_hosts 2>/dev/null)"
exec mix phx.server --no-compile
Y
chmod 700 /home/sprite/serve-prod.sh
sprite-env services delete agent >/dev/null 2>&1 || true; sprite-env services delete app >/dev/null 2>&1 || true; sleep 2
sprite-env services create app --cmd /home/sprite/serve-prod.sh --needs postgres --http-port 4000 --no-stream >/dev/null
for i in $(seq 1 60); do c=$(curl -s -o /home/sprite/p.html -w '%{http_code}' localhost:4000/ || true); [ "$c" = 200 ] && break; sleep 1; done; echo page $c; grep -o "[0-9]* of 100 pages printed" /home/sprite/p.html
sprite-env services create agent --cmd /home/sprite/crew.sh --needs app --no-stream >/dev/null; sleep 4; pgrep -x doctor >/dev/null && echo agent running
for p in /dev/dashboard /api/json/audits/open /phoenix/live_reload/frame /assets/css/app.css /requester; do echo "$p $(curl -s -o /dev/null -w '%{http_code}' localhost:4000$p)"; done
curl -sI -H 'x-forwarded-proto: https' -H 'host: builddoctor-b6tq7.sprites.app' localhost:4000/ | grep -iE "HTTP|strict|content-sec|x-frame|set-cookie" | cut -c1-120
tail -3 /.sprite/logs/services/app.log | cut -c1-200; sync
