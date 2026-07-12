#!/usr/bin/env python3
# TOOL: list_running_apps
# DESC: List all currently running (visible) applications
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(
    ["osascript", "-e", 'tell application "System Events" to get name of every process whose background only is false'],
    capture_output=True, text=True, timeout=10,
)
if r.returncode == 0:
    apps = sorted(a.strip() for a in r.stdout.strip().split(","))
    print(", ".join(apps))
else:
    print(f"Error: {r.stderr.strip()}")
