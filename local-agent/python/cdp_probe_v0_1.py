#!/usr/bin/env python3
"""Read-only Chrome DevTools Protocol endpoint probe.
No navigation, clicks, Generate actions, credentials, browser restart, or writes.
"""
from __future__ import annotations

import argparse
import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

VERSION = "PY_CDP_PROBE_V0_1_20260829"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_json(url: str, timeout: float) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": VERSION})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def probe(host: str, port: int, timeout: float = 3.0) -> dict[str, Any]:
    base = f"http://{host}:{port}"
    out: dict[str, Any] = {
        "ok": False,
        "version": VERSION,
        "host": host,
        "port": port,
        "generatedAt": now_iso(),
        "readOnly": True,
        "browserMutated": False,
        "navigationPerformed": False,
        "generateClicked": False,
        "credentialsTouched": False,
    }
    try:
        version_info = get_json(base + "/json/version", timeout)
        targets = get_json(base + "/json", timeout)
        pages = []
        for t in targets if isinstance(targets, list) else []:
            if t.get("type") != "page":
                continue
            pages.append({
                "id": t.get("id"),
                "title": t.get("title"),
                "url": t.get("url"),
                "webSocketDebuggerUrl": t.get("webSocketDebuggerUrl"),
            })
        out.update({
            "ok": True,
            "browser": version_info.get("Browser"),
            "protocolVersion": version_info.get("Protocol-Version"),
            "pageCount": len(pages),
            "pages": pages,
        })
    except Exception as exc:
        out["error"] = str(exc)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--timeout", type=float, default=3.0)
    ap.add_argument("--out")
    args = ap.parse_args()
    result = probe(args.host, args.port, args.timeout)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.out:
        p = Path(args.out)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    print(text)
    return 0 if result["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
