import importlib.util
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

    def test_own_comments_do_not_retrigger_but_reporter_edits_do(self):
        issue = {'number': 39, 'title': 'Resize', 'body': 'Wrong size', 'labels': []}
        comments = [{'body': 'Reproduction', 'user': {'login': 'reporter'}}]
        before = self.m.fingerprint(issue, comments, 'Caldis')
        comments.append({'body': '<!-- pir-maintainer:39:triage -->\nWorking', 'user': {'login': 'Caldis'}})
        self.assertEqual(before, self.m.fingerprint(issue, comments, 'Caldis'))
        comments[0]['body'] = 'New reproduction'
        self.assertNotEqual(before, self.m.fingerprint(issue, comments, 'Caldis'))

    def test_marker_from_another_author_does_not_hide_new_input(self):
        issue = {'number': 39, 'title': 'Resize', 'body': '', 'labels': []}
        before = self.m.fingerprint(issue, [], 'Caldis')
        comments = [{'body': '<!-- pir-maintainer:39:triage --> changed', 'user': {'login': 'reporter'}}]
        self.assertNotEqual(before, self.m.fingerprint(issue, comments, 'Caldis'))

    def test_upsert_reuses_own_comment_and_ignores_foreign_marker(self):
        marker = '<!-- pir-maintainer:39:triage -->'
        comments = [{'id': 2, 'body': marker + '\nforeign', 'user': {'login': 'reporter'}},
                    {'id': 3, 'body': marker + '\nold', 'user': {'login': 'Caldis'}}]
        calls = []
        def api(endpoint, method='GET', data=None):
            calls.append((endpoint, method, data))
            if method == 'GET': return comments
            return {'id': 3}
        self.m.upsert_comment(api, 39, 'triage', 'new', 'Caldis')
        self.assertEqual(calls[-1][0], 'repos/Caldis/Pir/issues/comments/3')
        self.assertEqual(calls[-1][1], 'PATCH')
        comments[1]['body'] = marker + '\nnew'
        calls.clear()
        self.m.upsert_comment(api, 39, 'triage', 'new', 'Caldis')
        self.assertEqual(len(calls), 1)

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
            self.m.upsert_comment(api, 39, 'triage', 'hello', 'Caldis')
        self.assertEqual(writes, [])
