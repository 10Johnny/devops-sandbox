#!/usr/bin/env bash
set -euo pipefail

ENV_ID=""
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_ID="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$ENV_ID" || -z "$MODE" ]]; then
  echo "Usage: $0 --env <env-id> --mode <crash|pause|network|recover|stress>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/envs/$ENV_ID.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: Unknown environment: $ENV_ID"
  exit 1
fi

CONTAINER_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['container'])")
NETWORK_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['network'])")

update_status() {
  NEW_STATUS="$1"

  python3 - << PYEOF
import json, os

path = "$STATE_FILE"

with open(path) as f:
    data = json.load(f)

data["status"] = "$NEW_STATUS"

tmp = path + ".tmp"

with open(tmp, "w") as f:
    json.dump(data, f, indent=2)

os.replace(tmp, path)
PYEOF

  echo "[OK] Status updated to: $NEW_STATUS"
}

echo "Simulating outage..."
echo "Environment: $ENV_ID"
echo "Container: $CONTAINER_NAME"
echo "Mode: $MODE"

case "$MODE" in
  crash)
    docker kill "$CONTAINER_NAME"
    update_status "crashed"
    echo "Container crashed."
    ;;

  pause)
    docker pause "$CONTAINER_NAME"
    update_status "paused"
    echo "Container paused."
    ;;

  network)
    docker network disconnect "$NETWORK_NAME" "$CONTAINER_NAME"
    update_status "network-isolated"
    echo "Container disconnected from network."
    ;;

  recover)
    CURRENT_STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('status','unknown'))")

    if [[ "$CURRENT_STATUS" == "paused" ]]; then
      docker unpause "$CONTAINER_NAME"
    elif [[ "$CURRENT_STATUS" == "network-isolated" ]]; then
      docker network connect "$NETWORK_NAME" "$CONTAINER_NAME"
    elif [[ "$CURRENT_STATUS" == "crashed" || "$CURRENT_STATUS" == "degraded" ]]; then
      docker start "$CONTAINER_NAME"
    else
      docker start "$CONTAINER_NAME" 2>/dev/null || true
    fi

    update_status "running"
    echo "Environment recovered."
    ;;

  stress)
    docker exec -d "$CONTAINER_NAME" stress-ng --cpu 2 --timeout 60s
    update_status "stressed"
    echo "CPU stress started for 60 seconds."
    ;;

  *)
    echo "Invalid mode: $MODE"
    echo "Valid modes: crash, pause, network, recover, stress"
    exit 1
    ;;
esac
