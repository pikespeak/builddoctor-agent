#!/bin/bash
cd /home/sprite/app
export MIX_ENV=prod DATABASE_URL="$(cat /home/sprite/db.url)" PHX_HOST=builddoctor-b6tq7.sprites.app PHX_SERVER=true IMPRINT_FILE=/home/sprite/imprint.json PUBLIC_MODE="$(cat /home/sprite/public_mode 2>/dev/null || echo full)"
export SECRET_KEY_BASE="$(cat /home/sprite/secret_key_base)" REQUESTER_KEY="$(cat /home/sprite/requester.key)" AGENT_TOKEN="$(cat /home/sprite/agent.secret)"
exec mix phx.server --no-compile
