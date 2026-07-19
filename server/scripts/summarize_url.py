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
    sys.exit(0)

html = r.stdout

# Strip elements that never contain main content
for tag in ['script', 'style', 'nav', 'footer', 'header', 'aside', 'noscript', 'svg', 'iframe']:
    html = re.sub(rf'<{tag}[^>]*>.*?</{tag}>', '', html, flags=re.DOTALL | re.IGNORECASE)
html = re.sub(r'<!--.*?-->', '', html, flags=re.DOTALL)

# Try to extract <article> or <main> content first
main_match = re.search(r'<(?:article|main)[^>]*>(.*?)</(?:article|main)>', html, re.DOTALL | re.IGNORECASE)
if main_match:
    html = main_match.group(1)

# Strip remaining tags and decode common entities
html = re.sub(r'<[^>]+>', ' ', html)
entity_map = {'&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&nbsp;': ' '}
for ent, char in entity_map.items():
    html = html.replace(ent, char)
html = re.sub(r'&#?\w+;', ' ', html)

# Collapse whitespace, preserving paragraph breaks
lines = [re.sub(r'[ \t]+', ' ', line).strip() for line in html.splitlines()]
text = '\n'.join(line for line in lines if line)
text = re.sub(r'\n{3,}', '\n\n', text)

if len(text) > 8000:
    text = text[:8000] + "\n... (truncated)"

if text.strip():
    print(text)
else:
    print("Could not extract text from this URL.")
