#!/usr/bin/env python3
# TOOL: list_save_dirs
# DESC: List available directories where notes can be saved
# PARAMS: {}
# REQUIRED: []

import json, os, sys

SAVE_DIRS_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "upload_dirs.json")

if not os.path.exists(SAVE_DIRS_FILE):
    print("No save directories configured.")
    sys.exit(0)

with open(SAVE_DIRS_FILE) as f:
    dirs = json.load(f).get("directories", [])

if not dirs:
    print("No save directories configured.")
    sys.exit(0)

for d in dirs:
    path = os.path.expanduser(d["path"])
    exists = "ok" if os.path.isdir(path) else "missing"
    print(f"- {d.get('label', os.path.basename(path))} ({path}) [{exists}]")
