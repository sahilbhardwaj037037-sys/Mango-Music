#!/usr/bin/env python3
"""Validate the local package, including yt-dlp's embedded native runtime."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from prepare import ROOT, STAGE, MANIFEST

if not __debug__:
    raise SystemExit("Run packaging validation without Python optimization; checks must remain enabled.")


def output(*args):
    return subprocess.check_output([str(x) for x in args], text=True, stderr=subprocess.STDOUT)


def check_macho(path, container):
    assert 'arm64' in output('/usr/bin/lipo', '-archs', path), f'Not arm64: {path}'
    commands = output('/usr/bin/otool', '-arch', 'arm64', '-l', path)
    rpaths = []
    minimums = []
    for block in re.split(r'Load command \d+', commands):
        if 'LC_BUILD_VERSION' in block or 'LC_VERSION_MIN_MACOSX' in block:
            minimum = re.search(r'(?:minos|version) (\d+(?:\.\d+)+)', block)
            assert minimum, f'No minimum OS: {path}'
            version = tuple(int(x) for x in minimum[1].split('.'))
            assert (version + (0, 0))[:3] <= (14, 0, 0), f'Requires newer macOS: {path}: {version}'
            minimums.append(version)
        if 'LC_RPATH' in block:
            rpath = re.search(r'path (.+) \(offset', block)[1]
            assert not rpath.startswith(('/opt/', '/Users/', '/Applications/Xcode')), f'External rpath: {path}'
            rpaths.append(rpath)
    assert minimums, f'No deployment target: {path}'
    lines = output('/usr/bin/otool', '-arch', 'arm64', '-L', path).splitlines()[1:]
    for line in lines:
        dependency = line.strip().split(' (')[0]
        if dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        if dependency.startswith('@loader_path/'):
            resolved = path.parent / dependency.removeprefix('@loader_path/')
        elif dependency.startswith('@executable_path/'):
            resolved = container / dependency.removeprefix('@executable_path/')
        elif dependency.startswith('@rpath/'):
            candidates = [Path(r.replace('@loader_path', str(path.parent)).replace('@executable_path', str(container))) / dependency.removeprefix('@rpath/') for r in rpaths]
            # otool includes a dylib's own install ID, which need not be a load dependency.
            if dependency.removeprefix('@rpath/') == path.name:
                continue
            resolved = next((p for p in candidates if p.exists()), None)
        else:
            raise AssertionError(f'External/unresolved library: {path}: {dependency}')
        assert resolved and resolved.exists(), f'Missing bundled library: {path}: {dependency}'
        assert resolved.resolve().is_relative_to(container.resolve()), f'Library escapes bundle: {resolved}'
    return len(lines)


def main():
    app = Path(sys.argv[1]).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.localmusic.MangoMusic'
    assert info['LSMinimumSystemVersion'] == '14.0'
    assert info['MangoBundledTools'] is True
    assert info['CFBundleDisplayName'] == 'Mango Music'
    assert info.get('CFBundleIconFile') or info.get('CFBundleIconName')
    assert (app / 'Contents/Resources/Assets.car').is_file()
    assert list((app / 'Contents/Resources').glob('*.icns'))
    native = app / 'Contents/MacOS'
    for name in (info['CFBundleExecutable'], 'mpv', 'yt-dlp', 'ffmpeg', 'ffprobe'):
        p = native / name
        assert p.is_file() and not p.is_symlink() and p.stat().st_mode & 0o111
        check_macho(p, native)
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(p)], check=True)
    assert output('/usr/bin/lipo', '-archs', native / info['CFBundleExecutable']).strip() == 'arm64'
    assert output('/usr/bin/lipo', '-archs', native / 'mpv').strip() == 'arm64'
    for name in ('ffmpeg', 'ffprobe'):
        assert output('/usr/bin/lipo', '-archs', native / name).strip() == 'arm64'
    # The verified upstream universal yt-dlp is intentionally not lipo-thinned: preserve its signed embedded archive.
    from PyInstaller.archive.readers import CArchiveReader
    archive = CArchiveReader(str(native / 'yt-dlp'))
    with tempfile.TemporaryDirectory(prefix='mango-runtime-audit-') as temporary:
        root = Path(temporary)
        native_files = []
        for name, entry in archive.toc.items():
            target = root / name
            assert target.resolve().is_relative_to(root.resolve())
            if entry[-1] == 'b':
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extract(name))
                native_files.append(target)
        for path in native_files:
            check_macho(path, root)
            subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(path)], check=True)
        assert (root / 'Python.framework/Versions/3.14/Python').is_file()
    expected = MANIFEST['yt-dlp']['sha256']
    assert hashlib.sha256((STAGE / 'downloads/yt-dlp_macos').read_bytes()).hexdigest() == expected, 'Upstream reference checksum mismatch'
    # Signing changes the outer bootloader; the bundled PyInstaller payload must stay byte-for-byte intact.
    original = CArchiveReader(str(STAGE / 'downloads/yt-dlp_macos'))
    assert archive.toc == original.toc
    for name in archive.toc:
        assert archive.extract(name) == original.extract(name), f'Modified yt-dlp payload: {name}'
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    entitlements = output('/usr/bin/codesign', '-d', '--entitlements', ':-', app)
    assert '<key>com.apple.security.app-sandbox</key>' not in entitlements
    forbidden = {'.sqlite', '.sqlite3', '.db', '.p12', '.pem', '.key', '.mobileprovision', '.log'}
    assert not any(p.suffix in forbidden for p in app.rglob('*') if p.is_file())
    size = sum(p.stat().st_size for p in app.rglob('*') if p.is_file())
    print(f'Bundle integrity/signatures/arm64/macOS 14/linkage passed; {len(native_files)} embedded yt-dlp native files; {size / 1048576:.2f} MiB.')


if __name__ == '__main__':
    main()
