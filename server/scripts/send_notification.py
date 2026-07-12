#!/usr/bin/env python3
# TOOL: send_notification
# DESC: Display a macOS notification on the Mac's screen (appears in Notification Center)
# PARAMS: {"title": {"type": "string", "description": "Notification title"}, "message": {"type": "string", "description": "Notification body text"}}
# REQUIRED: ["title", "message"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
title = args["title"].replace('"', '\\"').replace("\n", " ")
message = args["message"].replace('"', '\\"').replace("\n", " ")

r = subprocess.run(
    ["osascript", "-e", f'display notification "{message}" with title "{title}"'],
    capture_output=True, text=True, timeout=10,
)
if r.returncode == 0:
    print(f"Done. Notification displayed on Mac: \"{title} - {message}\"")
else:
    print(f"Failed: {r.stderr.strip()}")
