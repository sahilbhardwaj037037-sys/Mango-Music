#!/usr/bin/env python3
"""Build minimal helpers from verified cached sources; never download implicitly."""
import os
from pathlib import Path
import subprocess

import pkgconf
from prepare import ROOT, MANIFEST, verify_cache


def main():
    verify_cache()
    root = ROOT / '.build/packaging'
    prefix = root / 'prefix'
    prefix.mkdir(exist_ok=True)
    # Use the pinned native pkgconf binary, not its Python console wrapper.
    environment = os.environ.copy()
    environment.update(
        PATH=str(root / 'tools/bin') + ':/usr/bin:/bin:/usr/sbin:/sbin',
        MACOSX_DEPLOYMENT_TARGET='14.0', CC='/usr/bin/clang', CXX='/usr/bin/clang++',
        CFLAGS='-arch arm64 -mmacosx-version-min=14.0',
        CXXFLAGS='-arch arm64 -mmacosx-version-min=14.0',
        LDFLAGS='-arch arm64 -mmacosx-version-min=14.0',
        PKG_CONFIG_LIBDIR=str(prefix / 'lib/pkgconfig'),
        PKG_CONFIG_PATH=str(prefix / 'lib/pkgconfig'),
        PKG_CONFIG=str(pkgconf._get_executable()),
    )
    logs = root / 'logs'
    logs.mkdir(exist_ok=True)

    def run(arguments, directory, name):
        print(name, flush=True)
        log = logs / (name + '.log')
        with log.open('w') as stream:
            process = subprocess.run([str(a) for a in arguments], cwd=directory,
                                     env=environment, stdout=stream, stderr=subprocess.STDOUT)
        if process.returncode:
            print(log.read_text()[-9000:], flush=True)
            raise SystemExit(process.returncode)

    def meson(name, options):
        source = root / 'src' / name
        build = root / ('build-' + name)
        if not (build / 'meson-private/coredata.dat').exists():
            run(['meson', 'setup', build, source, '--prefix=' + str(prefix),
                 '--libdir=lib', '--buildtype=release', '--wrap-mode=nodownload',
                 '-Ddefault_library=static', '-Dprefer_static=true',
                 '-Dauto_features=disabled', *options], root, name + '-setup')
        else:
            run(['meson', 'setup', '--reconfigure', build, source, *options],
                root, name + '-reconfigure')
        run(['meson', 'compile', '-C', build, '-j', '8'], root, name + '-compile')
        run(['meson', 'install', '-C', build], root, name + '-install')

    # Refuse an unpatched or otherwise unexpected CoreAudio source tree.
    import hashlib
    patch = MANIFEST['mpv-coreaudio-fix']
    if hashlib.sha256((root / 'src' / patch['target']).read_bytes()).hexdigest() != patch['after_sha256']:
        raise SystemExit('Run prepare.py to apply the verified upstream CoreAudio fix')

    ffmpeg = root / 'src/ffmpeg'
    if not (ffmpeg / 'config.h').exists():
        run([
            ffmpeg / 'configure', '--prefix=' + str(prefix), '--arch=arm64',
            '--cc=/usr/bin/clang', '--disable-autodetect', '--disable-shared',
            '--enable-static', '--enable-pic', '--disable-programs', '--disable-doc',
            '--disable-debug', '--disable-everything', '--enable-network',
            '--enable-securetransport', '--enable-protocol=file,http,https,tcp,tls,crypto,data',
            '--enable-demuxer=hls,mov,matroska,ogg,mp3,aac,wav,flac,mpegts',
            '--enable-decoder=aac,aac_fixed,opus,vorbis,mp3,mp3float,flac,pcm_s16le,pcm_s24le,pcm_f32le',
            '--enable-parser=aac,aac_latm,opus,vorbis,mpegaudio,flac',
            '--enable-filter=abuffer,abuffersink,aformat,anull,aresample,atempo,volume,pan,buffer,buffersink,null,format,scale',
            '--enable-swresample', '--enable-swscale',
            '--extra-cflags=-arch arm64 -mmacosx-version-min=14.0',
            '--extra-ldflags=-arch arm64 -mmacosx-version-min=14.0',
        ], ffmpeg, 'ffmpeg-setup')
    run(['/usr/bin/make', '-j8'], ffmpeg, 'ffmpeg-compile')
    run(['/usr/bin/make', 'install'], ffmpeg, 'ffmpeg-install')
    meson('freetype', ['-Dharfbuzz=disabled', '-Dzlib=system', '-Dmmap=enabled'])
    meson('fribidi', ['-Ddocs=false', '-Dbin=false', '-Dtests=false'])
    meson('harfbuzz', [])
    meson('libass', ['-Dcoretext=enabled', '-Dasm=disabled'])
    meson('libplacebo', ['-Ddemos=false'])
    meson('mpv', ['-Dlibmpv=false', '-Dcplayer=true', '-Dbuild-date=false',
                  '-Dgl=disabled', '-Dlua=disabled', '-Dcoreaudio=enabled',
                  '-Dswift-build=disabled', '-Dmacos-media-player=disabled'])
    print('Helper build complete', flush=True)


if __name__ == '__main__':
    main()
