#!/bin/bash
# collector.sh — simple syslog tail sender
ORCHESTRATOR_HOST="ORCHESTRATOR_HOST"
ORCH="https://$ORCHESTRATOR_HOST:8443/api/ingest"
LOGFILE="/var/log/syslog"
TAIL_LINES=50

if ! command -v jq >/dev/null 2>&1; then
  echo "Please install jq (apt install -y jq)"
  exit 1
fi

tail -n $TAIL_LINES -F "$LOGFILE" | while IFS= read -r line; do
  host=$(hostname)
  time=$(date -Iseconds)
  payload=$(jq -n --arg h "$host" --arg t "$time" --arg m "$line" '{host:$h, time:$t, message:$m}')
  curl -k -s -X POST "$ORCH" -H "Content-Type: application/json" -d "$payload" || echo "send failed"
done
