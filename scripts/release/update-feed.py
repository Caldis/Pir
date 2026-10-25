#!/usr/bin/env python3
import base64
import datetime
import email.utils
import pathlib
import plistlib
import runpy
import sys
import urllib.parse
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)
VERSION_POLICY = runpy.run_path(str(pathlib.Path(__file__).resolve().parents[1] / 'version-metadata.py'))
build_order = VERSION_POLICY['build_order']
release_metadata = VERSION_POLICY['release_metadata']


def field(name):
    return '{' + SPARKLE + '}' + name


def metadata(app, channel, public_key, source):
    info = plistlib.loads((pathlib.Path(app) / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'me.caldis.pir':
        raise ValueError('Release app must be Pir')
    version, build = info.get('CFBundleShortVersionString', ''), info.get('CFBundleVersion', '')
    names = release_metadata(version, build, channel)
    order = build_order(build)
    if len(base64.b64decode(public_key, validate=True)) != 32 or info.get('SUPublicEDKey') != public_key:
        raise ValueError('App public key must match the Pir Keychain signing account')
    feed = ET.parse(source)
    previous = []
    for item in feed.findall('./channel/item'):
        enclosure = item.find('enclosure')
        old_build = item.findtext(field('version'))
        if old_build is None and enclosure is not None:
            old_build = enclosure.get(field('version'))
        if old_build:
            previous.append(build_order(old_build))
    if previous and order <= max(previous):
        raise ValueError('Build must be newer than every release already in the appcast')
    return info, feed, names['archive'], names['tag']


def prepare(app, channel, public_key, source, archive, signature, notes, output):
    info, feed, filename, tag = metadata(app, channel, public_key, source)
    archive = pathlib.Path(archive)
    if archive.name != filename or len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Update archive name or EdDSA signature is invalid')
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = 'Pir ' + info['CFBundleShortVersionString']
    ET.SubElement(item, field('version')).text = info['CFBundleVersion']
    ET.SubElement(item, field('shortVersionString')).text = info['CFBundleShortVersionString']
    ET.SubElement(item, field('minimumSystemVersion')).text = info.get('LSMinimumSystemVersion', '13.0')
    if channel == 'beta':
        ET.SubElement(item, field('channel')).text = 'beta'
    ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item, 'description').text = pathlib.Path(notes).read_text(encoding='utf-8')
    location = f'https://github.com/Caldis/Pir/releases/download/{urllib.parse.quote(tag, safe="")}/{urllib.parse.quote(filename, safe="")}'
    ET.SubElement(item, 'enclosure', {'url': location, 'length': str(archive.stat().st_size),
                                   'type': 'application/octet-stream', field('edSignature'): signature})
    root = feed.find('channel')
    if root is None:
        raise ValueError('Appcast channel is missing')
    first_item = next((index for index, child in enumerate(root) if child.tag == 'item'), len(root))
    root.insert(first_item, item)
    ET.indent(feed, space='  ')
    feed.write(output, encoding='utf-8', xml_declaration=True)
    print(f'Prepared Pir {info["CFBundleShortVersionString"]} · {info["CFBundleVersion"]}, tag {tag}')


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'name':
            print(metadata(*sys.argv[2:])[2])
        elif sys.argv[1] == 'prepare':
            prepare(*sys.argv[2:])
        else:
            raise ValueError('Expected name or prepare command')
    except (ValueError, KeyError, ET.ParseError) as error:
        raise SystemExit(str(error))
