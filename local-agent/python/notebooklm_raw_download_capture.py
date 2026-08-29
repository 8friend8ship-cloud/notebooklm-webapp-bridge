#!/usr/bin/env python3
"""Managed-Chrome raw download capture/verification.

Preserves the original bytes. Type detection is metadata-only and never decodes,
re-encodes, transcodes, or replaces the payload.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Optional

PARTIAL_SUFFIXES = {'.crdownload', '.part', '.tmp'}
GENERIC_SUFFIXES = {'', '.dat', '.bin', '.blob', '.download'}

MAGIC = (
    (b'\x89PNG\r\n\x1a\n', 'image/png', '.png'),
    (b'\xff\xd8\xff', 'image/jpeg', '.jpg'),
    (b'GIF87a', 'image/gif', '.gif'),
    (b'GIF89a', 'image/gif', '.gif'),
    (b'%PDF-', 'application/pdf', '.pdf'),
    (b'ID3', 'audio/mpeg', '.mp3'),
    (b'OggS', 'application/ogg', '.ogg'),
    (b'RIFF', 'application/riff', None),
)

OOXML_TYPES = {
    'word': ('application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.docx', 'OOXML_WORD'),
    'xl': ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.xlsx', 'OOXML_EXCEL'),
    'ppt': ('application/vnd.openxmlformats-officedocument.presentationml.presentation', '.pptx', 'OOXML_POWERPOINT'),
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def _detect_zip_package(path: Path) -> tuple[str, str, str]:
    """Classify ZIP containers without changing them."""
    try:
        with zipfile.ZipFile(path, 'r') as zf:
            names = {n.replace('\\', '/').lower() for n in zf.namelist()}
    except (zipfile.BadZipFile, OSError):
        return 'application/zip', '.zip', 'ZIP_OR_PK_CONTAINER'
    if '[content_types].xml' in names:
        for prefix, (mime, ext, package) in OOXML_TYPES.items():
            if any(n.startswith(prefix + '/') for n in names):
                return mime, ext, package
    return 'application/zip', '.zip', 'ZIP'


def _detect_utf8_text(path: Path) -> Optional[tuple[str, str, str]]:
    """Metadata-only UTF-8 inspection; the original bytes are never rewritten."""
    try:
        with path.open('rb') as f:
            probe = f.read(min(path.stat().st_size, 256 * 1024))
        if not probe or b'\x00' in probe:
            return None
        text = probe.decode('utf-8-sig', errors='strict')
    except (UnicodeDecodeError, OSError):
        return None
    stripped = text.strip()
    if not stripped:
        return 'text/plain', '.txt', 'UTF8_TEXT'
    if stripped[:1] in {'{', '['}:
        try:
            json.loads(stripped)
            return 'application/json', '.json', 'JSON_UTF8'
        except json.JSONDecodeError:
            pass
    lines = [ln for ln in stripped.splitlines() if ln.strip()]
    suffix = path.suffix.lower()
    if suffix == '.csv' or (len(lines) >= 2 and all(',' in ln for ln in lines[: min(5, len(lines))])):
        return 'text/csv', '.csv', 'CSV_UTF8'
    if suffix in {'.md', '.markdown'}:
        return 'text/markdown', '.md', 'MARKDOWN_UTF8'
    return 'text/plain', '.txt', 'UTF8_TEXT'


def detect_type(path: Path) -> dict:
    with path.open('rb') as f:
        head = f.read(64)
    mime = 'application/octet-stream'
    canonical_ext: Optional[str] = None
    container = ''

    if head.startswith(b'RIFF') and len(head) >= 12:
        if head[8:12] == b'WEBP':
            mime, canonical_ext, container = 'image/webp', '.webp', 'RIFF_WEBP'
        elif head[8:12] == b'WAVE':
            mime, canonical_ext, container = 'audio/wav', '.wav', 'RIFF_WAVE'
        elif head[8:12] == b'AVI ':
            mime, canonical_ext, container = 'video/x-msvideo', '.avi', 'RIFF_AVI'
    elif head.startswith(b'PK\x03\x04') or head.startswith(b'PK\x05\x06') or head.startswith(b'PK\x07\x08'):
        mime, canonical_ext, container = _detect_zip_package(path)
    else:
        for sig, m, ext in MAGIC:
            if head.startswith(sig):
                mime, canonical_ext, container = m, ext, 'MAGIC'
                break

    if len(head) >= 12 and head[4:8] == b'ftyp':
        brand = head[8:12]
        scan_limit = min(path.stat().st_size, 2 * 1024 * 1024)
        with path.open('rb') as f:
            probe = f.read(scan_limit)
        handlers = set()
        pos = 0
        while True:
            i = probe.find(b'hdlr', pos)
            if i < 0:
                break
            handler = probe[i + 12:i + 16]
            if handler in {b'soun', b'vide'}:
                handlers.add(handler)
            pos = i + 4
        if b'vide' in handlers:
            mime, canonical_ext = ('video/quicktime', '.mov') if brand == b'qt  ' else ('video/mp4', '.mp4')
            container = 'ISO_BMFF_VIDEO'
        elif b'soun' in handlers:
            mime, canonical_ext, container = 'audio/mp4', '.m4a', 'ISO_BMFF_AUDIO'
        elif brand == b'qt  ':
            mime, canonical_ext, container = 'video/quicktime', '.mov', 'ISO_BMFF_QUICKTIME'
        else:
            mime, canonical_ext, container = 'video/mp4', '.mp4', 'ISO_BMFF_UNKNOWN_HANDLER'

    if mime == 'application/octet-stream':
        text_type = _detect_utf8_text(path)
        if text_type:
            mime, canonical_ext, container = text_type

    return {
        'mime': mime,
        'canonicalExtension': canonical_ext,
        'sourceExtension': path.suffix.lower(),
        'magicVerified': mime != 'application/octet-stream',
        'containerType': container or 'UNKNOWN',
    }


def media_family(mime: str) -> str:
    if mime.startswith('image/'):
        return 'image'
    if mime.startswith('audio/'):
        return 'audio'
    if mime.startswith('video/'):
        return 'video'
    if mime in {
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    }:
        return 'document'
    if mime == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return 'spreadsheet'
    if mime == 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        return 'presentation'
    if mime in {'application/json', 'text/csv'}:
        return 'data'
    if mime.startswith('text/'):
        return 'text'
    if mime == 'application/zip':
        return 'archive'
    return 'unknown'


def is_complete_candidate(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() not in PARTIAL_SUFFIXES and not path.name.endswith('.receipt.json')


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


def newest_candidate(download_dir: Path, since: float = 0.0, expected_name: Optional[str] = None) -> Optional[Path]:
    candidates = []
    wanted = expected_name.casefold() if expected_name else None
    for p in download_dir.iterdir():
        if not is_complete_candidate(p):
            continue
        if wanted is not None and p.name.casefold() != wanted:
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
        alt = dest_dir / f'{stem}_{i}{suffix}'
        if not alt.exists():
            return alt
    raise RuntimeError('destination naming exhausted')


def destination_name(source: Path, kind: dict, expected_media: Optional[str], repair_generic_image_extension: bool) -> str:
    if not repair_generic_image_extension:
        return source.name
    if expected_media != 'image':
        raise RuntimeError('generic extension repair is allowed only when expected_media=image')
    if source.suffix.lower() not in GENERIC_SUFFIXES:
        return source.name
    if media_family(str(kind['mime'])) != 'image' or not kind.get('canonicalExtension'):
        raise RuntimeError('generic image extension repair requires magic-verified image bytes')
    stem = source.name[:-len(source.suffix)] if source.suffix else source.name
    return stem + str(kind['canonicalExtension'])


def capture_file(source: Path, dest_dir: Path, expected_media: Optional[str] = None, repair_generic_image_extension: bool = False) -> dict:
    if not wait_stable(source):
        raise RuntimeError(f'file did not become stable: {source}')
    dest_dir.mkdir(parents=True, exist_ok=True)

    source_size_before = source.stat().st_size
    src_hash = sha256_file(source)
    kind = detect_type(source)
    family = media_family(str(kind['mime']))
    if expected_media and family != expected_media:
        raise RuntimeError(f"media family mismatch: expected={expected_media} detected={family} mime={kind['mime']}")

    target_name = destination_name(source, kind, expected_media, repair_generic_image_extension)
    target = unique_destination(dest_dir, target_name)
    shutil.copy2(source, target)
    dst_hash = sha256_file(target)
    source_size_after = source.stat().st_size if source.exists() else -1
    src_hash_after = sha256_file(source) if source.exists() else ''
    if src_hash != dst_hash or source_size_before != target.stat().st_size or source_size_before != source_size_after or src_hash != src_hash_after:
        target.unlink(missing_ok=True)
        raise RuntimeError('binary integrity/source immutability mismatch after copy')

    receipt = {
        'ok': True,
        'status': 'RAW_BINARY_COPY_PASS',
        'sourcePath': str(source),
        'destinationPath': str(target),
        'sourceBytes': source_size_before,
        'destinationBytes': target.stat().st_size,
        'sourceSha256': src_hash,
        'destinationSha256': dst_hash,
        'sha256': dst_hash,
        'detected': kind,
        'detectedMediaFamily': family,
        'expectedMediaFamily': expected_media,
        'sourceImmutableVerified': True,
        'extensionRepaired': target.name != source.name,
        'payloadMutation': False,
        'capturedAt': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
    }
    receipt_path = target.with_name(target.name + '.receipt.json')
    tmp = receipt_path.with_suffix(receipt_path.suffix + '.tmp')
    tmp.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(tmp, receipt_path)
    receipt['receiptPath'] = str(receipt_path)
    return receipt


def watch_once(download_dir: Path, dest_dir: Path, since: float, timeout: int, expected_name: Optional[str] = None, expected_media: Optional[str] = None, repair_generic_image_extension: bool = False) -> dict:
    deadline = time.time() + timeout
    while time.time() <= deadline:
        p = newest_candidate(download_dir, since, expected_name=expected_name)
        if p:
            return capture_file(p, dest_dir, expected_media=expected_media, repair_generic_image_extension=repair_generic_image_extension)
        time.sleep(1)
    return {'ok': False, 'status': 'NO_COMPLETED_DOWNLOAD_WITHIN_TIMEOUT', 'expectedName': expected_name, 'expectedMediaFamily': expected_media}


def self_test() -> dict:
    png = b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\rIHDR' + bytes(range(32)) + b'\x00IEND\xaeB`\x82'
    with tempfile.TemporaryDirectory() as td:
        root = Path(td); d = root / 'Downloads'; g = root / 'DriveSync'; d.mkdir()
        src = d / 'fixture.png'; src.write_bytes(png)
        result = capture_file(src, g, expected_media='image')
        dst = Path(result['destinationPath'])
        assert dst.read_bytes() == png
        assert result['detected']['mime'] == 'image/png'
        assert result['sha256'] == hashlib.sha256(png).hexdigest()
        assert result['sourceImmutableVerified']
        return {'ok': True, 'status': 'SELF_TEST_PASS', 'sizeBytes': len(png), 'sha256': result['sha256'], 'mime': result['detected']['mime']}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--self-test', action='store_true')
    ap.add_argument('--download-dir')
    ap.add_argument('--source-file')
    ap.add_argument('--drive-dir')
    ap.add_argument('--expected-name')
    ap.add_argument('--expected-media', choices=['image','audio','video','document','spreadsheet','presentation','data','text','archive'])
    ap.add_argument('--repair-generic-image-extension', action='store_true')
    ap.add_argument('--since', type=float, default=0.0)
    ap.add_argument('--timeout', type=int, default=180)
    args = ap.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), ensure_ascii=False, indent=2)); return 0
    if not args.drive_dir:
        ap.error('--drive-dir is required unless --self-test is used')
    if bool(args.download_dir) == bool(args.source_file):
        ap.error('provide exactly one of --download-dir or --source-file')
    if args.repair_generic_image_extension and args.expected_media != 'image':
        ap.error('--repair-generic-image-extension requires --expected-media image')
    if args.source_file:
        result = capture_file(Path(args.source_file).expanduser(), Path(args.drive_dir).expanduser(), expected_media=args.expected_media, repair_generic_image_extension=args.repair_generic_image_extension)
    else:
        result = watch_once(Path(args.download_dir).expanduser(), Path(args.drive_dir).expanduser(), args.since or time.time(), max(1,args.timeout), expected_name=args.expected_name, expected_media=args.expected_media, repair_generic_image_extension=args.repair_generic_image_extension)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get('ok') else 2


if __name__ == '__main__':
    raise SystemExit(main())
