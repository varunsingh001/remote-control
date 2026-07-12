#!/usr/bin/env python3
# TOOL: wake_screen
# DESC: Wake the Mac screen if it is asleep or showing the screensaver
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(["caffeinate", "-u", "-t", "2"], capture_output=True, text=True, timeout=10)
print("Done. Screen is awake." if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
