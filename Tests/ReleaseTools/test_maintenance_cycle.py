import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def module():
    spec = importlib.util.spec_from_file_location('pir_cycle', ROOT / 'scripts/maintenance/cycle.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.m = module()
        auth = patch.object(self.m, 'app_client')
        self.auth = auth.start().return_value
        self.addCleanup(auth.stop)
        self.auth.environment.return_value = {'GH_TOKEN': 'offline-fixture'}
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.store = self.m.Store(Path(self.directory.name))

    def test_active_lease_excludes_second_run_and_wrong_writer(self):
        run = self.store.begin(now=100, ttl=120)
        with self.assertRaises(self.m.Busy):
            self.store.begin(now=101, ttl=120)
        with self.assertRaises(self.m.Busy):
            self.store.guard('wrong', now=101)
        self.store.guard(run['id'], now=101)

    def test_expired_lease_requires_explicit_recovery_and_invalidates_old_run(self):
        old = self.store.begin(now=100, ttl=120)
        with self.assertRaises(self.m.Busy):
            self.store.begin(now=221, ttl=120)
        new = self.store.begin(now=221, ttl=120, recover=True)
        with self.assertRaises(self.m.Busy):
            self.store.guard(old['id'], now=222)
        self.assertEqual(new['recoveredFrom'], old['id'])

    def test_finish_releases_lease_but_preserves_resume_checkpoint(self):
        run = self.store.begin(now=100, ttl=120)
        self.store.checkpoint(run['id'], 39, {'phase': 'merged', 'pr': 40, 'sha': 'abc'}, now=101)
        self.store.finish(run['id'], now=102)
        self.store.begin(now=103, ttl=120)
        self.assertEqual(self.store.read()['issues']['39']['phase'], 'merged')

    def test_finish_records_terminal_result_and_time_without_schedule(self):
        run = self.store.begin(now=100, ttl=120)
        result = self.store.finish(run['id'], now=110, outcome='waiting',
            note='CI pending', next_action='Read exact head CI', evidence=['ci.json'])
        self.assertEqual(result['finishedAt'], 110)
        self.assertEqual(result['outcome'], 'waiting')
        self.assertEqual(result['nextAction'], 'Read exact head CI')
        self.assertEqual(self.store.read()['lastRun'], result)
        self.assertIsNone(self.store.read()['lease'])
        journal = self.store.root / 'runs' / (run['id'] + '.json')
        self.assertEqual(__import__('json').loads(journal.read_text()), result)
        self.assertNotIn('frequency', result)

    def test_invalid_finish_keeps_lease_and_cannot_claim_success(self):
        run = self.store.begin(now=100, ttl=120)
        with self.assertRaises(ValueError):
            self.store.finish(run['id'], now=110, outcome='invented')
        self.assertEqual(self.store.read()['lease']['id'], run['id'])
        self.store.checkpoint(run['id'], 39, {'phase': 'implementing'}, now=111)
        with self.assertRaises(ValueError):
            self.store.finish(run['id'], now=112, outcome='idle')
        self.assertEqual(self.store.read()['lease']['id'], run['id'])

    def test_compact_summary_keeps_resume_facts_hides_old_bodies(self):
        run = self.store.begin(now=100, ttl=120)
        self.store.checkpoint(run['id'], 39, {'phase': 'blocked', 'pr': 40,
            'worktree': '/tmp/worker', 'branch': 'codex/issue-39',
            'nextAction': 'Read notary job', 'externalJob': 'apple-job-id',
            'retryWhen': 'Keychain unlocked'}, now=101)
        with self.store.transaction() as data:
            data['notifications'] = {'sent': {'status': 'sent', 'event': {'detail': 'old verbose body'}}}
        result = self.store.summary()
        self.assertEqual(result['issues']['39']['worktree'], '/tmp/worker')
        self.assertEqual(result['issues']['39']['externalJob'], 'apple-job-id')
        self.assertNotIn('old verbose body', __import__('json').dumps(result))
        self.assertEqual(result['notifications'], {'sent': 1})

    def test_journal_failure_keeps_lease_and_previous_result(self):
        run = self.store.begin(now=100, ttl=120)
        with patch.object(self.m.os, 'replace', side_effect=OSError('simulated disk failure')):
            with self.assertRaises(OSError):
                self.store.finish(run['id'], now=110, outcome='failed')
        self.assertEqual(self.store.read()['lease']['id'], run['id'])
        self.assertNotIn('lastRun', self.store.read())

    def test_finish_can_be_retried_after_unknown_local_outcome(self):
        run = self.store.begin(now=100, ttl=120)
        result = self.store.finish(run['id'], now=110, outcome='completed')
        self.assertEqual(self.store.finish(run['id'], now=111, outcome='completed'), result)
        new = self.store.begin(now=112, ttl=120)
        with self.assertRaises(self.m.Busy):
            self.store.finish(run['id'], now=113, outcome='completed')
        self.assertEqual(self.store.read()['lease']['id'], new['id'])

    def test_own_comments_do_not_retrigger_but_reporter_edits_do(self):
        issue = {'number': 39, 'title': 'Resize', 'body': 'Wrong size', 'labels': []}
        comments = [{'body': 'Reproduction', 'user': {'login': 'reporter'}}]
        before = self.m.fingerprint(issue, comments)
        comments.append({'body': '<!-- pir-maintainer:39:triage -->\nWorking', 'user': {'login': 'Caldis'}})
        self.assertEqual(before, self.m.fingerprint(issue, comments))
        comments[0]['body'] = 'New reproduction'
        self.assertNotEqual(before, self.m.fingerprint(issue, comments))

    def test_marker_from_another_author_does_not_hide_new_input(self):
        issue = {'number': 39, 'title': 'Resize', 'body': '', 'labels': []}
        before = self.m.fingerprint(issue, [])
        comments = [{'body': '<!-- pir-maintainer:39:triage --> changed', 'user': {'login': 'reporter'}}]
        self.assertNotEqual(before, self.m.fingerprint(issue, comments))

    def test_upsert_reuses_own_comment_and_ignores_foreign_marker(self):
        marker = '<!-- pir-maintainer:39:triage -->'
        comments = [{'id': 2, 'body': marker + '\nforeign', 'user': {'login': 'reporter'}},
                    {'id': 3, 'body': marker + '\nold', 'user': {'login': 'pir-maintainer[bot]', 'id': 349413745}}]
        calls = []
        def api(endpoint, method='GET', data=None):
            calls.append((endpoint, method, data))
            if method == 'GET': return comments
            return {'id': 3}
        self.m.upsert_comment(api, 39, 'triage', 'new')
        self.assertEqual(calls[-1][0], 'repos/Caldis/Pir/issues/comments/3')
        self.assertEqual(calls[-1][1], 'PATCH')
        comments[1]['body'] = marker + '\nnew'
        calls.clear()
        self.m.upsert_comment(api, 39, 'triage', 'new')
        self.assertEqual(len(calls), 1)

    def test_renamed_bot_marker_preserves_fingerprint_and_reuses_historical_comment(self):
        issue = {'number': 39, 'title': 'Resize', 'body': '', 'labels': []}
        marker = '<!-- pir-maintainer:39:triage -->'
        historical = {'id': 3, 'body': marker + '\nold',
                      'user': {'id': 349413745, 'login': 'caldis-pir-maintainer[bot]'}}
        comments = [historical]
        before = self.m.fingerprint(issue, [])
        self.assertEqual(before, self.m.fingerprint(issue, comments))
        historical['user']['login'] = 'pir-maintainer[bot]'
        self.assertEqual(before, self.m.fingerprint(issue, comments))
        historical['user']['login'] = 'caldis-pir-maintainer[bot]'
        # Even a newer matching marker with the current login cannot claim ownership.
        comments.extend([{'id': 4, 'body': marker + '\nowner', 'user': {'id': 1499953, 'login': 'Caldis'}},
                         {'id': 5, 'body': marker + '\nforeign', 'user': {'id': 999, 'login': 'pir-maintainer[bot]'}}])
        calls = []
        def api(endpoint, method='GET', data=None):
            calls.append((endpoint, method, data))
            return comments if method == 'GET' else {'id': 3}
        self.m.upsert_comment(api, 39, 'triage', 'new')
        self.assertEqual(calls[-1][:2], ('repos/Caldis/Pir/issues/comments/3', 'PATCH'))
        self.assertEqual(comments[1]['body'], marker + '\nowner')
        self.assertEqual(comments[2]['body'], marker + '\nforeign')
        self.assertNotEqual(before, self.m.fingerprint(issue, comments))

    def test_current_bot_login_without_matching_id_cannot_hide_or_edit_input(self):
        issue = {'number': 39, 'title': 'Resize', 'body': '', 'labels': []}
        marker = '<!-- pir-maintainer:39:triage -->'
        for user in ({'login': 'pir-maintainer[bot]'}, {'login': 'pir-maintainer[bot]', 'id': 999}):
            comments = [{'id': 2, 'body': marker + '\nforeign', 'user': user}]
            self.assertNotEqual(self.m.fingerprint(issue, []), self.m.fingerprint(issue, comments))
            calls = []
            def api(endpoint, method='GET', data=None):
                calls.append((endpoint, method))
                return comments if method == 'GET' else {'id': 3}
            self.m.upsert_comment(api, 39, 'triage', 'new')
            self.assertEqual(calls[-1][1], 'POST')

    def test_resume_action_is_not_hidden_when_issue_was_closed_on_merge(self):
        self.assertEqual(self.m.action({'phase': 'merged', 'fingerprint': 'x'}, 'x'), 'resume')
        self.assertEqual(self.m.action({'phase': 'verified', 'fingerprint': 'x'}, 'x'), 'unchanged')
        self.assertEqual(self.m.action({'phase': 'blocked', 'fingerprint': 'x'}, 'x'), 'blocked')
        self.assertEqual(self.m.action({'phase': 'verified', 'fingerprint': 'x'}, 'y'), 'changed')

    def test_verified_checkpoint_requires_real_evidence_fields(self):
        run = self.store.begin(now=100, ttl=120)
        with self.assertRaises(ValueError):
            self.store.checkpoint(run['id'], 39, {'phase': 'verified'}, now=101)

    def test_new_input_after_verified_does_not_reuse_old_release(self):
        run = self.store.begin(now=100, ttl=120)
        self.store.checkpoint(run['id'], 39, {'phase': 'verified', 'fingerprint': 'old',
            'release': '0.1.9', 'evidence': ['https://example.com/verified']}, now=101)
        self.store.checkpoint(run['id'], 39, {'phase': 'implementing', 'fingerprint': 'new'}, now=102)
        self.assertNotIn('release', self.store.read()['issues']['39'])

    def test_new_reporter_input_preserves_blocked_release_context(self):
        run = self.store.begin(now=100, ttl=120)
        self.store.checkpoint(run['id'], 39, {'phase': 'merged', 'fingerprint': 'old', 'pr': 40, 'sha': 'abc'}, now=101)
        self.store.checkpoint(run['id'], 39, {'phase': 'blocked', 'release': '0.1.10', 'retryWhen': 'macbook online'}, now=102)
        self.store.checkpoint(run['id'], 39, {'phase': 'blocked', 'fingerprint': 'new'}, now=103)
        item = self.store.read()['issues']['39']
        self.assertEqual(item['pr'], 40)
        self.assertEqual(item['resumePhase'], 'merged')
        self.assertEqual(item['release'], '0.1.10')

    def test_stage_scan_checks_only_marked_issues_and_never_intakes_child_as_root(self):
        root = {'taskSlug': 'project-root', 'itemId': 'ROOT_ITEM', 'content': {
            '__typename': 'Issue', 'id': 'ROOT_NODE', 'url': 'https://github.com/Caldis/Pir/issues/33',
            'repository': {'nameWithOwner': 'Caldis/Pir'}, 'body': ''}, 'stageMarker': None}
        marker = '<!-- pir-maintainer:project-stage:project-root:review -->'
        opened = [{'number': number, 'title': 'Work', 'body': body, 'labels': [],
            'state': 'open', 'html_url': f'https://github.com/Caldis/Pir/issues/{number}'}
            for number, body in [(33, ''), (34, marker), (35, marker), (36, '')]]
        calls = []
        def api(endpoint, method='GET', data=None):
            calls.append(endpoint)
            if endpoint == 'user': return {'login': 'Caldis'}
            if 'state=open' in endpoint: return opened
            if endpoint.endswith('/parent'):
                return {'node_id': 'ROOT_NODE' if '/34/' in endpoint else 'FOREIGN',
                        'html_url': 'https://github.com/Caldis/Pir/issues/33'}
            if '/comments' in endpoint: return []
            self.fail(endpoint)
        with patch.object(self.m, 'gh_api', api), patch.object(self.m, 'project_snapshot', return_value={'items': [root]}) as snapshot:
            result = self.m.scan(self.store)
        actions = {i['number']: i for i in result['issues']}
        self.assertEqual(actions[33]['action'], 'new')
        self.assertEqual(actions[34]['action'], 'stage')
        self.assertEqual(actions[34]['stageRoot']['taskSlug'], 'project-root')
        self.assertEqual(actions[35]['action'], 'blocked')
        self.assertEqual(actions[36]['action'], 'new')
        self.assertEqual(len([x for x in calls if x.endswith('/parent')]), 2)
        snapshot.assert_called_once()
        self.assertFalse(self.store.path.exists())

    def test_marked_issue_missing_parent_or_project_access_is_not_silently_skipped(self):
        opened = [{'number': 34, 'title': 'Task', 'body': '<!-- pir-maintainer:project-stage:project-root:review -->',
                   'labels': [], 'state': 'open', 'html_url': 'https://github.com/Caldis/Pir/issues/34'}]
        def api(endpoint, method='GET', data=None):
            if endpoint == 'user': return {'login': 'Caldis'}
            if 'state=open' in endpoint: return opened
            if '/comments' in endpoint: return []
            raise RuntimeError('read denied')
        opened.append({'number': 36, 'title': 'Owner task', 'body': '', 'labels': [],
                       'state': 'open', 'html_url': 'https://github.com/Caldis/Pir/issues/36'})
        with patch.object(self.m, 'gh_api', api), patch.object(self.m, 'project_snapshot', side_effect=RuntimeError('read denied')):
            result = self.m.scan(self.store)
        self.assertEqual(result['issues'][0]['action'], 'blocked')
        self.assertEqual(result['issues'][0]['skipReason'], 'stage-linkage-unverified')
        self.assertIn('sourceError', result['issues'][0])
        self.assertEqual(result['issues'][1]['action'], 'new')

    def test_scan_includes_closed_blocked_issues(self):
        run = self.store.begin(now=100, ttl=120)
        self.store.checkpoint(run['id'], 39, {'phase': 'blocked', 'fingerprint': 'x'}, now=101)
        def api(endpoint, method='GET', data=None):
            if endpoint == 'user': return {'login': 'Caldis'}
            if 'state=open' in endpoint: return []
            if '/comments' in endpoint: return []
            return {'number': 39, 'title': 'Bug', 'body': '', 'labels': [], 'state': 'closed', 'html_url': 'https://github.com/Caldis/Pir/issues/39'}
        with patch.object(self.m, 'gh_api', api):
            result = self.m.scan(self.store)
        self.assertEqual([i['number'] for i in result['issues']], [39])

    def test_comment_mutation_rechecks_lease_after_reading_comments(self):
        run = self.store.begin(now=100, ttl=120)
        writes = []
        def api(endpoint, method='GET', data=None):
            if method == 'GET': return []
            return self.store.mutate(run['id'], lambda: writes.append(data), now=300)
        with self.assertRaises(self.m.Busy):
            self.m.upsert_comment(api, 39, 'triage', 'hello')
        self.assertEqual(writes, [])

    def test_changed_input_on_blocked_merged_release_resumes_existing_work(self):
        previous = {'phase': 'blocked', 'resumePhase': 'merged', 'pr': 40, 'fingerprint': 'old'}
        self.assertEqual(self.m.action(previous, 'new'), 'resume')

    def task_checkpoint(self, run_id, fields, now=101, slug='task-recovery'):
        return self.store.checkpoint(run_id, None, fields, now=now, task=slug)

    def test_task_checkpoint_preserves_blocked_context_and_release_gates(self):
        run = self.store.begin(now=100, ttl=120)
        self.task_checkpoint(run['id'], {'phase': 'merged', 'plan': 'docs/plans/recovery.md',
            'pr': 41, 'mergeSha': 'abc', 'worktree': '/tmp/worker',
            'branch': 'codex/task-recovery', 'externalJob': 'github:42',
            'nextAction': 'Read current head CI'})
        self.task_checkpoint(run['id'], {'phase': 'blocked', 'retryWhen': 'CI succeeds'}, now=102)
        item = self.task_checkpoint(run['id'], {'phase': 'blocked', 'note': 'Still pending'}, now=103)
        self.assertEqual(item['resumePhase'], 'merged')
        self.assertEqual(item['pr'], 41)
        self.assertEqual(item['mergeSha'], 'abc')
        self.assertEqual(item['plan'], 'docs/plans/recovery.md')
        self.assertEqual(item['externalJob'], 'github:42')
        before = self.store.path.read_bytes()
        for phase in ('prepared', 'published', 'verified'):
            with self.assertRaises(ValueError):
                self.task_checkpoint(run['id'], {'phase': phase}, now=104)
            self.assertEqual(before, self.store.path.read_bytes())
        with self.assertRaises(ValueError):
            self.task_checkpoint(run['id'], {'phase': 'verified', 'release': 'not-required',
                'evidence': ['ci.json'], 'note': ''}, now=104)
        self.task_checkpoint(run['id'], {'phase': 'verified', 'release': 'not-required',
            'evidence': ['ci.json'], 'note': 'Tooling only'}, now=105)
        self.assertEqual(self.store.summary()['verifiedTaskCount'], 1)
        self.assertEqual(self.store.summary()['tasks'], {})

    def test_invalid_task_identity_plan_and_lease_do_not_mutate_state(self):
        run = self.store.begin(now=100, ttl=120)
        before = self.store.path.read_bytes()
        for slug in ('../escape', 'UPPER', 'a_b', 'a--b', '', 'a' * 65):
            with self.subTest(slug=slug), self.assertRaises(ValueError):
                self.task_checkpoint(run['id'], {'phase': 'implementing', 'plan': 'plan.md'}, slug=slug)
            self.assertEqual(before, self.store.path.read_bytes())
        for fields in ({'phase': 'implementing'}, {'phase': 'implementing', 'plan': '   '}):
            with self.assertRaises(ValueError):
                self.task_checkpoint(run['id'], fields)
            self.assertEqual(before, self.store.path.read_bytes())
        with self.assertRaises(self.m.Busy):
            self.task_checkpoint('wrong', {'phase': 'implementing', 'plan': 'plan.md'})
        self.assertEqual(before, self.store.path.read_bytes())
        with self.assertRaises(ValueError):
            self.store.checkpoint(run['id'], 39, {'phase': 'implementing', 'plan': 'plan.md'},
                now=101, task='task-recovery')
        self.assertEqual(before, self.store.path.read_bytes())

    def test_task_scan_is_read_only_and_keeps_tasks_separate_from_new_issues(self):
        run = self.store.begin(now=100, ttl=120)
        for slug, phase in (('resume-work', 'implementing'), ('blocked-work', 'blocked'), ('done-work', 'verified')):
            fields = {'phase': phase, 'plan': 'plan.md', 'pr': 41, 'nextAction': 'Read PR'}
            if phase == 'verified': fields.update(release='not-required', evidence=['ci.json'], note='Tooling')
            self.task_checkpoint(run['id'], fields, slug=slug)
        before = self.store.path.read_bytes()
        calls = []
        def api(endpoint, method='GET', data=None):
            calls.append((endpoint, method))
            if endpoint == 'user': return {'login': 'Caldis'}
            if 'state=open' in endpoint:
                return [{'number': 39, 'title': 'Bug', 'body': '', 'labels': [],
                    'state': 'open', 'html_url': 'https://github.com/Caldis/Pir/issues/39'}]
            if '/comments' in endpoint: return []
            self.fail('Task must not produce a GitHub issue lookup')
        with patch.object(self.m, 'gh_api', api):
            result = self.m.scan(self.store)
        self.assertEqual(before, self.store.path.read_bytes())
        self.assertEqual([(x['task'], x['action']) for x in result['tasks']],
            [('resume-work', 'resume'), ('blocked-work', 'blocked')])
        self.assertEqual(result['tasks'][0]['previous']['plan'], 'plan.md')
        self.assertEqual([(x['number'], x['action']) for x in result['issues']], [(39, 'new')])
        self.assertTrue(all(method == 'GET' for _, method in calls))

    def test_task_reopened_with_new_fingerprint_records_distinct_history(self):
        run = self.store.begin(now=100, ttl=120)
        fields = {'phase': 'verified', 'plan': 'plan.md', 'fingerprint': 'old',
            'release': 'not-required', 'note': 'Tooling', 'evidence': ['ci.json']}
        self.task_checkpoint(run['id'], fields)
        self.store.checkpoint(run['id'], 39, fields, now=101)
        self.task_checkpoint(run['id'], {'phase': 'implementing', 'plan': 'new-plan.md',
            'fingerprint': 'new'}, now=102)
        self.store.checkpoint(run['id'], 39, {'phase': 'implementing', 'fingerprint': 'new'}, now=102)
        history = self.store.read()['history']
        self.assertEqual(history[0]['task'], 'task-recovery')
        self.assertNotIn('issue', history[0])
        self.assertEqual(history[1]['issue'], 39)
        self.assertNotIn('task', history[1])
        self.assertNotIn('release', self.store.read()['tasks']['task-recovery'])

    def test_old_issue_only_state_supports_task_checkpoint_without_migration(self):
        old = {'schema': 1, 'repository': self.m.REPO, 'issues': {'39': {'phase': 'merged'}}, 'lease': None}
        self.store.path.write_text(json.dumps(old))
        self.assertEqual(self.store.summary()['tasks'], {})
        self.assertEqual(json.loads(self.store.path.read_text()), old)
        run = self.store.begin(now=100, ttl=120)
        self.task_checkpoint(run['id'], {'phase': 'implementing', 'plan': 'plan.md'})
        self.assertEqual(self.store.read()['issues'], old['issues'])

    def test_real_cli_recovers_task_across_two_runs_and_rejects_false_idle(self):
        def cli(*args, expected=0):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/maintenance/cycle.py'),
                '--state-dir', self.directory.name, *args], text=True, capture_output=True)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            return json.loads(result.stdout) if result.stdout else None
        first = cli('begin')['id']
        cli('checkpoint', '--run-id', first, '--task', 'task-recovery', '--phase', 'pr_open',
            '--plan', 'plan.md', '--pr', '41', '--pr-head-sha', 'abc', '--branch', 'codex/task-recovery',
            '--worktree', '/tmp/worker', '--next-action', 'Read current head CI', '--evidence', 'ci.json')
        cli('finish', '--run-id', first, '--outcome', 'waiting')
        recovered = cli('status')['tasks']['task-recovery']
        self.assertEqual(recovered['prHeadSha'], 'abc')
        self.assertEqual(recovered['plan'], 'plan.md')
        second = cli('begin')['id']
        self.assertNotEqual(first, second)
        before = self.store.path.read_bytes()
        cli('checkpoint', '--run-id', first, '--task', 'task-recovery', '--phase', 'merged', expected=75)
        cli('finish', '--run-id', second, '--outcome', 'idle', expected=1)
        cli('checkpoint', '--run-id', second, '--issue', '39', '--task', 'task-recovery',
            '--phase', 'merged', expected=2)
        cli('comment', '--run-id', second, '--task', 'task-recovery', '--phase', 'verified',
            '--body-file', 'unused', expected=2)
        self.assertEqual(before, self.store.path.read_bytes())
        cli('checkpoint', '--run-id', second, '--task', 'task-recovery', '--phase', 'merged', '--merge-sha', 'def')
        cli('checkpoint', '--run-id', second, '--task', 'task-recovery', '--phase', 'verified',
            '--release', 'not-required', '--note', 'Tooling only')
        self.assertEqual(cli('status')['tasks'], {})
        cli('finish', '--run-id', second, '--outcome', 'completed')


