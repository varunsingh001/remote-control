#!/usr/bin/env python3
# TOOL: summarize_url
# DESC: Fetch a URL and return its main text content (for the model to summarize)
# PARAMS: {"url": {"type": "string", "description": "The URL to fetch and extract text from"}}
# REQUIRED: ["url"]

import json, subprocess, sys, re

args = json.loads(sys.argv[1])
url = args["url"]

r = subprocess.run(
    ["curl", "-sL", "--max-time", "15", "-A",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", url],
    capture_output=True, text=True, timeout=20,
)

if r.returncode != 0:
    print(f"Failed to fetch: {r.stderr.strip()}")
else:
    html = r.stdout
    # Strip scripts, styles, and tags
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<[^>]+>', ' ', html)
    html = re.sub(r'&[a-z]+;', ' ', html)
    # Collapse whitespace
    text = re.sub(r'\s+', ' ', html).strip()
    # Truncate to keep context manageable
    if len(text) > 3000:
        text = text[:3000] + "... (truncated)"
    if text:
        print(text)
    else:
        print("Could not extract text from this URL.")
