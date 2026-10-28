#!/usr/bin/env python3
"""Prepare Sparkle assets using the configured existing login key in a one-shot Aqua job."""
import argparse
import base64
import pathlib
import plistlib
import runpy
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = runpy.run_path(str(ROOT/'scripts/local-config.py'))


def job_files(label, directory, command):
    script = '#!/bin/sh\n' + shlex.join(command) + '\nresult=$?\nprintf "%s\\n" "$result" > ' + shlex.quote(str(directory/'status')) + '\nexit "$result"\n'
    spec = {'Label': label, 'ProgramArguments': ['/bin/sh', str(directory/'job.sh')],
            'RunAtLoad': True, 'KeepAlive': False, 'LimitLoadToSessionType': 'Aqua',
            'WorkingDirectory': str(directory), 'StandardOutPath': str(directory/'job.log'),
            'StandardErrorPath': str(directory/'job.log'),
            'EnvironmentVariables': {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'}}
    return plistlib.dumps(spec), script


def stage_inputs(stage):
    for name in ('scripts/local-config.py', 'scripts/sparkle-tool.sh', 'scripts/version-metadata.py', 'scripts/release/prepare-update.sh', 'scripts/release/update-feed.py', 'release/appcast.xml'):
        destination = stage/name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT/name, destination)


def update_command(folder, channel, account):
    return ['/usr/bin/env', 'PIR_LOCAL_CONFIG=-', 'PIR_SPARKLE_ACCOUNT=' + account, '/bin/bash', str(folder/'scripts/release/prepare-update.sh'), str(folder/'Pir.app'), channel, str(folder/'notes.html')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=pathlib.Path)
    parser.add_argument('--notes', type=pathlib.Path)
    parser.add_argument('--channel', choices=['stable', 'beta'], default='stable')
    parser.add_argument('--host')
    parser.add_argument('--config', type=pathlib.Path)
    parser.add_argument('--project-dir')
    parser.add_argument('--account')
    parser.add_argument('--timeout', type=float, default=300)
    parser.add_argument('--check-key', action='store_true', help='Only read and compare existing public key in Aqua')
    args = parser.parse_args()
    settings = CONFIG['load_config'](args.config, overrides={'PIR_SPARKLE_HOST': args.host, 'PIR_SPARKLE_PROJECT_DIR': args.project_dir, 'PIR_SPARKLE_ACCOUNT': args.account})
    CONFIG['require'](settings, 'PIR_SPARKLE_HOST', 'PIR_SPARKLE_PROJECT_DIR', 'PIR_SPARKLE_ACCOUNT')
    args.host = settings['PIR_SPARKLE_HOST']
    account = settings['PIR_SPARKLE_ACCOUNT']
    if args.timeout <= 0 or args.host.startswith('-'):
        parser.error('Positive timeout and SSH host are required')
    if not args.check_key and (not args.app or not args.app.is_dir() or not args.notes or not args.notes.is_file()):
        parser.error('--app and --notes must exist')
    def remote(*command, check=True):
        return subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', args.host, shlex.join(map(str, command))], capture_output=True, check=check, timeout=30)
    remote_home = remote('printenv', 'HOME').stdout.decode().strip()
    uid = remote('id', '-u').stdout.decode().strip()
    label = 'me.caldis.pir.prepare.' + uuid.uuid4().hex
    folder = pathlib.Path('/tmp')/label
    target = f'gui/{uid}/{label}'
    remote('mkdir', '-m', '700', str(folder))
    try:
        with tempfile.TemporaryDirectory(prefix='pir-prepare-') as temporary:
            stage = pathlib.Path(temporary)
            stage_inputs(stage)
            if args.check_key:
                command = [str(folder/'scripts/sparkle-tool.sh'), 'generate_keys', '--account', account, '-p']
            else:
                subprocess.run(['ditto', str(args.app.resolve()), str(stage/'Pir.app')], check=True)
                shutil.copy2(args.notes, stage/'notes.html')
                command = update_command(folder, args.channel, account)
            spec, script = job_files(label, folder, command)
            (stage/'job.plist').write_bytes(spec)
            (stage/'job.sh').write_text(script)
            # tar preserves framework symlinks; scp -r dereferences them.
            with tempfile.TemporaryFile() as archive:
                subprocess.run(['tar', '-cf', '-', '-C', str(stage), '.'], stdout=archive, check=True)
                archive.seek(0)
                subprocess.run(['ssh', '-o', 'BatchMode=yes', args.host, shlex.join(['tar', '-xf', '-', '-C', str(folder)])], stdin=archive, check=True, timeout=args.timeout)
            project = settings['PIR_SPARKLE_PROJECT_DIR']
            if project.startswith('~/'):
                project = str(pathlib.Path(remote_home)/project[2:])
            remote('ln', '-s', str(pathlib.Path(project)/'.build'), str(folder/'.build'))
            remote('launchctl', 'bootstrap', f'gui/{uid}', str(folder/'job.plist'))
            deadline = time.monotonic() + args.timeout
            while True:
                result = remote('cat', str(folder/'status'), check=False)
                if result.returncode == 0:
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError(f'Aqua task timed out after {args.timeout:g}s; inspect login/keychain availability')
                time.sleep(min(2, max(0, deadline-time.monotonic())))
            log = remote('cat', str(folder/'job.log')).stdout.decode()
            if result.stdout.strip() != b'0':
                raise RuntimeError('Aqua task failed:\n' + log)
            if args.check_key:
                expected = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())['SUPublicEDKey']
                if log.strip() != expected:
                    raise ValueError('Configured account public key differs from Pir application')
                print('Existing configured public key matches Pir; one-shot Aqua job succeeded')
                return
            output = stage/'output'
            output.mkdir()
            archive = remote('tar', '-cf', '-', '-C', str(folder/'dist/updates'), '.').stdout
            subprocess.run(['tar', '-xf', '-', '-C', str(output)], input=archive, check=True)
            info = plistlib.loads((args.app/'Contents/Info.plist').read_bytes())
            metadata = runpy.run_path(str(ROOT/'scripts/version-metadata.py'))['release_metadata'](info['CFBundleShortVersionString'], info['CFBundleVersion'], args.channel)
            verify = runpy.run_path(str(ROOT/'scripts/release/verify-public.py'))
            verify['verify_hashes'](output, [metadata['archive'], 'appcast.xml'])
            verify['verify_updates'](output, info['CFBundleShortVersionString'], info['CFBundleVersion'], metadata['archive'], base64.b64decode(info['SUPublicEDKey'], validate=True), args.channel)
            destination = ROOT/'dist/updates'
            destination.mkdir(parents=True, exist_ok=True)
            for name in (metadata['archive'], 'appcast.xml', 'SHA256SUMS'):
                shutil.copy2(output/name, destination/name)
            shutil.copy2(output/'appcast.xml', ROOT/'release/appcast.xml')
            print(f'Independently verified Sparkle assets: {destination}')
    finally:
        try:
            remote('launchctl', 'bootout', target, check=False)
        finally:
            remote('rm', '-rf', str(folder), check=False)


if __name__ == '__main__':
    for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(name, lambda number, frame: (_ for _ in ()).throw(SystemExit(128+number)))
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error))
