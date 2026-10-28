import os
from pathlib import Path
import runpy
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT/'scripts/local-config.py'


class LocalConfigTests(unittest.TestCase):
    def api(self):
        self.assertTrue(SCRIPT.exists(), 'Shared local configuration helper is missing')
        return runpy.run_path(str(SCRIPT))

    def config(self, home, text):
        path = home/'.config/pir/maintenance/local.env'
        path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        path.write_text(text)
        path.chmod(0o600)
        return path

    def test_no_config_and_precedence(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self.assertEqual(api['load_config'](home=home, environ={}, root=home), {})
            self.config(home, 'PIR_SPARKLE_HOST=config-host\nPIR_EVIDENCE_DIR=~/evidence\n')
            result = api['load_config'](home=home, environ={'PIR_SPARKLE_HOST': 'env-host'}, overrides={'PIR_SPARKLE_HOST': 'option-host'}, root=home)
            self.assertEqual(result['PIR_SPARKLE_HOST'], 'option-host')
            self.assertEqual(result['PIR_EVIDENCE_DIR'], str(home/'evidence'))

    def test_rejects_unsafe_unknown_malformed_duplicate_and_insecure_files(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            for text in ('EVIL=value\n', 'export PIR_SPARKLE_HOST=host\n', 'PIR_SPARKLE_HOST=$(touch nope)\n', 'PIR_SPARKLE_HOST=`id`\n', 'PIR_SPARKLE_HOST=a\nPIR_SPARKLE_HOST=b\n', 'PIR_SPARKLE_HOST="unterminated\n', 'PIR_SPARKLE_HOST="\\u0000"\n'):
                self.config(home, text)
                with self.assertRaises(ValueError):
                    api['load_config'](home=home, environ={}, root=home)
            path = self.config(home, 'PIR_SPARKLE_HOST=host\n')
            for mode in (0o644, 0o666):
                path.chmod(mode)
                with self.assertRaises(ValueError):
                    api['load_config'](home=home, environ={}, root=home)
            path.chmod(0o600)
            path.parent.chmod(0o755)
            with self.assertRaises(ValueError):
                api['load_config'](home=home, environ={}, root=home)

    def test_invalid_utf8_reports_no_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = self.config(home, '')
            path.write_bytes(b'PRIVATE_VALUE=\xff')
            result = subprocess.run([sys.executable, str(SCRIPT), '--config', str(path), 'check'], capture_output=True, text=True, env={'HOME': directory})
            self.assertEqual(result.returncode, 1)
            self.assertNotIn('PRIVATE_VALUE', result.stderr)
            self.assertIn('UTF-8', result.stderr)

    def test_rejects_symlink_and_environment_injection(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = self.config(home, 'PIR_SPARKLE_HOST=host\n')
            other = home/'other'
            path.rename(other)
            path.symlink_to(other)
            with self.assertRaises(ValueError):
                api['load_config'](home=home, environ={}, root=home)
            path.unlink()
            for value in ('-oProxyCommand=id', 'host\nsecret', '$(id)'):
                with self.assertRaises(ValueError):
                    api['load_config'](home=home, environ={'PIR_SPARKLE_HOST': value}, root=home)

    def test_init_missing_is_private_no_clobber_and_reports_names_only(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            values, unresolved = api['discover'](home)
            self.assertIn('PIR_SPARKLE_HOST', unresolved)
            self.assertNotIn('PIR_SPARKLE_HOST', values)
            path = home/'.config/pir/maintenance/local.env'
            api['write_config'](path, values)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            with self.assertRaises(FileExistsError):
                api['write_config'](path, values)
            result = subprocess.run([sys.executable, str(SCRIPT), '--config', str(path), 'check'], capture_output=True, text=True, env={'PATH': os.environ['PATH'], 'HOME': str(home)})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('PIR_SPARKLE_HOST', result.stderr)
            self.assertNotIn(str(home), result.stdout + result.stderr)

    def test_discovery_only_uses_unique_paired_certificate(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            def fake(command, **kwargs):
                if '-pubkey' in command or command[1] == 'pkey':
                    return 'public key'
                if '-subject' in command:
                    return 'subject=\n    CN=Developer ID Application: Example (TEAM)'
                if '-fingerprint' in command:
                    return 'sha1 Fingerprint=' + ':'.join(['AB']*20)
                return ''
            first = home/'Docs/ci-signing/keys'
            first.mkdir(parents=True)
            for name in ('dev-id-app.pem', 'dev-id-app.key'):
                (first/name).touch()
            values, unresolved = api['discover'](home, execute=fake)
            self.assertEqual(values['PIR_SIGN_IDENTITY'], 'AB'*20)
            self.assertNotIn('PIR_SIGNING_DIR', unresolved)
            second = home/'Documents/ci-signing/keys'
            second.mkdir(parents=True)
            for name in ('dev-id-app.pem', 'dev-id-app.key'):
                (second/name).touch()
            values, unresolved = api['discover'](home, execute=fake)
            self.assertNotIn('PIR_SIGNING_DIR', values)
            self.assertIn('PIR_SIGNING_DIR', unresolved)
            def mismatch(command, **kwargs):
                return 'different' if command[1] == 'pkey' else fake(command, **kwargs)
            second.rename(second.with_name('unused'))
            values, unresolved = api['discover'](home, execute=mismatch)
            self.assertNotIn('PIR_SIGN_IDENTITY', values)
            self.assertIn('PIR_SIGNING_DIR', unresolved)




class HelperConfigIntegrationTests(unittest.TestCase):
    def test_signing_missing_config_stops_before_keychain_or_tools(self):
        from unittest import mock
        helper = runpy.run_path(str(ROOT/'scripts/release/with-local-signing.py'))
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(os.environ, {'HOME': directory}, clear=True), mock.patch.object(sys, 'argv', ['with-local-signing.py']):
            with mock.patch('subprocess.run', side_effect=AssertionError('External tools must not run')):
                with self.assertRaisesRegex(ValueError, 'PIR_SIGNING_DIR'):
                    helper['main']()

    def test_remote_staging_carries_parser_and_explicit_account_without_local_config(self):
        helper = runpy.run_path(str(ROOT/'scripts/release/prepare-on-macbook.py'))
        self.assertIn('stage_inputs', helper, 'Remote staging must carry shared parser')
        self.assertIn('update_command', helper, 'Remote job must receive resolved account explicitly')
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            helper['stage_inputs'](stage)
            self.assertTrue((stage/'scripts/local-config.py').is_file())
            self.assertFalse((stage/'.env.local').exists())
            command = helper['update_command'](stage, 'stable', 'test.account')
            self.assertEqual(command[:4], ['/usr/bin/env', 'PIR_LOCAL_CONFIG=-', 'PIR_SPARKLE_ACCOUNT=test.account', '/bin/bash'])
            self.assertIn(str(stage/'scripts/release/prepare-update.sh'), command)

    def test_remote_missing_config_stops_before_ssh(self):
        from unittest import mock
        helper = runpy.run_path(str(ROOT/'scripts/release/prepare-on-macbook.py'))
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(os.environ, {'HOME': directory}, clear=True), mock.patch.object(sys, 'argv', ['prepare-on-macbook.py', '--check-key']):
            with mock.patch('subprocess.run', side_effect=AssertionError('SSH must not run')):
                with self.assertRaisesRegex(ValueError, 'PIR_SPARKLE_HOST'):
                    helper['main']()


class ConfigStatusTests(unittest.TestCase):
    def test_remote_explicit_environment_can_skip_unrelated_host_config(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = home/'.config/pir/maintenance/local.env'
            path.parent.mkdir(parents=True)
            path.write_text('INVALID=file\n')
            result = subprocess.run([sys.executable, str(SCRIPT), 'get', 'PIR_SPARKLE_ACCOUNT'], env={'HOME': str(home), 'PIR_LOCAL_CONFIG': '-', 'PIR_SPARKLE_ACCOUNT': 'test.account'}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'test.account')

    def test_json_status_does_not_include_values(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(SCRIPT), 'check', '--json'], env={'HOME': directory, 'PIR_SPARKLE_HOST': 'private-host'}, capture_output=True, text=True)
            import json
            report = json.loads(result.stdout)
            self.assertEqual(report['configured'], ['PIR_SPARKLE_HOST'])
            self.assertIn('PIR_SIGNING_DIR', report['missing'])
            self.assertNotIn('private-host', result.stdout + result.stderr)


class HelperPrecedenceTests(unittest.TestCase):
    def test_signing_explicit_options_reach_command_and_pair_validation(self):
        from contextlib import nullcontext
        from unittest import mock
        helper = runpy.run_path(str(ROOT/'scripts/release/with-local-signing.py'))
        namespace = helper['main'].__globals__
        identity = 'CD' * 20
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home/'local.env'
            config.write_text('PIR_SIGNING_DIR=/file/keys\nPIR_SIGN_IDENTITY=' + 'AB'*20 + '\n')
            config.chmod(0o600)
            arguments = ['with-local-signing.py', '--config', str(config), '--signing-dir', '/option/keys', '--identity', identity, '--', '/bin/true']
            with mock.patch.dict(os.environ, {'HOME': directory, 'PIR_SIGNING_DIR': '/env/keys'}, clear=True), mock.patch.object(sys, 'argv', arguments), mock.patch('subprocess.run', side_effect=AssertionError('External tools must not run')):
                with mock.patch.dict(namespace['CONFIG'], certificate_identity=mock.Mock(return_value=identity)), mock.patch.object(namespace['runpy'], 'run_path', return_value={'resolve_openssl': lambda: '/test/openssl'}), mock.patch.dict(namespace, local_keychain=mock.Mock(return_value=nullcontext()), run_command=mock.Mock(return_value=0)):
                    self.assertEqual(helper['main'](), 0)
                    namespace['CONFIG']['certificate_identity'].assert_called_once_with(Path('/option/keys'), '/test/openssl', expected=identity)
                    namespace['local_keychain'].assert_called_once_with(Path('/option/keys'), '/test/openssl', recovery_dir=None)
                    command, environment = namespace['run_command'].call_args.args
                    self.assertEqual(command, ['/bin/true'])
                    self.assertEqual(environment['PIR_SIGN_IDENTITY'], identity)

    def test_update_shell_uses_existing_account_and_preserves_public_key(self):
        shell = (ROOT/'scripts/release/prepare-update.sh').read_text()
        self.assertIn('local-config.py', shell)
        self.assertNotIn('--account me.caldis.pir', shell)
        self.assertEqual(shell.count('--account "$PIR_SPARKLE_ACCOUNT"'), 5)
        configure = (ROOT/'scripts/release/configure-update-key.sh').read_text()
        self.assertIn('generate_keys --account "$PIR_SPARKLE_ACCOUNT" -p', configure)
        self.assertNotIn('write_bytes', configure)
        self.assertNotIn('generate_keys --account "$PIR_SPARKLE_ACCOUNT" >/dev/null', configure)



class ReviewRegressionTests(unittest.TestCase):
    def test_init_uses_selected_environment_and_explicit_config_paths(self):
        from contextlib import redirect_stdout, redirect_stderr
        import io
        from unittest import mock
        helper = runpy.run_path(str(SCRIPT))
        for explicit in (None, '~/explicit/local.env'):
            with self.subTest(explicit=explicit), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                env_path = home/'selected/local.env'
                expected = home/'explicit/local.env' if explicit else env_path
                argv = ['local-config.py'] + (['--config', explicit] if explicit else []) + ['init', '--json']
                namespace = helper['main'].__globals__
                with mock.patch.dict(os.environ, {'HOME': directory, 'PIR_LOCAL_CONFIG': str(env_path)}, clear=True), mock.patch.object(sys, 'argv', argv), mock.patch('subprocess.run', side_effect=AssertionError('No tools may run')), mock.patch.dict(namespace, discover=mock.Mock(return_value=({'PIR_SPARKLE_ACCOUNT': 'example.account'}, []))), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                    self.assertEqual(helper['main'](), 0)
                self.assertTrue(expected.is_file())
                self.assertFalse((home/'.config/pir/maintenance/local.env').exists())
                if explicit:
                    self.assertFalse(env_path.exists())
                self.assertEqual(helper['load_config'](environ={'PIR_LOCAL_CONFIG': str(expected)}, home=home)['PIR_SPARKLE_ACCOUNT'], 'example.account')

    def test_init_disabled_selection_does_not_discover_or_write(self):
        from contextlib import redirect_stdout, redirect_stderr
        import io
        from unittest import mock
        helper = runpy.run_path(str(SCRIPT))
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            with mock.patch.dict(os.environ, {'HOME': directory, 'PIR_LOCAL_CONFIG': '-'}, clear=True), mock.patch.object(sys, 'argv', ['local-config.py', 'init']), mock.patch('subprocess.run', side_effect=AssertionError('No tools may run')), mock.patch.dict(helper['main'].__globals__, discover=mock.Mock(side_effect=AssertionError('Disabled init must not discover'))), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(helper['main'](), 1)
            self.assertEqual(list(home.iterdir()), [])

    def test_signing_names_exactly_match_certificate_and_command_uses_fingerprint(self):
        from contextlib import nullcontext
        from unittest import mock
        helper = runpy.run_path(str(ROOT/'scripts/release/with-local-signing.py'))
        namespace = helper['main'].__globals__
        fingerprint = 'AB'*20
        names = ['Developer ID Application: Example (TEAM)', 'Developer ID Application: ' + 'X'*15]
        for common_name in names:
            self.assertTrue(common_name.startswith('Developer ID Application: '))
            for configured in (common_name, common_name + ' Other', fingerprint, 'CD'*20):
                valid = configured in (common_name, fingerprint)
                with self.subTest(common_name=common_name, configured=configured), tempfile.TemporaryDirectory() as directory:
                    keys = Path(directory)
                    for name in ('dev-id-app.pem', 'dev-id-app.key'):
                        (keys/name).touch()
                    def execute(command, **kwargs):
                        if '-subject' in command:
                            return 'subject=\n    CN=' + common_name
                        if '-pubkey' in command or command[1] == 'pkey':
                            return 'paired public key'
                        if '-fingerprint' in command:
                            return 'sha1 Fingerprint=' + ':'.join(['AB']*20)
                        return ''
                    original = namespace['CONFIG']['certificate_identity']
                    def validate_certificate(*args, **kwargs):
                        return original(*args, **kwargs, execute=execute)
                    command = mock.Mock(return_value=0)
                    keychain = mock.Mock(return_value=nullcontext())
                    env = {'HOME': directory, 'PIR_LOCAL_CONFIG': '-', 'PIR_SIGNING_DIR': directory, 'PIR_SIGN_IDENTITY': configured}
                    with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(sys, 'argv', ['with-local-signing.py', '--', '/bin/true']), mock.patch('subprocess.run', side_effect=AssertionError('No external tools may run')), mock.patch.dict(namespace['CONFIG'], certificate_identity=validate_certificate), mock.patch.object(namespace['runpy'], 'run_path', return_value={'resolve_openssl': lambda: '/test/openssl'}), mock.patch.dict(namespace, run_command=command, local_keychain=keychain):
                        if valid:
                            self.assertEqual(helper['main'](), 0)
                            self.assertEqual(command.call_args.args[1]['PIR_SIGN_IDENTITY'], fingerprint)
                            keychain.assert_called_once()
                        else:
                            with self.assertRaisesRegex(ValueError, 'PIR_SIGN_IDENTITY'):
                                helper['main']()
                            command.assert_not_called()
                            keychain.assert_not_called()

if __name__ == '__main__':
    unittest.main()
