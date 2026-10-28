#!/usr/bin/env python3
"""Pir maintenance leases, resumable checkpoints, read-only scan and comment upserts."""
import argparse
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

# Load from this checkout without depending on the caller's working directory or PYTHONPATH.
_auth_spec = importlib.util.spec_from_file_location('pir_github_app', Path(__file__).with_name('github_app.py'))
_auth = importlib.util.module_from_spec(_auth_spec)
_auth_spec.loader.exec_module(_auth)


def app_client():
    return _auth.client()


REPO = 'Caldis/Pir'
PHASES = ['triaged', 'implementing', 'pr_open', 'merged', 'prepared', 'published', 'verified', 'blocked']


class Busy(RuntimeError):
    pass


class Store:
    def __init__(self, root):
        self.root = Path(root)
        self.path = self.root / 'state.json'

    def read(self):
        if not self.path.exists(): return {'schema': 1, 'repository': REPO, 'issues': {}, 'lease': None}
        data = json.loads(self.path.read_text())
        if data.get('schema') != 1 or data.get('repository') != REPO:
            raise ValueError('Unexpected maintenance state; preserve it and inspect before continuing')
        return data

    @contextlib.contextmanager
    def transaction(self):
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.root / 'state.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self.read()
            yield data
            fd, name = tempfile.mkstemp(dir=self.root, prefix='.state-')
            try:
                with os.fdopen(fd, 'w') as output:
                    json.dump(data, output, ensure_ascii=False, indent=2)
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(name, self.path)
            finally:
                if os.path.exists(name): os.unlink(name)

    @staticmethod
    def require(data, run_id, now):
        lease = data.get('lease')
        if not lease or lease['id'] != run_id or lease['expiresAt'] <= now:
            raise Busy('No current lease for this run; reconcile state before any external write')
        return lease

    def begin(self, now=None, ttl=7200, recover=False):
        now = time.time() if now is None else now
        if not 60 <= ttl <= 86400:
            raise ValueError('Lease TTL must be 60..86400 seconds')
        with self.transaction() as data:
            previous = data.get('lease')
            if previous and (previous['expiresAt'] > now or not recover):
                raise Busy(json.dumps({'message': 'Existing lease; never overlap runs', 'lease': previous}))
            lease = {'id': uuid.uuid4().hex, 'startedAt': now, 'expiresAt': now + ttl}
            if previous: lease['recoveredFrom'] = previous['id']
            data['lease'] = lease
        return lease

    def guard(self, run_id, now=None, renew=None):
        now = time.time() if now is None else now
        with self.transaction() as data:
            lease = self.require(data, run_id, now)
            if renew: lease['expiresAt'] = now + renew
        return lease

    def checkpoint(self, run_id, number, fields, now=None, *, task=None):
        if (number is None) == (task is None):
            raise ValueError('Checkpoint requires exactly one issue number or task slug')
        if task is not None and (len(task) > 64 or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', task)):
            raise ValueError('Task slug must be 1..64 lowercase letters/digits separated by single hyphens')
        collection, identity, key = ('tasks', 'task', task) if task is not None else ('issues', 'issue', str(number))
        now = time.time() if now is None else now
        with self.transaction() as data:
            self.require(data, run_id, now)
            previous = data.get(collection, {}).get(key, {})
            changed = (previous.get('phase') == 'verified' and fields.get('fingerprint')
                       and previous.get('fingerprint') != fields['fingerprint'])
            item = {} if changed else dict(previous)
            item.update(fields)
            if fields.get('phase') == 'blocked' and previous.get('phase') != 'blocked':
                item.setdefault('resumePhase', previous.get('phase', 'triaged'))
            if task is not None and (not isinstance(item.get('plan'), str) or not item['plan'].strip()):
                raise ValueError('Task checkpoints require a plan path/URL')
            phase = item.get('phase')
            if phase not in PHASES:
                raise ValueError('Unknown maintenance phase')
            if phase in ('prepared', 'published', 'verified') and (not item.get('release') or not item.get('evidence')):
                raise ValueError('Release checkpoints require a release identifier and evidence paths/URLs')
            if phase == 'verified' and item['release'] == 'not-required' and not item.get('note'):
                raise ValueError('No-app-release completion requires an explicit reason')
            if changed:
                history = data.setdefault('history', [])
                history.append({identity: task if task is not None else number, **previous})
            data.setdefault(collection, {})[key] = item
            item['updatedAt'] = now
            item['runId'] = run_id
        return item

    def mutate(self, run_id, operation, now=None):
        now = time.time() if now is None else now
        with self.transaction() as data:
            self.require(data, run_id, now)
            return operation()

    def summary(self):
        data = self.read()
        fields = ('plan', 'phase', 'fingerprint', 'pr', 'prHeadSha', 'mergeSha', 'buildSha', 'tagSha',
                  'release', 'version', 'build', 'worktree', 'branch', 'nextAction',
                  'externalJob', 'retryWhen', 'resumePhase', 'evidence')
        notifications = {}
        for item in data.get('notifications', {}).values():
            status = item.get('status', 'unknown')
            notifications[status] = notifications.get(status, 0) + 1
        return {'repository': REPO, 'lease': data.get('lease'), 'lastRun': data.get('lastRun'),
                'issues': {number: {k: item[k] for k in fields if k in item}
                           for number, item in data['issues'].items() if item.get('phase') != 'verified'},
                'tasks': {slug: {k: item[k] for k in fields if k in item}
                          for slug, item in data.get('tasks', {}).items() if item.get('phase') != 'verified'},
                'verifiedTaskCount': sum(item.get('phase') == 'verified' for item in data.get('tasks', {}).values()),
                'verifiedCount': sum(item.get('phase') == 'verified' for item in data['issues'].values()),
                'notifications': notifications}

    def finish(self, run_id, now=None, outcome='completed', note=None, next_action=None, evidence=None):
        now = time.time() if now is None else now
        if outcome not in ('idle', 'completed', 'waiting', 'blocked', 'failed'):
            raise ValueError('Unknown run outcome')
        with self.transaction() as data:
            if not data.get('lease') and data.get('lastRun', {}).get('id') == run_id:
                return data['lastRun']
            lease = self.require(data, run_id, now)
            if outcome == 'idle' and any(item.get('phase') != 'verified'
                    for collection in ('issues', 'tasks') for item in data.get(collection, {}).values()):
                raise ValueError('Unfinished checkpoints require a waiting/blocked/failed or completed cycle result')
            result = {**lease, 'finishedAt': now, 'outcome': outcome}
            for key, value in (('note', note), ('nextAction', next_action), ('evidence', evidence)):
                if value is not None: result[key] = value
            # Persist the handoff before releasing ownership. An I/O failure keeps the lease intact.
            journal = self.root / 'runs'
            journal.mkdir(mode=0o700, exist_ok=True)
            fd, name = tempfile.mkstemp(dir=journal, prefix='.run-')
            try:
                with os.fdopen(fd, 'w') as output:
                    json.dump(result, output, ensure_ascii=False, indent=2)
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(name, journal / (run_id + '.json'))
            finally:
                if os.path.exists(name): os.unlink(name)
            data['lastRun'] = result
            data['lease'] = None
        return result


def fingerprint(issue, comments, viewer):
    marker = f'<!-- pir-maintainer:{issue["number"]}:'
    content = {'title': issue.get('title'), 'body': issue.get('body'),
               'labels': sorted(x['name'] for x in issue.get('labels', [])),
               'comments': [(c.get('user', {}).get('login'), c.get('body')) for c in comments
                            if not (c.get('user', {}).get('login') in (viewer, 'Caldis') and c.get('body', '').startswith(marker))]}
    return hashlib.sha256(json.dumps(content, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def action(previous, digest):
    if not previous: return 'new'
    if previous.get('phase') not in ('verified', 'blocked'): return 'resume'
    if previous.get('fingerprint') != digest:
        if previous.get('phase') == 'blocked' and (previous.get('pr') or previous.get('release')):
            return 'resume'
        return 'changed'
    return 'unchanged' if previous['phase'] == 'verified' else 'blocked'


def gh_api(endpoint, method='GET', data=None):
    command = ['gh', 'api', endpoint, '--method', method]
    if method == 'GET': command += ['--paginate', '--slurp']
    if data is not None: command += ['--input', '-']
    result = subprocess.run(command, input=json.dumps(data) if data is not None else None,
                            text=True, capture_output=True, timeout=90, env=app_client().environment())
    if result.returncode: raise RuntimeError('GitHub App repository request failed; verify permissions and retry after readback')
    response = json.loads(result.stdout)
    if method == 'GET':
        if len(response) == 1 and isinstance(response[0], dict): return response[0]
        return [item for page in response for item in page]
    return response


def upsert_comment(api, number, phase, text, viewer):
    marker = f'<!-- pir-maintainer:{number}:{phase} -->'
    body = marker + '\n' + text.strip()
    endpoint = f'repos/{REPO}/issues/{number}/comments'
    comments = api(endpoint)
    existing = next((c for c in reversed(comments) if c.get('user', {}).get('login') == viewer
                     and c.get('body', '').startswith(marker)), None)
    if existing and existing['body'] == body: return {'unchanged': True, 'id': existing['id']}
    if existing: return api(f'repos/{REPO}/issues/comments/{existing["id"]}', 'PATCH', {'body': body})
    return api(endpoint, 'POST', {'body': body})


def projects_module():
    spec = importlib.util.spec_from_file_location('pir_cycle_projects', Path(__file__).with_name('projects.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def project_snapshot():
    return projects_module().scan()


def scan(store):
    state = store.read()
    viewer = app_client().actor()
    opened = gh_api(f'repos/{REPO}/issues?state=open&per_page=100')
    issues = {str(x['number']): x for x in opened if 'pull_request' not in x}
    # A merge may have auto-closed an issue before a crashed release completed.
    for number, record in state['issues'].items():
        if record.get('phase') != 'verified' and number not in issues:
            issues[number] = gh_api(f'repos/{REPO}/issues/{number}')
    result = []
    projects = projects_module()
    stage_roots = None
    source_error = None
    for number, issue in issues.items():
        comments = gh_api(f'repos/{REPO}/issues/{number}/comments?per_page=100')
        digest = fingerprint(issue, comments, viewer)
        previous = state['issues'].get(number, {})
        entry = {'number': issue['number'], 'title': issue['title'], 'url': issue['html_url'],
                 'state': issue['state'], 'fingerprint': digest,
                 'action': action(previous, digest), 'previous': previous}
        marker = projects.parse_stage_marker(issue.get('body'))
        if marker:
            entry['stageMarker'] = marker
            if stage_roots is None:
                try:
                    stage_roots = {item['taskSlug']: item for item in project_snapshot()['items']}
                except (RuntimeError, OSError, ValueError):
                    stage_roots = {}
                    source_error = 'Project snapshot unavailable; verify stage linkage before intake'
            try:
                parent = gh_api(f'repos/{REPO}/issues/{number}/parent')
                # REST's url is an API URL; the shared verifier compares public issue URLs.
                parent = {'id': parent.get('node_id'), 'url': parent.get('html_url')}
                entry['parent'] = parent
                entry.update(projects.stage_linkage(marker, parent, stage_roots))
            except (RuntimeError, OSError, ValueError, AttributeError):
                entry.update(action='blocked', skipReason='stage-linkage-unverified', stageRoot=None)
                entry['sourceError'] = 'Native parent unavailable; verify stage linkage before intake'
            if source_error:
                entry['sourceError'] = source_error
        result.append(entry)
    result.sort(key=lambda x: (x['action'] != 'resume', x['number']))
    tasks = [{'task': slug, 'action': 'blocked' if record.get('phase') == 'blocked' else 'resume',
              'previous': record} for slug, record in state.get('tasks', {}).items()
             if record.get('phase') != 'verified']
    tasks.sort(key=lambda x: (x['action'] != 'resume', x['task']))
    return {'repository': REPO, 'lease': state.get('lease'), 'issues': result, 'tasks': tasks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, default=Path.home() / '.config/pir/maintenance')
    commands = parser.add_subparsers(dest='command', required=True)
    status = commands.add_parser('status')
    status.add_argument('--full', action='store_true')
    commands.add_parser('scan')
    begin = commands.add_parser('begin')
    begin.add_argument('--ttl', type=int, default=7200)
    begin.add_argument('--recover-expired', action='store_true')
    for name in ('guard', 'finish', 'checkpoint', 'comment'):
        sub = commands.add_parser(name)
        sub.add_argument('--run-id', required=True)
        if name == 'finish':
            sub.add_argument('--outcome', choices=['idle', 'completed', 'waiting', 'blocked', 'failed'], default='completed')
            sub.add_argument('--note')
            sub.add_argument('--next-action')
            sub.add_argument('--evidence', action='append')
        if name == 'guard': sub.add_argument('--renew', type=int, choices=range(60, 86401), metavar='SECONDS')
        if name == 'comment': sub.add_argument('--issue', required=True, type=int)
        if name == 'checkpoint':
            identity = sub.add_mutually_exclusive_group(required=True)
            identity.add_argument('--issue', type=int)
            identity.add_argument('--task')
            sub.add_argument('--plan')
        if name == 'checkpoint':
            sub.add_argument('--phase', choices=PHASES, required=True)
            for field in ('fingerprint', 'sha', 'release', 'note', 'version', 'build',
                          'pr-head-sha', 'merge-sha', 'build-sha', 'tag-sha', 'retry-when', 'resume-phase',
                          'worktree', 'branch', 'next-action', 'external-job'): sub.add_argument('--' + field)
            sub.add_argument('--pr', type=int)
            sub.add_argument('--evidence', action='append')
        if name == 'comment':
            sub.add_argument('--phase', choices=['triage', 'needs-info', 'blocked', 'verified'], required=True)
            sub.add_argument('--body-file', type=Path, required=True)
            sub.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    store = Store(args.state_dir)
    if args.command == 'status': result = store.read() if args.full else store.summary()
    elif args.command == 'scan': result = scan(store)
    elif args.command == 'begin': result = store.begin(ttl=args.ttl, recover=args.recover_expired)
    elif args.command == 'guard': result = store.guard(args.run_id, renew=args.renew)
    elif args.command == 'finish':
        result = store.finish(args.run_id, outcome=args.outcome, note=args.note,
                              next_action=args.next_action, evidence=args.evidence)
    elif args.command == 'checkpoint':
        fields = {k: v for k, v in vars(args).items() if k in
                  ('plan', 'phase', 'fingerprint', 'sha', 'release', 'note', 'pr', 'evidence', 'version', 'build',
                   'pr_head_sha', 'merge_sha', 'build_sha', 'tag_sha', 'retry_when', 'resume_phase', 'worktree', 'branch', 'next_action', 'external_job') if v is not None}
        aliases = {'pr_head_sha': 'prHeadSha', 'merge_sha': 'mergeSha', 'build_sha': 'buildSha',
                   'tag_sha': 'tagSha', 'retry_when': 'retryWhen', 'resume_phase': 'resumePhase',
                   'next_action': 'nextAction', 'external_job': 'externalJob'}
        fields = {aliases.get(k, k): v for k, v in fields.items()}
        result = store.checkpoint(args.run_id, args.issue, fields, task=args.task)
    else:
        store.guard(args.run_id)
        if args.dry_run: result = {'dryRun': True, 'body': args.body_file.read_text()}
        else:
            viewer = app_client().actor()
            store.guard(args.run_id)
            def guarded_api(endpoint, method='GET', data=None):
                if method == 'GET': return gh_api(endpoint)
                return store.mutate(args.run_id, lambda: gh_api(endpoint, method, data))
            result = upsert_comment(guarded_api, args.issue, args.phase, args.body_file.read_text(), viewer)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try: main()
    except Busy as error:
        print(json.dumps({'busy': str(error)}, ensure_ascii=False))
        raise SystemExit(75)
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'error': str(error)}, ensure_ascii=False))
        raise SystemExit(1)
