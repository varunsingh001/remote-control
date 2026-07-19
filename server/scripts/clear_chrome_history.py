#!/usr/bin/env python3
# TOOL: clear_chrome_history
# DESC: Clear Google Chrome browsing history
# PARAMS: {}
# REQUIRED: []

import glob
import os
import subprocess
import time

chrome_default = os.path.expanduser(
    "~/Library/Application Support/Google/Chrome/Default"
)

if not os.path.isdir(chrome_default):
    print("Chrome profile not found")
    raise SystemExit(1)

# Force quit Chrome so DB locks are released
subprocess.run(["pkill", "-f", "Google Chrome"], capture_output=True, timeout=5)
time.sleep(2)

history_files = [
    "History",
    "History-journal",
    "History Provider Cache",
    "Visited Links",
    "Top Sites",
    "Top Sites-journal",
    "Network Action Predictor",
    "Network Action Predictor-journal",
    "Shortcuts",
    "Shortcuts-journal",
]

removed = 0
for fname in history_files:
    path = os.path.join(chrome_default, fname)
    if os.path.exists(path):
        try:
            os.remove(path)
            removed += 1
        except OSError:
            pass

# Also clear session storage that may hold recent tabs
for f in glob.glob(os.path.join(chrome_default, "Sessions", "*")):
    try:
        os.remove(f)
        removed += 1
    except OSError:
        pass

if removed > 0:
    print(f"Chrome history cleared ({removed} files removed). Note: if Chrome Sync is enabled, history may reappear from your Google account.")
else:
    print("No history files found to remove")
