from datetime import datetime, timedelta, timezone
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class GitHubAppTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('pir_auth_test', ROOT / 'scripts/maintenance/github_app.py')
        self.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.m)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.directory.chmod(0o700)
        self.key = self.directory / 'app.pem'
        self.key.write_text('test fixture, never used for signing')
        self.key.chmod(0o600)
        self.config = self.directory / 'github-app.json'
        self.value = dict(app_id=5512939, app_slug='caldis-pir-maintainer', installation_id=176235800,
                          owner='Caldis', repository='Caldis/Pir', private_key_path=str(self.key))
        self.save()

    def save(self):
        self.config.write_text(json.dumps(self.value))
        self.config.chmod(0o600)

    def responses(self, expires=None):
        expires = expires or (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
        return [{'id': 5512939, 'slug': 'caldis-pir-maintainer'},
                {'id': 176235800, 'app_id': 5512939, 'account': {'login': 'Caldis'},
                 'repository_selection': 'selected', 'permissions': self.m.PERMISSIONS},
                {'token': 'ghs_testsecret', 'expires_at': expires, 'permissions': self.m.PERMISSIONS},
                {'total_count': 1, 'repositories': [{'full_name': 'Caldis/Pir'}]}]

    def test_rejects_insecure_modes_symlink_and_wrong_identity(self):
        for field, value in [('app_id', 1), ('repository', 'Caldis/Other'), ('installation_id', True)]:
            with self.subTest(field=field):
                original = self.value[field]
                self.value[field] = value
                self.save()
                with self.assertRaises(self.m.AuthError): self.m.Client(self.config)
                self.value[field] = original
        self.save()
        self.key.chmod(0o644)
        with self.assertRaises(self.m.AuthError): self.m.Client(self.config)
        self.key.chmod(0o600)
        self.config.chmod(0o644)
        with self.assertRaises(self.m.AuthError): self.m.Client(self.config)
        self.config.chmod(0o600)
        self.key.unlink()
        self.key.symlink_to(self.config)
        with self.assertRaises(self.m.AuthError): self.m.Client(self.config)

    def test_installation_environment_overwrites_owner_and_uses_no_user_endpoint(self):
        client = self.m.Client(self.config)
        with patch.object(client, '_jwt', return_value='private-jwt'), patch.object(client, '_request', side_effect=self.responses()) as request, patch.dict(os.environ, {'GH_TOKEN': 'owner-secret', 'GITHUB_TOKEN': 'owner-secret', 'GH_ENTERPRISE_TOKEN': 'owner-secret'}):
            env = client.environment()
            self.assertEqual(env['GH_TOKEN'], 'ghs_testsecret')
            self.assertNotIn('GITHUB_TOKEN', env)
            self.assertNotIn('GH_ENTERPRISE_TOKEN', env)
            self.assertEqual(client.actor(), 'caldis-pir-maintainer[bot]')
            self.assertNotIn('/user', [call.args[0] for call in request.call_args_list])
            self.assertEqual(request.call_args_list[2].kwargs['data']['repositories'], ['Pir'])

    def test_expired_token_permissions_or_repository_mismatch_fail_without_fallback(self):
        for mode in ('expired', 'permissions', 'repository', 'owner'):
            client = self.m.Client(self.config)
            responses = self.responses()
            if mode == 'expired': responses[2]['expires_at'] = '2000-01-01T00:00:00Z'
            if mode == 'permissions': responses[2]['permissions'] = {'issues': 'read'}
            if mode == 'repository': responses[3]['repositories'][0]['full_name'] = 'Caldis/Other'
            if mode == 'owner': responses[1]['account']['login'] = 'Other'
            with self.subTest(mode=mode), patch.object(client, '_jwt', return_value='private-jwt'), patch.object(client, '_request', side_effect=responses), patch.dict(os.environ, {'GH_TOKEN': 'owner-secret'}):
                with self.assertRaises(self.m.AuthError): client.environment()
                self.assertIsNone(client._token)

    def test_refresh_before_expiry_and_do_not_reuse_after_refresh_failure(self):
        client = self.m.Client(self.config)
        with patch.object(client, '_jwt', return_value='private-jwt'), patch.object(client, '_request', side_effect=self.responses()):
            client.environment()
        client._expires = 0
        with patch.object(client, '_jwt', side_effect=self.m.AuthError('GitHub App signing failed')):
            with self.assertRaises(self.m.AuthError): client.environment()
        self.assertIsNone(client._token)

    def test_missing_config_never_invokes_gh_or_inherited_auth(self):
        with patch.object(self.m.subprocess, 'run') as run:
            with self.assertRaises(self.m.AuthError): self.m.Client(self.directory / 'absent')
            run.assert_not_called()

    def test_git_credentials_are_environment_only_and_other_helpers_disabled(self):
        client = self.m.Client(self.config)
        with patch.object(client, 'environment', return_value={'GH_TOKEN': 'ghs_testsecret'}):
            command, env = client.command(['git', 'push', 'origin', 'HEAD'])
        self.assertNotIn('ghs_testsecret', ' '.join(command))
        self.assertEqual(command, ['git', 'push', 'origin', 'HEAD'])
        with self.assertRaises(self.m.AuthError): client.command(['sh', '-c', 'echo unsafe'])
        with self.assertRaises(self.m.AuthError): client.command(['gh', 'auth', 'token'])

    def test_real_openssl_jwt_has_verifiable_signature_and_bounded_claims(self):
        generated = subprocess.run(['openssl', 'genrsa', '-out', str(self.key), '2048'], capture_output=True)
        self.assertEqual(generated.returncode, 0)
        self.key.chmod(0o600)
        client = self.m.Client(self.config)
        with patch.object(self.m.time, 'time', return_value=10000):
            jwt = client._jwt()
        header, claims, signature = jwt.split('.')
        decode = lambda value: base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
        self.assertEqual(json.loads(decode(header)), {'alg': 'RS256', 'typ': 'JWT'})
        self.assertEqual(json.loads(decode(claims)), {'iat': 9940, 'exp': 10540, 'iss': '5512939'})
        public = self.directory / 'public.pem'
        result = subprocess.run(['openssl', 'rsa', '-in', str(self.key), '-pubout', '-out', str(public)], capture_output=True)
        self.assertEqual(result.returncode, 0)
        signature_path = self.directory / 'signature'
        signature_path.write_bytes(decode(signature))
        result = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', str(public), '-signature', str(signature_path)], input=(header + '.' + claims).encode(), capture_output=True)
        self.assertEqual(result.returncode, 0)

    def test_runner_redacts_echoed_token_and_rejects_explicit_token_export(self):
        import contextlib
        import io
        fake = self.m.Client(self.config)
        fake._token = 'ghs_testsecret'
        with patch.object(self.m, 'Client', return_value=fake), patch.object(fake, 'run', return_value=subprocess.CompletedProcess([], 1, 'ghs_testsecret', 'ghs_testsecret')):
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                self.assertEqual(self.m.main(['run', '--', 'gh', 'api', 'repos/Caldis/Pir']), 1)
            self.assertEqual(out.getvalue(), '[REDACTED]')
            self.assertEqual(err.getvalue(), '[REDACTED]')

    def test_local_headers_helpers_and_ssh_cannot_use_personal_credentials_even_for_gh_children(self):
        repo = self.directory / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', str(repo)], capture_output=True, check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'http.https://github.com/.extraheader', 'Authorization: fixture-personal'], check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'credential.helper', '!echo fixture-personal'], check=True)
        original = os.getcwd()
        self.addCleanup(os.chdir, original)
        os.chdir(repo)
        client = self.m.Client(self.config)
        client._token = 'ghs_testsecret'
        client._expires = __import__('time').time() + 3600
        with patch.dict(os.environ, {'GIT_SSH_COMMAND': 'echo fixture-personal', 'GH_CONFIG_DIR': str(repo)}):
            command, env = client.command(['gh', 'pr', 'create'])
        self.assertNotEqual(env['GH_CONFIG_DIR'], str(repo))
        self.assertEqual(env['HOME'], env['GH_CONFIG_DIR'])
        self.assertEqual(env['GIT_ALLOW_PROTOCOL'], 'https')
        self.assertEqual(env['GIT_SSH_COMMAND'], '/usr/bin/false')
        headers = subprocess.run(['git', 'config', '--get-all', 'http.https://github.com/.extraheader'], env=env, capture_output=True, text=True, check=True)
        self.assertTrue(headers.stdout.endswith('\n\n'))
        helpers = subprocess.run(['git', 'config', '--get-all', 'credential.helper'], env=env, capture_output=True, text=True, check=True)
        self.assertIn('\n\n!f()', helpers.stdout)
        self.assertNotIn('ghs_testsecret', helpers.stdout)
        denied = subprocess.run(['git', 'ls-remote', 'ssh://git@github.com:22/Caldis/Pir.git'], env=env, capture_output=True, text=True)
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn("transport 'ssh' not allowed", denied.stderr)
        self.assertNotIn('fixture-personal', denied.stderr)
        for url in ('https://github.com/Caldis/Other.git', 'https://other.invalid/Caldis/Pir.git'):
            credentials = subprocess.run(['git', 'credential', 'fill'], env=env, input='url=' + url + '\n', capture_output=True, text=True)
            self.assertNotEqual(credentials.returncode, 0)
            self.assertNotIn('ghs_testsecret', credentials.stdout)
        credentials = subprocess.run(['git', 'credential', 'fill'], env=env, input='url=https://github.com/Caldis/Pir.git\n', capture_output=True, text=True, check=True)
        self.assertIn('password=ghs_testsecret', credentials.stdout)

    def test_effective_remote_credentials_and_personal_rewrites_are_rejected(self):
        repo = self.directory / 'repo'
        subprocess.run(['git', 'init', str(repo)], capture_output=True, check=True)
        subprocess.run(['git', '-C', str(repo), 'remote', 'add', 'origin', 'https://github.com/Caldis/Pir.git'], check=True)
        original = os.getcwd()
        self.addCleanup(os.chdir, original)
        os.chdir(repo)
        client = self.m.Client(self.config)
        client._token = 'ghs_testsecret'
        client._expires = __import__('time').time() + 3600
        client.environment()
        subprocess.run(['git', 'config', 'remote.origin.pushurl', 'https://fixture-user:fixture-pass@github.com/Caldis/Pir.git'], check=True)
        with self.assertRaises(self.m.AuthError): client.environment()
        subprocess.run(['git', 'config', '--unset', 'remote.origin.pushurl'], check=True)
        subprocess.run(['git', 'config', 'url.https://fixture-user:fixture-pass@github.com/.insteadOf', 'https://github.com/'], check=True)
        with self.assertRaises(self.m.AuthError): client.command(['gh', 'pr', 'create'])

    def test_direct_url_cannot_use_personal_rewrite_without_named_remote(self):
        repo = self.directory / 'repo'
        subprocess.run(['git', 'init', str(repo)], capture_output=True, check=True)
        subprocess.run(['git', '-C', str(repo), 'config', 'url.https://fixture-user:fixture-pass@github.com/.insteadOf', 'https://github.com/'], check=True)
        original = os.getcwd()
        self.addCleanup(os.chdir, original)
        os.chdir(repo)
        client = self.m.Client(self.config)
        client._token = 'ghs_testsecret'
        client._expires = __import__('time').time() + 3600
        with self.assertRaises(self.m.AuthError): client.command(['git', 'ls-remote', 'https://github.com/Caldis/Pir.git'])

    def test_explicit_gh_auth_and_host_overrides_are_rejected_before_auth(self):
        client = self.m.Client(self.config)
        for args in (['-H', 'Authorization: fixture-personal'], ['--header=Authorization: fixture-personal'], ['--hostname', 'other.invalid'], ['https://fixture:personal@api.github.com/repos/Caldis/Pir']):
            with self.subTest(args=args), patch.object(client, 'environment') as env:
                with self.assertRaises(self.m.AuthError): client.command(['gh', 'api'] + args)
                env.assert_not_called()
