import base64
import pathlib
import plistlib
import runpy
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
FEED = runpy.run_path(str(ROOT / 'scripts/release/update-feed.py'))
POLICY = runpy.run_path(str(ROOT / 'scripts/version-metadata.py'))


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='pir-update-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        self.app = self.root / 'Pir.app'
        (self.app / 'Contents').mkdir(parents=True)
        self.key = base64.b64encode(bytes(range(32))).decode()
        self.info = {'CFBundleIdentifier': 'me.caldis.pir', 'CFBundleShortVersionString': '0.2.0',
                     'CFBundleVersion': '20261025.2', 'SUPublicEDKey': self.key,
                     'LSMinimumSystemVersion': '13.0'}
        self.write_info()
        self.source = self.root / 'source.xml'
        self.source.write_text('<rss version="2.0"><channel><title>Pir</title></channel></rss>')

    def write_info(self):
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_stable_and_beta_names_match_mos_convention(self):
        stable = POLICY['release_metadata']('0.2.0', '20261025.2')
        beta = POLICY['release_metadata']('0.2.0', '20261025.2', 'beta')
        self.assertEqual(stable['tag'], '0.2.0')
        self.assertEqual(stable['archive'], 'Pir.Versions.0.2.0-20261025.2.zip')
        self.assertEqual(beta['tag'], '0.2.0-beta-20261025.2')
        self.assertEqual(beta['archive'], 'Pir.Versions.0.2.0-beta-20261025.2.zip')

    def test_invalid_version_build_date_sequence_and_channel_are_rejected(self):
        for version, build, channel in [('v0.2.0', '20261025.2', 'stable'),
                                        ('0.2', '20261025.2', 'stable'),
                                        ('0.2.0-beta', '20261025.2', 'beta'),
                                        ('0.2.0', '20260230.1', 'stable'),
                                        ('0.2.0', '20261025.0', 'stable'),
                                        ('0.2.0', '20261025.2', 'nightly')]:
            with self.subTest(version=version, build=build, channel=channel), self.assertRaises(ValueError):
                POLICY['release_metadata'](version, build, channel)

    def test_app_key_must_match_signing_account(self):
        wrong_key = base64.b64encode(bytes(reversed(range(32)))).decode()
        with self.assertRaisesRegex(ValueError, 'public key'):
            FEED['metadata'](self.app, 'stable', wrong_key, self.source)

    def test_feed_preserves_history_and_rejects_duplicate_or_older_builds(self):
        self.prepare('beta')
        self.source.write_bytes((self.root / 'out.xml').read_bytes())
        with self.assertRaisesRegex(ValueError, 'newer'):
            FEED['metadata'](self.app, 'stable', self.key, self.source)
        self.info['CFBundleVersion'] = '20261025.1'
        self.write_info()
        with self.assertRaisesRegex(ValueError, 'newer'):
            FEED['metadata'](self.app, 'stable', self.key, self.source)
        self.info['CFBundleVersion'] = '20261025.3'
        self.write_info()
        self.prepare('stable')
        items = ET.parse(self.root / 'out.xml').findall('./channel/item')
        self.assertEqual([item.findtext(FEED['field']('version')) for item in items], ['20261025.3', '20261025.2'])
        self.assertIsNone(items[0].find(FEED['field']('channel')))
        self.assertEqual(items[1].findtext(FEED['field']('channel')), 'beta')

    def test_generated_beta_uses_release_asset_and_preserves_notes(self):
        self.prepare('beta')
        item = ET.parse(self.root / 'out.xml').find('./channel/item')
        self.assertEqual(item.find('enclosure').get('url'),
                         'https://github.com/Caldis/Pir/releases/download/0.2.0-beta-20261025.2/Pir.Versions.0.2.0-beta-20261025.2.zip')
        self.assertEqual(item.findtext(FEED['field']('minimumSystemVersion')), '13.0')
        self.assertEqual(item.findtext('description'), '<h2>Updates</h2><p>Pir &lt;3</p>')

    def prepare(self, channel):
        names = POLICY['release_metadata'](self.info['CFBundleShortVersionString'], self.info['CFBundleVersion'], channel)
        archive = self.root / names['archive']
        archive.write_bytes(b'update fixture')
        notes = self.root / 'notes.html'
        notes.write_text('<h2>Updates</h2><p>Pir &lt;3</p>')
        signature = base64.b64encode(bytes(64)).decode()
        FEED['prepare'](self.app, channel, self.key, self.source, archive, signature, notes, self.root / 'out.xml')


if __name__ == '__main__':
    unittest.main()
