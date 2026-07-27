# TOOL: run_python
# DESC: Execute Python code ONLY when the user explicitly asks to run code or the task requires complex computation that you cannot do in your head (e.g. large matrix operations, data analysis, plotting). Do NOT use this for simple math, trivia, or questions you already know the answer to. Available packages: numpy, pandas, scipy, sympy, matplotlib, math, statistics. Blocked: subprocess, socket, ctypes, shutil, threading, multiprocessing. Print results to stdout.
# PARAMS: {"code": {"type": "string", "description": "Python code to execute. Use print() to output results."}}
# REQUIRED: ["code"]

import json
import subprocess
import sys
import time
import urllib.request
import urllib.error

CONTAINER = "python-sandbox"
SANDBOX_URL = "http://localhost:8050"
DOCKER = "/usr/local/bin/docker"

args = json.loads(sys.argv[1])
code = args["code"]


def container_running():
    try:
        out = subprocess.check_output(
            [DOCKER, "inspect", "-f", "{{.State.Running}}", CONTAINER],
            stderr=subprocess.DEVNULL,
        )
        return out.strip() == b"true"
    except Exception:
        return False


def start_container():
    try:
        out = subprocess.check_output(
            [DOCKER, "ps", "-a", "--filter", f"name={CONTAINER}", "--format", "{{.Names}}"],
            stderr=subprocess.DEVNULL,
        )
        if CONTAINER.encode() in out:
            subprocess.check_call([DOCKER, "start", CONTAINER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            subprocess.check_call([
                DOCKER, "run", "-d",
                "--name", CONTAINER,
                "--read-only",
                "--tmpfs", "/tmp:size=50m",
                "--cap-drop", "ALL",
                "--security-opt", "no-new-privileges",
                "--memory", "512m",
                "--cpus", "1",
                "--pids-limit", "50",
                "-p", "8050:8050",
                CONTAINER,
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Error: Failed to start sandbox container: {e}")
        sys.exit(1)


def wait_ready(timeout=15):
    for _ in range(timeout * 2):
        try:
            urllib.request.urlopen(f"{SANDBOX_URL}/health", timeout=2)
            return True
        except Exception:
            time.sleep(0.5)
    return False


if not container_running():
    start_container()
    if not wait_ready():
        print("Error: Sandbox container failed to start. Is Docker Desktop running?")
        sys.exit(1)

try:
    data = json.dumps({"code": code, "timeout": 30}).encode()
    req = urllib.request.Request(
        f"{SANDBOX_URL}/execute",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=35) as resp:
        result = json.loads(resp.read())

    if result.get("success"):
        output = result.get("output", "").strip()
        stderr = result.get("stderr", "").strip()
        print(output if output else "(no output)")
        if stderr:
            print(f"stderr: {stderr}")
    else:
        output = result.get("output", "").strip()
        if output:
            print(output)
        print(f"Error: {result.get('error', 'Unknown error')}")
except urllib.error.URLError:
    print("Error: Python sandbox is not running. Is Docker Desktop running?")
except Exception as e:
    print(f"Error: {e}")
