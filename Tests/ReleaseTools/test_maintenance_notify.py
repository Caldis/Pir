import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[2]


class NotificationTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / 'scripts/maintenance/notify.py'
        self.assertTrue(path.exists(), 'notification helper is not implemented')
        spec = importlib.util.spec_from_file_location('pir_notify', path)
        self.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.m)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = self.m.Store(Path(self.tmp.name) / 'state')
        self.run = self.store.begin(now=100, ttl=7200)['id']
        self.config = Path(self.tmp.name) / 'config.json'
        self.config.write_text(json.dumps({'bot_token': '123:SECRET', 'chat_id': 42, 'user_id': 42}))
        self.config.chmod(0o600)
        self.event = {'issue': 39, 'title': '缩放 <test>', 'event': 'progress',
                      'fact': 'reproduced', 'detail': '已复现，开始最小修复', 'pr': 40}

    def send(self, **kwargs):
        return self.m.notify(self.store, self.run, self.event, self.config, now=101, **kwargs)

    @staticmethod
    def success(request, timeout):
        return io.BytesIO(b'{"ok":true,"result":{"message_id":7}}')

    def test_fixed_recipient_plain_text_and_dedupe_across_runs(self):
        with patch.object(self.m.urllib.request, 'urlopen', side_effect=self.success) as api:
            self.assertEqual(self.send()['status'], 'sent')
            request = api.call_args.args[0]
            payload = json.loads(request.data)
            self.assertEqual(payload['chat_id'], 42)
            self.assertNotIn('parse_mode', payload)
            self.assertIn('https://github.com/Caldis/Pir/issues/39', payload['text'])
            self.assertIn('https://github.com/Caldis/Pir/pull/40', payload['text'])
            self.store.finish(self.run, now=102)
            self.run = self.store.begin(now=103)['id']
            self.assertEqual(self.send()['status'], 'sent')
            self.assertEqual(api.call_count, 1)
            self.event['fact'] = 'tests-passed'
            self.send()
            self.assertEqual(api.call_count, 2)

    def test_unknown_result_and_crash_reservation_are_not_resent(self):
        with patch.object(self.m.urllib.request, 'urlopen', side_effect=TimeoutError('123:SECRET')) as api:
            result = self.send()
            self.assertEqual(result['status'], 'unknown')
            self.assertNotIn('SECRET', json.dumps(result))
            self.send()
            self.assertEqual(api.call_count, 1)
        with self.store.transaction() as data:
            record = next(iter(data['notifications'].values()))
            record['status'] = 'sending'
        with patch.object(self.m.urllib.request, 'urlopen') as api:
            self.assertEqual(self.send()['status'], 'unknown')
            api.assert_not_called()

    def test_known_failure_retries_in_later_cycles_with_a_total_bound(self):
        error = HTTPError('https://api.telegram.org/bot123:SECRET', 429, 'SECRET', {}, io.BytesIO())
        self.addCleanup(error.close)
        with patch.object(self.m.urllib.request, 'urlopen', side_effect=error) as api:
            self.assertEqual(self.send()['status'], 'failed')
            self.send()
            self.assertEqual(api.call_count, 1)
            for now in (4000, 8000, 12000):
                self.store.finish(self.run, now=now)
                self.run = self.store.begin(now=now)['id']
                self.m.retry(self.store, self.run, self.config, now=now + 1)
            self.assertEqual(api.call_count, 3)
            self.assertNotIn('SECRET', json.dumps(self.store.read()))

    def test_dry_run_neither_reads_config_nor_mutates_state(self):
        before = self.store.read()
        with patch.object(self.m.urllib.request, 'urlopen') as api:
            self.config.unlink()
            self.assertEqual(self.send(dry_run=True)['status'], 'dry-run')
            self.assertEqual(self.store.read(), before)
            api.assert_not_called()

    def test_config_failure_is_safe_and_recovers_next_cycle(self):
        self.config.write_text('SECRET invalid json')
        result = self.send()
        self.assertEqual(result['error'], 'configuration-unavailable')
        self.assertNotIn('SECRET', json.dumps(result))
        self.config.write_text(json.dumps({'bot_token': '123:SECRET', 'chat_id': 42, 'user_id': 42}))
        self.store.finish(self.run, now=4000)
        self.run = self.store.begin(now=4000)['id']
        with patch.object(self.m.urllib.request, 'urlopen', side_effect=self.success):
            self.assertEqual(self.m.retry(self.store, self.run, self.config, now=4001)[0]['status'], 'sent')

    def test_lease_and_private_chat_binding(self):
        with patch.object(self.m.urllib.request, 'urlopen') as api:
            with self.assertRaises(self.m.Busy):
                self.m.notify(self.store, 'wrong', self.event, self.config, now=101)
            api.assert_not_called()
            self.config.write_text(json.dumps({'bot_token': '123:SECRET', 'chat_id': 43, 'user_id': 42}))
            self.assertEqual(self.send()['error'], 'configuration-unavailable')
            api.assert_not_called()

    def test_server_error_and_malformed_success_are_unknown_without_checkpoint_changes(self):
        self.store.checkpoint(self.run, 39, {'phase': 'merged', 'pr': 40}, now=101)
        checkpoint = self.store.read()['issues']['39']
        error = HTTPError('https://api.telegram.org/bot123:SECRET', 503, 'SECRET', {}, io.BytesIO())
        self.addCleanup(error.close)
        with patch.object(self.m.urllib.request, 'urlopen', side_effect=error):
            self.assertEqual(self.send()['status'], 'unknown')
        self.event['fact'] = 'another-stage'
        with patch.object(self.m.urllib.request, 'urlopen', return_value=io.BytesIO(b'{invalid SECRET')):
            self.assertEqual(self.send()['status'], 'unknown')
        self.assertEqual(self.store.read()['issues']['39'], checkpoint)
        self.assertNotIn('SECRET', json.dumps(self.store.read()))

    def test_api_rejection_and_unsafe_config_are_not_success(self):
        with patch.object(self.m.urllib.request, 'urlopen', return_value=io.BytesIO(b'{"ok":false,"description":"SECRET"}')):
            self.assertEqual(self.send()['error'], 'telegram-rejected')
        self.event['fact'] = 'next-stage'
        self.config.chmod(0o644)
        with patch.object(self.m.urllib.request, 'urlopen') as api:
            self.assertEqual(self.send()['error'], 'configuration-unavailable')
            api.assert_not_called()
        self.assertNotIn('SECRET', json.dumps(self.store.read()))

    def test_success_and_release_are_distinct_events(self):
        with patch.object(self.m.urllib.request, 'urlopen', side_effect=self.success) as api:
            self.event.update(event='succeeded', fact='merged-sha', detail='代码已合并，应用发布待验证')
            self.send()
            self.event.update(event='released', fact='0.1.10/20261028.2', version='0.1.10',
                              detail='公开下载与真实 Sparkle 升级均已验证')
            self.send()
            self.assertEqual(api.call_count, 2)
            self.assertIn('releases/tag/0.1.10', json.loads(api.call_args.args[0].data)['text'])


if __name__ == '__main__':
    unittest.main()
