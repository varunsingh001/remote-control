#!/usr/bin/env python3
# TOOL: empty_trash
# DESC: Empty the Trash
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(
    ["osascript", "-e", 'tell application "Finder" to empty trash'],
    capture_output=True, text=True, timeout=10,
)
print("Trash emptied" if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
