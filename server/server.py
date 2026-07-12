import asyncio
import json
import os
import platform
import re
import subprocess

import aiohttp
import websockets

OLLAMA_BASE = "http://localhost:11434"
SCRIPTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts")
PYTHON_PATH = "/opt/homebrew/anaconda3/bin/python3"

ALLOWED_COMMANDS = {
    "battery": ["pmset", "-g", "batt"],
    "disk_space": ["df", "-h"],
    "uptime": ["uptime"],
    "memory": ["vm_stat"],
    "network": ["ifconfig"],
    "os_version": ["sw_vers"],
}


def load_tools_from_scripts():
    tools = []
    tool_scripts = {}
    for filename in sorted(os.listdir(SCRIPTS_DIR)):
        if not filename.endswith(".py"):
            continue
        path = os.path.join(SCRIPTS_DIR, filename)
        meta = {"name": None, "desc": "", "params": {}, "required": []}
        with open(path) as f:
            for line in f:
                if not line.startswith("#"):
                    break
                if line.startswith("# TOOL:"):
                    meta["name"] = line.split(":", 1)[1].strip()
                elif line.startswith("# DESC:"):
                    meta["desc"] = line.split(":", 1)[1].strip()
                elif line.startswith("# PARAMS:"):
                    try:
                        meta["params"] = json.loads(line.split(":", 1)[1].strip())
                    except json.JSONDecodeError:
                        pass
                elif line.startswith("# REQUIRED:"):
                    try:
                        meta["required"] = json.loads(line.split(":", 1)[1].strip())
                    except json.JSONDecodeError:
                        pass
        if not meta["name"]:
            continue
        tool_def = {
            "type": "function",
            "function": {
                "name": meta["name"],
                "description": meta["desc"],
                "parameters": {
                    "type": "object",
                    "properties": meta["params"],
                    "required": meta["required"],
                },
            },
        }
        tools.append(tool_def)
        tool_scripts[meta["name"]] = path
    return tools, tool_scripts


# Meta-tools that manage scripts (stay in the server)
META_TOOLS = []


def execute_script(script_path, args):
    try:
        cmd = [PYTHON_PATH, script_path]
        if args:
            cmd.append(json.dumps(args))
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        output = r.stdout.strip()
        if r.returncode != 0 and r.stderr.strip():
            output += f"\nSTDERR: {r.stderr.strip()}"
        if len(output) > 1000:
            output = output[:1000] + "... (truncated)"
        return output if output else "(no output)"
    except subprocess.TimeoutExpired:
        return "Tool timed out"
    except Exception as e:
        return f"Error: {e}"




def gather_dashboard():
    info = {
        "hostname": platform.node(),
        "os": f"macOS {platform.mac_ver()[0]}",
        "arch": platform.machine(),
        "processor": platform.processor(),
        "cpu_cores": str(os.cpu_count()),
    }

    try:
        r = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=5)
        total = int(r.stdout.strip())
        info["memory_total"] = f"{total / (1024**3):.0f} GB"
    except Exception:
        info["memory_total"] = "Unknown"

    try:
        r = subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().split("\n")
        info["battery"] = lines[-1].strip() if len(lines) > 1 else "No battery"
    except Exception:
        info["battery"] = "N/A"

    try:
        r = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, timeout=5)
        lines = r.stdout.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            info["disk"] = f"{parts[2]} used of {parts[1]} ({parts[4]})"
        else:
            info["disk"] = "Unknown"
    except Exception:
        info["disk"] = "Unknown"

    try:
        r = subprocess.run(["uptime"], capture_output=True, text=True, timeout=5)
        raw = r.stdout.strip()
        match = re.search(r"up\s+(.+?),\s+\d+\s+user", raw)
        info["uptime"] = match.group(1).strip() if match else raw
    except Exception:
        info["uptime"] = "Unknown"

    return info


