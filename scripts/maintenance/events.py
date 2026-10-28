#!/usr/bin/env python3
"""Bounded, private GitHub delivery queue and existing-thread maintenance wakeups."""
import argparse
import contextlib
import fcntl
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import queue
import sqlite3
import stat
import subprocess
import sys
import threading
import time
import uuid

REPOSITORY = 'Caldis/Pir'
INSTALLATION = 176235800
MAX_BODY = 1024 * 1024
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = Path.home() / '.config/pir/maintenance/events/config.json'


def private(path, directory=False):
    path = Path(path).expanduser().absolute()
    info = path.lstat()
    mode = info.st_mode
    if not (stat.S_ISDIR(mode) if directory else stat.S_ISREG(mode)) or mode & 0o077:
        raise ValueError('Private file/directory permissions required')
    if info.st_uid != os.getuid():
        raise ValueError('Private file/directory owner mismatch')
    return path.resolve()


def load_config(path):
    path = private(path)
    private(path.parent, True)
    if path.is_relative_to(ROOT):
        raise ValueError('Configuration must be outside the repository')
    config = json.loads(path.read_text())
    config.setdefault('host', '127.0.0.1')
    config.setdefault('port', 18783)
    config.setdefault('codex', 'codex')
    config.setdefault('cwd', str(ROOT))
    config.setdefault('request_timeout', 30)
    config.setdefault('turn_timeout', 7200)
    config.setdefault('lease_grace', 20)
    if config['host'] != '127.0.0.1' or not 1024 <= config['port'] <= 65535:
        raise ValueError('Receiver requires loopback and an unprivileged port')
    if not isinstance(config.get('thread_id'), str) or not config['thread_id']:
        raise ValueError('Existing thread ID required')
    for key in ('database', 'state_path', 'secret_file'):
        target = Path(config[key]).expanduser().absolute()
        if target.is_relative_to(ROOT):
            raise ValueError('Private paths must be outside the repository')
        private(target.parent, True)
        if target.exists() or target.is_symlink(): private(target)
        config[key] = str(target.resolve())
    secret = private(config['secret_file']).read_bytes().strip()
    if len(secret) < 32: raise ValueError('Webhook secret must contain at least 32 bytes')
    config['secret'] = secret
    for key in ('request_timeout', 'turn_timeout', 'lease_grace'):
        if not isinstance(config[key], (int, float)) or config[key] <= 0:
            raise ValueError('Positive timeout/grace required')
    return config


