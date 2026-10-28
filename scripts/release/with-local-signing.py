#!/usr/bin/env python3
"""Run a release command with existing local certificate/key in a disposable keychain."""
import argparse
import contextlib
import datetime
import json
import os
import pathlib
import runpy
import secrets
import shlex
import signal
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = runpy.run_path(str(ROOT/'scripts/local-config.py'))


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode:
        # Command arguments can contain ephemeral passwords. Never print them.
        raise RuntimeError(f'{pathlib.Path(command[0]).name} {command[1]} failed ({result.returncode})')
    return result.stdout


@contextlib.contextmanager
def local_keychain(keys, openssl, execute=run, recovery_dir=None):
    for name in ('dev-id-app.key', 'dev-id-app.pem'):
        if not (keys / name).is_file():
            raise RuntimeError('Existing signing material unavailable; inspect PIR_SIGNING_DIR and PIR_SIGNING_GUIDE')
    original = shlex.split(execute(['security', 'list-keychains', '-d', 'user']))
    with tempfile.TemporaryDirectory(prefix='pir-signing-') as directory:
        folder = pathlib.Path(directory)
        keychain = str(folder / 'release.keychain-db')
        password = secrets.token_hex(32)
        created = False
        recovery_dir = pathlib.Path(recovery_dir) if recovery_dir is not None else pathlib.Path.home()/'.config/pir/maintenance/signing'
        recovery = recovery_dir/(folder.name + '.json')
        try:
            execute([openssl, 'pkcs12', '-export', '-legacy', '-inkey', str(keys/'dev-id-app.key'), '-in', str(keys/'dev-id-app.pem'), '-out', str(folder/'identity.p12'), '-passout', 'stdin'], input=password+'\n')
            # create-keychain itself may change the search list: persist first.
            recovery_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            with recovery.open('x', encoding='utf-8') as record:
                os.chmod(recovery, 0o600)
                json.dump({'originalKeychains': original, 'temporaryKeychain': keychain,
                           'pid': os.getpid(), 'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()}, record)
                record.flush()
                os.fsync(record.fileno())
            execute(['security', 'create-keychain', '-p', password, keychain])
            created = True
            execute(['security', 'set-keychain-settings', '-lut', '21600', keychain])
            execute(['security', 'unlock-keychain', '-p', password, keychain])
            execute(['security', 'import', str(folder/'identity.p12'), '-k', keychain, '-P', password, '-T', '/usr/bin/codesign'])
            execute(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain])
            execute(['security', 'list-keychains', '-d', 'user', '-s', keychain, *original])
            yield
        finally:
            if created:
                try:
                    execute(['security', 'list-keychains', '-d', 'user', '-s', *original])
                finally:
                    execute(['security', 'delete-keychain', keychain])
                recovery.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=pathlib.Path)
    parser.add_argument('--signing-dir')
    parser.add_argument('--identity')
    parser.add_argument('--evidence-dir')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    settings = CONFIG['load_config'](args.config, overrides={'PIR_SIGNING_DIR': args.signing_dir, 'PIR_SIGN_IDENTITY': args.identity, 'PIR_EVIDENCE_DIR': args.evidence_dir})
    CONFIG['require'](settings, 'PIR_SIGNING_DIR', 'PIR_SIGN_IDENTITY')
    openssl = runpy.run_path(str(ROOT/'scripts/release/verify-public.py'))['resolve_openssl']()
    for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(name, lambda number, frame: sys.exit(128 + number))
    environment = dict(os.environ)
    keys = pathlib.Path(settings['PIR_SIGNING_DIR'])
    identity = CONFIG['certificate_identity'](keys, openssl, expected=settings['PIR_SIGN_IDENTITY'])
    # Use the verified paired certificate, avoiding name matches in other keychains.
    environment['PIR_SIGN_IDENTITY'] = identity
    command = args.command or [str(ROOT/'scripts/release.sh')]
    if command[:1] == ['--']:
        command = command[1:]
    recovery = pathlib.Path(settings['PIR_EVIDENCE_DIR'])/'signing' if settings.get('PIR_EVIDENCE_DIR') else None
    with local_keychain(keys, openssl, recovery_dir=recovery):
        return run_command(command, environment)


def run_command(command, environment):
    process = subprocess.Popen(command, cwd=ROOT, env=environment, start_new_session=True)
    try:
        return process.wait()
    finally:
        # The command may have exited while build/notary descendants still run.
        # Stop the entire isolated group before the signing keychain is removed.
        for action in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(process.pid, action)
            except ProcessLookupError:
                pass
            if action == signal.SIGTERM:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
        process.wait()



if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, ValueError) as error:
        sys.exit(str(error))
