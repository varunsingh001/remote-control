#!/usr/bin/env python3
# TOOL: open_url
# DESC: Open a URL in the default web browser
# PARAMS: {"url": {"type": "string", "description": "The URL to open"}}
# REQUIRED: ["url"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
url = args["url"]

r = subprocess.run(["open", url], capture_output=True, text=True, timeout=10)
print(f"Opened {url}" if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
