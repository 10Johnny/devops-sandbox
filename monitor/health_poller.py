#!/usr/bin/env python3

import json
import os
import time
import urllib.request
import urllib.error
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ENVS_DIR = BASE_DIR / "envs"
LOGS_DIR = BASE_DIR / "logs"

POLL_INTERVAL = 30
TIMEOUT = 5
FAIL_THRESHOLD = 3

failure_counts = {}


def load_envs():
    envs = []

    for file in ENVS_DIR.glob("*.json"):
        try:
            with open(file) as f:
                envs.append(json.load(f))
        except Exception as e:
            print(f"[WARN] Could not read {file}: {e}")

    return envs


def update_status(env_id, new_status):
    state_file = ENVS_DIR / f"{env_id}.json"

    if not state_file.exists():
        return

    try:
        with open(state_file) as f:
            data = json.load(f)

        data["status"] = new_status

        tmp_file = str(state_file) + ".tmp"

        with open(tmp_file, "w") as f:
            json.dump(data, f, indent=2)

        os.replace(tmp_file, state_file)

    except Exception as e:
        print(f"[WARN] Could not update status for {env_id}: {e}")


def check_health(env):
    port = env.get("port")

    if not port:
        return None, -1

    url = f"http://localhost:{port}/health"
    start_time = time.time()

    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
            latency_ms = round((time.time() - start_time) * 1000, 2)
            return response.status, latency_ms

    except urllib.error.HTTPError as e:
        latency_ms = round((time.time() - start_time) * 1000, 2)
        return e.code, latency_ms

    except Exception:
        return None, -1


def write_health_log(env_id, status, latency):
    log_dir = LOGS_DIR / env_id
    log_dir.mkdir(parents=True, exist_ok=True)

    timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    with open(log_dir / "health.log", "a") as f:
        f.write(f"{timestamp} | {status} | {latency}ms\n")


def main():
    print("Health poller started")
    print(f"Checking environments every {POLL_INTERVAL} seconds")

    while True:
        envs = load_envs()

        if not envs:
            print("[INFO] No active environments")

        for env in envs:
            env_id = env["id"]
            env_name = env.get("name", "unknown")

            status_code, latency = check_health(env)

            if status_code == 200:
                failure_counts[env_id] = 0
                write_health_log(env_id, "200 OK", latency)

                print(f"[OK] {env_id} ({env_name}) healthy - {latency}ms")

                if env.get("status") == "degraded":
                    update_status(env_id, "running")

            else:
                failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
                count = failure_counts[env_id]

                reason = status_code if status_code else "CONNECTION_FAILED"

                write_health_log(env_id, reason, latency)

                print(f"[FAIL] {env_id} ({env_name}) failed health check {count}/{FAIL_THRESHOLD}")

                if count >= FAIL_THRESHOLD:
                    update_status(env_id, "degraded")
                    print(f"[DEGRADED] {env_id} marked as degraded")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
