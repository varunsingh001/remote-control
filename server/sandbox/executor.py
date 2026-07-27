import io
import multiprocessing
import sys

from flask import Flask, jsonify, request

import collections
import datetime
import functools
import itertools
import json as json_mod
import math
import re
import statistics

import numpy as np
import pandas as pd
import scipy
import sympy

app = Flask(__name__)

BLOCKED_IMPORTS = {
    "subprocess", "ctypes", "socket", "signal", "shutil",
    "pip", "ensurepip", "importlib", "webbrowser", "antigravity",
    "turtle", "tkinter", "multiprocessing", "threading",
}

BLOCKED_PATTERNS = [
    "os.system", "os.popen", "os.exec", "os.spawn", "os.fork",
    "os.kill", "os.remove", "os.unlink", "os.rmdir", "os.rename",
    "os.makedirs", "os.mkdir", "os.chmod", "os.chown",
    "__import__",
]


def validate(code):
    for line in code.split("\n"):
        s = line.strip()
        if s.startswith("import ") or s.startswith("from "):
            for mod in BLOCKED_IMPORTS:
                if mod in s.split():
                    return f"import '{mod}' is not allowed"
                if s.startswith(f"from {mod}"):
                    return f"import '{mod}' is not allowed"
    for pat in BLOCKED_PATTERNS:
        if pat in code:
            return f"'{pat}' is not allowed"
    return None


NAMESPACE_TEMPLATE = {
    "math": math, "re": re, "json": json_mod,
    "datetime": datetime, "statistics": statistics,
    "collections": collections, "itertools": itertools,
    "functools": functools,
    "np": np, "numpy": np,
    "pd": pd, "pandas": pd,
    "scipy": scipy, "sympy": sympy,
}


def _run(code):
    buf = io.StringIO()
    err = io.StringIO()
    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = buf, err
    try:
        ns = dict(NAMESPACE_TEMPLATE)
        exec(code, ns)
        return {
            "success": True,
            "output": buf.getvalue()[:50000],
            "stderr": err.getvalue()[:5000],
        }
    except Exception as e:
        return {
            "success": False,
            "output": buf.getvalue()[:50000],
            "error": f"{type(e).__name__}: {e}",
        }
    finally:
        sys.stdout, sys.stderr = old_out, old_err


pool = multiprocessing.Pool(processes=2, maxtasksperchild=1)


@app.route("/execute", methods=["POST"])
def execute():
    data = request.json
    code = data.get("code", "")
    timeout = min(data.get("timeout", 30), 60)

    err = validate(code)
    if err:
        return jsonify({"success": False, "error": err})

    try:
        result = pool.apply_async(_run, (code,)).get(timeout=timeout)
        return jsonify(result)
    except multiprocessing.TimeoutError:
        return jsonify({"success": False, "error": f"Timed out after {timeout}s"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8050)
