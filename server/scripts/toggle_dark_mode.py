#!/usr/bin/env python3
# TOOL: toggle_dark_mode
# DESC: Toggle macOS between light and dark appearance
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(
    ["osascript", "-e", 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'],
    capture_output=True, text=True, timeout=10,
)
print("Dark mode toggled" if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
