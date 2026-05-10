SHELL := /bin/bash
.RECIPEPREFIX := >

PROJECT_DIR := $(shell pwd)
NAME ?= demo
TTL ?= 1800
ENV ?=
MODE ?= crash
API_PORT ?= 8000

.PHONY: help build up start-nginx start-daemon start-monitor start-api down create destroy logs health simulate clean status api-logs monitor-logs daemon-logs

help:
> @echo "DevOps Sandbox Platform - Make Commands"
> @echo ""
> @echo "make up                         Start Nginx, cleanup daemon, health monitor, and API"
> @echo "make down                       Stop API, monitor, daemon, Nginx, and destroy active envs"
> @echo "make create                     Create env interactively"
> @echo "make create NAME=myapp TTL=600  Create env with default prompt values"
> @echo "make destroy ENV=env-xxxx       Destroy a specific env"
> @echo "make logs ENV=env-xxxx          Tail app logs for an env"
> @echo "make health                     Show active env health/status"
> @echo "make simulate ENV=env-xxxx MODE=crash|pause|network|recover|stress"
> @echo "make clean                      Wipe state, logs, archives, and generated configs"
> @echo "make status                     Show running containers and API status"

build:
> @echo "[INFO] Checking sandbox demo app image..."
> @if docker image inspect sandbox-demo-app >/dev/null 2>&1; then \
>   echo "[OK] Image already exists: sandbox-demo-app"; \
> else \
>   echo "[INFO] Image not found. Building sandbox-demo-app..."; \
>   docker build -t sandbox-demo-app ./demo-app; \
>   echo "[OK] Image built: sandbox-demo-app"; \
> fi

start-nginx:
> @mkdir -p nginx/conf.d logs envs
> @if docker ps --format '{{.Names}}' | grep -q '^sandbox-nginx$$'; then \
>   echo "[OK] Nginx already running"; \
> else \
>   docker rm -f sandbox-nginx >/dev/null 2>&1 || true; \
>   docker network create sandbox-infra >/dev/null 2>&1 || true; \
>   docker run -d \
>     --name sandbox-nginx \
>     --network sandbox-infra \
>     -p 80:80 \
>     -v "$(PROJECT_DIR)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
>     -v "$(PROJECT_DIR)/nginx/conf.d:/etc/nginx/conf.d:rw" \
>     nginx:alpine >/dev/null; \
>   echo "[OK] Nginx started on port 80"; \
> fi

start-daemon:
> @mkdir -p logs
> @if [ -f logs/daemon.pid ] && ps -p $$(cat logs/daemon.pid) >/dev/null 2>&1; then \
>   echo "[OK] Cleanup daemon already running"; \
> else \
>   nohup bash platform/cleanup_daemon.sh > logs/daemon.log 2>&1 & \
>   echo $$! > logs/daemon.pid; \
>   echo "[OK] Cleanup daemon started"; \
> fi

start-monitor:
> @mkdir -p logs
> @if [ -f logs/monitor.pid ] && ps -p $$(cat logs/monitor.pid) >/dev/null 2>&1; then \
>   echo "[OK] Health monitor already running"; \
> else \
>   nohup python3 -u monitor/health_poller.py > logs/monitor.log 2>&1 & \
>   echo $$! > logs/monitor.pid; \
>   echo "[OK] Health monitor started"; \
> fi

start-api:
> @mkdir -p logs
> @if [ -f logs/api.pid ] && ps -p $$(cat logs/api.pid) >/dev/null 2>&1; then \
>   echo "[OK] API already running on port $(API_PORT)"; \
> else \
>   nohup python3 -m uvicorn api:app \
>     --host 0.0.0.0 \
>     --port $(API_PORT) \
>     --app-dir "$(PROJECT_DIR)/platform" \
>     > logs/api.log 2>&1 & \
>   echo $$! > logs/api.pid; \
>   sleep 2; \
>   if curl -fsS http://localhost:$(API_PORT)/ >/dev/null 2>&1; then \
>     echo "[OK] API started on port $(API_PORT)"; \
>   else \
>     echo "[WARN] API may not have started. Check logs/api.log"; \
>     cat logs/api.log; \
>   fi; \
> fi

