#!/usr/bin/env python3

import json
import subprocess
import time
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

BASE_DIR = Path(__file__).resolve().parent.parent
ENVS_DIR = BASE_DIR / "envs"
LOGS_DIR = BASE_DIR / "logs"
PLATFORM_DIR = BASE_DIR / "platform"

app = FastAPI(
    title="DevOps Sandbox Platform API",
    description="API for creating, listing, destroying, monitoring, and breaking sandbox environments",
    version="1.0.0"
)


class CreateEnvRequest(BaseModel):
    name: str
    ttl: Optional[int] = 1800


class OutageRequest(BaseModel):
    mode: str


def run_command(command):
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=120
    )

    if result.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail=result.stderr or result.stdout or "Command failed"
        )

    return result.stdout


def load_state(env_id: str):
    state_file = ENVS_DIR / f"{env_id}.json"

    if not state_file.exists():
        raise HTTPException(status_code=404, detail=f"Environment {env_id} not found")

    with open(state_file) as f:
        return json.load(f)


@app.get("/")
def root():
    return {
        "service": "DevOps Sandbox Platform",
        "status": "running",
        "message": "Control API is ready"
    }


@app.post("/envs", status_code=201)
def create_env(request: CreateEnvRequest):
    output = run_command([
        "bash",
        str(PLATFORM_DIR / "create_env.sh"),
        request.name,
        str(request.ttl)
    ])

    env_id = None

    for line in output.splitlines():
        if line.startswith("ID: env-"):
            env_id = line.replace("ID:", "").strip()

    return {
        "message": "Environment created",
        "env_id": env_id,
        "output": output
    }


@app.get("/envs")
def list_envs():
    environments = []

    for file in ENVS_DIR.glob("*.json"):
        try:
            with open(file) as f:
                data = json.load(f)

            now = int(time.time())
            data["ttl_remaining"] = max(0, data["created_at"] + data["ttl"] - now)

            environments.append(data)
        except Exception:
            continue

    return {
        "count": len(environments),
        "environments": environments
    }


@app.delete("/envs/{env_id}")
def destroy_env(env_id: str):
    load_state(env_id)

    output = run_command([
        "bash",
        str(PLATFORM_DIR / "destroy_env.sh"),
        env_id
    ])

    return {
        "message": f"Environment {env_id} destroyed",
        "output": output
    }


@app.get("/envs/{env_id}/logs")
def get_logs(env_id: str, lines: int = 100):
    load_state(env_id)

    log_file = LOGS_DIR / env_id / "app.log"

    if not log_file.exists():
        raise HTTPException(status_code=404, detail="App log not found yet")

    result = subprocess.run(
        ["tail", f"-{lines}", str(log_file)],
        capture_output=True,
        text=True
    )

    return {
        "env_id": env_id,
        "logs": result.stdout.splitlines()
    }


@app.get("/envs/{env_id}/health")
def get_health(env_id: str):
    load_state(env_id)

    health_file = LOGS_DIR / env_id / "health.log"

    if not health_file.exists():
        return {
            "env_id": env_id,
            "message": "No health checks recorded yet",
            "checks": []
        }

    lines = health_file.read_text().splitlines()

    return {
        "env_id": env_id,
        "checks": lines[-10:]
    }


@app.post("/envs/{env_id}/outage")
def simulate_outage(env_id: str, request: OutageRequest):
    load_state(env_id)

    valid_modes = ["crash", "pause", "network", "recover", "stress"]

    if request.mode not in valid_modes:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid mode. Use one of: {valid_modes}"
        )

    output = run_command([
        "bash",
        str(PLATFORM_DIR / "simulate_outage.sh"),
        "--env",
        env_id,
        "--mode",
        request.mode
    ])

    return {
        "env_id": env_id,
        "mode": request.mode,
        "output": output
    }
