#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "notebooklm_raw_download_capture.py"
spec = importlib.util.spec_from_file_location("rawcap", MODULE_PATH)
rawcap = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(rawcap)


def check(cond: bool, name: str):
    if not cond:
        raise AssertionError(name)
    print(f"PASS {name}")


def main():
    fixtures = {
        "png": ("sample.png", b"\x89PNG\r\n\x1a\n" + b"\x00"*80, "image/png"),
        "jpeg": ("sample.jpg", b"\xff\xd8\xff\xe0" + b"\x00"*80, "image/jpeg"),
        "webp": ("sample.webp", b"RIFF" + (32).to_bytes(4,"little") + b"WEBP" + b"\x00"*40, "image/webp"),
        "pdf": ("sample.pdf", b"%PDF-1.7\n" + b"\x00"*80, "application/pdf"),
        "mp3": ("sample.mp3", b"ID3" + b"\x04\x00\x00" + b"\x00"*80, "audio/mpeg"),
        "wav": ("sample.wav", b"RIFF" + (32).to_bytes(4,"little") + b"WAVE" + b"\x00"*40, "audio/wav"),
        "mp4": ("sample.mp4", b"\x00\x00\x00\x18ftypisom" + b"\x00"*64, "video/mp4"),
        "unknown": ("sample.bin", b"\x01\x02\x03\x04" + b"\x99"*80, "application/octet-stream"),
    }
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        downloads = root / "Downloads"
        drive = root / "Drive"
        downloads.mkdir()
        drive.mkdir()

        for label, (name, payload, expected_mime) in fixtures.items():
            src = downloads / name
            src.write_bytes(payload)
            result = rawcap.capture_file(src, drive)
            dst = Path(result["destinationPath"])
            check(dst.read_bytes() == payload, f"{label}:binary-preserved")
            check(result["sha256"] == hashlib.sha256(payload).hexdigest(), f"{label}:sha256")
            check(result["detected"]["mime"] == expected_mime, f"{label}:mime")

        duplicate = rawcap.capture_file(downloads / "sample.png", drive)
        check(Path(duplicate["destinationPath"]).name == "sample_1.png", "duplicate-name")

        partial = downloads / "never-copy.crdownload"
        partial.write_bytes(b"\x89PNG\r\n\x1a\n" + b"x"*40)
        candidate = rawcap.newest_candidate(downloads, since=partial.stat().st_mtime - 0.1)
        check(candidate is None or candidate.name != partial.name, "partial-file-excluded")

        receipt = json.loads(Path(duplicate["receiptPath"]).read_text(encoding="utf-8"))
        check(receipt["status"] == "RAW_BINARY_COPY_PASS", "receipt-status")
        check(receipt["sha256"] == duplicate["sha256"], "receipt-sha")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        downloads = root / "Downloads"
        drive = root / "Drive"
        downloads.mkdir()
        payload = b"\x89PNG\r\n\x1a\n" + b"A"*1024
        since = time.time()

        def chrome_like_producer():
            time.sleep(0.8)
            part = downloads / "notebook-result.png.crdownload"
            part.write_bytes(payload[:400])
            time.sleep(0.4)
            with part.open("ab") as f:
                f.write(payload[400:])
            time.sleep(0.4)
            part.rename(downloads / "notebook-result.png")

        t = threading.Thread(target=chrome_like_producer)
        t.start()
        result = rawcap.watch_once(downloads, drive, since=since, timeout=8)
        t.join()

        check(result["ok"], "chrome-rename:captured")
        dst = Path(result["destinationPath"])
        check(dst.read_bytes() == payload, "chrome-rename:binary-preserved")
        check(result["sha256"] == hashlib.sha256(payload).hexdigest(), "chrome-rename:sha256")
        check(result["detected"]["mime"] == "image/png", "chrome-rename:mime")
        check(not any(p.suffix.lower() == ".crdownload" for p in drive.iterdir()), "chrome-rename:no-partial-in-drive")

    print("ALL_TESTS_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
