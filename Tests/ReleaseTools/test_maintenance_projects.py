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
            'fieldValues': connection([]),
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
        self.assertEqual(result['items'][1]['skipReason'], 'stage-linkage-unverified')
        self.assertEqual(result['items'][1]['action'], 'blocked')

    def test_stage_requires_matching_root_item_and_native_parent_across_pages(self):
        root, child = item('root'), item('child')
        slug = self.m.task_slug(metadata()['id'], 'root')
        child['content']['body'] = f'<!-- pir-maintainer:project-stage:{slug}:review -->'
        child['content']['parent'] = {'id': root['content']['id'], 'url': root['content']['url']}
        responses = [{'data': {'user': {'projectV2': metadata()}}},
            {'data': {'node': {'id': metadata()['id'], 'items': connection([child], 'root-page')}}},
            {'data': {'node': {'id': metadata()['id'], 'items': connection([root])}}}]
        with patch.object(self.m, 'graphql', side_effect=responses):
            result = self.m.scan()
        self.assertEqual(result['items'][0]['action'], 'stage')
        self.assertEqual(result['items'][0]['stageRoot']['taskSlug'], slug)
        child['content']['parent']['id'] = 'wrong-parent'
        self.assertEqual(self.scan([root, child])['items'][1]['action'], 'blocked')
        child['content']['parent'] = None
        self.assertEqual(self.scan([root, child])['items'][1]['action'], 'blocked')

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

    def test_draft_stage_links_parent_item_without_issue_conversion(self):
        root, stage = item('root', 'DraftIssue'), item('stage', 'DraftIssue')
        slug = self.m.task_slug(metadata()['id'], 'root')
        stage['content']['body'] = f'<!-- pir-maintainer:project-stage:{slug}:implementation -->\nParent item: root'
        stage['fieldValues'] = connection([{'__typename': 'ProjectV2ItemFieldTextValue',
            'id': 'PARENT_VALUE', 'field': {'id': 'PARENT_FIELD', 'name': 'Parent item'}, 'text': 'root'}])
        result = self.scan([stage, root])
        self.assertEqual(result['items'][0]['action'], 'stage')
        self.assertEqual(result['items'][0]['stageRoot']['itemId'], 'root')
        self.assertFalse(result['items'][1]['requiresConversion'])
        self.assertEqual(result['items'][1]['action'], 'new')
        for line in ['', 'Parent item: ROOT', 'Parent item: foreign', 'Parent item: root\nParent item: root']:
            stage['content']['body'] = f'<!-- pir-maintainer:project-stage:{slug}:implementation -->\n{line}'
            self.assertEqual(self.scan([stage, root])['items'][0]['action'], 'blocked')

    def test_draft_parent_text_field_cannot_conflict_with_body_and_item_url(self):
        root, stage = item('root', 'DraftIssue'), item('stage', 'DraftIssue')
        root['fullDatabaseId'] = '286166724'
        slug = self.m.task_slug(metadata()['id'], 'root')
        stage['content']['body'] = f'<!-- pir-maintainer:project-stage:{slug}:review -->\nParent item: root'
        parent = {'__typename': 'ProjectV2ItemFieldTextValue', 'id': 'PARENT_VALUE',
                  'field': {'id': 'PARENT_FIELD', 'name': 'Parent item'}, 'text': 'foreign'}
        stage['fieldValues'] = connection([parent])
        self.assertEqual(self.scan([root, stage])['items'][1]['action'], 'blocked')
        stage['fieldValues'] = connection([])
        self.assertEqual(self.scan([root, stage])['items'][1]['action'], 'blocked')
        stage['fieldValues'] = connection([parent])
        parent['text'] = 'https://github.com/users/Caldis/projects/7?pane=issue&itemId=286166724'
        result = self.scan([root, stage])
        self.assertEqual(result['items'][1]['action'], 'stage')
        self.assertEqual(result['items'][0]['fullDatabaseId'], '286166724')
        self.assertEqual(result['items'][0]['itemURL'], parent['text'])
        self.assertIsNone(result['items'][1]['itemURL'])
        parent['text'] += ' | root'
        self.assertEqual(self.scan([root, stage])['items'][1]['action'], 'stage')
        parent['text'] = parent['text'].replace(' | root', ' | wrong')
        self.assertEqual(self.scan([root, stage])['items'][1]['action'], 'blocked')

    def test_full_field_metadata_and_non_status_values_preserved(self):
        meta, task = metadata(), item()
        meta['fields']['nodes'].extend([
            {'__typename': 'ProjectV2Field', 'id': 'ESTIMATE', 'name': 'Estimate', 'dataType': 'NUMBER'},
            {'__typename': 'ProjectV2SingleSelectField', 'id': 'PRIORITY', 'name': 'Priority',
             'options': [{'id': 'priority-high', 'name': 'High'}]}])
        values = [{'__typename': 'ProjectV2ItemFieldNumberValue', 'id': 'VALUE1', 'number': 3,
                   'field': {'id': 'ESTIMATE', 'name': 'Estimate'}},
                  {'__typename': 'ProjectV2ItemFieldSingleSelectValue', 'id': 'VALUE2',
                   'optionId': 'priority-high', 'name': 'High', 'field': {'id': 'PRIORITY', 'name': 'Priority'}}]
        task['fieldValues'] = connection(values)
        result = self.scan([task], meta=meta)
        self.assertEqual(result['fields'], meta['fields']['nodes'])
        self.assertEqual(result['items'][0]['fieldValues'], values)

    def test_query_bounds_nested_connections_below_github_node_limit(self):
        self.assertIn('items(first: 100', self.m.ITEMS_QUERY)
        self.assertIn('fieldValues(first: 100)', self.m.ITEMS_QUERY)
        for name in ('labels', 'users', 'reviewers', 'pullRequests'):
            self.assertIn(name + '(first: 10)', self.m.ITEMS_QUERY)

    def test_native_field_values_have_field_identity_without_invented_value_id(self):
        task = item()
        native = {'__typename': 'ProjectV2ItemFieldLabelValue',
                  'field': {'id': 'LABELS', 'name': 'Labels'},
                  'labels': connection([{'id': 'LABEL1', 'name': 'bug'}])}
        task['fieldValues'] = connection([native])
        self.assertEqual(self.scan([task])['items'][0]['fieldValues'], [native])
        native['labels'] = connection([], 'more-labels')
        with self.assertRaises(self.m.ScanError):
            self.scan([task])
        native['__typename'] = 'FutureProjectValue'
        native['labels'] = connection([])
        with self.assertRaises(self.m.ScanError):
            self.scan([task])

    def test_truncated_or_inaccessible_field_values_fail_closed(self):
        task = item()
        for values in [connection([], 'values-page-2'), connection([None]), None]:
            task['fieldValues'] = values
            with self.subTest(values=values), self.assertRaises(self.m.ScanError):
                self.scan([task])
        del task['fieldValues']
        with self.assertRaises(self.m.ScanError):
            self.scan([task])

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

    def test_nonzero_graphql_error_is_not_misreported_as_auth_failure(self):
        response = subprocess.CompletedProcess([], 1, json.dumps({'errors': [{'type': 'MAX_NODE_LIMIT_EXCEEDED', 'message': 'secret-token'}]}), 'secret-token')
        with patch.object(self.m.subprocess, 'run', return_value=response):
            with self.assertRaises(self.m.ScanError) as failure:
                self.m.graphql('query {}', {})
        self.assertIn('GraphQL', str(failure.exception))
        self.assertNotIn('authentication', str(failure.exception))
        self.assertNotIn('secret-token', str(failure.exception))

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
