import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def module():
    spec = importlib.util.spec_from_file_location('pir_projects', ROOT / 'scripts/maintenance/projects.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def connection(nodes, cursor=None):
    return {'nodes': nodes, 'pageInfo': {'hasNextPage': cursor is not None, 'endCursor': cursor}}


def metadata():
    return {'id': 'PVT_CaseSensitive', 'number': 7, 'url': 'https://github.com/users/Caldis/projects/7',
            'title': 'Pir', 'closed': False,
            'fields': connection([{'__typename': 'ProjectV2SingleSelectField', 'id': 'STATUS',
                'name': 'Status', 'options': [{'id': 'todo-real', 'name': 'Todo'},
                    {'id': 'doing-real', 'name': 'In Progress'},
                    {'id': 'done-real', 'name': 'Done'}, {'id': 'blocked-real', 'name': 'Blocked'}]}])}


def item(identity='PVTI_A', kind='Issue', repository='Caldis/Pir', status='todo-real'):
    content = {'__typename': kind, 'id': 'CONTENT_' + identity, 'title': 'Task', 'body': 'Details'}
    if kind != 'DraftIssue':
        content.update(number=39, url='https://github.com/' + repository + '/issues/39',
                       state='OPEN', repository={'nameWithOwner': repository})
    if kind == 'Issue':
        content['parent'] = None
    return {'id': identity, 'isArchived': False, 'content': content,
            'fieldValueByName': {'__typename': 'ProjectV2ItemFieldSingleSelectValue',
                                 'optionId': status, 'name': 'Todo', 'field': {'id': 'STATUS'}}}


class ProjectsTests(unittest.TestCase):
    def setUp(self):
        self.m = module()

    def scan(self, items, pending=None, meta=None):
        meta = meta or metadata()
        responses = [{'data': {'user': {'projectV2': meta}}},
                     {'data': {'node': {'id': meta['id'], 'items': connection(items)}}}]
        with patch.object(self.m, 'graphql', side_effect=responses):
            return self.m.scan(pending=pending or {})

    def test_all_pages_and_dynamic_status_options(self):
        meta = metadata()
        last_field = meta['fields']['nodes'].pop()
        meta['fields'] = connection([{'__typename': 'ProjectV2Field', 'id': 'TITLE', 'name': 'Title'}], 'fields-2')
        responses = [{'data': {'user': {'projectV2': meta}}},
                     {'data': {'node': {'id': meta['id'], 'fields': connection([last_field])}}},
                     {'data': {'node': {'id': meta['id'], 'items': connection([item()], 'items-2')}}},
                     {'data': {'node': {'id': meta['id'], 'items': connection([item('PVTI_B', 'DraftIssue')])}}}]
        with patch.object(self.m, 'graphql', side_effect=responses) as api:
            result = self.m.scan()
        self.assertEqual(len(result['items']), 2)
        self.assertEqual(result['statusField']['options'][2]['id'], 'done-real')
        self.assertEqual(api.call_args_list[1].args[1]['cursor'], 'fields-2')
        self.assertEqual(api.call_args_list[3].args[1]['cursor'], 'items-2')
        self.assertEqual(result['project']['url'], metadata()['url'])

    def test_mixed_content_alias_and_foreign_repository(self):
        result = self.scan([item(), item('draft', 'DraftIssue'), item('pr', 'PullRequest'),
                            item('foreign', repository='Caldis/Mos')])
        issue, draft, pr, foreign = result['items']
        self.assertEqual(issue['issueAlias'], 'Caldis/Pir#39')
        self.assertIsNone(draft['issueAlias'])
        self.assertEqual(draft['action'], 'new')
        self.assertEqual(pr['skipReason'], 'pull-request')
        self.assertEqual(foreign['skipReason'], 'foreign-repository')

    def test_identity_case_sensitive_and_title_independent(self):
        first = self.scan([item()])['items'][0]['taskSlug']
        renamed = item()
        renamed['content']['title'] = 'Changed title'
        self.assertEqual(first, self.scan([renamed])['items'][0]['taskSlug'])
        self.assertNotEqual(first, self.scan([item('pvti_a')])['items'][0]['taskSlug'])
        self.assertLessEqual(len(first), 64)
        self.assertRegex(first, r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
        self.assertNotEqual(first, self.m.task_slug('pvt_casesensitive', 'PVTI_A'))

    def test_stage_children_parent_and_marker_are_never_new_roots(self):
        child, marked = item('child'), item('marked')
        child['content']['parent'] = {'id': 'ROOT', 'number': 1, 'url': 'https://github.com/Caldis/Pir/issues/1'}
        marked['content']['body'] = '<!-- pir-maintainer:project-stage:project-abc:review -->'
        result = self.scan([child, marked])
        self.assertEqual(result['items'][0]['action'], 'new')
        self.assertEqual(result['items'][0]['parent']['number'], 1)
        self.assertEqual(result['items'][1]['skipReason'], 'stage-child')

    def test_done_archived_closed_deleted_blocked_and_pending_recovery(self):
        done, archived, closed, deleted, blocked = (item(x) for x in ('done', 'archived', 'closed', 'deleted', 'blocked'))
        done['fieldValueByName']['optionId'] = 'done-real'
        archived['isArchived'] = True
        closed['content']['state'] = 'CLOSED'
        deleted['content'] = None
        blocked['fieldValueByName']['optionId'] = 'blocked-real'
        slug = self.m.task_slug(metadata()['id'], 'done')
        pending = {slug: {'phase': 'merged', 'plan': 'plan.md'}, 'other-pending': {'phase': 'published'},
                   'finished': {'phase': 'verified'}}
        result = self.scan([done, archived, closed, deleted, blocked], pending)
        self.assertEqual(result['items'][0]['action'], 'resume')
        self.assertEqual([x['action'] for x in result['items'][1:]], ['skip', 'skip', 'skip', 'blocked'])
        self.assertEqual(result['resumeTasks'][0]['taskSlug'], slug)
        self.assertEqual(result['resumeTasks'][1]['taskSlug'], 'other-pending')
        self.assertFalse(result['resumeTasks'][1]['presentInProject'])
        self.assertEqual(result['items'][3]['skipReason'], 'inaccessible-or-deleted-content')

    def test_null_project_missing_status_and_incomplete_pagination_fail_closed(self):
        bad = metadata()
        bad['fields']['nodes'] = []
        with self.assertRaises(self.m.ScanError):
            self.scan([], meta=bad)
        with patch.object(self.m, 'graphql', return_value={'data': {'user': {'projectV2': None}}}):
            with self.assertRaises(self.m.ScanError):
                self.m.scan()
        bad = metadata()
        bad['fields']['pageInfo'] = {'hasNextPage': True, 'endCursor': None}
        with self.assertRaises(self.m.ScanError):
            self.scan([], meta=bad)
        bad_item = item()
        del bad_item['isArchived']
        with self.assertRaises(self.m.ScanError):
            self.scan([bad_item])
        bad_item = item()
        bad_item['fieldValueByName']['optionId'] = 'unknown'
        self.assertEqual(self.scan([bad_item])['items'][0]['skipReason'], 'unknown-status-option')

    def test_parent_in_foreign_repository_requires_review(self):
        child = item('child')
        child['content']['parent'] = {'id': 'foreign', 'number': 3,
            'url': 'https://github.com/Caldis/Mos/issues/3',
            'repository': {'nameWithOwner': 'Caldis/Mos'}}
        result = self.scan([child])['items'][0]
        self.assertEqual(result['action'], 'blocked')
        self.assertEqual(result['skipReason'], 'foreign-parent-repository')

    def test_repeated_items_cursor_duplicate_items_and_null_nodes_fail_closed(self):
        meta = metadata()
        for tail in [connection([item()], 'repeated'), connection([item()]), connection([None])]:
            responses = [{'data': {'user': {'projectV2': meta}}},
                {'data': {'node': {'id': meta['id'], 'items': connection([item()], 'repeated')}}},
                {'data': {'node': {'id': meta['id'], 'items': tail}}}]
            with self.subTest(tail=tail), patch.object(self.m, 'graphql', side_effect=responses):
                with self.assertRaises(self.m.ScanError):
                    self.m.scan()

    def test_verified_and_unconfigured_status_never_restart_work(self):
        original = item()
        slug = self.m.task_slug(metadata()['id'], original['id'])
        result = self.scan([original], {slug: {'phase': 'verified'}})
        self.assertEqual(result['items'][0]['action'], 'unchanged')
        self.assertEqual(result['resumeTasks'], [])
        for selection in [None, {**original['fieldValueByName'], 'optionId': 'unexpected'}]:
            original['fieldValueByName'] = selection
            self.assertEqual(self.scan([original])['items'][0]['action'], 'blocked')

    def test_partial_failure_cli_has_no_partial_snapshot(self):
        meta = metadata()
        responses = [{'data': {'user': {'projectV2': meta}}},
            {'data': {'node': {'id': meta['id'], 'items': connection([item()], 'second')}}},
            self.m.ScanError('GitHub Project returned errors or inaccessible data; snapshot discarded')]
        with tempfile.TemporaryDirectory() as directory, patch.object(self.m, 'graphql', side_effect=responses), \
             patch('sys.stdout', new_callable=io.StringIO) as out, patch('sys.stderr', new_callable=io.StringIO):
            self.assertEqual(self.m.main(['--state-dir', directory]), 1)
            self.assertEqual(out.getvalue(), '')
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_graphql_partial_errors_timeout_and_stderr_never_leak(self):
        for completed in [subprocess.CompletedProcess([], 0, json.dumps({'data': {'user': {}}, 'errors': [{'message': 'secret-token'}]}), ''),
                          subprocess.CompletedProcess([], 1, '', 'secret-token'),
                          subprocess.CompletedProcess([], 0, 'not JSON secret-token', '')]:
            with self.subTest(completed=completed), patch.object(self.m.subprocess, 'run', return_value=completed) as run:
                with self.assertRaises(self.m.ScanError) as failure:
                    self.m.graphql('query { viewer { login } }', {})
                self.assertNotIn('secret-token', str(failure.exception))
                self.assertEqual(run.call_args.kwargs['timeout'], 90)
                self.assertEqual(run.call_args.args[0][:3], ['gh', 'api', 'graphql'])
        with patch.object(self.m.subprocess, 'run', side_effect=subprocess.TimeoutExpired('gh secret-token', 90)):
            with self.assertRaises(self.m.ScanError) as failure:
                self.m.graphql('query {}', {})
        self.assertNotIn('secret-token', str(failure.exception))

    def test_cli_state_read_only_and_error_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'state.json'
            original = json.dumps({'schema': 1, 'repository': 'Caldis/Pir', 'issues': {}, 'tasks': {'project-old': {'phase': 'merged'}}})
            path.write_text(original)
            with patch.object(self.m, 'scan', return_value={'items': []}) as scan, patch('sys.stdout', new_callable=io.StringIO) as output:
                self.assertEqual(self.m.main(['--state-dir', directory]), 0)
                self.assertEqual(json.loads(output.getvalue()), {'items': []})
            self.assertEqual(scan.call_args.kwargs['pending']['project-old']['phase'], 'merged')
            self.assertEqual(path.read_text(), original)
            self.assertEqual(sorted(p.name for p in Path(directory).iterdir()), ['state.json'])
        with patch.object(self.m, 'scan', side_effect=self.m.ScanError('Read denied')), patch('sys.stderr', new_callable=io.StringIO) as err:
            self.assertEqual(self.m.main([]), 1)
            self.assertIn('Read denied', err.getvalue())


if __name__ == '__main__':
    unittest.main()
