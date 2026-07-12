#!/usr/bin/env python3
# TOOL: get_clipboard
# DESC: Read the current clipboard/pasteboard text contents
# PARAMS: {}
# REQUIRED: []

import subprocess

r = subprocess.run(["pbpaste"], capture_output=True, text=True, timeout=10)
content = r.stdout
if len(content) > 500:
    content = content[:500] + "... (truncated)"
print(content if content else "(clipboard is empty)")
