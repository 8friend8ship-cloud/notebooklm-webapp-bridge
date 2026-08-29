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
        "png": ("sample.png", b"\x89PNG\r\n\x1a\n" + b"\x00"*80, "image/png", "image"),
        "jpeg": ("sample.jpg", b"\xff\xd8\xff\xe0" + b"\x00"*80, "image/jpeg", "image"),
        "webp": ("sample.webp", b"RIFF" + (32).to_bytes(4,"little") + b"WEBP" + b"\x00"*40, "image/webp", "image"),
        "pdf": ("sample.pdf", b"%PDF-1.7\n" + b"\x00"*80, "application/pdf", "document"),
        "mp3": ("sample.mp3", b"ID3" + b"\x04\x00\x00" + b"\x00"*80, "audio/mpeg", "audio"),
        "wav": ("sample.wav", b"RIFF" + (32).to_bytes(4,"little") + b"WAVE" + b"\x00"*40, "audio/wav", "audio"),
        "mp4": ("sample.mp4", b"\x00\x00\x00\x18ftypisom" + b"\x00"*24 + b"hdlr" + b"\x00"*8 + b"vide" + b"\x00"*64, "video/mp4", "video"),
        "m4a": ("sample.m4a", b"\x00\x00\x00\x18ftypdash" + b"\x00"*24 + b"hdlr" + b"\x00"*8 + b"soun" + b"\x00"*64, "audio/mp4", "audio"),
        "unknown": ("sample.bin", b"\x01\x02\x03\x04" + b"\x99"*80, "application/octet-stream", "unknown"),
    }
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        downloads = root / "Downloads"
        drive = root / "Drive"
        downloads.mkdir()
        drive.mkdir()

        for label, (name, payload, expected_mime, family) in fixtures.items():
            src = downloads / name
            src.write_bytes(payload)
            result = rawcap.capture_file(src, drive)
            dst = Path(result["destinationPath"])
            check(dst.read_bytes() == payload, f"{label}:binary-preserved")
            check(result["sha256"] == hashlib.sha256(payload).hexdigest(), f"{label}:sha256")
            check(result["detected"]["mime"] == expected_mime, f"{label}:mime")
            check(result["detectedMediaFamily"] == family, f"{label}:family")
            check(result["sourceImmutableVerified"], f"{label}:source-immutable")

        duplicate = rawcap.capture_file(downloads / "sample.png", drive, expected_media="image")
        check(Path(duplicate["destinationPath"]).name == "sample_1.png", "duplicate-name")

        try:
            rawcap.capture_file(downloads / "sample.m4a", drive, expected_media="video")
            raise AssertionError("wrong media family accepted")
        except RuntimeError as exc:
            check("media family mismatch" in str(exc), "wrong-media-fail-closed")

        generic_png = downloads / "generic-image.dat"
        generic_payload = b"\x89PNG\r\n\x1a\n" + b"Z"*100
        generic_png.write_bytes(generic_payload)
        repaired = rawcap.capture_file(
            generic_png, drive, expected_media="image", repair_generic_image_extension=True
        )
        repaired_path = Path(repaired["destinationPath"])
        check(repaired_path.suffix == ".png", "generic-image-extension-repaired")
        check(repaired_path.read_bytes() == generic_payload, "generic-image-repair-binary-preserved")

        generic_audio = downloads / "generic-audio.bin"
        generic_audio.write_bytes(b"ID3" + b"A"*100)
        no_repair = rawcap.capture_file(generic_audio, drive, expected_media="audio")
        check(Path(no_repair["destinationPath"]).suffix == ".bin", "generic-audio-not-renamed")

        partial = downloads / "never-copy.crdownload"
        partial.write_bytes(b"\x89PNG\r\n\x1a\n" + b"x"*40)
        candidate = rawcap.newest_candidate(downloads, since=partial.stat().st_mtime - 0.1)
        check(candidate is None or candidate.name != partial.name, "partial-file-excluded")

        receipt = json.loads(Path(duplicate["receiptPath"]).read_text(encoding="utf-8"))
        check(receipt["status"] == "RAW_BINARY_COPY_PASS", "receipt-status")
        check(receipt["sourceSha256"] == duplicate["sha256"], "receipt-source-sha")
        check(receipt["destinationSha256"] == duplicate["sha256"], "receipt-destination-sha")

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        downloads = root / "Downloads"
        drive = root / "Drive"
        downloads.mkdir()
        payload = b"\x89PNG\r\n\x1a\n" + b"A"*1024
        since = time.time()
        (downloads / "unrelated.txt").write_text("distractor", encoding="utf-8")

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
        result = rawcap.watch_once(
            downloads, drive, since=since, timeout=8,
            expected_name="notebook-result.png", expected_media="image"
        )
        t.join()

        check(result["ok"], "chrome-rename:captured")
        dst = Path(result["destinationPath"])
        check(dst.read_bytes() == payload, "chrome-rename:binary-preserved")
        check(result["sha256"] == hashlib.sha256(payload).hexdigest(), "chrome-rename:sha256")
        check(result["detected"]["mime"] == "image/png", "chrome-rename:mime")
        check(result["sourceImmutableVerified"], "chrome-rename:source-immutable")
        check(not any(p.suffix.lower() == ".crdownload" for p in drive.iterdir()), "chrome-rename:no-partial-in-drive")

    print("ALL_TESTS_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
