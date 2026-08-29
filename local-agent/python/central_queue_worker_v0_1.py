#!/usr/bin/env python3
"""Central Agent Python local queue worker prototype.

Purpose: validate a Python execution lane without touching Chrome, OAuth, Flow,
or the real Drive queue. Fixture mode exercises the canonical state machine:
READY/RETRY -> CLAIMED -> STARTED -> DONE/ERROR, with ERROR/HOLD excluded from
claim eligibility. The real-device adapter can later replace the JSON store with
Drive/Sheets IO while keeping these transition rules.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

EXECUTABLE_STATES = {"READY", "RETRY"}
TERMINAL_STATES = {"DONE", "ERROR", "HOLD"}
VERSION = "PY_LOCAL_WORKER_V0_1_20260829"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class Receipt:
    ok: bool
    workerVersion: str
    taskId: str | None
    beforeStatus: str | None
    afterStatus: str | None
    claimed: bool
    started: bool
    commandExecuted: bool
    exitCode: int | None
    generatedAt: str
    error: str | None = None


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def choose_task(tasks: list[dict[str, Any]]) -> tuple[int, dict[str, Any]] | tuple[None, None]:
    for idx, task in enumerate(tasks):
        if str(task.get("status", "")).upper() in EXECUTABLE_STATES:
            return idx, task
    return None, None


def run_once(queue_path: Path, receipt_path: Path, execute: bool) -> int:
    doc = read_json(queue_path)
    tasks = doc.get("tasks", [])
    if not isinstance(tasks, list):
        raise ValueError("queue document must contain tasks[]")

    idx, task = choose_task(tasks)
    if task is None:
        receipt = Receipt(True, VERSION, None, None, None, False, False, False, None, now_iso())
        write_json(receipt_path, asdict(receipt))
        return 0

    before = str(task.get("status", "")).upper()
    task_id = str(task.get("taskId", "")) or None
    task["status"] = "CLAIMED"
    task["claimedAt"] = now_iso()
    write_json(queue_path, doc)

    task["status"] = "STARTED"
    task["startedAt"] = now_iso()
    write_json(queue_path, doc)

    executed = False
    exit_code: int | None = None
    error: str | None = None
    try:
        if execute:
            command = task.get("command")
            if not isinstance(command, list) or not command:
                raise ValueError("execute=true requires task.command as a non-empty argv list")
            cp = subprocess.run(command, check=False, timeout=int(task.get("timeoutSeconds", 60)))
            executed = True
            exit_code = int(cp.returncode)
            if exit_code != 0:
                raise RuntimeError(f"child exit {exit_code}")
        task["status"] = "DONE"
        task["completedAt"] = now_iso()
        task["result"] = {"workerVersion": VERSION, "mode": "EXECUTE" if execute else "FIXTURE_DRY_RUN"}
        ok = True
    except Exception as exc:
        task["status"] = "ERROR"
        task["completedAt"] = now_iso()
        task["error"] = str(exc)
        error = str(exc)
        ok = False
    write_json(queue_path, doc)

    receipt = Receipt(
        ok=ok,
        workerVersion=VERSION,
        taskId=task_id,
        beforeStatus=before,
        afterStatus=task["status"],
        claimed=True,
        started=True,
        commandExecuted=executed,
        exitCode=exit_code,
        generatedAt=now_iso(),
        error=error,
    )
    write_json(receipt_path, asdict(receipt))
    return 0 if ok else 1


def self_test() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        queue = root / "queue.json"
        receipt = root / "receipt.json"
        fixture = {
            "tasks": [
                {"taskId": "E1", "status": "ERROR"},
                {"taskId": "H1", "status": "HOLD"},
                {"taskId": "R1", "status": "READY"},
                {"taskId": "R2", "status": "READY"},
            ]
        }
        write_json(queue, fixture)
        rc = run_once(queue, receipt, execute=False)
        if rc != 0:
            raise AssertionError(f"run_once returned {rc}")
        out = read_json(queue)
        statuses = {t["taskId"]: t["status"] for t in out["tasks"]}
        if statuses != {"E1": "ERROR", "H1": "HOLD", "R1": "DONE", "R2": "READY"}:
            raise AssertionError(f"unexpected transitions: {statuses}")
        r = read_json(receipt)
        if not (r["ok"] and r["taskId"] == "R1" and r["claimed"] and r["started"] and r["afterStatus"] == "DONE"):
            raise AssertionError(f"bad receipt: {r}")

        # Verify non-zero child exits fail closed to ERROR and do not auto-retry it.
        fixture2 = {"tasks": [{"taskId": "X1", "status": "READY", "command": [sys.executable, "-c", "import sys;sys.exit(7)"]}]}
        write_json(queue, fixture2)
        rc = run_once(queue, receipt, execute=True)
        if rc != 1:
            raise AssertionError(f"expected failure rc=1, got {rc}")
        out2 = read_json(queue)
        if out2["tasks"][0]["status"] != "ERROR":
            raise AssertionError(f"failed child was not fail-closed: {out2}")
        # second pass must not claim ERROR again
        rc2 = run_once(queue, receipt, execute=False)
        if rc2 != 0 or read_json(queue)["tasks"][0]["status"] != "ERROR":
            raise AssertionError("ERROR task was retried without explicit RETRY")

    print(json.dumps({"ok": True, "version": VERSION, "tests": ["READY_TO_DONE", "ERROR_HOLD_SKIPPED", "CHILD_FAILURE_TO_ERROR", "NO_ERROR_AUTORETRY"]}))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--queue")
    ap.add_argument("--receipt")
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if not args.queue or not args.receipt:
        ap.error("--queue and --receipt are required unless --self-test is used")
    return run_once(Path(args.queue), Path(args.receipt), execute=args.execute)


if __name__ == "__main__":
    raise SystemExit(main())