up: build start-nginx start-daemon start-monitor start-api
> @echo ""
> @echo "[READY] DevOps Sandbox Platform is up"
> @echo "Nginx: http://localhost"
> @echo "API:   http://localhost:$(API_PORT)"
> @echo "Docs:  http://localhost:$(API_PORT)/docs"

create:
> @read -p "Environment name [$(NAME)]: " input_name; \
> input_name=$${input_name:-$(NAME)}; \
> read -p "TTL seconds [$(TTL)]: " input_ttl; \
> input_ttl=$${input_ttl:-$(TTL)}; \
> bash platform/create_env.sh "$$input_name" "$$input_ttl"

destroy:
> @if [ -z "$(ENV)" ]; then \
>   echo "Usage: make destroy ENV=env-xxxx"; \
>   exit 1; \
> fi
> @bash platform/destroy_env.sh "$(ENV)"

logs:
> @if [ -z "$(ENV)" ]; then \
>   echo "Usage: make logs ENV=env-xxxx"; \
>   exit 1; \
> fi
> @if [ -f "logs/$(ENV)/app.log" ]; then \
>   tail -n 100 -f "logs/$(ENV)/app.log"; \
> elif [ -f "logs/archived/$(ENV)/app.log" ]; then \
>   echo "[INFO] Showing archived logs for $(ENV)"; \
>   tail -n 100 "logs/archived/$(ENV)/app.log"; \
> else \
>   echo "No app log found for $(ENV)"; \
>   exit 1; \
> fi

health:
> @echo "Active environment health/status:"
> @found=0; \
> for f in envs/*.json; do \
>   [ -f "$$f" ] || continue; \
>   found=1; \
>   python3 -c "import json,sys,time; d=json.load(open(sys.argv[1])); print(f\"{d['id']} | name={d.get('name')} | status={d.get('status')} | port={d.get('port')} | ttl_remaining={max(0, d['created_at'] + d['ttl'] - int(time.time()))}s\")" "$$f"; \
>   env_id=$$(basename "$$f" .json); \
>   if [ -f "logs/$$env_id/health.log" ]; then \
>     tail -n 3 "logs/$$env_id/health.log"; \
>   else \
>     echo "No health log yet"; \
>   fi; \
>   echo ""; \
> done; \
> if [ "$$found" -eq 0 ]; then echo "No active environments"; fi

simulate:
> @if [ -z "$(ENV)" ]; then \
>   echo "Usage: make simulate ENV=env-xxxx MODE=crash"; \
>   exit 1; \
> fi
> @bash platform/simulate_outage.sh --env "$(ENV)" --mode "$(MODE)"

down:
> @echo "[INFO] Stopping API, health monitor, and cleanup daemon..."
> @if [ -f logs/api.pid ]; then kill $$(cat logs/api.pid) >/dev/null 2>&1 || true; rm -f logs/api.pid; fi
> @if [ -f logs/monitor.pid ]; then kill $$(cat logs/monitor.pid) >/dev/null 2>&1 || true; rm -f logs/monitor.pid; fi
> @if [ -f logs/daemon.pid ]; then kill $$(cat logs/daemon.pid) >/dev/null 2>&1 || true; rm -f logs/daemon.pid; fi
> @echo "[INFO] Destroying active sandbox environments..."
> @for f in envs/*.json; do \
>   [ -f "$$f" ] || continue; \
>   env_id=$$(basename "$$f" .json); \
>   bash platform/destroy_env.sh "$$env_id" || true; \
> done
> @docker rm -f sandbox-nginx >/dev/null 2>&1 || true
> @docker network rm sandbox-infra >/dev/null 2>&1 || true
> @echo "[OK] Platform stopped"

clean: down
> @echo "[INFO] Wiping generated state, logs, archives, and Nginx env configs..."
> @rm -rf logs/* envs/* nginx/conf.d/*
> @mkdir -p logs envs nginx/conf.d
> @echo "[OK] Clean complete"

status:
> @echo "Docker containers:"
> @docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
> @echo ""
> @echo "API status:"
> @curl -fsS http://localhost:$(API_PORT)/ || echo "API is not responding"

api-logs:
> @tail -n 100 -f logs/api.log

monitor-logs:
> @tail -n 100 -f logs/monitor.log

daemon-logs:
> @tail -n 100 -f logs/cleanup.log
