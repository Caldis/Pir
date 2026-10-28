#!/usr/bin/env python3
"""Independently verify public release hashes, Sparkle signatures and macOS trust."""
import argparse
import base64
import hashlib
import os
import pathlib
import plistlib
import re
import runpy
import shutil
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def resolve_openssl():
    override = os.environ.get('PIR_OPENSSL')
    candidates = [override] if override else [
        '/opt/homebrew/opt/openssl@3/bin/openssl',
        '/usr/local/opt/openssl@3/bin/openssl',
        shutil.which('openssl')]
    for candidate in candidates:
        if not candidate:
            continue
        path = pathlib.Path(candidate).expanduser()
        if not path.is_absolute():
            path = pathlib.Path(shutil.which(str(path)) or path).resolve()
        if not path.is_file():
            continue
        try:
            result = subprocess.run([str(path), 'version'], capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and result.stdout.startswith('OpenSSL 3.'):
            return str(path.resolve())
    raise RuntimeError('OpenSSL 3 is required for Ed25519 and legacy PKCS12; install openssl@3 with Homebrew or set PIR_OPENSSL to its executable path')


def verify_hashes(directory, names):
    sums = {}
    for line in (directory/'SHA256SUMS').read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = name.lstrip('*')
        if name in sums or pathlib.Path(name).name != name:
            raise ValueError('Ambiguous SHA256 manifest')
        sums[name] = digest
    for name in names:
        if hashlib.sha256((directory/name).read_bytes()).hexdigest() != sums.get(name):
            raise ValueError(f'SHA256 mismatch: {name}')


def verify_signature(payload, signature, public):
    if len(public) != 32 or len(signature) != 64:
        raise ValueError('Invalid Ed25519 key or signature length')
    with tempfile.TemporaryDirectory(prefix='pir-verify-') as directory:
        folder = pathlib.Path(directory)
        (folder/'key').write_bytes(bytes.fromhex('302a300506032b6570032100') + public)
        (folder/'payload').write_bytes(payload)
        (folder/'signature').write_bytes(signature)
        result = subprocess.run([resolve_openssl(), 'pkeyutl', '-verify', '-pubin', '-keyform', 'DER', '-inkey', str(folder/'key'), '-rawin', '-in', str(folder/'payload'), '-sigfile', str(folder/'signature')], capture_output=True)
        if result.returncode:
            raise RuntimeError('Independent Ed25519 verification failed')


def verify_updates(directory, version, build, archive, public, channel='stable'):
    feed = (directory/'appcast.xml').read_bytes()
    match = re.search(rb'<!-- sparkle-signatures:\s*edSignature: ([A-Za-z0-9+/=]+)\s*length: (\d+)\s*-->\s*$', feed)
    if not match or int(match[2]) != match.start():
        raise ValueError('Signed feed trailer or payload length is invalid')
    verify_signature(feed[:int(match[2])], base64.b64decode(match[1], validate=True), public)
    item = ET.fromstring(feed).find('./channel/item')
    if item is None or item.findtext(NS+'shortVersionString') != version or item.findtext(NS+'version') != build:
        raise ValueError('Feed latest version/build mismatch')
    metadata = runpy.run_path(str(ROOT/'scripts/version-metadata.py'))['release_metadata'](version, build, channel)
    expected_url = f'https://github.com/Caldis/Pir/releases/download/{metadata["tag"]}/{metadata["archive"]}'
    enclosure = item.find('enclosure')
    if archive != metadata['archive'] or enclosure is None or enclosure.get('url') != expected_url or int(enclosure.get('length', '-1')) != (directory/archive).stat().st_size:
        raise ValueError('Feed archive metadata mismatch')
    verify_signature((directory/archive).read_bytes(), base64.b64decode(enclosure.get(NS+'edSignature', ''), validate=True), public)


def verify_app(app, version, build, public):
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'), info.get('CFBundleVersion'), base64.b64decode(info.get('SUPublicEDKey', ''))) != ('me.caldis.pir', version, build, public):
        raise ValueError('Downloaded application metadata mismatch')
    for command in (['codesign', '--verify', '--deep', '--strict', str(app)], ['xcrun', 'stapler', 'validate', str(app)], ['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)]):
        subprocess.run(command, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--channel', choices=['stable', 'beta'], default='stable')
    parser.add_argument('--directory', type=pathlib.Path)
    parser.add_argument('--local', type=pathlib.Path, help='Verify already downloaded assets without networking')
    parser.add_argument('--compare-feed', action='store_true', help='Require published feed bytes to match release/appcast.xml')
    args = parser.parse_args()
    metadata = runpy.run_path(str(ROOT/'scripts/version-metadata.py'))['release_metadata'](args.version, args.build, args.channel)
    directory = args.local or args.directory or ROOT/'dist/public-verification'/metadata['tag']
    directory.mkdir(parents=True, exist_ok=True)
    dmg, archive = f'Pir-{args.version}-universal.dmg', metadata['archive']
    if not args.local:
        base = f'https://github.com/Caldis/Pir/releases/download/{metadata["tag"]}/'
        for name in (dmg, archive, 'SHA256SUMS', 'appcast.xml'):
            url = 'https://github.com/Caldis/Pir/releases/download/update-feed/appcast.xml' if name == 'appcast.xml' else base+name
            with urllib.request.urlopen(url, timeout=60) as response:
                (directory/name).write_bytes(response.read())
    verify_hashes(directory, [dmg, archive])
    public = base64.b64decode(plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())['SUPublicEDKey'], validate=True)
    verify_updates(directory, args.version, args.build, archive, public, args.channel)
    if args.compare_feed and (directory/'appcast.xml').read_bytes() != (ROOT/'release/appcast.xml').read_bytes():
        raise ValueError('Published feed differs from repository')
    with tempfile.TemporaryDirectory(prefix='pir-public-') as temporary:
        folder = pathlib.Path(temporary)
        subprocess.run(['ditto', '-x', '-k', str(directory/archive), str(folder/'zip')], check=True)
        verify_app(folder/'zip/Pir.app', args.version, args.build, public)
        subprocess.run(['codesign', '--verify', '--strict', str(directory/dmg)], check=True)
        subprocess.run(['hdiutil', 'verify', str(directory/dmg)], check=True)
        subprocess.run(['xcrun', 'stapler', 'validate', str(directory/dmg)], check=True)
        mount = folder/'mount'
        try:
            subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(directory/dmg)], check=True)
            verify_app(mount/'Pir.app', args.version, args.build, public)
        finally:
            if mount.is_mount():
                subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
    print(f'Public release verified: {metadata["tag"]} / {args.build}')


if __name__ == '__main__':
    main()
