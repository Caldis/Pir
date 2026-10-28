import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ReleaseSigningTests(unittest.TestCase):
    def test_missing_local_identity_stops_before_build(self):
        source = Path(__file__).resolve().parents[2] / 'scripts/release.sh'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / 'scripts'
            scripts.mkdir()
            release = scripts / 'release.sh'
            release.write_bytes(source.read_bytes())
            marker = root / 'build-started'
            check = scripts / 'check.sh'
            check.write_text(f'#!/bin/bash\ntouch "{marker}"\nexit 99\n')
            check.chmod(0o755)
            env = dict(os.environ)
            env.pop('PIR_SIGN_IDENTITY', None)
            result = subprocess.run(['bash', str(release)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('PIR_SIGN_IDENTITY', result.stderr)
            self.assertFalse(marker.exists(), 'Missing signing identity must fail before checks/build')


if __name__ == '__main__':
    unittest.main()
