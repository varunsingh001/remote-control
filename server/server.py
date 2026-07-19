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
HF_CACHE_DIR = os.path.expanduser("~/.cache/huggingface/hub")
MLX_LM_SERVER_CMD = "/opt/miniconda3/bin/mlx_lm.server"
MLX_PORT = 8085

mlx_process = None
mlx_loaded_model = None
mlx_ready = False
mlx_lock = asyncio.Lock()



def discover_mlx_models():
    models = []
    if not os.path.isdir(HF_CACHE_DIR):
        return models
    for dirname in sorted(os.listdir(HF_CACHE_DIR)):
        if not dirname.startswith("models--mlx-community--"):
            continue
        model_id = dirname.replace("models--", "", 1).replace("--", "/", 1)
        snapshots = os.path.join(HF_CACHE_DIR, dirname, "snapshots")
        if not os.path.isdir(snapshots):
            continue
        snaps = os.listdir(snapshots)
        if not snaps:
            continue
        snap_path = os.path.join(snapshots, snaps[0])
        files = os.listdir(snap_path)
        if not any(f.endswith(".safetensors") for f in files):
            continue

        total_size = sum(
            os.path.getsize(os.path.join(snap_path, f))
            for f in files if f.endswith(".safetensors")
        )

        config = {}
        config_path = os.path.join(snap_path, "config.json")
        if os.path.exists(config_path):
            with open(config_path) as cf:
                try:
                    config = json.load(cf)
                except json.JSONDecodeError:
                    pass

        model_base = model_id.split("/")[-1]
        quant = ""
        for q in ["2bit", "3bit", "4bit", "6bit", "8bit"]:
            if q in model_base.lower():
                quant = q
                break

        param_match = re.search(r"-(\d+(?:\.\d+)?[bB])(?:-|$)", model_base)
        param_size = param_match.group(1).upper() if param_match else ""

        models.append({
            "name": model_id,
            "size": total_size,
            "modified_at": "",
            "family": config.get("model_type", ""),
            "parameter_size": param_size,
            "quantization": quant,
            "source": "mlx",
        })
    return models


async def stop_mlx_server():
    global mlx_process, mlx_loaded_model, mlx_ready

    async with mlx_lock:
        if mlx_process and mlx_process.poll() is None:
            print(f"[mlx] unloading model {mlx_loaded_model}", flush=True)
            mlx_process.terminate()
            try:
                mlx_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                mlx_process.kill()
        mlx_process = None
        mlx_loaded_model = None
        mlx_ready = False


async def ensure_mlx_server(model_name):
    global mlx_process, mlx_loaded_model, mlx_ready

    async with mlx_lock:
        if (mlx_process and mlx_process.poll() is None
                and mlx_loaded_model == model_name and mlx_ready):
            return True

        mlx_ready = False

        if mlx_process and mlx_process.poll() is None:
            print(f"[mlx] stopping server (was running {mlx_loaded_model})", flush=True)
            mlx_process.terminate()
            try:
                mlx_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                mlx_process.kill()

        if not os.path.exists(MLX_LM_SERVER_CMD):
            print(f"[mlx] mlx_lm.server not found at {MLX_LM_SERVER_CMD}", flush=True)
            return False

        print(f"[mlx] starting server with {model_name}...", flush=True)
        mlx_process = subprocess.Popen(
            [MLX_LM_SERVER_CMD, "--model", model_name,
             "--port", str(MLX_PORT), "--host", "0.0.0.0",
             "--prompt-cache-bytes", str(4 * 1024 * 1024 * 1024)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        mlx_loaded_model = model_name

        for i in range(120):
            if mlx_process.poll() is not None:
                print(f"[mlx] server exited with code {mlx_process.returncode}", flush=True)
                mlx_loaded_model = None
                return False
            try:
                check_timeout = aiohttp.ClientTimeout(total=2)
                async with aiohttp.ClientSession(timeout=check_timeout) as sess:
                    async with sess.get(f"http://localhost:{MLX_PORT}/v1/models") as resp:
                        if resp.status == 200:
                            print(f"[mlx] server ready (took {i + 1}s)", flush=True)
                            mlx_ready = True
                            return True
            except Exception:
                pass
            await asyncio.sleep(1)

        print("[mlx] server failed to start within 120s", flush=True)
        return False


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
        if len(output) > 8000:
            output = output[:8000] + "... (truncated)"
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


SYSTEM_PROMPT = (
    "You control a Mac. Be very concise. "
    "For kill/quit/close app requests: call list_running_apps first, then kill the matching app. "
    "For other commands (sleep, wake, lock, volume, etc): execute immediately, no lookup needed."
)


async def handle_ollama_chat(websocket, model, messages, all_tools, tool_scripts, think, temperature):
    try:
        timeout = aiohttp.ClientTimeout(total=120, sock_read=60)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            conversation = [{"role": "system", "content": SYSTEM_PROMPT}] + list(messages)

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

                async with http.post(f"{OLLAMA_BASE}/api/chat", json=payload) as resp:
                    if resp.status != 200:
                        error_text = await resp.text()
                        print(f"[chat] ollama error: {error_text}", flush=True)
                        await websocket.send(json.dumps({
                            "success": False,
                            "error": f"Ollama error: {error_text}",
                        }))
                        had_error = True
                    else:
                        in_thinking = False
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
                                    "thinking": False,
                                }))

                            thinking_content = msg_chunk.get("thinking", "")
                            if thinking_content:
                                if not in_thinking:
                                    in_thinking = True
                                await websocket.send(json.dumps({
                                    "success": True,
                                    "action": "ollama_chat",
                                    "data": thinking_content,
                                    "done": False,
                                    "thinking": True,
                                }))

                            if done:
                                in_thinking = False
                                print(f"[chat] done chunk, tool_calls={'yes' if tool_calls else 'no'}, len={len(accumulated)}", flush=True)
                                break

                if had_error:
                    break

                if not tool_calls:
                    print("[chat] sending done to client", flush=True)
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

                    conversation.append({"role": "tool", "content": result})

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


