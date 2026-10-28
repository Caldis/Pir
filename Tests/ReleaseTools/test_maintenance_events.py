import hashlib
import hmac
import importlib.util
import json
import io
from email.message import Message
import queue
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('maintenance_events', ROOT / 'scripts/maintenance/events.py')


class EventTestCase(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SPEC.origin and Path(SPEC.origin).exists(), 'event receiver implementation is missing')
        self.m = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.m)
        guard = patch.object(self.m.subprocess, 'Popen', side_effect=AssertionError('All subprocesses must be mocked'))
        guard.start()
        self.addCleanup(guard.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.queue = self.m.Queue(self.root / 'events.sqlite3')
        self.payload = {'repository': {'full_name': 'Caldis/Pir'}, 'installation': {'id': 176235800},
                        'action': 'opened', 'issue': {'number': 12}, 'sender': {'type': 'User', 'login': 'owner'}}

    def receive(self, payload=None, event='issues', delivery=None, signature=None):
        body = json.dumps(self.payload if payload is None else payload).encode()
        sig = 'sha256=' + hmac.new(b'secret', body, hashlib.sha256).hexdigest()
        return self.m.intake(self.queue, b'secret', event, delivery or str(uuid.uuid4()), sig if signature is None else signature, body, {}, now=100)



class EventTests(EventTestCase):
    def test_signed_durable_deduplicated_identifiers_only(self):
        self.payload['issue']['body'] = 'private raw body must not be persisted'
        delivery = str(uuid.uuid4())
        self.assertEqual(self.receive(delivery=delivery), (202, 'queued'))
        self.assertEqual(self.receive(delivery=delivery), (202, 'duplicate'))
        self.assertEqual(self.queue.status()['pending'], 1)
        self.assertNotIn(b'private raw', (self.root / 'events.sqlite3').read_bytes())
        self.assertEqual(self.m.Queue(self.root / 'events.sqlite3').status()['pending'], 1)

    def test_untrusted_invalid_and_ignored_events(self):
        self.assertEqual(self.receive(signature='sha256=bad')[0], 401)
        self.assertEqual(self.receive(delivery='not-a-uuid')[0], 400)
        self.payload['repository']['full_name'] = 'other/repo'
        self.assertEqual(self.receive()[0], 403)
        self.payload['repository']['full_name'] = 'Caldis/Pir'
        self.payload['installation']['id'] = 42
        self.assertEqual(self.receive()[0], 403)
        self.payload['installation']['id'] = 176235800
        self.payload['sender']['type'] = 'Bot'
        self.assertEqual(self.receive(), (202, 'ignored'))
        self.payload['sender']['type'] = 'User'
        self.payload['issue']['pull_request'] = {}
        self.assertEqual(self.receive(), (202, 'ignored'))
        self.assertEqual(self.m.intake(self.queue, b'x', 'issues', str(uuid.uuid4()), '', b'x' * (1048576 + 1), {}), (413, 'too_large'))

    def test_quiet_max_wait_atomic_claim_and_new_arrivals(self):
        self.receive()
        self.assertIsNone(self.queue.claim(399))
        self.queue.accept(str(uuid.uuid4()), 'issues', 13, None, 390)
        self.assertIsNone(self.queue.claim(689))
        batch = self.queue.claim(690)
        self.assertEqual(batch['issues'], [12, 13])
        self.queue.accept(str(uuid.uuid4()), 'issues', 14, None, 700)
        self.assertIsNone(self.queue.claim(2000))
        self.queue.complete(batch['id'], 'turn-1')
        self.assertEqual(self.queue.claim(2000)['issues'], [14])

    def test_max_wait_and_unknown_outcome_requires_explicit_reconcile(self):
        self.receive()
        for now in (350, 600, 850):
            self.queue.accept(str(uuid.uuid4()), 'issues', 13, None, now)
        batch = self.queue.claim(1000)
        self.assertIsNotNone(batch)
        self.assertIsNone(self.m.Queue(self.root / 'events.sqlite3').claim(9000))
        self.queue.reconcile(batch['id'], 'retry', 'thread/read confirms no accepted turn')
        self.assertIsNotNone(self.queue.claim(9000))

    def test_lease_blocks_even_expired_until_owner_reconciles(self):
        self.receive()
        state = self.root / 'state.json'
        state.write_text(json.dumps({'schema': 1, 'repository': 'Caldis/Pir', 'lease': {'expiresAt': 0}}))
        with patch.object(self.m, 'AppServer') as adapter:
            self.assertEqual(self.m.dispatch(self.queue, {'state_path': str(state), 'thread_id': 'thread'}, now=1000), 'lease_busy')
            adapter.assert_not_called()

    def test_config_enforces_private_loopback_external_paths(self):
        conf = self.root / 'config.json'
        secret = self.root / 'secret'
        secret.write_text('a' * 64)
        secret.chmod(0o600)
        self.root.chmod(0o700)
        conf.write_text(json.dumps({'secret_file': str(secret), 'database': str(self.root / 'queue.sqlite3'),
                                    'state_path': str(self.root / 'state.json'), 'thread_id': 'existing', 'cwd': str(ROOT)}))
        conf.chmod(0o600)
        self.assertEqual(self.m.load_config(conf)['host'], '127.0.0.1')
        conf.chmod(0o644)
        with self.assertRaises(ValueError): self.m.load_config(conf)


    def test_http_handler_strict_path_framing_and_storage_failure(self):
        config = {'secret': b'secret', 'port': 18783, 'state_path': str(self.root / 'state.json')}
        with patch.object(self.m, 'BoundedHTTPServer') as server:
            self.m.make_server(self.queue, config)
            self.assertEqual(server.call_args.args[0], ('127.0.0.1', 18783))
            handler_class = server.call_args.args[1]
        body = json.dumps(self.payload).encode()
        signature = 'sha256=' + hmac.new(b'secret', body, hashlib.sha256).hexdigest()
        def request(path='/github/events', length=None, extra=None):
            handler = object.__new__(handler_class)
            handler.path = path
            handler.headers = Message()
            handler.headers['Content-Length'] = str(len(body)) if length is None else length
            handler.headers['X-GitHub-Event'] = 'issues'
            handler.headers['X-GitHub-Delivery'] = str(uuid.uuid4())
            handler.headers['X-Hub-Signature-256'] = signature
            for key, value in extra or []: handler.headers[key] = value
            handler.rfile = io.BytesIO(body)
            handler.connection = Mock()
            handler.respond = Mock()
            handler.do_POST()
            return handler.respond.call_args.args
        self.assertEqual(request(), (202, 'queued'))
        self.assertEqual(request('/github/events?x=1'), (404, 'not_found'))
        self.assertEqual(request(length='1048577'), (413, 'too_large'))
        self.assertEqual(request(length='-1'), (400, 'invalid_length'))
        self.assertEqual(request(extra=[('Content-Length', '1')]), (400, 'invalid_length'))
        self.assertEqual(request(extra=[('Transfer-Encoding', 'chunked')]), (400, 'invalid_framing'))
        with patch.object(self.queue, 'accept', side_effect=self.m.sqlite3.OperationalError('private internal detail')):
            self.assertEqual(request(), (503, 'unavailable'))


    def test_http_concurrency_limit_rejects_excess_connections(self):
        server = object.__new__(self.m.BoundedHTTPServer)
        server.slots = Mock()
        server.slots.acquire.return_value = False
        request = Mock()
        server.process_request(request, ('127.0.0.1', 1))
        request.close.assert_called_once()
        server.slots.acquire.assert_called_once_with(blocking=False)


class FakeProcess:
    def __init__(self, mismatch=False, approval=False, disconnect=False):
        self.lines = queue.Queue()
        self.sent = []
        self.stdout = self
        self.stdin = self
        self.mismatch = mismatch
        self.approval = approval
        self.disconnect = disconnect

    def __iter__(self): return self
    def __next__(self):
        line = self.lines.get(timeout=3)
        if line is None: raise StopIteration
        return json.dumps(line) + '\n'

    def write(self, line):
        msg = json.loads(line)
        self.sent.append(msg)
        if 'id' not in msg or 'method' not in msg: return
        method = msg['method']
        if method == 'initialize': result = {}
        elif method in ('thread/resume', 'thread/read'):
            result = {'thread': {'id': 'wrong' if self.mismatch else 'existing', 'status': {'type': 'idle'}}}
        elif method == 'turn/start':
            if self.approval:
                self.lines.put({'id': 99, 'method': 'item/commandExecution/requestApproval', 'params': {}})
                return
            if self.disconnect:
                self.lines.put(None)
                return
            result = {'turn': {'id': 'turn-1'}}
            self.lines.put({'method': 'turn/completed', 'params': {'threadId': 'existing',
                           'turn': {'id': 'other-turn', 'status': 'completed'}}})
            self.lines.put({'method': 'turn/completed', 'params': {'threadId': 'existing',
                           'turn': {'id': 'turn-1', 'status': 'completed'}}})
        else: raise AssertionError(method)
        self.lines.put({'id': msg['id'], 'result': result})

    def flush(self): pass
    def terminate(self): self.lines.put(None)
    def wait(self, timeout=None): return 0
    def close(self): pass


class ProtocolTests(EventTestCase):
    def config(self):
        return {'cwd': str(ROOT), 'thread_id': 'existing', 'request_timeout': .2, 'turn_timeout': .2,
                'state_path': str(self.root / 'state.json')}

    def test_same_thread_protocol_and_readonly_probe(self):
        process = FakeProcess()
        with patch.object(self.m.subprocess, 'Popen', return_value=process) as popen:
            adapter = self.m.AppServer(self.config())
            accepted = []
            self.assertEqual(adapter.wake('fixed prompt', accepted.append), 'turn-1')
            adapter.close()
        self.assertEqual(accepted, ['turn-1'])
        methods = [m['method'] for m in process.sent]
        self.assertEqual(methods, ['initialize', 'initialized', 'thread/resume', 'turn/start'])
        self.assertTrue(process.sent[2]['params']['excludeTurns'])
        self.assertEqual(process.sent[3]['params']['threadId'], 'existing')
        popen.assert_called_once()
        process = FakeProcess()
        adapter = self.m.AppServer(self.config(), popen=lambda *a, **k: process)
        self.assertTrue(adapter.probe()['readable'])
        adapter.close()
        self.assertEqual([m['method'] for m in process.sent], ['initialize', 'initialized', 'thread/read'])

    def test_mismatch_and_approval_fail_closed(self):
        for options in ({'mismatch': True}, {'approval': True}, {'disconnect': True}):
            process = FakeProcess(**options)
            adapter = self.m.AppServer(self.config(), popen=lambda *a, **k: process)
            with self.assertRaises(self.m.ProtocolError): adapter.wake('fixed', lambda x: None)
            adapter.close()
            if options.get('mismatch'):
                self.assertNotIn('turn/start', [m.get('method') for m in process.sent])
            if options.get('approval'):
                self.assertIn('error', process.sent[-1])

    def test_dispatch_empty_never_spawns_and_failed_wakeup_never_replays(self):
        with patch.object(self.m.subprocess, 'Popen', side_effect=AssertionError('unexpected process')):
            self.assertEqual(self.m.dispatch(self.queue, self.config(), now=1000), 'idle')
        self.receive()
        process = FakeProcess(disconnect=True)
        with patch.object(self.m.subprocess, 'Popen', return_value=process) as popen:
            self.assertEqual(self.m.dispatch(self.queue, self.config(), now=1000), 'unknown')
            self.assertEqual(self.m.dispatch(self.queue, self.config(), now=2000), 'idle')
            popen.assert_called_once()
        self.assertEqual(self.queue.status()['batches'][0]['status'], 'unknown')

    def test_workflow_only_matches_pending_external_job(self):
        payload = dict(self.payload, action='completed', workflow_run={'id': 123})
        body = json.dumps(payload).encode()
        signature = 'sha256=' + hmac.new(b'secret', body, hashlib.sha256).hexdigest()
        def receive(state):
            return self.m.intake(self.queue, b'secret', 'workflow_run', str(uuid.uuid4()), signature, body, state)
        self.assertEqual(receive({}), (202, 'ignored'))
        state = {'tasks': {'work': {'phase': 'pr_open', 'externalJob': 'github-actions:123'}}}
        self.assertEqual(receive(state), (202, 'queued'))
        payload['sender'] = {'type': 'Bot', 'login': 'github-actions[bot]'}
        body = json.dumps(payload).encode()
        signature = 'sha256=' + hmac.new(b'secret', body, hashlib.sha256).hexdigest()
        self.assertEqual(receive(state), (202, 'queued'))
        state['tasks']['work']['phase'] = 'verified'
        self.assertEqual(receive(state), (202, 'ignored'))

    def test_non_ascii_signature_and_malformed_payload_are_sanitized(self):
        self.assertEqual(self.receive(signature='sha256=é'), (401, 'invalid_signature'))
        for payload in ([], {'repository': []}, {'repository': {'full_name': 'Caldis/Pir'}, 'installation': []}):
            self.assertEqual(self.receive(payload=payload)[0], 400)


    def test_lease_grace_and_successful_dispatch(self):
        self.payload['issue']['body'] = 'UNTRUSTED_PAYLOAD_INSTRUCTIONS'
        self.receive()
        state_path = self.root / 'state.json'
        state_path.write_text(json.dumps({'schema': 1, 'repository': 'Caldis/Pir', 'lease': None,
                                          'lastRun': {'finishedAt': 990}}))
        self.assertEqual(self.m.dispatch(self.queue, self.config(), now=1000), 'lease_grace')
        process = FakeProcess()
        with patch.object(self.m.subprocess, 'Popen', return_value=process):
            self.assertEqual(self.m.dispatch(self.queue, self.config(), now=1010), 'completed')
        self.assertEqual(self.queue.status()['batches'][0]['turn'], 'turn-1')
        prompt = process.sent[-1]['params']['input'][0]['text']
        self.assertIn('[12]', prompt)
        self.assertIn(self.queue.status()['batches'][0]['id'], prompt)
        self.assertNotIn('UNTRUSTED_PAYLOAD_INSTRUCTIONS', prompt)

    def test_protocol_timeout_is_bounded(self):
        process = FakeProcess()
        def no_response(line): process.sent.append(json.loads(line))
        process.write = no_response
        adapter = self.m.AppServer(self.config(), popen=lambda *a, **k: process)
        with self.assertRaisesRegex(self.m.ProtocolError, 'timeout'): adapter.probe()
        adapter.close()


if __name__ == '__main__': unittest.main()
