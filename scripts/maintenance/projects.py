#!/usr/bin/env python3
"""Read-only, complete snapshot of Caldis's personal Pir Project (number 7)."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

# Load from this checkout without depending on the caller's working directory or PYTHONPATH.
_auth_spec = importlib.util.spec_from_file_location('pir_github_app', Path(__file__).with_name('github_app.py'))
_auth = importlib.util.module_from_spec(_auth_spec)
_auth_spec.loader.exec_module(_auth)


def app_client():
    return _auth.client()


OWNER = 'Caldis'
NUMBER = 7
REPO = 'Caldis/Pir'
PROJECT_URL = 'https://github.com/users/Caldis/projects/7'
STAGE_MARKER = re.compile(r'<!--\s*pir-maintainer:project-stage:([^\s:]+):([^\s>]+)\s*-->')
FIELDS = '''fields(first: 100, after: $cursor) {
  nodes {
    __typename
    ... on ProjectV2Field { id name dataType }
    ... on ProjectV2IterationField { id name dataType configuration { duration startDay
      iterations { id title startDate duration } completedIterations { id title startDate duration }
    } }
    ... on ProjectV2SingleSelectField { id name dataType options { id name } }
    ... on ProjectV2MultiSelectField { id name dataType multiSelectOptions { id name } }
  }
  pageInfo { hasNextPage endCursor }
}'''
METADATA_QUERY = '''query($cursor: String) {
  user(login: "Caldis") { projectV2(number: 7) {
    id number title url closed
    ''' + FIELDS + '''
  } }
}'''
FIELDS_QUERY = '''query($id: ID!, $cursor: String) {
  node(id: $id) { ... on ProjectV2 { id ''' + FIELDS + ''' } }
}'''
# Keep field IDs and value types so custom fields can be maintained without fixed IDs.
FIELD_CONFIG = """fragment FieldConfig on ProjectV2FieldConfiguration {
  ... on ProjectV2Field { id name dataType }
  ... on ProjectV2SingleSelectField { id name dataType }
  ... on ProjectV2IterationField { id name dataType }
  ... on ProjectV2MultiSelectField { id name dataType }
}"""
# Bound nested connections: 100 items × 100 values × four 10-node lists stays
# below GitHub's 500,000-node query limit. Truncation still discards the snapshot.
VALUE_TYPES = {
    'Date': 'date', 'Number': 'number', 'Text': 'text',
    'MultiSelect': 'options { id name } value',
    'SingleSelect': 'optionId name', 'Iteration': 'iterationId title startDate duration',
    'Milestone': 'milestone { id title dueOn }',
    'Repository': 'repository { id nameWithOwner }',
    'Label': 'labels(first: 10) { nodes { id name } pageInfo { hasNextPage endCursor } }',
    'User': 'users(first: 10) { nodes { id login } pageInfo { hasNextPage endCursor } }',
    'Reviewer': 'reviewers(first: 10) { nodes { __typename ... on User { id login } ... on Team { id name } } pageInfo { hasNextPage endCursor } }',
    'PullRequest': 'pullRequests(first: 10) { nodes { id url title state } pageInfo { hasNextPage endCursor } }',
}
VALUE_NODES = {'Date', 'Iteration', 'MultiSelect', 'Number', 'SingleSelect', 'Text'}
FIELD_VALUES = 'fieldValues(first: 100) { nodes { __typename ' + ' '.join(
    '... on ProjectV2ItemField' + kind + 'Value { ' + ('id ' if kind in VALUE_NODES else '') + 'field { ...FieldConfig } ' + selection + ' }'
    for kind, selection in VALUE_TYPES.items()) + ' } pageInfo { hasNextPage endCursor } }'
ITEMS_QUERY = '''query($id: ID!, $cursor: String) {
  node(id: $id) { ... on ProjectV2 {
    id items(first: 100, after: $cursor) {
      nodes {
        id isArchived fullDatabaseId
        ''' + FIELD_VALUES + '''
        fieldValueByName(name: "Status") {
          __typename
          ... on ProjectV2ItemFieldSingleSelectValue {
            optionId name field { ... on ProjectV2SingleSelectField { id } }
          }
        }
        content {
          __typename
          ... on Issue {
            id number title body url state repository { nameWithOwner }
            parent { id number url repository { nameWithOwner } }
          }
          ... on PullRequest { id number title body url state repository { nameWithOwner } }
          ... on DraftIssue { id title body }
        }
      }
      pageInfo { hasNextPage endCursor }
    }
  } }
}''' + '\n' + FIELD_CONFIG


class ScanError(RuntimeError):
    """A complete, safe snapshot was unavailable; callers must not triage partial data."""


def graphql(query, variables):
    # Never return gh stderr or GraphQL error text: either can contain private data.
    payload = {'query': query, 'variables': variables}
    try:
        result = subprocess.run(['gh', 'api', 'graphql', '--input', '-'],
                                input=json.dumps(payload), text=True,
                                capture_output=True, timeout=90, env=app_client().environment())
    except _auth.AuthError:
        raise ScanError('GitHub App Project access unavailable; no owner credential fallback') from None
    except subprocess.TimeoutExpired:
        raise ScanError('GitHub Project read timed out after 90 seconds') from None
    except OSError:
        raise ScanError('Cannot execute gh for GitHub Project read') from None
    if result.returncode:
        try:
            failed = json.loads(result.stdout)
        except (ValueError, TypeError):
            failed = None
        if isinstance(failed, dict) and failed.get('errors'):
            raise ScanError('GitHub Project GraphQL read failed; check query and permissions; snapshot discarded')
        raise ScanError('GitHub App Project read failed; prove access to Caldis Project #7; no owner credential fallback')
    try:
        response = json.loads(result.stdout)
    except (ValueError, TypeError):
        raise ScanError('GitHub Project returned invalid JSON') from None
    if not isinstance(response, dict) or response.get('errors') or not isinstance(response.get('data'), dict):
        raise ScanError('GitHub Project returned errors or inaccessible data; snapshot discarded')
    return response


def required(value, key, kind):
    if not isinstance(value, dict) or key not in value or not isinstance(value[key], kind):
        raise ScanError('GitHub Project snapshot is missing required field: ' + key)
    return value[key]


def page(connection):
    nodes = required(connection, 'nodes', list)
    info = required(connection, 'pageInfo', dict)
    more = required(info, 'hasNextPage', bool)
    if 'endCursor' not in info:
        raise ScanError('GitHub Project pagination is missing endCursor')
    cursor = info['endCursor']
    if more and (not isinstance(cursor, str) or not cursor):
        raise ScanError('GitHub Project pagination has no continuation cursor')
    if any(not isinstance(node, dict) for node in nodes):
        raise ScanError('GitHub Project page contains inaccessible nodes')
    return nodes, cursor if more else None


def node_data(response, project_id):
    data = required(response, 'data', dict)
    node = required(data, 'node', dict)
    if required(node, 'id', str) != project_id:
        raise ScanError('GitHub Project identity changed during pagination')
    return node


def task_slug(project_id, item_id):
    # Node IDs are case-sensitive. JSON separates both values without ambiguous joins.
    identity = json.dumps([project_id, item_id], separators=(',', ':')).encode()
    return 'project-' + hashlib.sha256(identity).hexdigest()[:56]


def parse_stage_marker(body):
    matches = list(STAGE_MARKER.finditer(body or ''))
    if not matches:
        return None
    # Multiple stage claims are ambiguous and must never be silently swallowed.
    return {'taskSlug': matches[0][1], 'stage': matches[0][2], 'ambiguous': len(matches) != 1}


def stage_linkage(marker, parent, roots):
    root = roots.get(marker['taskSlug'])
    content = root.get('content') if root else None
    verified = (not marker.get('ambiguous') and isinstance(parent, dict)
        and isinstance(content, dict) and content.get('__typename') == 'Issue'
        and not root.get('stageMarker')
        and content.get('repository', {}).get('nameWithOwner', '').casefold() == REPO.casefold()
        and isinstance(content.get('id'), str) and isinstance(content.get('url'), str)
        and parent.get('id', parent.get('node_id')) == content['id']
        and parent.get('url') == content['url'])
    return {'action': 'stage' if verified else 'blocked',
            'skipReason': 'stage-child' if verified else 'stage-linkage-unverified',
            'stageRoot': {'taskSlug': root['taskSlug'], 'itemId': root['itemId'],
                          'issueNodeId': content['id'], 'issueURL': content['url']} if verified else None}


def draft_stage_linkage(marker, body, roots, values):
    parents = re.findall(r'^Parent item: ([^\s]+)[ \t]*$', body, flags=re.MULTILINE)
    root = roots.get(marker['taskSlug'])
    content = root.get('content') if root else None
    linked = [value.get('text') for value in values
              if value.get('__typename') == 'ProjectV2ItemFieldTextValue'
              and value.get('field', {}).get('name') == 'Parent item']
    valid_links = {root['itemId'], root.get('itemURL')} if root else set()
    valid_links.discard(None)
    if root and root.get('itemURL'):
        valid_links.add(root['itemURL'] + ' | ' + root['itemId'])
    verified = (not marker.get('ambiguous') and len(parents) == 1 and root is not None
        and len(linked) == 1 and all(link in valid_links for link in linked)
        and parents[0] == root['itemId'] and not root.get('stageMarker')
        and isinstance(content, dict) and (content.get('__typename') == 'DraftIssue'
            or (content.get('__typename') in ('Issue', 'PullRequest')
                and content.get('repository', {}).get('nameWithOwner', '').casefold() == REPO.casefold())))
    return {'action': 'stage' if verified else 'blocked',
            'skipReason': 'stage-child' if verified else 'stage-linkage-unverified',
            'stageRoot': {'taskSlug': root['taskSlug'], 'itemId': root['itemId']} if verified else None}


def complete_connections(value):
    if isinstance(value, dict):
        if 'pageInfo' in value:
            _, cursor = page(value)
            if cursor is not None:
                raise ScanError('GitHub Project field values exceed one page; snapshot discarded')
        for nested in value.values():
            complete_connections(nested)
    elif isinstance(value, list):
        for nested in value:
            complete_connections(nested)


def normalize(item, project, status_field, pending):
    identity = required(item, 'id', str)
    archived = required(item, 'isArchived', bool)
    if 'content' not in item or 'fieldValueByName' not in item:
        raise ScanError('GitHub Project item is missing content or Status selection')
    values = required(item, 'fieldValues', dict)
    complete_connections(values)
    nodes, cursor = page(values)
    if cursor is not None:
        raise ScanError('GitHub Project field values exceed one page; snapshot discarded')
    for value in nodes:
        required(value, '__typename', str)
        kind = value['__typename']
        if kind not in {'ProjectV2ItemField' + name + 'Value' for name in VALUE_TYPES}:
            raise ScanError('GitHub Project returned an unsupported field value type; snapshot discarded')
        if kind in {'ProjectV2ItemField' + name + 'Value' for name in VALUE_NODES}:
            required(value, 'id', str)
        required(required(value, 'field', dict), 'id', str)
    slug = task_slug(project['id'], identity)
    database_id = item.get('fullDatabaseId')
    if database_id is not None and (isinstance(database_id, bool) or not str(database_id).isdigit()):
        raise ScanError('GitHub Project item has an invalid database identity')
    result = {'itemId': identity, 'taskSlug': slug, 'isArchived': archived,
              'fullDatabaseId': database_id,
              'itemURL': PROJECT_URL + '?pane=issue&itemId=' + str(database_id) if database_id is not None else None,
              'content': item['content'], 'fieldValues': nodes, 'issueAlias': None, 'parent': None,
              'stageMarker': None, 'requiresConversion': False, 'status': None,
              'action': 'new', 'skipReason': None, 'previous': pending.get(slug)}
    status = item['fieldValueByName']
    reason = None
    if status is not None:
        required(status, 'optionId', str)
        field = required(status, 'field', dict)
        if required(field, 'id', str) != status_field['id']:
            raise ScanError('GitHub Project item Status field does not match metadata')
        option = next((x for x in status_field['options'] if x['id'] == status['optionId']), None)
        if option is None:
            reason = 'unknown-status-option'
        else:
            result['status'] = option
            name = option['name'].casefold()
            if name == 'done': reason = 'done'
            elif name == 'blocked': reason = 'blocked-status'
            elif name not in ('todo', 'to do', 'backlog', 'ready', 'in progress'):
                reason = 'unmapped-status-name'
    else:
        reason = 'missing-status-selection'
    content = item['content']
    if content is None:
        reason = 'inaccessible-or-deleted-content'
    else:
        kind = required(content, '__typename', str)
        for field_name in ('id', 'title', 'body'):
            required(content, field_name, str)
        marker = parse_stage_marker(content['body'])
        result['stageMarker'] = marker
        if kind in ('Issue', 'PullRequest'):
            repository = required(required(content, 'repository', dict), 'nameWithOwner', str)
            required(content, 'url', str)
            number = required(content, 'number', int)
            state = required(content, 'state', str)
            if kind == 'Issue':
                if 'parent' not in content:
                    raise ScanError('GitHub Project Issue is missing parent relationship')
                result['parent'] = content['parent']
                if content['parent'] is not None:
                    required(content['parent'], 'id', str)
                    required(content['parent'], 'url', str)
                    parent_repo = content['parent'].get('repository')
                    if parent_repo is not None and required(parent_repo, 'nameWithOwner', str).casefold() != REPO.casefold():
                        reason = 'foreign-parent-repository'
                result['issueAlias'] = repository + '#' + str(number)
            if state != 'OPEN': reason = 'closed-content'
            if kind == 'PullRequest': reason = 'pull-request'
            if repository.casefold() != REPO.casefold(): reason = 'foreign-repository'
        elif kind == 'DraftIssue':
            result['requiresConversion'] = False
        else:
            reason = 'unsupported-content-type'
        if marker: reason = 'stage-linkage-unverified'
    if archived: reason = 'archived'
    if project['closed']: reason = 'closed-project'
    result['skipReason'] = reason
    if reason:
        result['action'] = 'blocked' if reason in ('blocked-status', 'unknown-status-option',
            'unmapped-status-name', 'missing-status-selection', 'foreign-parent-repository', 'stage-linkage-unverified') else 'skip'
    previous = pending.get(slug)
    # Local recovery survives remote completion/deletion; it is not permission to restart work.
    if previous:
        result['action'] = 'unchanged' if previous.get('phase') == 'verified' else 'resume'
    return result


def scan(*, pending=None):
    pending = {} if pending is None else pending
    data = required(graphql(METADATA_QUERY, {}), 'data', dict)
    user = required(data, 'user', dict)
    remote = required(user, 'projectV2', dict)
    project = {key: required(remote, key, kind) for key, kind in
               (('id', str), ('number', int), ('title', str), ('url', str), ('closed', bool))}
    if project['url'] != PROJECT_URL or project['number'] != NUMBER:
        raise ScanError('Unexpected GitHub Project identity')
    fields, cursor = page(required(remote, 'fields', dict))
    seen = set()
    while cursor is not None:
        if cursor in seen: raise ScanError('GitHub Project fields pagination repeated a cursor')
        seen.add(cursor)
        node = node_data(graphql(FIELDS_QUERY, {'id': project['id'], 'cursor': cursor}), project['id'])
        more, cursor = page(required(node, 'fields', dict))
        fields.extend(more)
    for field in fields:
        required(field, '__typename', str)
        required(field, 'id', str)
        required(field, 'name', str)
    statuses = [field for field in fields if field.get('name') == 'Status']
    if len(statuses) != 1 or statuses[0].get('__typename') != 'ProjectV2SingleSelectField':
        raise ScanError('GitHub Project requires one single-select Status field')
    status_field = statuses[0]
    required(status_field, 'id', str)
    options = required(status_field, 'options', list)
    if not options:
        raise ScanError('GitHub Project Status has no options')
    for option in options:
        required(option, 'id', str)
        required(option, 'name', str)
    if len({x['id'] for x in options}) != len(options):
        raise ScanError('GitHub Project Status has duplicate option identities')
    items, cursor, seen, identities = [], None, set(), set()
    while True:
        node = node_data(graphql(ITEMS_QUERY, {'id': project['id'], 'cursor': cursor}), project['id'])
        more, cursor = page(required(node, 'items', dict))
        for item in more:
            normalized = normalize(item, project, status_field, pending)
            if normalized['itemId'] in identities:
                raise ScanError('GitHub Project items changed across pages; retry complete snapshot')
            identities.add(normalized['itemId'])
            items.append(normalized)
        if cursor is None: break
        if cursor in seen: raise ScanError('GitHub Project items pagination repeated a cursor')
        seen.add(cursor)
    by_slug = {item['taskSlug']: item for item in items}
    # Resolve after all pages: a child may precede its root in Project order.
    for item in items:
        if item['stageMarker']:
            if item['content']['__typename'] == 'DraftIssue':
                item.update(draft_stage_linkage(item['stageMarker'], item['content']['body'], by_slug, item['fieldValues']))
            else:
                item.update(stage_linkage(item['stageMarker'], item['parent'], by_slug))
    resumes = [{'taskSlug': slug, 'previous': record, 'presentInProject': slug in by_slug,
                'itemId': by_slug.get(slug, {}).get('itemId')}
               for slug, record in pending.items() if record.get('phase') != 'verified']
    return {'schema': 1, 'repository': REPO, 'project': project, 'fields': fields, 'statusField': status_field,
            'items': items, 'resumeTasks': resumes, 'recoveryFirst': True}


def read_pending(directory):
    # Reuse Store's schema/repository checks without opening a transaction or creating files.
    spec = importlib.util.spec_from_file_location('pir_project_cycle', Path(__file__).with_name('cycle.py'))
    cycle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cycle)
    state = cycle.Store(directory).read()
    tasks = state.get('tasks', {})
    if not isinstance(tasks, dict) or any(not isinstance(record, dict) for record in tasks.values()):
        raise ScanError('Invalid maintenance task state; preserve and inspect state.json')
    return tasks


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, default=Path.home() / '.config/pir/maintenance',
                        help='Read existing cycle.py Store checkpoints without modifying them')
    args = parser.parse_args(argv)
    try:
        result = scan(pending=read_pending(args.state_dir))
    except (ScanError, ValueError, OSError):
        # Only our fixed diagnostic text is safe to expose; raw state/API exceptions are not.
        error = sys.exc_info()[1]
        message = str(error) if isinstance(error, ScanError) else 'Cannot read maintenance state; preserve state.json and inspect locally'
        print('Project scan failed: ' + message, file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
