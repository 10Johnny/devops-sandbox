# DevOps Sandbox Platform

A lightweight self-service DevOps sandbox platform for creating, routing, monitoring, breaking, recovering, and automatically cleaning up temporary application environments.

This project demonstrates Docker-based environment provisioning, dynamic Nginx routing, health monitoring, outage simulation, log collection, a Control API, and Makefile automation.

## Features

- Create temporary sandbox environments
- Destroy sandbox environments manually
- Auto-cleanup expired environments using TTL
- Dynamic Nginx reverse proxy routing
- Health monitoring every 30 seconds
- Failure detection and degraded status update
- Outage simulation: crash, pause, network isolation, stress, recover
- Log collection and log archiving
- FastAPI Control API
- Makefile automation

## Architecture

User interacts with the platform through either the Makefile or the FastAPI Control API.

The platform scripts handle the main work:

- create_env.sh creates a Docker network, app container, Nginx config, state file, and logs.
- destroy_env.sh removes the app container, Nginx config, Docker network, state file, and archives logs.
- cleanup_daemon.sh checks TTL and automatically destroys expired environments.
- health_poller.py checks each environment health endpoint and marks failed environments as degraded.
- simulate_outage.sh intentionally breaks or recovers environments for testing.

Nginx acts as the reverse proxy and routes each sandbox hostname to the correct app container.

## Project Structure

devops-sandbox/
├── demo-app/
│   ├── app.py
│   └── Dockerfile
├── platform/
│   ├── api.py
│   ├── create_env.sh
│   ├── destroy_env.sh
│   ├── cleanup_daemon.sh
│   └── simulate_outage.sh
├── monitor/
│   └── health_poller.py
├── nginx/
│   ├── nginx.conf
│   └── conf.d/
├── envs/
├── logs/
├── Makefile
├── .gitignore
└── README.md

## Requirements

- Docker
- Python 3
- pip
- FastAPI
- Uvicorn
- Make
- Bash

Install API dependencies:

    pip3 install fastapi uvicorn --break-system-packages

## Running the Platform

Start all platform services:

    make up

This starts:

- Nginx
- Cleanup daemon
- Health monitor
- Control API

Expected output:

    [READY] DevOps Sandbox Platform is up
    Nginx: http://localhost
    API:   http://localhost:8000
    Docs:  http://localhost:8000/docs

## Makefile Commands

Show all commands:

    make help

Start platform:

    make up

Create environment:

    make create

Check health:

    make health

View logs:

    make logs ENV=env-xxxx

Simulate outage:

    make simulate ENV=env-xxxx MODE=crash

Recover environment:

    make simulate ENV=env-xxxx MODE=recover

Destroy environment:

    make destroy ENV=env-xxxx

Stop platform:

    make down

Clean generated runtime files:

    make clean

Check status:

    make status

## Creating an Environment

Run:

    make create

Example output:

    Environment created successfully!
    ID: env-d3290787
    Name: make-testenv
    Direct URL: http://localhost:4585
    Nginx Hostname: http://env-d3290787.sandbox.local

Test the app directly:

    curl http://localhost:4585/health

Test through Nginx:

    curl -H "Host: env-d3290787.sandbox.local" http://localhost/

## Health Monitoring

The health monitor checks active environments every 30 seconds.

Run:

    make health

Example output:

    env-d3290787 | name=make-testenv | status=running | port=4585
    2026-05-10T03:54:51Z | 200 OK | 62.7ms

Health logs are stored in:

    logs/<env-id>/health.log

## Outage Simulation

Crash an environment:

    make simulate ENV=env-d3290787 MODE=crash

After failed health checks, the environment becomes degraded:

    status=degraded
    CONNECTION_FAILED

Recover the environment:

    make simulate ENV=env-d3290787 MODE=recover

Test recovery:

    curl http://localhost:4585/health

Expected response:

    {"status":"ok"}

## Control API

The Control API runs on:

    http://localhost:8000

Interactive documentation:

    http://localhost:8000/docs

API endpoints:

| Method | Endpoint | Description |
|---|---|---|
| GET | / | API status |
| POST | /envs | Create environment |
| GET | /envs | List environments |
| DELETE | /envs/{env_id} | Destroy environment |
| GET | /envs/{env_id}/logs | View app logs |
| GET | /envs/{env_id}/health | View health logs |
| POST | /envs/{env_id}/outage | Simulate outage or recover |

## API Examples

Create environment:

    curl -X POST http://localhost:8000/envs \
      -H "Content-Type: application/json" \
      -d '{"name":"api-test","ttl":600}'

List environments:

    curl http://localhost:8000/envs

Crash environment:

    curl -X POST http://localhost:8000/envs/env-xxxx/outage \
      -H "Content-Type: application/json" \
      -d '{"mode":"crash"}'

Recover environment:

    curl -X POST http://localhost:8000/envs/env-xxxx/outage \
      -H "Content-Type: application/json" \
      -d '{"mode":"recover"}'

Destroy environment:

    curl -X DELETE http://localhost:8000/envs/env-xxxx

## TTL Cleanup

Each environment has a TTL in seconds.

When the TTL expires, cleanup_daemon.sh automatically destroys the environment and archives logs.

Archived logs are stored in:

    logs/archived/<env-id>/

## Evidence of Working Flow

The project was tested with:

    make up
    make create
    make health
    curl /health
    curl through Nginx Host header
    make simulate MODE=crash
    make health
    make simulate MODE=recover
    curl /health
    make destroy

The test confirmed that the platform can create an environment, monitor it, detect failure, mark it as degraded, recover it, destroy it, and archive logs.

## Troubleshooting

If Docker cannot pull images and shows:

    lookup registry-1.docker.io: no such host

Check Docker Desktop, internet, or DNS connectivity.

If the API says port 8000 is already in use, it means the API is already running.

Check:

    curl http://localhost:8000/

If no health log appears immediately, wait 30 seconds and run:

    make health

## Author

Built by johnnnnyboy.

GitHub: https://github.com/10Johnny

## Architecture Diagram

```text
User / Grader
     |
     |---- Makefile Commands
     |---- FastAPI Control API
     |
     v
Platform Bash Scripts
     |
     |---- create_env.sh
     |       |---- creates Docker network
     |       |---- starts app container
     |       |---- writes env state file
     |       |---- creates Nginx route
     |
     |---- destroy_env.sh
     |       |---- removes container
     |       |---- removes Docker network
     |       |---- removes Nginx config
     |       |---- archives logs
     |
     |---- cleanup_daemon.sh
     |       |---- checks TTL
     |       |---- destroys expired environments
     |
     |---- simulate_outage.sh
             |---- crash
             |---- pause
             |---- network
             |---- recover
             |---- stress

Nginx Reverse Proxy
     |
     v
Sandbox Flask App
     |
     v
/health Endpoint

health_poller.py
     |
     |---- checks /health every 30 seconds
     |---- writes health logs
     |---- marks failed envs as degraded

## Walkthrough Video

Video link: https://drive.google.com/file/d/1AdmouClwVQ_K2WJWuKrrxC0_HZT8GVuG/view?usp=drive_link
