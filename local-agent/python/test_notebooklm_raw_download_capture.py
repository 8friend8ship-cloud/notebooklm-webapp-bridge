#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import threading
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / 'notebooklm_raw_download_capture.py'
spec = importlib.util.spec_from_file_location('rawcap', MODULE_PATH)
rawcap = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(rawcap)

COUNT = 0

def check(cond: bool, name: str):
    global COUNT
    if not cond:
        raise AssertionError(name)
    COUNT += 1
    print(f'PASS {name}')


def write_ooxml(path: Path, kind: str):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', '<Types/>')
        if kind == 'docx':
            zf.writestr('word/document.xml', '<document/>')
        elif kind == 'xlsx':
            zf.writestr('xl/workbook.xml', '<workbook/>')
        elif kind == 'pptx':
            zf.writestr('ppt/presentation.xml', '<presentation/>')
        else:
            raise AssertionError(kind)


def main():
    fixtures = {
        'png': ('sample.png', b'\x89PNG\r\n\x1a\n' + b'\x00'*80, 'image/png', 'image'),
        'jpeg': ('sample.jpg', b'\xff\xd8\xff\xe0' + b'\x00'*80, 'image/jpeg', 'image'),
        'webp': ('sample.webp', b'RIFF' + (32).to_bytes(4,'little') + b'WEBP' + b'\x00'*40, 'image/webp', 'image'),
        'pdf': ('sample.pdf', b'%PDF-1.7\n' + b'\x00'*80, 'application/pdf', 'document'),
        'mp3': ('sample.mp3', b'ID3' + b'\x04\x00\x00' + b'\x00'*80, 'audio/mpeg', 'audio'),
        'wav': ('sample.wav', b'RIFF' + (32).to_bytes(4,'little') + b'WAVE' + b'\x00'*40, 'audio/wav', 'audio'),
        'mp4': ('sample.mp4', b'\x00\x00\x00\x18ftypisom' + b'\x00'*24 + b'hdlr' + b'\x00'*8 + b'vide' + b'\x00'*64, 'video/mp4', 'video'),
        'm4a': ('sample.m4a', b'\x00\x00\x00\x18ftypdash' + b'\x00'*24 + b'hdlr' + b'\x00'*8 + b'soun' + b'\x00'*64, 'audio/mp4', 'audio'),
        'json': ('sample.json', b'{"ok":true,"n":1}\n', 'application/json', 'data'),
        'csv': ('sample.csv', b'a,b\n1,2\n3,4\n', 'text/csv', 'data'),
        'txt': ('sample.txt', b'plain utf8 text\n', 'text/plain', 'text'),
        'unknown': ('sample.bin', b'\x01\x02\x03\x04' + b'\x99'*80, 'application/octet-stream', 'unknown'),
    }
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        downloads = root / 'Downloads'
        drive = root / 'Drive'
        downloads.mkdir(); drive.mkdir()

        for label, (name, payload, expected_mime, family) in fixtures.items():
            src = downloads / name
            src.write_bytes(payload)
            result = rawcap.capture_file(src, drive)
            dst = Path(result['destinationPath'])
            check(dst.read_bytes() == payload, f'{label}:binary-preserved')
            check(result['sha256'] == hashlib.sha256(payload).hexdigest(), f'{label}:sha256')
            check(result['detected']['mime'] == expected_mime, f'{label}:mime')
            check(result['detectedMediaFamily'] == family, f'{label}:family')
            check(result['sourceImmutableVerified'], f'{label}:source-immutable')
            check(result['payloadMutation'] is False, f'{label}:no-payload-mutation')

        ooxml_cases = {
            'docx': ('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'document', 'OOXML_WORD'),
            'xlsx': ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'spreadsheet', 'OOXML_EXCEL'),
            'pptx': ('application/vnd.openxmlformats-officedocument.presentationml.presentation', 'presentation', 'OOXML_POWERPOINT'),
        }
        for kind, (mime, family, container) in ooxml_cases.items():
            src = downloads / f'sample.{kind}'
            write_ooxml(src, kind)
            before = src.read_bytes()
            result = rawcap.capture_file(src, drive, expected_media=family)
            dst = Path(result['destinationPath'])
            check(dst.read_bytes() == before, f'{kind}:binary-preserved')
            check(result['sha256'] == hashlib.sha256(before).hexdigest(), f'{kind}:sha256')
            check(result['detected']['mime'] == mime, f'{kind}:mime')
            check(result['detectedMediaFamily'] == family, f'{kind}:family')
            check(result['detected']['containerType'] == container, f'{kind}:container')
            check(result['payloadMutation'] is False, f'{kind}:no-payload-mutation')

        zip_src = downloads / 'sample.zip'
        with zipfile.ZipFile(zip_src, 'w') as zf:
            zf.writestr('payload.bin', b'\x00\x01\x02')
        zip_before = zip_src.read_bytes()
        zip_result = rawcap.capture_file(zip_src, drive, expected_media='archive')
        check(Path(zip_result['destinationPath']).read_bytes() == zip_before, 'zip:binary-preserved')
        check(zip_result['detected']['mime'] == 'application/zip', 'zip:mime')
        check(zip_result['detectedMediaFamily'] == 'archive', 'zip:family')

        duplicate = rawcap.capture_file(downloads / 'sample.png', drive, expected_media='image')
        check(Path(duplicate['destinationPath']).name == 'sample_1.png', 'duplicate-name')

        try:
            rawcap.capture_file(downloads / 'sample.m4a', drive, expected_media='video')
            raise AssertionError('wrong media family accepted')
        except RuntimeError as exc:
            check('media family mismatch' in str(exc), 'wrong-media-fail-closed')

        generic_png = downloads / 'generic-image.dat'
        generic_payload = b'\x89PNG\r\n\x1a\n' + b'Z'*100
        generic_png.write_bytes(generic_payload)
        repaired = rawcap.capture_file(generic_png, drive, expected_media='image', repair_generic_image_extension=True)
        repaired_path = Path(repaired['destinationPath'])
        check(repaired_path.suffix == '.png', 'generic-image-extension-repaired')
        check(repaired_path.read_bytes() == generic_payload, 'generic-image-repair-binary-preserved')

        generic_audio = downloads / 'generic-audio.bin'
        generic_audio.write_bytes(b'ID3' + b'A'*100)
        no_repair = rawcap.capture_file(generic_audio, drive, expected_media='audio')
        check(Path(no_repair['destinationPath']).suffix == '.bin', 'generic-audio-not-renamed')

        partial = downloads / 'never-copy.crdownload'
        partial.write_bytes(b'\x89PNG\r\n\x1a\n' + b'x'*40)
        candidate = rawcap.newest_candidate(downloads, since=partial.stat().st_mtime - 0.1)
        check(candidate is None or candidate.name != partial.name, 'partial-file-excluded')

        receipt = json.loads(Path(duplicate['receiptPath']).read_text(encoding='utf-8'))
        check(receipt['status'] == 'RAW_BINARY_COPY_PASS', 'receipt-status')
        check(receipt['sourceSha256'] == duplicate['sha256'], 'receipt-source-sha')
        check(receipt['destinationSha256'] == duplicate['sha256'], 'receipt-destination-sha')
        check(receipt['payloadMutation'] is False, 'receipt-no-payload-mutation')

    with tempfile.TemporaryDirectory() as td:
        root = Path(td); downloads = root / 'Downloads'; drive = root / 'Drive'; downloads.mkdir()
        payload = b'%PDF-1.7\n' + b'A'*1024
        since = time.time()
        def chrome_like_producer():
            time.sleep(0.8)
            part = downloads / 'notebook-result.pdf.crdownload'
            part.write_bytes(payload[:400])
            time.sleep(0.4)
            with part.open('ab') as f: f.write(payload[400:])
            time.sleep(0.4)
            part.rename(downloads / 'notebook-result.pdf')
        t = threading.Thread(target=chrome_like_producer); t.start()
        result = rawcap.watch_once(downloads, drive, since=since, timeout=8, expected_name='notebook-result.pdf', expected_media='document')
        t.join()
        check(result['ok'], 'chrome-rename:captured')
        check(Path(result['destinationPath']).read_bytes() == payload, 'chrome-rename:binary-preserved')
        check(result['sha256'] == hashlib.sha256(payload).hexdigest(), 'chrome-rename:sha256')
        check(result['detected']['mime'] == 'application/pdf', 'chrome-rename:mime')
        check(result['sourceImmutableVerified'], 'chrome-rename:source-immutable')
        check(not any(p.suffix.lower() == '.crdownload' for p in drive.iterdir()), 'chrome-rename:no-partial-in-drive')

    print(f'ALL_TESTS_PASS checks={COUNT}')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
