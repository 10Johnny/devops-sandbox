#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVS_DIR="$SCRIPT_DIR/envs"
LOG_FILE="$SCRIPT_DIR/logs/cleanup.log"
DESTROY_SCRIPT="$SCRIPT_DIR/platform/destroy_env.sh"

mkdir -p "$SCRIPT_DIR/logs"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

log "Cleanup daemon started. PID=$$"

while true; do
  NOW=$(date -u +%s)
  FOUND=0

  for STATE_FILE in "$ENVS_DIR"/*.json; do
    [[ -f "$STATE_FILE" ]] || continue

    FOUND=1
    ENV_ID=$(basename "$STATE_FILE" .json)

    CREATED_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['created_at'])" 2>/dev/null || echo 0)
    TTL=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['ttl'])" 2>/dev/null || echo 0)
    STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('status','unknown'))" 2>/dev/null || echo "unknown")

    EXPIRES_AT=$((CREATED_AT + TTL))
    REMAINING=$((EXPIRES_AT - NOW))

    if (( NOW >= EXPIRES_AT )); then
      log "EXPIRED | $ENV_ID | status=$STATUS | destroying now"

      if bash "$DESTROY_SCRIPT" "$ENV_ID" >> "$LOG_FILE" 2>&1; then
        log "DESTROYED | $ENV_ID | success"
      else
        log "FAILED | $ENV_ID | destroy failed"
      fi
    else
      log "ACTIVE | $ENV_ID | status=$STATUS | ${REMAINING}s remaining"
    fi
  done

  if (( FOUND == 0 )); then
    log "IDLE | no active environments"
  fi

  sleep 60
done
