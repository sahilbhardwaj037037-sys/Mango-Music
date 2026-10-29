#!/usr/bin/env python3
"""Opt-in destructive fixtures use copies of the package, never the original."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

APP = Path(sys.argv.pop(1)).resolve()
VALIDATOR = Path(__file__).with_name('validate.py')


class BundleValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='mango-invalid-bundle-')
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / 'Mango Music.app'
        shutil.copytree(APP, self.app)

    def expect_rejected(self):
        result = subprocess.run([sys.executable, str(VALIDATOR), str(self.app)],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertNotEqual(result.returncode, 0, 'Damaged package was accepted')

    def test_missing_helper(self):
        (self.app / 'Contents/MacOS/mpv').unlink()
        self.expect_rejected()

    def test_nonexecutable_helper(self):
        (self.app / 'Contents/MacOS/mpv').chmod(0o644)
        self.expect_rejected()

    def test_missing_conversion_tool(self):
        (self.app / 'Contents/MacOS/ffprobe').unlink()
        self.expect_rejected()

    def test_nonexecutable_conversion_tool(self):
        (self.app / 'Contents/MacOS/ffmpeg').chmod(0o644)
        self.expect_rejected()

    def test_newer_deployment_target(self):
        path = self.app / 'Contents/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['LSMinimumSystemVersion'] = '26.0'
        path.write_bytes(plistlib.dumps(info))
        self.expect_rejected()

    def test_tampered_signature(self):
        path = self.app / 'Contents/MacOS/mpv'
        with path.open('r+b') as binary:
            binary.seek(4096)
            value = binary.read(1)
            binary.seek(4096)
            binary.write(bytes([value[0] ^ 1]))
        self.expect_rejected()


if __name__ == '__main__':
    unittest.main()