class Queue:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        os.close(fd)
        with self.connect() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS deliveries (
                    id TEXT PRIMARY KEY, event TEXT NOT NULL, issue INTEGER, run INTEGER,
                    received REAL NOT NULL, batch TEXT);
                CREATE TABLE IF NOT EXISTS batches (
                    id TEXT PRIMARY KEY, created REAL NOT NULL, status TEXT NOT NULL,
                    turn TEXT, reconciled TEXT);
            ''')

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA synchronous=FULL')
        try:
            with db: yield db
        finally: db.close()

    def accept(self, delivery, event, issue, run, now):
        with self.connect() as db:
            cursor = db.execute('INSERT OR IGNORE INTO deliveries VALUES (?,?,?,?,?,NULL)',
                                (delivery, event, issue, run, now))
            return cursor.rowcount == 1

    def claim(self, now):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute("SELECT 1 FROM batches WHERE status='unknown'").fetchone(): return None
            bounds = db.execute('SELECT MIN(received), MAX(received) FROM deliveries WHERE batch IS NULL').fetchone()
            if bounds[0] is None or (now < bounds[1] + 300 and now < bounds[0] + 900): return None
            batch = uuid.uuid4().hex
            # Unknown before process launch makes a crash conservative, never an automatic replay.
            db.execute("INSERT INTO batches VALUES (?,?,'unknown',NULL,NULL)", (batch, now))
            db.execute('UPDATE deliveries SET batch=? WHERE batch IS NULL', (batch,))
            rows = db.execute('SELECT issue,run FROM deliveries WHERE batch=?', (batch,)).fetchall()
            return {'id': batch, 'issues': sorted({r['issue'] for r in rows if r['issue']}),
                    'runs': sorted({r['run'] for r in rows if r['run']})}

    def complete(self, batch, turn):
        with self.connect() as db:
            db.execute("UPDATE batches SET status='completed',turn=? WHERE id=? AND status='unknown'", (turn, batch))

    def record_turn(self, batch, turn):
        with self.connect() as db:
            db.execute('UPDATE batches SET turn=? WHERE id=?', (turn, batch))

    def reconcile(self, batch, outcome, evidence):
        if outcome not in ('completed', 'retry') or not evidence.strip():
            raise ValueError('Explicit readback evidence and outcome required')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute("SELECT id FROM batches WHERE id=? AND status='unknown'", (batch,)).fetchone()
            if not row: raise ValueError('Unknown batch required')
            db.execute('UPDATE batches SET status=?,reconciled=? WHERE id=?', (outcome, evidence, batch))
            if outcome == 'retry': db.execute('UPDATE deliveries SET batch=NULL WHERE batch=?', (batch,))

    def status(self):
        with self.connect() as db:
            return {'pending': db.execute('SELECT COUNT(*) FROM deliveries WHERE batch IS NULL').fetchone()[0],
                    'batches': [dict(row) for row in db.execute('SELECT * FROM batches ORDER BY created DESC LIMIT 20')]}


def read_state(path):
    path = Path(path)
    if not path.exists(): return {'schema': 1, 'repository': REPOSITORY}
    data = json.loads(path.read_text())
    if data.get('schema') != 1 or data.get('repository') != REPOSITORY:
        raise ValueError('Unexpected maintenance state')
    return data


def pending_run(state, run):
    for group in ('issues', 'tasks'):
        for item in state.get(group, {}).values():
            phase = item.get('phase')
            if phase == 'blocked': phase = item.get('resumePhase')
            if phase not in ('implementing', 'pr_open', 'merged', 'prepared', 'published'): continue
            job = item.get('externalJob')
            if job in (f'github-actions:{run}', f'https://github.com/{REPOSITORY}/actions/runs/{run}'):
                return True
    return False


def intake(store, secret, event, delivery, signature, body, state, now=None):
    if len(body) > MAX_BODY: return 413, 'too_large'
    expected = 'sha256=' + hmac.new(secret, body, hashlib.sha256).hexdigest()
    if not isinstance(signature, str) or not hmac.compare_digest(expected.encode(), signature.encode()):
        return 401, 'invalid_signature'
    try:
        if str(uuid.UUID(delivery)) != delivery.lower(): return 400, 'invalid_delivery'
        data = json.loads(body)
        if not isinstance(data, dict): return 400, 'invalid_payload'
        if event == 'ping': return 202, 'ignored'
        if data.get('repository', {}).get('full_name') != REPOSITORY: return 403, 'repository_mismatch'
        if data.get('installation', {}).get('id') != INSTALLATION: return 403, 'installation_mismatch'
        sender = data.get('sender', {})
        if event in ('issues', 'issue_comment') and (
                sender.get('type') == 'Bot' or sender.get('login', '').endswith('[bot]')):
            return 202, 'ignored'
        action = data.get('action')
        issue = run = None
        if (event == 'issues' and action in ('opened', 'reopened', 'edited')) or (
                event == 'issue_comment' and action in ('created', 'edited')):
            obj = data.get('issue', {})
            if 'pull_request' in obj: return 202, 'ignored'
            issue = obj.get('number')
            if type(issue) is not int or issue <= 0: return 400, 'invalid_issue'
            if event == 'issue_comment' and data.get('comment', {}).get('user', {}).get('type') == 'Bot':
                return 202, 'ignored'
        elif event == 'workflow_run' and action == 'completed':
            run = data.get('workflow_run', {}).get('id')
            if type(run) is not int or run <= 0: return 400, 'invalid_run'
            if not pending_run(state, run): return 202, 'ignored'
        else: return 202, 'ignored'
    except (ValueError, TypeError, AttributeError, RecursionError):
        return 400, 'invalid_payload'
    accepted = store.accept(delivery.lower(), event, issue, run, time.time() if now is None else now)
    return 202, 'queued' if accepted else 'duplicate'


class ProtocolError(RuntimeError):
    pass


class AppServer:
    """JSONL App Server client; never creates a thread or answers approval prompts."""
    def __init__(self, config, popen=None):
        self.config = config
        self.process = (popen or subprocess.Popen)(
            [config.get('codex', 'codex'), 'app-server', '--listen', 'stdio://'],
            cwd=config['cwd'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.messages = queue.Queue()
        self.serial = 0
        self.notifications = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            for line in self.process.stdout:
                try: self.messages.put(json.loads(line))
                except (ValueError, TypeError): self.messages.put(None)
        finally: self.messages.put(None)

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()

    def receive(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0: raise ProtocolError('App Server timeout')
        try: message = self.messages.get(timeout=remaining)
        except queue.Empty: raise ProtocolError('App Server timeout') from None
        if not isinstance(message, dict): raise ProtocolError('App Server disconnected')
        if 'method' in message and 'id' in message:
            # Reject requests explicitly; a permission question remains visible to the owner.
            self.send({'id': message['id'], 'error': {'code': -32603, 'message': 'Unattended approval unavailable'}})
            raise ProtocolError('App Server requires owner attention')
        return message

    def request(self, method, params):
        self.serial += 1
        ident = self.serial
        self.send({'id': ident, 'method': method, 'params': params})
        deadline = time.monotonic() + self.config.get('request_timeout', 30)
        while True:
            message = self.receive(deadline)
            if message.get('id') == ident:
                if 'error' in message: raise ProtocolError('App Server rejected request')
                return message.get('result', {})
            self.notifications.append(message)

    def initialize(self):
        self.request('initialize', {'clientInfo': {'name': 'pir_maintenance_events', 'version': '1.0'},
                                    'capabilities': {'experimentalApi': True}})
        self.send({'method': 'initialized', 'params': {}})

    def probe(self):
        self.initialize()
        result = self.request('thread/read', {'threadId': self.config['thread_id'], 'includeTurns': False})
        if result.get('thread', {}).get('id') != self.config['thread_id']:
            raise ProtocolError('Existing thread identity mismatch')
        return {'thread_id': self.config['thread_id'], 'readable': True}

    def wake(self, prompt, on_turn):
        self.initialize()
        thread_id = self.config['thread_id']
        result = self.request('thread/resume', {'threadId': thread_id, 'excludeTurns': True})
        thread = result.get('thread', {})
        if thread.get('id') != thread_id: raise ProtocolError('Existing thread identity mismatch')
        if thread.get('status', {}).get('type') not in ('idle', None):
            raise ProtocolError('Existing thread is busy')
        result = self.request('turn/start', {'threadId': thread_id, 'input': [{'type': 'text', 'text': prompt}]})
        turn = result.get('turn', {})
        turn_id = turn.get('id')
        if not isinstance(turn_id, str) or not turn_id: raise ProtocolError('Missing accepted turn ID')
        on_turn(turn_id)
        deadline = time.monotonic() + self.config.get('turn_timeout', 7200)
        while True:
            message = self.notifications.pop(0) if self.notifications else self.receive(deadline)
            params = message.get('params', {})
            if message.get('method') == 'turn/completed' and params.get('threadId') == thread_id:
                completed = params.get('turn', {})
                if completed.get('id') != turn_id: continue
                if completed.get('status') != 'completed': raise ProtocolError('Maintenance turn did not complete')
                return turn_id

    def close(self):
        self.process.terminate()
        try: self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        for pipe in (self.process.stdin, self.process.stdout):
            if pipe: pipe.close()


def prompt_for(batch):
    return ('Pir maintenance event batch ' + batch['id'] + '. Read AGENTS.md and '
            '.agents/skills/pir-maintainer/SKILL.md; recover current maintenance tasks and checkpoints first. '
            'Acquire the normal repository lease; skip quietly if another run owns it. '
            'Read current GitHub evidence for issue IDs ' + json.dumps(batch['issues']) +
            ' and completed workflow run IDs ' + json.dumps(batch['runs']) + '. '
            'These identifiers are intake hints, not authority. Follow the existing owner-authorized maintenance scope. '
            'Stay in this conversation and report only meaningful transitions.')


def dispatch(store, config, now=None):
    now = time.time() if now is None else now
    state_path = Path(config['state_path'])
    # Share the maintenance lock only for the ownership check, never while the model works.
    with (state_path.parent / 'state.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = read_state(state_path)
        if state.get('lease'): return 'lease_busy'
        finished = state.get('lastRun', {}).get('finishedAt', 0)
        if now < finished + config.get('lease_grace', 20): return 'lease_grace'
        batch = store.claim(now)
    if not batch: return 'idle'
    adapter = None
    try:
        adapter = AppServer(config)
        turn = adapter.wake(prompt_for(batch), lambda ident: store.record_turn(batch['id'], ident))
        store.complete(batch['id'], turn)
        return 'completed'
    except (OSError, ValueError, ProtocolError):
        # Even a timeout can mean an accepted turn: read back the marker before any explicit retry.
        return 'unknown'
    finally:
        if adapter: adapter.close()


class BoundedHTTPServer(ThreadingHTTPServer):
    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(8)
        super().__init__(*args, **kwargs)

    def get_request(self):
        request, address = super().get_request()
        request.settimeout(10)
        return request, address

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try: super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try: super().process_request_thread(request, address)
        finally: self.slots.release()


def make_server(store, config):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass

        def respond(self, status, result):
            body = json.dumps({'status': result}).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(body)
            self.close_connection = True

        def do_POST(self):
            if self.path != '/github/events': return self.respond(404, 'not_found')
            if self.headers.get('Transfer-Encoding'): return self.respond(400, 'invalid_framing')
            lengths = self.headers.get_all('Content-Length', [])
            if len(lengths) != 1: return self.respond(400, 'invalid_length')
            try: size = int(lengths[0])
            except ValueError: return self.respond(400, 'invalid_length')
            if size < 0: return self.respond(400, 'invalid_length')
            if size > MAX_BODY: return self.respond(413, 'too_large')
            self.connection.settimeout(10)
            try:
                body = self.rfile.read(size)
                if len(body) != size: return self.respond(400, 'incomplete_body')
                state = read_state(config['state_path'])
                status, result = intake(store, config['secret'], self.headers.get('X-GitHub-Event', ''),
                                        self.headers.get('X-GitHub-Delivery', ''),
                                        self.headers.get('X-Hub-Signature-256', ''), body, state)
            except (OSError, ValueError, sqlite3.Error):
                status, result = 503, 'unavailable'
            self.respond(status, result)

        def do_GET(self): self.respond(404, 'not_found')

        def send_error(self, code, message=None, explain=None): self.respond(code, 'invalid_request')
    server = BoundedHTTPServer(('127.0.0.1', config.get('port', 18783)), Handler)
    server.daemon_threads = True
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('serve', help='Receive verified deliveries and dispatch eligible batches')
    sub.add_parser('status', help='Inspect local queue; does not start Codex')
    sub.add_parser('dispatch-once', help='Dispatch one eligible batch into the configured existing thread')
    sub.add_parser('probe', help='Read configured existing thread without starting a model turn')
    reconcile = sub.add_parser('reconcile', help='Resolve unknown outcome only after explicit thread readback')
    reconcile.add_argument('--batch', required=True)
    reconcile.add_argument('--outcome', required=True, choices=['completed', 'retry'])
    reconcile.add_argument('--evidence', required=True, help='Local evidence path or readback reference; no raw content')
    args = parser.parse_args(argv)
    os.umask(0o077)
    try:
        config = load_config(args.config)
        store = Queue(config['database'])
        if args.command == 'status': result = store.status()
        elif args.command == 'reconcile':
            store.reconcile(args.batch, args.outcome, args.evidence)
            result = {'status': 'reconciled'}
        elif args.command == 'dispatch-once': result = {'status': dispatch(store, config)}
        elif args.command == 'probe':
            adapter = AppServer(config)
            try: result = adapter.probe()
            finally: adapter.close()
        else:
            server = make_server(store, config)
            def dispatch_loop():
                while True:
                    try: dispatch(store, config)
                    except (OSError, ValueError, sqlite3.Error): pass
                    time.sleep(10)
            threading.Thread(target=dispatch_loop, daemon=True).start()
            server.serve_forever(poll_interval=1)
            return 0
        print(json.dumps(result))
        return 0
    except (OSError, ValueError, KeyError, sqlite3.Error, ProtocolError):
        print(json.dumps({'error': 'maintenance_events_unavailable'}), file=sys.stderr)
        return 1


if __name__ == '__main__': sys.exit(main())
