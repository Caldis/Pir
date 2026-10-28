#!/usr/bin/env python3
"""Read private maintenance settings as data; initialize only verified local values."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ('PIR_SIGNING_DIR', 'PIR_SIGN_IDENTITY', 'PIR_SIGNING_GUIDE',
          'PIR_SPARKLE_HOST', 'PIR_SPARKLE_PROJECT_DIR', 'PIR_SPARKLE_ACCOUNT', 'PIR_EVIDENCE_DIR')
PATH_FIELDS = {'PIR_SIGNING_DIR', 'PIR_SIGNING_GUIDE', 'PIR_SPARKLE_PROJECT_DIR', 'PIR_EVIDENCE_DIR'}


def validate(name, value, home):
    if name not in FIELDS:
        raise ValueError('Unknown maintenance field')
    if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value) or any(c in value for c in ('$', '`')):
        raise ValueError(f'Invalid value for {name}')
    if not value:
        return ''
    if name in PATH_FIELDS:
        # Remote project paths expand against the remote HOME, never the local one.
        if value.startswith('~/') and name != 'PIR_SPARKLE_PROJECT_DIR':
            value = str(home/value[2:])
        if not value.startswith('/') and not (name == 'PIR_SPARKLE_PROJECT_DIR' and value.startswith('~/')):
            raise ValueError(f'{name} requires an absolute path or ~/ path')
    elif name == 'PIR_SPARKLE_HOST':
        if value.startswith('-') or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.@:-]*', value):
            raise ValueError(f'Invalid value for {name}')
    elif name == 'PIR_SPARKLE_ACCOUNT':
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.@-]*', value):
            raise ValueError(f'Invalid value for {name}')
    elif name == 'PIR_SIGN_IDENTITY':
        if not re.fullmatch(r'[0-9A-Fa-f]{40}', value) and not value.startswith('Developer ID Application: '):
            raise ValueError(f'Invalid value for {name}')
    return value


def read_config(path, home, repository_fallback=False):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return {}
    parent = path.parent.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600
            or not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid()
            or (not repository_fallback and stat.S_IMODE(parent.st_mode) != 0o700)):
        raise ValueError('Maintenance config requires an owned regular 0600 file in an owned 0700 directory; symlinks are rejected')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, encoding='utf-8') as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
            raise ValueError('Maintenance config changed while opening')
        try:
            text = stream.read(65537)
        except UnicodeError:
            raise ValueError('Maintenance config must be UTF-8 text') from None
    if len(text) > 65536:
        raise ValueError('Maintenance config is too large')
    values = {}
    for number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'([A-Z][A-Z0-9_]*)=(.*)', line)
        if not match:
            raise ValueError(f'Malformed maintenance config line {number}')
        name, value = match.groups()
        if name not in FIELDS or name in values:
            raise ValueError(f'Unknown or duplicate maintenance field on line {number}')
        value = value.strip()
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except (ValueError, TypeError):
                raise ValueError(f'Malformed maintenance config line {number}') from None
        elif value.startswith("'"):
            if len(value) < 2 or not value.endswith("'") or "'" in value[1:-1]:
                raise ValueError(f'Malformed maintenance config line {number}')
            value = value[1:-1]
        elif any(c in value for c in ('"', "'", '#')):
            raise ValueError(f'Malformed maintenance config line {number}')
        values[name] = validate(name, value, home)
    return values


def selected_config_path(config, environment, home):
    selected = config or environment.get('PIR_LOCAL_CONFIG')
    if str(selected) == '-':
        return None
    if not selected:
        return home/'.config/pir/maintenance/local.env'
    value = str(selected)
    return home/value[2:] if value.startswith('~/') else Path(value)


def load_config(config=None, *, environ=None, overrides=None, home=None, root=ROOT):
    environment = os.environ if environ is None else environ
    home = Path.home() if home is None else Path(home)
    selected = config or environment.get('PIR_LOCAL_CONFIG')
    path = selected_config_path(config, environment, home)
    if path is None:
        result = {}
    else:
        fallback = False
        if selected and not path.exists() and not path.is_symlink():
            raise ValueError('Selected maintenance config is missing; run init or select an existing file')
        if not selected and not path.exists() and not path.is_symlink():
            path = Path(root)/'.env.local'
            fallback = True
        result = read_config(path, home, fallback)
    for source in (environment, overrides or {}):
        for name in FIELDS:
            if source.get(name) is not None:
                result[name] = validate(name, source[name], home)
    return {name: value for name, value in result.items() if value}


def require(values, *names):
    missing = [name for name in names if not values.get(name)]
    if missing:
        raise ValueError('Missing maintenance settings: ' + ', '.join(missing) + '; run scripts/local-config.py init, then supply unresolved fields')


def execute(command, **kwargs):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=15, **kwargs)
    except (OSError, subprocess.TimeoutExpired):
        raise ValueError('Local signing candidate could not be inspected') from None
    if result.returncode:
        raise ValueError('Local signing candidate could not be validated')
    return result.stdout.strip()


def certificate_identity(keys, openssl='openssl', execute=execute, *, expected=None):
    certificate, key = keys/'dev-id-app.pem', keys/'dev-id-app.key'
    if not certificate.is_file() or not key.is_file() or certificate.is_symlink() or key.is_symlink():
        raise ValueError('Existing certificate and paired key are required')
    subject = execute([openssl, 'x509', '-in', str(certificate), '-noout', '-subject', '-nameopt', 'sep_multiline,sname,utf8'])
    common_names = re.findall(r'^\s*CN\s*=\s*(.+)$', subject, flags=re.MULTILINE)
    if len(common_names) != 1 or not common_names[0].startswith('Developer ID Application: '):
        raise ValueError('Signing certificate must be Developer ID Application')
    execute([openssl, 'x509', '-in', str(certificate), '-noout', '-checkend', '0'])
    public = execute([openssl, 'x509', '-in', str(certificate), '-noout', '-pubkey'])
    paired = execute([openssl, 'pkey', '-in', str(key), '-passin', 'pass:', '-pubout'])
    if public.strip() != paired.strip():
        raise ValueError('Signing certificate and private key do not match')
    fingerprint = execute([openssl, 'x509', '-in', str(certificate), '-noout', '-fingerprint', '-sha1'])
    identity = fingerprint.rsplit('=', 1)[-1].replace(':', '').strip()
    if not re.fullmatch('[0-9A-Fa-f]{40}', identity):
        raise ValueError('Signing certificate fingerprint unavailable')
    if expected is not None:
        matches = identity.upper() == expected.upper() if re.fullmatch(r'[0-9A-Fa-f]{40}', expected) else common_names[0] == expected
        if not matches:
            raise ValueError('Configured PIR_SIGN_IDENTITY differs from existing certificate')
    return identity.upper()


def discover(home=None, execute=execute):
    home = Path.home() if home is None else Path(home)
    values = {'PIR_EVIDENCE_DIR': str(home/'.config/pir/maintenance/evidence')}
    candidates = []
    for folder in (home/'Docs/ci-signing/keys', home/'Documents/ci-signing/keys'):
        if folder.is_symlink() or not folder.is_dir():
            continue
        try:
            identity = certificate_identity(folder, execute=execute)
        except ValueError:
            continue
        candidates.append((folder, identity))
    if len(candidates) == 1:
        folder, identity = candidates[0]
        values.update(PIR_SIGNING_DIR=str(folder), PIR_SIGN_IDENTITY=identity)
        guide = folder.parent/'github-macos-codesign.md'
        if guide.is_file() and not guide.is_symlink():
            values['PIR_SIGNING_GUIDE'] = str(guide)
    return values, [name for name in FIELDS if name not in values]


def write_config(path, values):
    path = Path(path)
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    parent = path.parent.lstat()
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700:
        raise ValueError('Maintenance config directory must be owned, regular and 0700')
    payload = '# Private maintenance settings; values are data, never shell commands.\n'
    for name in FIELDS:
        payload += name + '=' + json.dumps(validate(name, values.get(name, ''), Path.home())) + '\n'
    temporary = None
    try:
        descriptor, temporary = tempfile.mkstemp(prefix='.local-env-', dir=path.parent)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        # A hard link publishes the complete file atomically without overwriting.
        os.link(temporary, path)
    finally:
        if temporary:
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path)
    commands = parser.add_subparsers(dest='command', required=True)
    initialize = commands.add_parser('init')
    initialize.add_argument('--json', action='store_true')
    check = commands.add_parser('check')
    check.add_argument('--json', action='store_true')
    check.add_argument('--require', nargs='+', choices=FIELDS, default=list(FIELDS))
    get = commands.add_parser('get', help='Print one explicitly requested value for a helper')
    get.add_argument('field', choices=FIELDS)
    args = parser.parse_args()
    try:
        if args.command == 'init':
            destination = selected_config_path(args.config, os.environ, Path.home())
            if destination is None:
                raise ValueError('Maintenance config loading is disabled; select a private config file to initialize')
            values, unresolved = discover()
            write_config(destination, values)
            if args.json:
                print(json.dumps({'initialized': True, 'configured': list(values), 'missing': unresolved}))
                return 0
            print('Private maintenance config initialized')
            if unresolved:
                print('Owner input required for unresolved or ambiguous fields: ' + ', '.join(unresolved))
            return 0
        values = load_config(args.config)
        if args.command == 'get':
            require(values, args.field)
            print(values[args.field])
        else:
            if args.json:
                missing = [name for name in args.require if name not in values]
                print(json.dumps({'configured': list(values), 'missing': missing}))
                return int(bool(missing))
            require(values, *args.require)
            print('Required maintenance settings are configured')
        return 0
    except (ValueError, OSError) as error:
        # Filesystem errors can expose personal paths; only expose field-level errors.
        print(str(error) if isinstance(error, ValueError) else 'Maintenance config unavailable or already exists; no file overwritten', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
