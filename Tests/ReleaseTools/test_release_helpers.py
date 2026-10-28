import base64
import hashlib
import pathlib
import plistlib
import runpy
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ReleaseHelpersTests(unittest.TestCase):
    def helper(self, name):
        path = ROOT / 'scripts/release' / name
        self.assertTrue(path.is_file(), f'Missing helper: {name}')
        return runpy.run_path(str(path))

    def test_keychain_restored_when_import_fails(self):
        helper = self.helper('with-local-signing.py')
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            if command[:3] == ['security', 'list-keychains', '-d'] and '-s' not in command:
                return '"/original/login.keychain-db"\n'
            if command[:2] == ['security', 'import']:
                raise RuntimeError('import failed')
            return ''
        with tempfile.TemporaryDirectory() as directory:
            keys = pathlib.Path(directory)
            for name in ('dev-id-app.key', 'dev-id-app.pem'):
                (keys / name).touch()
            with self.assertRaisesRegex(RuntimeError, 'import failed'):
                with helper['local_keychain'](keys, 'openssl', run, recovery_dir=keys/'recovery'):
                    self.fail('import failure must abort command')
        self.assertIn(['security', 'list-keychains', '-d', 'user', '-s', '/original/login.keychain-db'], calls)
        deleted = [c for c in calls if c[:2] == ['security', 'delete-keychain']]
        self.assertEqual(len(deleted), 1)
        self.assertNotEqual(deleted[0][-1], '/original/login.keychain-db')

    def test_checksum_tampering_rejected(self):
        helper = self.helper('verify-public.py')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'asset.zip').write_bytes(b'original')
            (root / 'SHA256SUMS').write_text(hashlib.sha256(b'original').hexdigest() + '  asset.zip\n')
            helper['verify_hashes'](root, ['asset.zip'])
            (root / 'asset.zip').write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError, 'SHA256'):
                helper['verify_hashes'](root, ['asset.zip'])

    def test_real_ed25519_rejects_tampering(self):
        helper = self.helper('verify-public.py')
        openssl = helper['resolve_openssl']()
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run([openssl, 'genpkey', '-algorithm', 'ED25519', '-out', str(root/'key')], check=True, capture_output=True)
            public = subprocess.check_output([openssl, 'pkey', '-in', str(root/'key'), '-pubout', '-outform', 'DER'])[-32:]
            (root/'payload').write_bytes(b'original')
            signature = subprocess.check_output([openssl, 'pkeyutl', '-sign', '-inkey', str(root/'key'), '-rawin', '-in', str(root/'payload')])
            helper['verify_signature'](b'original', signature, public)
            with self.assertRaises((RuntimeError, subprocess.CalledProcessError)):
                helper['verify_signature'](b'tampered', signature, public)

    def test_aqua_job_runs_once_and_writes_result_on_failure(self):
        helper = self.helper('prepare-on-macbook.py')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            spec, script = helper['job_files']('test.pir', root, ['/bin/sh', '-c', 'exit 23'])
            job = plistlib.loads(spec)
            self.assertTrue(job['RunAtLoad'])
            self.assertFalse(job['KeepAlive'])
            self.assertEqual(job['LimitLoadToSessionType'], 'Aqua')
            (root/'job.sh').write_text(script)
            subprocess.run(job['ProgramArguments'], check=False)
            self.assertEqual((root/'status').read_text().strip(), '23')

    def test_wrapper_signal_stops_descendant_process_group(self):
        import os
        import signal
        import sys
        import time
        helper_path = ROOT/'scripts/release/with-local-signing.py'
        self.assertIn('run_command', self.helper('with-local-signing.py'))
        with tempfile.TemporaryDirectory() as directory:
            marker = pathlib.Path(directory)/'child'
            child = 'import os,signal,time,pathlib; signal.signal(signal.SIGTERM, signal.SIG_IGN); pathlib.Path(' + repr(str(marker)) + ').write_text(str(os.getpid())); time.sleep(60)'
            parent = 'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",' + repr(child) + ']); time.sleep(60)'
            wrapper = 'import runpy,signal,sys; h=runpy.run_path(' + repr(str(helper_path)) + '); signal.signal(signal.SIGTERM, lambda n,f: sys.exit(128+n)); h["run_command"]([sys.executable,"-c",' + repr(parent) + '], dict(__import__("os").environ))'
            process = subprocess.Popen([sys.executable, '-c', wrapper])
            pid = None
            try:
                deadline = time.monotonic()+5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue(marker.exists(), 'descendant did not start')
                pid = int(marker.read_text())
                process.terminate()
                process.wait(timeout=15)
                deadline = time.monotonic()+2
                while time.monotonic() < deadline:
                    status = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
                    if not status or status.startswith('Z'):
                        break
                    time.sleep(.02)
                self.assertTrue(not status or status.startswith('Z'), 'descendant survived wrapper termination')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                if pid:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_signed_feed_requires_exact_pir_asset_url_for_each_channel(self):
        import xml.etree.ElementTree as ET
        helper = self.helper('verify-public.py')
        metadata = runpy.run_path(str(ROOT/'scripts/version-metadata.py'))['release_metadata']
        ns = helper['NS']
        openssl = helper['resolve_openssl']()
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run([openssl, 'genpkey', '-algorithm', 'ED25519', '-out', str(root/'key')], check=True, capture_output=True)
            public = subprocess.check_output([openssl, 'pkey', '-in', str(root/'key'), '-pubout', '-outform', 'DER'])[-32:]
            def sign(payload):
                (root/'payload').write_bytes(payload)
                return base64.b64encode(subprocess.check_output([openssl, 'pkeyutl', '-sign', '-inkey', str(root/'key'), '-rawin', '-in', str(root/'payload')])).decode()
            for channel in ('stable', 'beta'):
                names = metadata('0.2.0', '20261028.2', channel)
                archive = names['archive']
                (root/archive).write_bytes(b'archive payload')
                exact = f'https://github.com/Caldis/Pir/releases/download/{names["tag"]}/{archive}'
                for url in (exact, f'https://example.com/{archive}', f'https://github.com/Other/Pir/releases/download/{names["tag"]}/{archive}', f'https://github.com/Caldis/Pir/releases/download/wrong/{archive}'):
                    feed = ET.Element('rss')
                    item = ET.SubElement(ET.SubElement(feed, 'channel'), 'item')
                    ET.SubElement(item, ns+'version').text = '20261028.2'
                    ET.SubElement(item, ns+'shortVersionString').text = '0.2.0'
                    ET.SubElement(item, 'enclosure', {'url': url, 'length': str((root/archive).stat().st_size), ns+'edSignature': sign((root/archive).read_bytes())})
                    payload = ET.tostring(feed)
                    (root/'appcast.xml').write_bytes(payload + f'<!-- sparkle-signatures:\nedSignature: {sign(payload)}\nlength: {len(payload)}\n-->'.encode())
                    if url == exact:
                        helper['verify_updates'](root, '0.2.0', '20261028.2', archive, public, channel)
                    else:
                        with self.assertRaisesRegex(ValueError, 'archive metadata'):
                            helper['verify_updates'](root, '0.2.0', '20261028.2', archive, public, channel)

    def test_signing_recovery_snapshot_retained_if_cleanup_fails(self):
        import json
        helper = self.helper('with-local-signing.py')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in ('dev-id-app.key', 'dev-id-app.pem'):
                (root/name).touch()
            def execute(command, **kwargs):
                if command == ['security', 'list-keychains', '-d', 'user']:
                    return '"/original/login.keychain-db"\n'
                if command[:2] == ['security', 'delete-keychain']:
                    raise RuntimeError('delete failed')
                return ''
            recovery = root/'recovery'
            with self.assertRaisesRegex(RuntimeError, 'delete failed'):
                with helper['local_keychain'](root, 'openssl', execute, recovery_dir=recovery):
                    records = list(recovery.glob('*.json'))
                    self.assertEqual(len(records), 1)
                    snapshot = json.loads(records[0].read_text())
                    self.assertEqual(set(snapshot), {'originalKeychains', 'temporaryKeychain', 'pid', 'timestamp'})
                    self.assertEqual(snapshot['originalKeychains'], ['/original/login.keychain-db'])
            self.assertEqual(json.loads(records[0].read_text()), snapshot)

    def test_signing_recovery_snapshot_removed_after_successful_cleanup(self):
        helper = self.helper('with-local-signing.py')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in ('dev-id-app.key', 'dev-id-app.pem'):
                (root/name).touch()
            def execute(command, **kwargs):
                return '"/original/login.keychain-db"\n' if command == ['security', 'list-keychains', '-d', 'user'] else ''
            recovery = root/'recovery'
            with helper['local_keychain'](root, 'openssl', execute, recovery_dir=recovery):
                self.assertEqual(len(list(recovery.glob('*.json'))), 1)
            self.assertEqual(list(recovery.glob('*.json')), [])

    def test_explicit_openssl3_ignores_old_system_path_and_keeps_crypto_checks(self):
        import os
        from unittest import mock
        helper = self.helper('verify-public.py')
        self.assertTrue(callable(helper.get('resolve_openssl')), 'OpenSSL 3 resolver is missing')
        actual = helper['resolve_openssl']()
        self.assertTrue(pathlib.Path(actual).is_absolute())
        with tempfile.TemporaryDirectory() as directory:
            old = pathlib.Path(directory)/'openssl'
            old.write_text('#!/bin/sh\necho "LibreSSL 3.3.6"\n')
            old.chmod(0o755)
            with mock.patch.dict(os.environ, {'PATH': directory, 'PIR_OPENSSL': actual}):
                self.assertEqual(helper['resolve_openssl'](), actual)
                self.test_real_ed25519_rejects_tampering()
            with mock.patch.dict(os.environ, {'PATH': directory, 'PIR_OPENSSL': str(old)}):
                with self.assertRaisesRegex(RuntimeError, 'OpenSSL 3.*PIR_OPENSSL'):
                    helper['resolve_openssl']()