async def handle(websocket):
    async for raw in websocket:
        try:
            msg = json.loads(raw)
            action = msg.get("action")

            if action == "system_info":
                data = (
                    f"Hostname: {platform.node()}\n"
                    f"OS: {platform.system()} {platform.mac_ver()[0]}\n"
                    f"Architecture: {platform.machine()}\n"
                    f"Processor: {platform.processor()}"
                )
                await websocket.send(json.dumps({"success": True, "data": data}))

            elif action == "dashboard":
                info = await asyncio.to_thread(gather_dashboard)
                await websocket.send(json.dumps({
                    "success": True,
                    "action": "dashboard",
                    "data": json.dumps(info),
                }))

            elif action == "run_command":
                cmd_name = msg.get("command")
                if cmd_name in ALLOWED_COMMANDS:
                    result = subprocess.run(
                        ALLOWED_COMMANDS[cmd_name],
                        capture_output=True, text=True, timeout=10,
                    )
                    await websocket.send(
                        json.dumps({"success": True, "data": result.stdout or result.stderr})
                    )
                else:
                    allowed = list(ALLOWED_COMMANDS.keys())
                    await websocket.send(json.dumps({
                        "success": False,
                        "error": f"Command '{cmd_name}' not allowed. Allowed: {allowed}",
                    }))

            elif action == "ollama_list_models":
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(f"{OLLAMA_BASE}/api/tags") as resp:
                            if resp.status == 200:
                                body = await resp.json()
                                models = []
                                for m in body.get("models", []):
                                    models.append({
                                        "name": m.get("name", ""),
                                        "size": m.get("size", 0),
                                        "modified_at": m.get("modified_at", ""),
                                        "family": m.get("details", {}).get("family", ""),
                                        "parameter_size": m.get("details", {}).get("parameter_size", ""),
                                        "quantization": m.get("details", {}).get("quantization_level", ""),
                                    })
                                await websocket.send(json.dumps({
                                    "success": True,
                                    "action": "ollama_list_models",
                                    "data": json.dumps(models),
                                }))
                            else:
                                await websocket.send(json.dumps({
                                    "success": False,
                                    "error": f"Ollama returned status {resp.status}",
                                }))
                except aiohttp.ClientError:
                    await websocket.send(json.dumps({
                        "success": False,
                        "error": "Cannot connect to Ollama. Is it running?",
                    }))

            elif action == "ollama_chat":
                model = msg.get("model")
                messages = msg.get("messages", [])
                think = msg.get("think", True)
                temperature = msg.get("temperature")

                # Reload tools from scripts on every chat (picks up new scripts at runtime)
                script_tools, tool_scripts = load_tools_from_scripts()
                all_tools = script_tools

                print(f"[chat] loaded {len(script_tools)} script tools", flush=True)

                try:
                    timeout = aiohttp.ClientTimeout(total=120, sock_read=60)
                    async with aiohttp.ClientSession(timeout=timeout) as http:
                        conversation = [
                            {
                                "role": "system",
                                "content": (
                                    "You control a Mac. Be very concise. "
                                    "For kill/quit/close app requests: call list_running_apps first, then kill the matching app. "
                                    "For other commands (sleep, wake, lock, volume, etc): execute immediately, no lookup needed."
                                ),
                            }
                        ] + list(messages)

                        last_tool_call = None
                        for round_idx in range(10):
                            print(f"[chat] round {round_idx}, msgs={len(conversation)}", flush=True)
                            payload = {
                                "model": model,
                                "messages": conversation,
                                "tools": all_tools,
                                "stream": True,
                                "think": think,
                            }
                            if temperature is not None:
                                payload["options"] = {"temperature": temperature}

                            accumulated = ""
                            tool_calls = None
                            had_error = False

                            async with http.post(
                                f"{OLLAMA_BASE}/api/chat", json=payload,
                            ) as resp:
                                if resp.status != 200:
                                    error_text = await resp.text()
                                    print(f"[chat] ollama error: {error_text}", flush=True)
                                    await websocket.send(json.dumps({
                                        "success": False,
                                        "error": f"Ollama error: {error_text}",
                                    }))
                                    had_error = True
                                else:
                                    async for line in resp.content:
                                        if not line:
                                            continue
                                        try:
                                            chunk = json.loads(line)
                                        except json.JSONDecodeError:
                                            continue
                                        msg_chunk = chunk.get("message", {})
                                        content = msg_chunk.get("content", "")
                                        done = chunk.get("done", False)

                                        tc = msg_chunk.get("tool_calls")
                                        if tc:
                                            tool_calls = tc
                                            print(f"[chat] tool_calls: {[t['function']['name'] for t in tc]}", flush=True)

                                        if content:
                                            accumulated += content
                                            await websocket.send(json.dumps({
                                                "success": True,
                                                "action": "ollama_chat",
                                                "data": content,
                                                "done": False,
                                            }))

                                        if done:
                                            print(f"[chat] done chunk, tool_calls={'yes' if tool_calls else 'no'}, len={len(accumulated)}", flush=True)
                                            break

                            if had_error:
                                break

                            if not tool_calls:
                                print(f"[chat] sending done to client", flush=True)
                                await websocket.send(json.dumps({
                                    "success": True,
                                    "action": "ollama_chat",
                                    "data": "",
                                    "done": True,
                                }))
                                break

                            conversation.append({
                                "role": "assistant",
                                "content": accumulated,
                                "tool_calls": tool_calls,
                            })

                            for tc in tool_calls:
                                fn = tc["function"]["name"]
                                fn_args = tc["function"]["arguments"]
                                this_call = (fn, json.dumps(fn_args, sort_keys=True))

                                if this_call == last_tool_call:
                                    print(f"[chat] skipping duplicate: {fn}", flush=True)
                                    result = "Already done (duplicate call skipped)."
                                elif fn in tool_scripts:
                                    print(f"[chat] executing: {fn}({fn_args})", flush=True)
                                    result = await asyncio.to_thread(execute_script, tool_scripts[fn], fn_args)
                                else:
                                    result = f"Unknown tool: {fn}"

                                last_tool_call = this_call

                                print(f"[chat] result: {result[:100]}", flush=True)

                                args_display = ", ".join(f"{k}={v}" for k, v in fn_args.items())
                                await websocket.send(json.dumps({
                                    "success": True,
                                    "action": "ollama_chat_tool",
                                    "data": f"{fn}({args_display})",
                                    "done": False,
                                }))
                                await websocket.send(json.dumps({
                                    "success": True,
                                    "action": "ollama_chat_tool",
                                    "data": result,
                                    "done": True,
                                }))

                                conversation.append({
                                    "role": "tool",
                                    "content": result,
                                })

                except (aiohttp.ClientError, asyncio.TimeoutError) as e:
                    await websocket.send(json.dumps({
                        "success": False,
                        "error": f"Ollama connection error: {e}" if isinstance(e, asyncio.TimeoutError) else "Cannot connect to Ollama. Is it running?",
                    }))
                except Exception as e:
                    try:
                        await websocket.send(json.dumps({
                            "success": False,
                            "error": f"Chat error: {str(e)}",
                        }))
                    except Exception:
                        pass

            elif action == "ping":
                await websocket.send(json.dumps({"success": True, "data": "pong"}))

            else:
                await websocket.send(json.dumps({
                    "success": False,
                    "error": f"Unknown action: {action}",
                }))

        except json.JSONDecodeError:
            await websocket.send(
                json.dumps({"success": False, "error": "Invalid JSON"})
            )
        except subprocess.TimeoutExpired:
            await websocket.send(
                json.dumps({"success": False, "error": "Command timed out"})
            )
        except Exception as e:
            await websocket.send(json.dumps({"success": False, "error": str(e)}))


async def main():
    tools, _ = load_tools_from_scripts()
    print("Remote Control server running on ws://0.0.0.0:8765")
    print(f"Allowed commands: {list(ALLOWED_COMMANDS.keys())}")
    print(f"Script tools: {[t['function']['name'] for t in tools]}")
    print(f"Meta tools: {[t['function']['name'] for t in META_TOOLS]}")
    print(f"Scripts dir: {SCRIPTS_DIR}")
    async with websockets.serve(handle, "0.0.0.0", 8765):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
