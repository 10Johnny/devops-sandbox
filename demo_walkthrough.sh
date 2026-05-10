#!/usr/bin/env bash
set -u

cd ~/devops-sandbox

ENV_NAME="${1:-video-demo}"
TTL="${2:-600}"
ENV_ID=""
PORT=""

echo "=============================="
echo "1. PROJECT STRUCTURE"
echo "=============================="
find . -maxdepth 2 -type f | sort | grep -v "logs/" | grep -v "envs/"

echo ""
echo "=============================="
echo "2. START PLATFORM"
echo "=============================="
make up

echo ""
echo "=============================="
echo "3. CREATE SANDBOX ENVIRONMENT"
echo "=============================="
CREATE_OUTPUT=$(printf "%s\n%s\n" "$ENV_NAME" "$TTL" | make create)
echo "$CREATE_OUTPUT"

ENV_ID=$(echo "$CREATE_OUTPUT" | awk '/^ID: env-/{print $2; exit}')
PORT=$(echo "$CREATE_OUTPUT" | awk '/^Port: /{print $2; exit}')

if [ -z "$ENV_ID" ] || [ -z "$PORT" ]; then
  echo "ERROR: Could not detect ENV_ID or PORT"
  exit 1
fi

echo ""
echo "Detected ENV_ID=$ENV_ID"
echo "Detected PORT=$PORT"

echo ""
echo "Waiting for app container to become ready..."
READY=0
for i in {1..20}; do
  if curl -fsS "http://localhost:$PORT/health" >/tmp/sandbox_health.out 2>/dev/null; then
    READY=1
    echo "App is ready."
    break
  fi
  echo "Still starting... retry $i"
  sleep 2
done

if [ "$READY" -ne 1 ]; then
  echo "ERROR: App did not become ready"
  make destroy ENV="$ENV_ID" || true
  exit 1
fi

echo ""
echo "=============================="
echo "4. TEST DIRECT HEALTH ENDPOINT"
echo "=============================="
echo "curl http://localhost:$PORT/health"
cat /tmp/sandbox_health.out
echo ""

echo ""
echo "=============================="
echo "5. TEST NGINX DYNAMIC ROUTING"
echo "=============================="
echo "curl -H \"Host: $ENV_ID.sandbox.local\" http://localhost/"
curl -H "Host: $ENV_ID.sandbox.local" http://localhost/
echo ""

echo ""
echo "=============================="
echo "6. SIMULATE CRASH OUTAGE"
echo "=============================="
make simulate ENV="$ENV_ID" MODE=crash

echo ""
echo "Waiting for health monitor to mark environment as degraded..."
for i in {1..7}; do
  sleep 15
  make health

  STATUS=$(python3 -c "import json; print(json.load(open('envs/$ENV_ID.json')).get('status'))" 2>/dev/null || echo "missing")

  if [ "$STATUS" = "degraded" ]; then
    echo "Environment is degraded."
    break
  fi
done

echo ""
echo "=============================="
echo "7. RECOVER ENVIRONMENT"
echo "=============================="
make simulate ENV="$ENV_ID" MODE=recover

echo ""
echo "Testing health after recovery..."
sleep 5
curl "http://localhost:$PORT/health"
echo ""

echo ""
echo "=============================="
echo "8. DESTROY ENVIRONMENT"
echo "=============================="
make destroy ENV="$ENV_ID"

echo ""
echo "=============================="
echo "9. README ARCHITECTURE"
echo "=============================="
tail -40 README.md

echo ""
echo "DEMO COMPLETE"
