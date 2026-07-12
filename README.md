# Remote Control

An iOS app that lets you control your Mac remotely through a local LLM running on [Ollama](https://ollama.com). Chat naturally with the model and it executes macOS actions via tool-calling — kill apps, lock the screen, adjust volume, and more.

The server runs on your Mac, the app connects over your local network (or [Tailscale](https://tailscale.com) for remote access), and Ollama handles the intelligence.

## How It Works

```
iPhone App  ←—WebSocket—→  Python Server  ←—HTTP—→  Ollama (local LLM)
                                ↓
                          Tool Scripts (macOS actions)
```

1. You type a message in the iOS chat (e.g. "kill Chrome" or "lock my Mac")
2. The server forwards it to Ollama with available tool definitions
3. Ollama decides which tool to call and returns structured tool calls
4. The server executes the matching Python script and returns the result
5. Ollama generates a natural language response based on the tool output

Tools are standalone Python scripts in `server/scripts/`. The server discovers them at runtime — drop a new script in the folder and it's immediately available as a tool.

## Features

- **Dashboard** — system info at a glance (hostname, OS, CPU, memory, battery, disk, uptime)
- **Model Selection** — browse and select from locally installed Ollama models
- **LLM Chat** — streaming responses with tool-calling support
- **14 Built-in Tools** — see [Tools](#tools) below
- **Extensible** — add new tools by dropping a Python script in `server/scripts/`

## Prerequisites

- **Mac** (Apple Silicon or Intel) running the server
- **iPhone** running iOS 17+
- **[Ollama](https://ollama.com)** installed with at least one model pulled (e.g. `ollama pull qwen3`)
- **Python 3.10+** with pip
- **Xcode 15+** to build the iOS app
- **Network** — both devices on the same network, or [Tailscale](https://tailscale.com) for remote access

## Setup

### Server (Mac)

```bash
# Install Python dependencies
cd server
pip install -r requirements.txt

# Run the server
python server.py
```

The server starts on `ws://0.0.0.0:8765`.

#### Auto-start on boot (optional)

Create a LaunchAgent plist at `~/Library/LaunchAgents/com.vs.remotecontrol.server.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vs.remotecontrol.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/python3</string>
        <string>/path/to/remote-control/server/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/remotecontrol-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/remotecontrol-server.err</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.vs.remotecontrol.server.plist
```

### iOS App

1. Open `ios/RemoteControl.xcodeproj` in Xcode
2. Select your team for code signing
3. Build and run on your iPhone
4. Enter your Mac's IP address (local or Tailscale) and tap Connect

### Ollama

```bash
# Install Ollama (if not already)
brew install ollama

# Pull a model with tool-calling support
ollama pull qwen3

# Ollama runs automatically — verify with:
curl http://localhost:11434/api/tags
```

## Tools

| Tool | Description |
|------|-------------|
| `kill_app` | Force quit an app (looks up running apps first) |
| `open_app` | Launch an application |
| `list_running_apps` | List all visible running apps |
| `open_url` | Open a URL in the default browser |
| `set_volume` | Set system volume (0–100) |
| `get_top_processes` | Top processes by CPU or memory |
| `send_notification` | Display a macOS notification |
| `lock_screen` | Lock the screen |
| `wake_screen` | Wake the display |
| `sleep_mac` | Put the Mac to sleep |
| `toggle_dark_mode` | Switch light/dark mode |
| `empty_trash` | Empty the Trash |
| `get_clipboard` | Read clipboard contents |
| `set_clipboard` | Write text to clipboard |
| `summarize_url` | Fetch and extract text from a URL |

## Adding Custom Tools

Create a Python script in `server/scripts/` with this header format:

```python
#!/usr/bin/env python3
# TOOL: my_tool_name
# DESC: What this tool does (shown to the LLM)
# PARAMS: {"param_name": {"type": "string", "description": "Param description"}}
# REQUIRED: ["param_name"]

import json, sys

args = json.loads(sys.argv[1])
# ... your logic ...
print("result")
```

The server picks it up automatically on the next chat message — no restart needed.

## App Screenshots

The iOS app has three tabs:

- **My Mac** — connection status, system dashboard, quick commands
- **Models** — Ollama model list, thinking toggle, temperature slider
- **Chat** — LLM conversation with streaming and tool-call bubbles

## Project Structure

```
remote-control/
├── ios/
│   └── RemoteControl/
│       ├── ContentView.swift          # Tab container
│       ├── DashboardView.swift        # System info + connection
│       ├── ModelsView.swift           # Model selection + settings
│       ├── ChatView.swift             # LLM chat interface
│       ├── WebSocketManager.swift     # WebSocket client
│       └── Models.swift               # Data models
└── server/
    ├── server.py                      # WebSocket server + Ollama proxy
    ├── requirements.txt               # Python dependencies
    └── scripts/                       # Tool scripts (auto-discovered)
        ├── kill_app.py
        ├── lock_screen.py
        ├── ...
        └── summarize_url.py
```

## License

MIT
