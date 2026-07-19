#!/usr/bin/env python3
# TOOL: save_note
# DESC: Save a text note to a permitted directory. Call with directory label and content. Use list_save_dirs to see available directories first.
# PARAMS: {"directory": {"type": "string", "description": "Directory label (e.g. 'Wiki-Raw')"}, "filename": {"type": "string", "description": "Filename with extension (e.g. 'meeting-notes.md')"}, "content": {"type": "string", "description": "Text content to save"}}
# REQUIRED: ["directory", "filename", "content"]

import json, os, sys

SAVE_DIRS_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "upload_dirs.json")

args = json.loads(sys.argv[1])
label = args["directory"]
filename = os.path.basename(args["filename"])
content = args["content"]

if not filename:
    print("Error: invalid filename")
    sys.exit(0)

if not os.path.exists(SAVE_DIRS_FILE):
    print("Error: no save directories configured")
    sys.exit(0)

with open(SAVE_DIRS_FILE) as f:
    dirs = json.load(f).get("directories", [])

match = None
for d in dirs:
    if d.get("label", "").lower() == label.lower():
        match = os.path.expanduser(d["path"])
        break

if not match:
    available = ", ".join(d.get("label", d["path"]) for d in dirs)
    print(f"Error: directory '{label}' not found. Available: {available}")
    sys.exit(0)

if not os.path.isdir(match):
    print(f"Error: directory does not exist on disk")
    sys.exit(0)

target = os.path.join(match, filename)
with open(target, "w") as f:
    f.write(content)

size = len(content.encode("utf-8"))
if size >= 1024:
    size_str = f"{size / 1024:.1f} KB"
else:
    size_str = f"{size} bytes"

print(f"Saved {filename} ({size_str}) to {label}")