async def handle_mlx_chat(websocket, model, messages, all_tools, tool_scripts, temperature):
    ready = await ensure_mlx_server(model)
    if not ready:
        await websocket.send(json.dumps({
            "success": False,
            "error": f"MLX server failed to start for {model}",
        }))
        return

    try:
        timeout = aiohttp.ClientTimeout(total=300, sock_read=120)
        async with aiohttp.ClientSession(timeout=timeout) as http:
            recent_messages = list(messages)[-20:]
            conversation = [{"role": "system", "content": SYSTEM_PROMPT}] + recent_messages

            last_tool_call = None
            for round_idx in range(10):
                print(f"[mlx] round {round_idx}, msgs={len(conversation)}", flush=True)

                payload = {
                    "model": model,
                    "messages": conversation,
                    "stream": True,
                    "max_tokens": 2048,
                }
                if all_tools:
                    payload["tools"] = all_tools
                if temperature is not None:
                    payload["temperature"] = temperature

                accumulated = ""
                tool_calls_acc = {}
                had_error = False

                async with http.post(
                    f"http://localhost:{MLX_PORT}/v1/chat/completions", json=payload,
                ) as resp:
                    if resp.status != 200:
                        error_text = await resp.text()
                        print(f"[mlx] error: {error_text}", flush=True)
                        await websocket.send(json.dumps({
                            "success": False,
                            "error": f"MLX error: {error_text}",
                        }))
                        had_error = True
                    else:
                        while True:
                            line_bytes = await resp.content.readline()
                            if not line_bytes:
                                break
                            line = line_bytes.decode().strip()
                            if not line or not line.startswith("data: "):
                                continue
                            data_str = line[6:]
                            if data_str == "[DONE]":
                                break

                            try:
                                chunk = json.loads(data_str)
                            except json.JSONDecodeError:
                                continue

                            choices = chunk.get("choices", [])
                            if not choices:
                                continue
                            delta = choices[0].get("delta", {})
                            content = delta.get("content", "")

                            tc_deltas = delta.get("tool_calls")
                            if tc_deltas:
                                for tcd in tc_deltas:
                                    idx = tcd.get("index", 0)
                                    if idx not in tool_calls_acc:
                                        tool_calls_acc[idx] = {
                                            "id": tcd.get("id", f"call_{round_idx}_{idx}"),
                                            "function": {"name": "", "arguments": ""},
                                        }
                                    fn_d = tcd.get("function", {})
                                    if fn_d.get("name"):
                                        tool_calls_acc[idx]["function"]["name"] += fn_d["name"]
                                    if fn_d.get("arguments"):
                                        tool_calls_acc[idx]["function"]["arguments"] += fn_d["arguments"]

                            if content:
                                accumulated += content
                                await websocket.send(json.dumps({
                                    "success": True,
                                    "action": "ollama_chat",
                                    "data": content,
                                    "done": False,
                                    "thinking": False,
                                }))

                if had_error:
                    break

                if not tool_calls_acc:
                    print("[mlx] sending done to client", flush=True)
                    await websocket.send(json.dumps({
                        "success": True,
                        "action": "ollama_chat",
                        "data": "",
                        "done": True,
                    }))
                    break

                assistant_tool_calls = []
                for idx in sorted(tool_calls_acc):
                    tc = tool_calls_acc[idx]
                    assistant_tool_calls.append({
                        "id": tc["id"],
                        "type": "function",
                        "function": {
                            "name": tc["function"]["name"],
                            "arguments": tc["function"]["arguments"],
                        },
                    })
                conversation.append({
                    "role": "assistant",
                    "content": accumulated or None,
                    "tool_calls": assistant_tool_calls,
                })

                for idx in sorted(tool_calls_acc):
                    tc = tool_calls_acc[idx]
                    fn = tc["function"]["name"]
                    try:
                        fn_args = json.loads(tc["function"]["arguments"])
                    except (json.JSONDecodeError, TypeError):
                        fn_args = {}
                    this_call = (fn, json.dumps(fn_args, sort_keys=True))

                    if this_call == last_tool_call:
                        print(f"[mlx] skipping duplicate: {fn}", flush=True)
                        result = "Already done (duplicate call skipped)."
                    elif fn in tool_scripts:
                        print(f"[mlx] executing: {fn}({fn_args})", flush=True)
                        result = await asyncio.to_thread(execute_script, tool_scripts[fn], fn_args)
                    else:
                        result = f"Unknown tool: {fn}"

                    last_tool_call = this_call
                    print(f"[mlx] result: {result[:100]}", flush=True)

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
                        "tool_call_id": tc["id"],
                        "content": result,
                    })

    except (aiohttp.ClientError, asyncio.TimeoutError) as e:
        await websocket.send(json.dumps({
            "success": False,
            "error": f"MLX connection error: {e}",
        }))
    except Exception as e:
        try:
            await websocket.send(json.dumps({
                "success": False,
                "error": f"MLX chat error: {str(e)}",
            }))
        except Exception:
            pass


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
                models = []
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(f"{OLLAMA_BASE}/api/tags") as resp:
                            if resp.status == 200:
                                body = await resp.json()
                                for m in body.get("models", []):
                                    models.append({
                                        "name": m.get("name", ""),
                                        "size": m.get("size", 0),
                                        "modified_at": m.get("modified_at", ""),
                                        "family": m.get("details", {}).get("family", ""),
                                        "parameter_size": m.get("details", {}).get("parameter_size", ""),
                                        "quantization": m.get("details", {}).get("quantization_level", ""),
                                        "source": "ollama",
                                    })
                except aiohttp.ClientError:
                    pass

                models.extend(discover_mlx_models())

                if models:
                    await websocket.send(json.dumps({
                        "success": True,
                        "action": "ollama_list_models",
                        "data": json.dumps(models),
                    }))
                else:
                    await websocket.send(json.dumps({
                        "success": False,
                        "error": "No models found. Is Ollama running?",
                    }))

            elif action == "ollama_chat":
                model = msg.get("model")
                messages = msg.get("messages", [])
                think = msg.get("think", True)
                temperature = msg.get("temperature")

                script_tools, tool_scripts = load_tools_from_scripts()
                all_tools = script_tools
                print(f"[chat] loaded {len(script_tools)} script tools", flush=True)

                mlx_model_names = {m["name"] for m in discover_mlx_models()}
                if model in mlx_model_names:
                    await handle_mlx_chat(websocket, model, messages, all_tools, tool_scripts, temperature)
                else:
                    await stop_mlx_server()
                    await handle_ollama_chat(websocket, model, messages, all_tools, tool_scripts, think, temperature)

            elif action == "unload_model":
                source = msg.get("source")
                if source == "mlx":
                    await stop_mlx_server()
                    await websocket.send(json.dumps({
                        "success": True,
                        "action": "unload_model",
                        "data": "MLX model unloaded",
                    }))
                elif source == "ollama":
                    model = msg.get("model")
                    if model:
                        try:
                            async with aiohttp.ClientSession() as session:
                                async with session.post(
                                    f"{OLLAMA_BASE}/api/generate",
                                    json={"model": model, "keep_alive": 0},
                                ) as resp:
                                    await resp.read()
                        except Exception:
                            pass
                    await websocket.send(json.dumps({
                        "success": True,
                        "action": "unload_model",
                        "data": f"Ollama model {model} unloaded",
                    }))
                else:
                    await websocket.send(json.dumps({
                        "success": True,
                        "action": "unload_model",
                        "data": "No model to unload",
                    }))

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
    mlx_models = discover_mlx_models()

    print("Remote Control server starting...")
    print(f"Allowed commands: {list(ALLOWED_COMMANDS.keys())}")
    print(f"Script tools: {[t['function']['name'] for t in tools]}")
    print(f"Meta tools: {[t['function']['name'] for t in META_TOOLS]}")
    print(f"Scripts dir: {SCRIPTS_DIR}")
    print(f"MLX models: {[m['name'] for m in mlx_models]}")

    if mlx_models:
        asyncio.create_task(ensure_mlx_server(mlx_models[0]["name"]))

    async with websockets.serve(handle, "0.0.0.0", 8765, max_size=100 * 1024 * 1024):
        print("Remote Control server running on ws://0.0.0.0:8765")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
