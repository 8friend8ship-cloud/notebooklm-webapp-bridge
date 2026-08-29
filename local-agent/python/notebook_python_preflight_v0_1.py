#!/usr/bin/env python3
"""Notebook read-only Python/CDP preflight.

Checks the active Python runtime and whether the existing dedicated Chrome/CFT CDP
ports 9223 (NotebookLM) and 9224 (Flow) expose readable DevTools endpoints.
It does not start/restart browsers, navigate, click, Generate, access credentials,
or change OAuth/settings. Writes a syncable JSON receipt when CentralRoot exists.
"""
from __future__ import annotations

import argparse
import json
import platform
import sys
from pathlib import Path

from cdp_probe_v0_1 import probe

VERSION = "PY_NOTEBOOK_PREFLIGHT_V0_1_20260829"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--central-root", default=r"G:\내 드라이브\00_중앙에이전트")
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--out")
    args = ap.parse_args()

    checks = {
        "9223": probe("127.0.0.1", 9223, args.timeout),
        "9224": probe("127.0.0.1", 9224, args.timeout),
    }
    body = {
        "ok": True,
        "version": VERSION,
        "pythonVersion": platform.python_version(),
        "pythonExecutable": sys.executable,
        "platform": platform.platform(),
        "readOnly": True,
        "browserMutated": False,
        "browserRestarted": False,
        "navigationPerformed": False,
        "generateClicked": False,
        "credentialsTouched": False,
        "cdp": checks,
        "realNotebookRuntimePass": bool(checks["9223"].get("ok") or checks["9224"].get("ok")),
    }

    if args.out:
        out = Path(args.out)
    else:
        out = Path(args.central_root) / "Runtime_Readback" / "PYTHON" / "PY_NOTEBOOK_PREFLIGHT_V0_1.json"
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(body, ensure_ascii=False, indent=2), encoding="utf-8")
        body["receiptPath"] = str(out)
    except Exception as exc:
        body["receiptWriteError"] = str(exc)
        body["ok"] = False

    print(json.dumps(body, ensure_ascii=False, indent=2))
    # Python runtime itself is valid even if both CDP ports are currently unavailable.
    return 0 if body["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
