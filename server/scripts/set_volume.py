#!/usr/bin/env python3
# TOOL: set_volume
# DESC: Set the system audio output volume
# PARAMS: {"level": {"type": "integer", "description": "Volume level from 0 (mute) to 100 (max)"}}
# REQUIRED: ["level"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
level = max(0, min(100, int(args["level"])))

r = subprocess.run(
    ["osascript", "-e", f"set volume output volume {level}"],
    capture_output=True, text=True, timeout=10,
)
print(f"Volume set to {level}%" if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
