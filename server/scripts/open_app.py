#!/usr/bin/env python3
# TOOL: open_app
# DESC: Launch or open an application
# PARAMS: {"app_name": {"type": "string", "description": "Application name, e.g. 'Safari', 'Terminal'"}}
# REQUIRED: ["app_name"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
app = args["app_name"]

r = subprocess.run(["open", "-a", app], capture_output=True, text=True, timeout=10)
print(f"Opened {app}" if r.returncode == 0 else f"Could not open {app}: {r.stderr.strip()}")
