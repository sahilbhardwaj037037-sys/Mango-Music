#!/usr/bin/env python3
"""Optional packaged-helper smoke test. Never print raw subprocess output or media URLs."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import wave

if not __debug__:
    raise SystemExit("Run packaging validation without Python optimization; checks must remain enabled.")


def pidpath(pid):
    buffer = ctypes.create_string_buffer(4096)
    system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    assert system.proc_pidpath(pid, buffer, len(buffer)) > 0
    return Path(os.fsdecode(buffer.value)).resolve()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--live', action='store_true', help='resolve a public YouTube fixture; no complete download')
    parser.add_argument('--audio', action='store_true', help='use real CoreAudio at low volume; requires manual audible confirmation')
    args = parser.parse_args()
    native = args.app.resolve() / 'Contents/MacOS'
    with tempfile.TemporaryDirectory(prefix='mango-packaged-smoke-') as directory:
        root = Path(directory)
        environment = {'PATH': str(native) + ':/usr/bin:/bin', 'HOME': str(root), 'CFFIXED_USER_HOME': str(root)}
        if args.live:
            tool = native / 'yt-dlp'
            child = subprocess.Popen([str(tool), '--ignore-config', '--no-plugin-dirs', '--no-cache-dir', '--skip-download', '--no-playlist', '--socket-timeout', '15', '--retries', '1', '--format', 'bestaudio[protocol^=m3u8]/bestaudio', '--get-url', '--', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'], env=environment, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            assert pidpath(child.pid) == tool
            try:
                stdout, _ = child.communicate(timeout=60)
            except BaseException:
                child.terminate()
                child.wait(timeout=10)
                raise
            assert child.returncode == 0 and stdout.startswith(b'https://') and len(stdout.strip().splitlines()) == 1, 'Resolution failed'
            media = stdout.decode().strip()
            print('Bundled yt-dlp process path and restricted-PATH live resolution: passed')
        else:
            audio = root / 'fixture.wav'
            with wave.open(str(audio), 'wb') as wav:
                wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(8000); wav.writeframes(bytes(16000 * 8))
            media = str(audio)
        ipc = root / 'ipc'
        tool = native / 'mpv'
        process = subprocess.Popen([str(tool), '--no-config', '--idle=yes', '--vid=no', '--audio-display=no', '--force-window=no', '--no-terminal', '--media-controls=no', '--input-media-keys=no', '--stop-screensaver=no', '--cache-on-disk=no', '--save-position-on-quit=no', '--volume=10', '--network-timeout=20', '--ao=' + ('coreaudio' if args.audio else 'null'), '--input-ipc-server=' + str(ipc)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        connection = None
        try:
            assert pidpath(process.pid) == tool
            for _ in range(150):
                if ipc.exists(): break
                assert process.poll() is None, 'mpv startup failed'
                time.sleep(.03)
            connection = socket.socket(socket.AF_UNIX)
            connection.settimeout(20)
            connection.connect(str(ipc))
            stream = connection.makefile('rb')
            sequence = 0
            def command(*values):
                nonlocal sequence
                sequence += 1
                connection.sendall((json.dumps({'command': values, 'request_id': sequence}) + '\n').encode())
                while True:
                    message = json.loads(stream.readline())
                    if message.get('request_id') == sequence:
                        assert message.get('error') == 'success', 'IPC command failed'
                        return message.get('data')
            command('loadfile', media, 'replace')
            for _ in range(600):
                time.sleep(.05)
                # Properties can be unavailable while networking/demuxing starts.
                try:
                    position = command('get_property', 'time-pos')
                    if position and position > .2: break
                except AssertionError:
                    pass
            else:
                raise AssertionError('No actual playback clock')
            assert command('get_property', 'current-ao') == ('coreaudio' if args.audio else 'null')
            command('set_property', 'pause', True)
            assert command('get_property', 'pause') is True
            command('set_property', 'volume', 15)
            assert abs(command('get_property', 'volume') - 15) < .01
            command('seek', 4, 'absolute+exact')
            command('set_property', 'pause', False)
            assert command('get_property', 'pause') is False
            time.sleep(.5)
            command('quit')
            process.wait(timeout=5)
            assert process.returncode == 0
            print('Bundled mpv path, playback clock, pause/resume, seek dispatch, volume readback and graceful exit: passed')
            print('Audio output:', 'CoreAudio (audibility requires human confirmation)' if args.audio else 'null (no audible claim)')
        finally:
            if connection: connection.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
        # mpv leaves the socket pathname behind; the app's OwnedMPVProcess removes
        # its entire private directory. This standalone harness owns this directory.
        if ipc.exists(): ipc.unlink()
        assert not ipc.exists(), 'Harness failed to remove its IPC socket'
        try:
            os.kill(process.pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError('Owned mpv process remains')
        print('Owned mpv PID exited; harness IPC socket cleanup: passed')


if __name__ == '__main__':
    main()
