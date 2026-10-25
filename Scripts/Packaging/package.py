#!/usr/bin/env python3
"""Build a local ad-hoc signed Release app. No downloads or installation."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
from prepare import ROOT, STAGE, MANIFEST, verify_cache

if not __debug__:
    raise SystemExit("Run packaging validation without Python optimization; checks must remain enabled.")


def run(args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)


def main():
    verify_cache()
    assert os.uname().machine == 'arm64', 'Build on an Apple Silicon Mac'
    app = STAGE / 'output/Mango Music.app'
    if app.exists():
        raise SystemExit('Move the previous isolated output aside before rebuilding: ' + str(app))
    run([sys.executable, ROOT / 'Scripts/Packaging/build_helpers.py'])
    derived = STAGE / 'DerivedData'
    logs = STAGE / 'logs'
    logs.mkdir(exist_ok=True)
    with (logs / 'xcode-release.log').open('w') as log:
        run(['/usr/bin/xcodebuild', '-project', ROOT / 'MangoMusic.xcodeproj', '-scheme', 'MangoMusic', '-configuration', 'Release', '-derivedDataPath', derived, 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'MACOSX_DEPLOYMENT_TARGET=14.0', 'ENABLE_APP_SANDBOX=NO', 'CODE_SIGNING_ALLOWED=NO', 'build'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    output = STAGE / 'output'
    output.mkdir(exist_ok=True)
    app = output / 'Mango Music.app'
    if app.exists():
        # Never replace an artifact (and possibly a running app) implicitly.
        raise SystemExit('Output already exists. Move it aside before rebuilding: ' + str(app))
    shutil.copytree(derived / 'Build/Products/Release/MangoMusic.app', app, symlinks=True)
    native = app / 'Contents/MacOS'
    shutil.copy2(STAGE / 'prefix/bin/mpv', native / 'mpv')
    shutil.copy2(STAGE / 'downloads/yt-dlp_macos', native / 'yt-dlp')
    for name in ('mpv', 'yt-dlp'):
        (native / name).chmod(0o755)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['MangoBundledTools'] = True
    info_path.write_bytes(plistlib.dumps(info))
    notices = app / 'Contents/Resources/ThirdPartyNotices'
    notices.mkdir()
    shutil.copy2(ROOT / 'Scripts/Packaging/dependencies.json', notices / 'dependencies.json')
    shutil.copy2(ROOT / 'Scripts/Packaging/LICENSE-NOTES.md', notices / 'LICENSE-NOTES.md')
    for name in ('mpv', 'ffmpeg', 'libass', 'libplacebo', 'fribidi', 'harfbuzz', 'freetype'):
        src = STAGE / 'src' / name
        destination = notices / name
        destination.mkdir()
        for path in src.iterdir():
            if path.is_file() and (path.name.startswith(('LICENSE', 'COPYING', 'Copyright'))):
                shutil.copy2(path, destination / path.name)
    for name in ('FTL.TXT', 'GPLv2.TXT'):
        shutil.copy2(STAGE / 'src/freetype/docs' / name, notices / 'freetype' / name)
    for name in ('fast_float', 'Vulkan-Headers'):
        destination = notices / name
        destination.mkdir()
        for path in (STAGE / 'src/libplacebo/3rdparty' / name).rglob('*'):
            if path.is_file() and path.name.startswith(('LICENSE', 'COPYING')):
                relative = path.relative_to(STAGE / 'src/libplacebo/3rdparty' / name)
                (destination / relative).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination / relative)
    from PyInstaller.archive.readers import CArchiveReader
    archive = CArchiveReader(str(native / 'yt-dlp'))
    (notices / 'yt-dlp-THIRD_PARTY_LICENSES.txt').write_bytes(archive.extract('THIRD_PARTY_LICENSES.txt'))
    # These freshly built helpers need no non-system dylibs. yt-dlp's native extensions
    # are already signed inside the verified upstream archive; do not modify that payload.
    for name in ('mpv', 'yt-dlp', info['CFBundleExecutable']):
        run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', native / name])
    run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', app])
    run([sys.executable, ROOT / 'Scripts/Packaging/validate.py', app])
    print(app)


if __name__ == '__main__':
    main()
