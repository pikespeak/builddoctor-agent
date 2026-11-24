#!/bin/bash
# Holds the Sprite awake until a date (costs running time), renewed every 20 minutes. Run on the Mac:
#   ops/awake.sh until 2026-12-05   (end of that day, UTC; at most 14 days ahead)
#   ops/awake.sh off | status
set -e
run() { sprite exec -s builddoctor --no-stdin -- bash -c "$1"; }
case "$1" in
  until)
    [[ "$2" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Give a date, such as 2026-12-05."; exit 2; }
    run "set -e; end=\$(date -u -d '$2 23:59:59' +%s); left=\$((end - \$(date +%s)))
      [ \$left -gt 0 ] && [ \$left -le 1209600 ] || { echo 'The date must be within the next 14 days.'; exit 2; }
      printf '#!/bin/bash\nend=%s\nwhile [ \$(date +%%s) -lt \$end ]; do sprite-env curl -s -X PUT /v1/tasks/awake -d \"{\\\\\"expire\\\\\":\\\\\"1h\\\\\"}\" >/dev/null; sleep 1200; done\nsprite-env curl -s -X DELETE /v1/tasks/awake >/dev/null\nexec sleep infinity\n' \$end > /home/sprite/awake.sh
      bash -n /home/sprite/awake.sh; chmod 700 /home/sprite/awake.sh
      sprite-env services delete awake >/dev/null 2>&1 || true
      sprite-env services create awake --cmd /home/sprite/awake.sh --no-stream >/dev/null; sleep 2; sprite-env curl -s /v1/tasks; echo" ;;
  off) run "sprite-env services delete awake >/dev/null 2>&1 || true; sprite-env curl -s -X DELETE /v1/tasks/awake >/dev/null || true; sprite-env curl -s /v1/tasks; echo" ;;
  status) run "sprite-env services list | grep -o '\"name\":\"awake\"' || echo 'no awake service'; sprite-env curl -s /v1/tasks; echo" ;;
  *) echo "Usage: ops/awake.sh until DATE | off | status"; exit 2 ;;
esac
