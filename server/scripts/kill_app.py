#!/usr/bin/env python3
# TOOL: kill_app
# DESC: Force quit a running application. Requires exact name from list_running_apps.
# PARAMS: {"app_name": {"type": "string", "description": "Exact application name from list_running_apps"}}
# REQUIRED: ["app_name"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
app = args["app_name"]

r = subprocess.run(
    ["osascript", "-e", f'tell application "{app}" to quit'],
    capture_output=True, text=True, timeout=10,
)
if r.returncode != 0:
    r = subprocess.run(["killall", app], capture_output=True, text=True, timeout=10)

print(f"Done. {app} has been quit." if r.returncode == 0 else f"Failed: could not quit {app}: {r.stderr.strip()}")
