#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-}"
TTL="${2:-1800}"

if [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <name> [ttl_seconds]"
  echo "Example: $0 myapp 600"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVS_DIR="$SCRIPT_DIR/envs"
NGINX_CONF_DIR="$SCRIPT_DIR/nginx/conf.d"
LOGS_DIR="$SCRIPT_DIR/logs"

mkdir -p "$ENVS_DIR" "$NGINX_CONF_DIR" "$LOGS_DIR"

ENV_ID="env-$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 8)"
NETWORK_NAME="net-$ENV_ID"
CONTAINER_NAME="app-$ENV_ID"
CREATED_AT=$(date -u +%s)

# Pick a random available port between 4000 and 4999
while true; do
  PORT=$(shuf -i 4000-4999 -n 1)
  if ! docker ps --format '{{.Ports}}' | grep -q ":$PORT->"; then
    break
  fi
done

echo "Creating sandbox environment..."
echo "Name: $ENV_NAME"
echo "ID: $ENV_ID"
echo "TTL: $TTL seconds"
echo "Port: $PORT"

# 1. Create a private Docker network for this environment
docker network create "$NETWORK_NAME" >/dev/null

# 2. Connect Nginx to this environment network
NGINX_CONTAINER=$(docker ps --filter "name=sandbox-nginx" --format "{{.Names}}" | head -1 || true)

if [[ -n "$NGINX_CONTAINER" ]]; then
  docker network connect "$NETWORK_NAME" "$NGINX_CONTAINER" 2>/dev/null || true
fi

# 3. Start the app container
docker run -d \
  --name "$CONTAINER_NAME" \
  --network "$NETWORK_NAME" \
  --label "sandbox.env=$ENV_ID" \
  --label "sandbox.name=$ENV_NAME" \
  -p "$PORT:3000" \
  -e ENV_ID="$ENV_ID" \
  -e ENV_NAME="$ENV_NAME" \
  sandbox-demo-app >/dev/null

# 4. Start simple log shipping
mkdir -p "$LOGS_DIR/$ENV_ID"
docker logs -f "$CONTAINER_NAME" >> "$LOGS_DIR/$ENV_ID/app.log" 2>&1 &
LOG_PID=$!

# 5. Create Nginx config for this environment
cat > "$NGINX_CONF_DIR/$ENV_ID.conf" << NGINXEOF
server {
    listen 80;
    server_name $ENV_ID.sandbox.local;

    location / {
        proxy_pass http://$CONTAINER_NAME:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
NGINXEOF

# 6. Reload Nginx so it sees the new route
if [[ -n "$NGINX_CONTAINER" ]]; then
  docker exec "$NGINX_CONTAINER" nginx -s reload
fi

# 7. Save environment state
STATE_FILE="$ENVS_DIR/$ENV_ID.json"
TMP_FILE="$STATE_FILE.tmp"

cat > "$TMP_FILE" << JSONEOF
{
  "id": "$ENV_ID",
  "name": "$ENV_NAME",
  "container": "$CONTAINER_NAME",
  "network": "$NETWORK_NAME",
  "port": $PORT,
  "created_at": $CREATED_AT,
  "ttl": $TTL,
  "status": "running",
  "log_pid": $LOG_PID
}
JSONEOF

mv "$TMP_FILE" "$STATE_FILE"

echo ""
echo "Environment created successfully!"
echo "ID: $ENV_ID"
echo "Name: $ENV_NAME"
echo "Direct URL: http://localhost:$PORT"
echo "Nginx Hostname: http://$ENV_ID.sandbox.local"
echo "State file: $STATE_FILE"
