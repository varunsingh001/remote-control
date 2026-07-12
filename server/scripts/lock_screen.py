#!/usr/bin/env python3
# TOOL: lock_screen
# DESC: Lock the Mac screen immediately
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(["open", "-a", "ScreenSaverEngine"], capture_output=True, text=True, timeout=10)
if r.returncode == 0:
    print("Done. Screen is now locked.")
else:
    r = subprocess.run(["pmset", "displaysleepnow"], capture_output=True, text=True, timeout=10)
    print("Done. Display is sleeping." if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
