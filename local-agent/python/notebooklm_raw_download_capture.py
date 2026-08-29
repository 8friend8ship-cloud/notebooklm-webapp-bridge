#!/usr/bin/env python3
"""
NotebookLM / managed-Chrome raw download capture fallback.

Purpose:
- Never convert a downloaded binary asset to text.
- Watch a Chrome download folder for completed files.
- Verify file type from magic bytes.
- Copy raw bytes to a Google Drive Desktop-synced folder.
- Write an immutable JSON receipt with SHA-256, size and detected type.

No third-party packages required.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
import time
from pathlib import Path
from typing import Optional

PARTIAL_SUFFIXES = {".crdownload", ".part", ".tmp"}

MAGIC = (
    (b"\x89PNG\r\n\x1a\n", "image/png", ".png"),
    (b"\xff\xd8\xff", "image/jpeg", ".jpg"),
    (b"GIF87a", "image/gif", ".gif"),
    (b"GIF89a", "image/gif", ".gif"),
    (b"%PDF-", "application/pdf", ".pdf"),
    (b"PK\x03\x04", "application/zip", ".zip"),
    (b"ID3", "audio/mpeg", ".mp3"),
    (b"OggS", "application/ogg", ".ogg"),
    (b"RIFF", "application/riff", None),
)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def detect_type(path: Path) -> dict:
    with path.open("rb") as f:
        head = f.read(64)
    mime = "application/octet-stream"
    canonical_ext: Optional[str] = None

    if head.startswith(b"RIFF") and len(head) >= 12:
        if head[8:12] == b"WEBP":
            mime, canonical_ext = "image/webp", ".webp"
        elif head[8:12] == b"WAVE":
            mime, canonical_ext = "audio/wav", ".wav"
        elif head[8:12] == b"AVI ":
            mime, canonical_ext = "video/x-msvideo", ".avi"
    else:
        for sig, m, ext in MAGIC:
            if head.startswith(sig):
                mime, canonical_ext = m, ext
                break

    # ISO Base Media / MP4 family has an ftyp box at byte 4.
    # NotebookLM audio may use DASH/MP4 containers, so ftyp alone cannot tell
    # whether the payload is audio or video. Inspect early `hdlr` boxes and
    # prefer the actual media handler (`soun` / `vide`) when present.
    if len(head) >= 12 and head[4:8] == b"ftyp":
        brand = head[8:12]
        scan_limit = min(path.stat().st_size, 2 * 1024 * 1024)
        with path.open("rb") as f:
            probe = f.read(scan_limit)
        handlers = set()
        pos = 0
        while True:
            i = probe.find(b"hdlr", pos)
            if i < 0:
                break
            # FullBox: type(4) + version/flags(4) + pre_defined(4) + handler_type(4)
            handler = probe[i + 12:i + 16]
            if handler in {b"soun", b"vide"}:
                handlers.add(handler)
            pos = i + 4

        if b"vide" in handlers:
            mime, canonical_ext = ("video/quicktime", ".mov") if brand == b"qt  " else ("video/mp4", ".mp4")
        elif b"soun" in handlers:
            mime, canonical_ext = "audio/mp4", ".m4a"
        elif brand == b"qt  ":
            mime, canonical_ext = "video/quicktime", ".mov"
        else:
            mime, canonical_ext = "video/mp4", ".mp4"

    return {
        "mime": mime,
        "canonicalExtension": canonical_ext,
        "sourceExtension": path.suffix.lower(),
        "magicVerified": mime != "application/octet-stream",
    }

def is_complete_candidate(path: Path) -> bool:
    return (
        path.is_file()
        and path.suffix.lower() not in PARTIAL_SUFFIXES
        and not path.name.endswith(".receipt.json")
    )

def wait_stable(path: Path, checks: int = 3, interval: float = 0.5) -> bool:
    last = None
    same = 0
    for _ in range(max(checks * 3, 6)):
        if not path.exists() or not path.is_file():
            return False
        size = path.stat().st_size
        if size == last and size > 0:
            same += 1
            if same >= checks:
                return True
        else:
            same = 0
            last = size
        time.sleep(interval)
    return False

def newest_candidate(download_dir: Path, since: float = 0.0) -> Optional[Path]:
    candidates = []
    for p in download_dir.iterdir():
        if not is_complete_candidate(p):
            continue
        st = p.stat()
        if max(st.st_mtime, st.st_ctime) >= since:
            candidates.append((st.st_mtime, p))
    candidates.sort(reverse=True, key=lambda x: x[0])
    return candidates[0][1] if candidates else None

def unique_destination(dest_dir: Path, name: str) -> Path:
    target = dest_dir / name
    if not target.exists():
        return target
    stem, suffix = target.stem, target.suffix
    for i in range(1, 10000):
        alt = dest_dir / f"{stem}_{i}{suffix}"
        if not alt.exists():
            return alt
    raise RuntimeError("destination naming exhausted")

def capture_file(source: Path, dest_dir: Path) -> dict:
    if not wait_stable(source):
        raise RuntimeError(f"file did not become stable: {source}")
    dest_dir.mkdir(parents=True, exist_ok=True)

    src_hash = sha256_file(source)
    kind = detect_type(source)
    target = unique_destination(dest_dir, source.name)

    # Binary-preserving copy. Never decode/re-encode the payload.
    shutil.copy2(source, target)
    dst_hash = sha256_file(target)
    if src_hash != dst_hash or source.stat().st_size != target.stat().st_size:
        target.unlink(missing_ok=True)
        raise RuntimeError("binary integrity mismatch after copy")

    receipt = {
        "ok": True,
        "status": "RAW_BINARY_COPY_PASS",
        "sourcePath": str(source),
        "destinationPath": str(target),
        "sizeBytes": target.stat().st_size,
        "sha256": dst_hash,
        "detected": kind,
        "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    receipt_path = target.with_name(target.name + ".receipt.json")
    tmp = receipt_path.with_suffix(receipt_path.suffix + ".tmp")
    tmp.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, receipt_path)
    receipt["receiptPath"] = str(receipt_path)
    return receipt

def watch_once(download_dir: Path, dest_dir: Path, since: float, timeout: int) -> dict:
    deadline = time.time() + timeout
    while time.time() <= deadline:
        p = newest_candidate(download_dir, since)
        if p:
            return capture_file(p, dest_dir)
        time.sleep(1)
    return {"ok": False, "status": "NO_COMPLETED_DOWNLOAD_WITHIN_TIMEOUT"}

def self_test() -> dict:
    # Minimal valid PNG-like binary header + opaque payload; verifies byte-for-byte preservation.
    png = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + bytes(range(32)) + b"\x00IEND\xaeB`\x82"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        d = root / "Downloads"
        g = root / "DriveSync"
        d.mkdir()
        src = d / "fixture.png"
        src.write_bytes(png)
        result = capture_file(src, g)
        dst = Path(result["destinationPath"])
        assert dst.read_bytes() == png
        assert result["detected"]["mime"] == "image/png"
        assert result["sha256"] == hashlib.sha256(png).hexdigest()
        return {
            "ok": True,
            "status": "SELF_TEST_PASS",
            "sizeBytes": len(png),
            "sha256": result["sha256"],
            "mime": result["detected"]["mime"],
        }

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--download-dir")
    ap.add_argument("--drive-dir")
    ap.add_argument("--since", type=float, default=0.0)
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()

    if args.self_test:
        print(json.dumps(self_test(), ensure_ascii=False, indent=2))
        return 0

    if not args.download_dir or not args.drive_dir:
        ap.error("--download-dir and --drive-dir are required unless --self-test is used")

    result = watch_once(
        Path(args.download_dir).expanduser(),
        Path(args.drive_dir).expanduser(),
        args.since or time.time(),
        max(1, args.timeout),
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok") else 2

if __name__ == "__main__":
    raise SystemExit(main())
