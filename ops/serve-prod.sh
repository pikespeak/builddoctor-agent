#!/bin/bash
cd /home/sprite/app
export MIX_ENV=prod DATABASE_URL="$(cat /home/sprite/db.url)" PHX_HOST=builddoctor.app PHX_SERVER=true IMPRINT_FILE=/home/sprite/imprint.json POSTHOG_HOST=https://r.builddoctor.app POSTHOG_KEY="$(cat /home/sprite/posthog.key 2>/dev/null)" PUBLIC_MODE="$(cat /home/sprite/public_mode 2>/dev/null || echo full)"
export SECRET_KEY_BASE="$(cat /home/sprite/secret_key_base)" REQUESTER_KEY="$(cat /home/sprite/requester.key)" AGENT_TOKEN="$(cat /home/sprite/agent.secret)" EDGE_SECRET="$(cat /home/sprite/edge.secret 2>/dev/null)" OTHER_HOSTS="$(cat /home/sprite/other_hosts 2>/dev/null)"
exec mix phx.server --no-compile
