#!/usr/bin/env python3
# TOOL: sleep_mac
# DESC: Put the Mac to sleep immediately
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(["pmset", "sleepnow"], capture_output=True, text=True, timeout=10)
print("Done. Mac is now sleeping." if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
