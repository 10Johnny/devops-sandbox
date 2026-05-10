#!/usr/bin/env bash
set -euo pipefail

ENV_ID="${1:-}"

if [[ -z "$ENV_ID" ]]; then
  echo "Usage: $0 <env-id>"
  echo "Example: $0 env-a841954c"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/envs/$ENV_ID.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: No environment found with ID: $ENV_ID"
  echo "Expected state file: $STATE_FILE"
  exit 1
fi

echo "Destroying sandbox environment..."
echo "ID: $ENV_ID"

CONTAINER_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['container'])")
NETWORK_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['network'])")
LOG_PID=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('log_pid', ''))")

NGINX_CONTAINER=$(docker ps --filter "name=sandbox-nginx" --format "{{.Names}}" | head -1 || true)

# Stop log shipping process
if [[ -n "$LOG_PID" ]] && kill -0 "$LOG_PID" 2>/dev/null; then
  kill "$LOG_PID" 2>/dev/null || true
  echo "[OK] Log shipping process stopped"
else
  echo "[OK] Log shipping process already stopped or not found"
fi

# Stop and remove sandbox container
if docker ps -a --format "{{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
  echo "[OK] Container removed: $CONTAINER_NAME"
else
  echo "[OK] Container already removed or not found"
fi

# Remove Nginx config
NGINX_CONF="$SCRIPT_DIR/nginx/conf.d/$ENV_ID.conf"

if [[ -f "$NGINX_CONF" ]]; then
  rm -f "$NGINX_CONF"
  echo "[OK] Nginx config removed: $NGINX_CONF"
else
  echo "[OK] Nginx config already removed or not found"
fi

# Reload Nginx
if [[ -n "$NGINX_CONTAINER" ]]; then
  docker exec "$NGINX_CONTAINER" nginx -s reload >/dev/null 2>&1 || true
  echo "[OK] Nginx reloaded"
fi

# Disconnect Nginx from the sandbox network
if [[ -n "$NGINX_CONTAINER" ]]; then
  docker network disconnect "$NETWORK_NAME" "$NGINX_CONTAINER" >/dev/null 2>&1 || true
fi

# Remove Docker network
docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
echo "[OK] Docker network removed: $NETWORK_NAME"

# Archive logs
LOG_DIR="$SCRIPT_DIR/logs/$ENV_ID"
ARCHIVE_DIR="$SCRIPT_DIR/logs/archived/$ENV_ID"

if [[ -d "$LOG_DIR" ]]; then
  mkdir -p "$ARCHIVE_DIR"
  cp -r "$LOG_DIR/." "$ARCHIVE_DIR/" 2>/dev/null || true
  rm -rf "$LOG_DIR"
  echo "[OK] Logs archived to: $ARCHIVE_DIR"
fi

# Remove state file
rm -f "$STATE_FILE"
echo "[OK] State file removed"

echo ""
echo "Environment destroyed successfully!"
echo "ID: $ENV_ID"
