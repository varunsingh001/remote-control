#!/usr/bin/env python3
# TOOL: set_clipboard
# DESC: Copy text to the clipboard/pasteboard
# PARAMS: {"text": {"type": "string", "description": "Text to place on the clipboard"}}
# REQUIRED: ["text"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
text = args["text"]

r = subprocess.run(["pbcopy"], input=text, capture_output=True, text=True, timeout=10)
print("Clipboard updated" if r.returncode == 0 else f"Failed: {r.stderr.strip()}")
