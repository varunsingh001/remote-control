#!/usr/bin/env python3
# TOOL: get_top_processes
# DESC: Get the top processes sorted by CPU or memory usage
# PARAMS: {"sort_by": {"type": "string", "enum": ["cpu", "memory"], "description": "Sort by cpu or memory usage"}, "limit": {"type": "integer", "description": "Number of processes to return (default 10)"}}
# REQUIRED: ["sort_by"]

import json, subprocess, sys

args = json.loads(sys.argv[1])
sort_by = args.get("sort_by", "cpu")
limit = int(args.get("limit", 10))
flag = "-r" if sort_by == "cpu" else "-m"

r = subprocess.run(
    ["ps", "-eo", "pid,pcpu,pmem,comm", flag],
    capture_output=True, text=True, timeout=10,
)
lines = r.stdout.strip().split("\n")[:limit + 1]
print("\n".join(lines))