class AppIdentityIntegrationTests(unittest.TestCase):
    def test_scan_and_comment_migration_preserve_legacy_owner_comments(self):
        m = module()
        with tempfile.TemporaryDirectory() as directory:
            store = m.Store(Path(directory))
            endpoints = []
            def api(endpoint, method='GET', data=None):
                endpoints.append(endpoint)
                if 'state=open' in endpoint:
                    return [{'number': 1, 'title': 'Owner request', 'body': '', 'labels': [], 'state': 'open', 'html_url': 'https://github.com/Caldis/Pir/issues/1'}]
                return []
            with patch.object(m, 'gh_api', side_effect=api):
                result = m.scan(store)
            self.assertEqual(result['issues'][0]['number'], 1)
            self.assertNotIn('user', endpoints)
            legacy = [{'id': 3, 'user': {'login': 'Caldis'}, 'body': '<!-- pir-maintainer:1:triage -->\nOld'}]
            issue = {'number': 1, 'title': 'Owner request', 'body': '', 'labels': []}
            self.assertEqual(m.fingerprint(issue, legacy), m.fingerprint(issue, []))
            writes = []
            def comments(endpoint, method='GET', data=None):
                if method == 'GET': return legacy
                writes.append((endpoint, method, data))
                return {'id': 4}
            m.upsert_comment(comments, 1, 'triage', 'Current bot status')
            self.assertEqual(writes[0][1], 'POST')
            self.assertEqual(legacy[0]['body'], '<!-- pir-maintainer:1:triage -->\nOld')

    def test_repository_call_never_falls_back_and_does_not_echo_stderr(self):
        m = module()
        with patch.object(m, 'app_client') as auth, patch.object(m.subprocess, 'run') as run:
            auth.return_value.environment.side_effect = m._auth.AuthError('GitHub App local credential is unavailable')
            with self.assertRaises(m._auth.AuthError): m.gh_api('repos/Caldis/Pir')
            run.assert_not_called()
        with patch.object(m, 'app_client') as auth, patch.object(m.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'owner-secret')) as run:
            auth.return_value.environment.return_value = {'GH_TOKEN': 'installation-fixture'}
            with self.assertRaises(RuntimeError) as failure: m.gh_api('repos/Caldis/Pir')
            self.assertNotIn('owner-secret', str(failure.exception))
            self.assertEqual(run.call_args.kwargs['env'], {'GH_TOKEN': 'installation-fixture'})
