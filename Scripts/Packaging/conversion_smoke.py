#!/usr/bin/env python3
"""Exercise yt-dlp -> bundled FFmpeg/ffprobe with generated, authorized audio only."""
import argparse
import functools
import http.server
import json
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import threading
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    native = args.app.resolve() / 'Contents/MacOS'
    with tempfile.TemporaryDirectory(prefix='mango-conversion-') as directory:
        root = Path(directory)
        environment = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'CFFIXED_USER_HOME': str(root)}
        for name, flag in [('yt-dlp', '--version'), ('mpv', '--version'), ('ffmpeg', '-version'), ('ffprobe', '-version')]:
            result = subprocess.run([str(native / name), flag], env=environment, capture_output=True, text=True, check=True, timeout=60)
            print(result.stdout.splitlines()[0])
        with wave.open(str(root / 'tone.wav'), 'wb') as audio:
            audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(8000)
            audio.writeframes(b''.join(struct.pack('<h', int(2000 * math.sin(2 * math.pi * 440 * i / 8000))) for i in range(32000)))

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(root)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run([
                str(native / 'yt-dlp'), '--ignore-config', '--no-plugin-dirs', '--no-cache-dir',
                '--no-playlist', '--verbose', '--extract-audio', '--audio-format', 'm4a',
                '--ffmpeg-location', str(native), '--output', str(root / 'converted.%(ext)s'),
                '--', f'http://127.0.0.1:{server.server_port}/tone.wav',
            ], env=environment, capture_output=True, text=True, timeout=90)
            if result.returncode != 0:
                raise RuntimeError('Generated-audio yt-dlp conversion failed')
            if str(native / 'ffmpeg') not in result.stderr or str(native / 'ffprobe') not in result.stderr:
                raise RuntimeError('yt-dlp did not report both exact bundled conversion executable paths')
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=5)
        converted = root / 'converted.m4a'
        result = subprocess.run([str(native / 'ffprobe'), '-v', 'error', '-show_entries',
                                 'stream=codec_name,codec_type:format=duration', '-of', 'json', str(converted)],
                                env=environment, capture_output=True, text=True, check=True, timeout=15)
        probe = json.loads(result.stdout)
        if not (float(probe['format']['duration']) >= 3.9 and probe['streams'] and
                all(s['codec_type'] == 'audio' and s['codec_name'] == 'aac' for s in probe['streams'])):
            raise RuntimeError('Converted fixture is not audio-only AAC of expected duration')
        subprocess.run([str(native / 'mpv'), '--no-config', '--vid=no', '--ao=null', '--no-terminal', str(converted)],
                       env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=15)
        print('Generated WAV -> yt-dlp -> exact bundled ffprobe/ffmpeg -> AAC/M4A -> bundled mpv: passed')
        print('PATH=/usr/bin:/bin; isolated HOME; localhost stopped before decode; no third-party media downloaded.')


if __name__ == '__main__':
    main()
