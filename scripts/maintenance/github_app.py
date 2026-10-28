#!/usr/bin/env python3
"""Run bounded Pir maintenance commands as the native GitHub App installation."""
import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import stat
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from urllib.parse import urlsplit
import weakref

APP_ID = 5512939
APP_SLUG = 'pir-maintainer'
BOT_USER_ID = 349413745
INSTALLATION_ID = 176235800
OWNER = 'Caldis'
REPOSITORY = 'Caldis/Pir'
PERMISSIONS = {'issues': 'write', 'pull_requests': 'write', 'contents': 'write',
               'actions': 'read', 'checks': 'read', 'metadata': 'read'}
DEFAULT_CONFIG = Path.home() / '.config/pir/maintenance/github-app.json'


class AuthError(RuntimeError):
    """Only fixed diagnostics may cross the credential boundary."""


def private_path(path, directory=False):
    try:
        info = path.lstat()
        kind = stat.S_ISDIR if directory else stat.S_ISREG
        if not kind(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != (0o700 if directory else 0o600):
            raise AuthError('GitHub App local credential permissions are unsafe')
    except OSError:
        raise AuthError('GitHub App local credential is unavailable') from None


def permissions_valid(value):
    return isinstance(value, dict) and all(value.get(key) == level for key, level in PERMISSIONS.items())


def allowed_remote(url):
    return url in {prefix + suffix for prefix in ('https://github.com/Caldis/Pir',
        'git@github.com:Caldis/Pir', 'ssh://git@github.com/Caldis/Pir') for suffix in ('', '.git')}


class Client:
    def __init__(self, config=DEFAULT_CONFIG):
        self._token = None
        self._expires = 0
        self._actor = None
        self.config_path = Path(config).expanduser()
        private_path(self.config_path.parent, directory=True)
        private_path(self.config_path)
        try:
            value = json.loads(self.config_path.read_text())
            expected = {'app_id': APP_ID, 'app_slug': APP_SLUG, 'installation_id': INSTALLATION_ID,
                        'owner': OWNER, 'repository': REPOSITORY}
            if not isinstance(value, dict) or set(value) != set(expected) | {'private_key_path'}:
                raise ValueError()
            if any(type(value[key]) is not type(wanted) or value[key] != wanted for key, wanted in expected.items()):
                raise ValueError()
            if not isinstance(value['private_key_path'], str): raise ValueError()
            self.key = Path(value['private_key_path']).expanduser()
            if not self.key.is_absolute(): raise ValueError()
            checkout = Path(__file__).resolve().parents[2]
            if self.key.resolve().is_relative_to(checkout) or any((parent / '.git').exists() for parent in self.key.resolve().parents): raise ValueError()
        except (ValueError, TypeError, OSError):
            raise AuthError('GitHub App configuration is invalid') from None
        private_path(self.key.parent, directory=True)
        private_path(self.key)
        self._gh_config = tempfile.mkdtemp(prefix='pir-github-app-')
        weakref.finalize(self, shutil.rmtree, self._gh_config, ignore_errors=True)

    def _jwt(self):
        # OpenSSL reads the PEM itself; neither private key nor signature enters argv.
        private_path(self.key)
        encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b'=')
        now = int(time.time())
        signing = encode(b'{"alg":"RS256","typ":"JWT"}') + b'.' + encode(json.dumps({'iat': now - 60, 'exp': now + 540, 'iss': str(APP_ID)}, separators=(',', ':')).encode())
        try:
            result = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(self.key)],
                                    input=signing, capture_output=True, timeout=10)
            if result.returncode: raise AuthError('GitHub App signing failed')
        except (OSError, subprocess.TimeoutExpired):
            raise AuthError('GitHub App signing failed') from None
        return (signing + b'.' + encode(result.stdout)).decode('ascii')

    def _request(self, endpoint, credential, *, data=None):
        request = urllib.request.Request('https://api.github.com' + endpoint,
            data=json.dumps(data).encode() if data is not None else None,
            headers={'Authorization': 'Bearer ' + credential, 'Accept': 'application/vnd.github+json',
                     'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Pir-maintainer'})
        # Do not follow redirects carrying Authorization to another endpoint/host.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs): return None
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
                value = json.load(response)
            if not isinstance(value, dict): raise ValueError()
            return value
        except Exception:
            raise AuthError('GitHub App API request failed; verify installation access') from None

    def _refresh(self):
        self._token, self._expires, self._actor = None, 0, None
        try:
            jwt = self._jwt()
            app = self._request('/app', jwt)
            if app.get('id') != APP_ID or app.get('slug') != APP_SLUG:
                raise AuthError('GitHub App identity mismatch')
            installation = self._request(f'/app/installations/{INSTALLATION_ID}', jwt)
            if (installation.get('id') != INSTALLATION_ID or installation.get('app_id') != APP_ID
                or installation.get('account', {}).get('login') != OWNER
                or installation.get('repository_selection') != 'selected'
                or installation.get('suspended_at') is not None
                or not permissions_valid(installation.get('permissions'))):
                raise AuthError('GitHub App installation identity or permissions mismatch')
            value = self._request(f'/app/installations/{INSTALLATION_ID}/access_tokens', jwt,
                                  data={'repositories': ['Pir'], 'permissions': PERMISSIONS})
            token = value.get('token')
            expires = datetime.fromisoformat(value['expires_at'].replace('Z', '+00:00')).timestamp()
            now = time.time()
            if not isinstance(token, str) or not token or not now + 300 < expires <= now + 3700 or not permissions_valid(value.get('permissions')):
                raise AuthError('GitHub App installation token is expired or has invalid permissions')
            repositories = self._request('/installation/repositories?per_page=100', token)
            if repositories.get('total_count') != 1 or [r.get('full_name') for r in repositories.get('repositories', [])] != [REPOSITORY]:
                raise AuthError('GitHub App token repository scope mismatch')
            actor = self._request(f'/user/{BOT_USER_ID}', token)
            if (actor.get('id') != BOT_USER_ID or actor.get('type') != 'Bot'
                or not isinstance(actor.get('login'), str) or not actor['login'].endswith('[bot]')):
                raise AuthError('GitHub App bot identity mismatch')
            self._token, self._expires, self._actor = token, expires, actor['login']
        except AuthError:
            raise
        except (ValueError, KeyError, TypeError, AttributeError):
            raise AuthError('GitHub App returned invalid installation data') from None

    def actor(self):
        self.environment()
        return self._actor

    def environment(self):
        if not self._token or self._expires <= time.time() + 300: self._refresh()
        env = {key: value for key, value in os.environ.items()
               if key not in ('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN', 'GH_HOST', 'GH_CONFIG_DIR', 'GH_DEBUG', 'GIT_CURL_VERBOSE')
               and not key.startswith(('GIT_CONFIG', 'GIT_SSH', 'GIT_TRACE'))}
        env.update(GH_TOKEN=self._token, GH_HOST='github.com', GH_PROMPT_DISABLED='1',
                   GH_CONFIG_DIR=self._gh_config, HOME=self._gh_config, GIT_TERMINAL_PROMPT='0',
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                   GIT_ALLOW_PROTOCOL='https', GIT_SSH_COMMAND='/usr/bin/false',
                   GIT_ASKPASS='/usr/bin/false', SSH_ASKPASS='/usr/bin/false')
        # These settings also protect Git spawned by gh pr create/release commands.
        helper = '!f() { host=; path=; while IFS="=" read -r k v; do case "$k" in host) host="$v";; path) path="$v";; esac; done; if [ "$1" = get ] && [ "$host" = github.com ] && { [ "$path" = Caldis/Pir ] || [ "$path" = Caldis/Pir.git ]; }; then printf "username=x-access-token\\npassword=%s\\n" "$GH_TOKEN"; fi; }; f'
        settings = [('credential.helper', ''), ('credential.helper', helper),
                    ('credential.useHttpPath', 'true'), ('http.extraHeader', ''),
                    ('http.followRedirects', 'false'),
                    ('url.https://github.com/Caldis/Pir.insteadOf', 'git@github.com:Caldis/Pir'),
                    ('url.https://github.com/Caldis/Pir.insteadOf', 'ssh://git@github.com/Caldis/Pir')]
        # Clear URL-scoped headers too. Read names only; credential values never enter output.
        try:
            result = subprocess.run(['git', 'config', '--local', '--name-only', '--get-regexp',
                                     r'^http\..*extraheader$'], env=env, capture_output=True, text=True, timeout=10)
            if result.returncode not in (0, 1, 128): raise AuthError('GitHub App Git configuration check failed')
            if result.returncode == 0:
                for key in result.stdout.splitlines():
                    if not key.lower().startswith('http.') or not key.lower().endswith('extraheader'):
                        raise AuthError('GitHub App Git configuration check failed')
                    settings.append((key, ''))
        except (OSError, subprocess.TimeoutExpired):
            raise AuthError('GitHub App Git configuration check failed') from None
        # URL-embedded credentials bypass credential helpers. Check effective fetch/push
        # URLs after Git applies local insteadOf/pushInsteadOf mappings.
        try:
            remotes = subprocess.run(['git', 'remote'], env=env, capture_output=True, text=True, timeout=10)
            if remotes.returncode not in (0, 128): raise AuthError('GitHub App Git remote check failed')
            if remotes.returncode == 0:
                for remote in remotes.stdout.splitlines():
                    for direction in ([], ['--push']):
                        urls = subprocess.run(['git', 'remote', 'get-url', '--all'] + direction + [remote],
                                              env=env, capture_output=True, text=True, timeout=10)
                        if urls.returncode or not urls.stdout.splitlines() or any(not allowed_remote(url) for url in urls.stdout.splitlines()):
                            raise AuthError('GitHub App requires credential-free Caldis/Pir Git remotes')
        except (OSError, subprocess.TimeoutExpired):
            raise AuthError('GitHub App Git remote check failed') from None
        env['GIT_CONFIG_COUNT'] = str(len(settings))
        for index, (key, value) in enumerate(settings):
            env['GIT_CONFIG_KEY_' + str(index)] = key
            env['GIT_CONFIG_VALUE_' + str(index)] = value
        return env

    def command(self, command):
        if len(command) < 2 or command[0] not in ('gh', 'git'):
            raise AuthError('GitHub App runner accepts gh or git commands only')
        if command[0] == 'gh' and command[1] not in ('api', 'issue', 'pr', 'release', 'run', 'workflow', 'project', 'repo'):
            raise AuthError('GitHub App runner command is not supported')
        if command[0] == 'gh':
            if any(arg.startswith(('-H', '--header', '--hostname')) for arg in command[2:]):
                raise AuthError('GitHub App runner does not accept authentication or host overrides')
            for arg in command[2:]:
                if arg.startswith(('https://', 'http://')):
                    url = urlsplit(arg)
                    if url.scheme != 'https' or url.hostname not in ('github.com', 'api.github.com') or url.username or url.password:
                        raise AuthError('GitHub App runner URL is not supported')
        if command[0] == 'git':
            if command[1] not in ('push', 'fetch', 'pull', 'clone', 'ls-remote') or any(
                arg.startswith(('-c', '--config', '--exec-path', '--upload-pack', '--receive-pack')) for arg in command[2:]):
                raise AuthError('GitHub App Git command is not supported')
        if command[0] == 'git' and any('://' in arg and not allowed_remote(arg.split('=', 1)[-1]) for arg in command[2:]):
            raise AuthError('GitHub App command URL is not supported')
        env = self.environment()
        if command[0] == 'git':
            for arg in command[2:]:
                if '://' not in arg and not arg.startswith('git@'): continue
                try:
                    resolved = subprocess.run(['git', 'ls-remote', '--get-url', arg], env=env,
                                              capture_output=True, text=True, timeout=10)
                    if resolved.returncode or not allowed_remote(resolved.stdout.strip()):
                        raise AuthError('GitHub App requires credential-free Caldis/Pir Git URLs')
                except (OSError, subprocess.TimeoutExpired):
                    raise AuthError('GitHub App Git URL check failed') from None
        return command, env

    def run(self, command, **kwargs):
        command, env = self.command(command)
        try:
            return subprocess.run(command, env=env, **kwargs)
        except (OSError, subprocess.TimeoutExpired):
            raise AuthError('GitHub App command failed or timed out') from None

    def summary(self):
        self.environment()
        return {'appId': APP_ID, 'appSlug': APP_SLUG, 'installationId': INSTALLATION_ID,
                'actor': self._actor, 'botUserId': BOT_USER_ID, 'repository': REPOSITORY, 'permissions': PERMISSIONS,
                'expiresAt': datetime.fromtimestamp(self._expires, timezone.utc).isoformat()}


_default = None


def client():
    global _default
    if _default is None: _default = Client()
    return _default


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    parser.add_argument('operation', choices=('check', 'run'))
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        auth = Client(args.config)
        if args.operation == 'check':
            if args.command: parser.error('check accepts no command')
            print(json.dumps(auth.summary(), indent=2))
            return 0
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        result = auth.run(command, capture_output=True, text=True, timeout=300)
        # A child may echo its environment on failure; never forward our bearer token.
        for stream, output in ((sys.stdout, result.stdout), (sys.stderr, result.stderr)):
            stream.write(output.replace(auth._token, '[REDACTED]'))
        return result.returncode
    except AuthError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
