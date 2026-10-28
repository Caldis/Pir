#!/usr/bin/env python3
"""Send bounded, deduplicated Pir milestones to the owner's fixed Telegram chat."""
import argparse
import hashlib
import importlib.util
import json
import re
import time
from pathlib import Path
import urllib.error
import urllib.request

_spec = importlib.util.spec_from_file_location('pir_maintenance_cycle', Path(__file__).with_name('cycle.py'))
_cycle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cycle)
Store, Busy = _cycle.Store, _cycle.Busy
CONFIG = Path.home() / '.config/codex/telegram/config.json'
EVENTS = {'received': '接到 issue', 'started': '开始执行', 'progress': '阶段进展',
          'blocked': '遇到阻塞', 'recovered': '恢复执行', 'succeeded': '执行成功',
          'released': '发布完成', 'enabled': '通知已启用'}


def prepare(event):
    event = dict(event)
    if event.get('event') not in EVENTS or not event.get('fact') or not event.get('detail'):
        raise ValueError('Event, stable fact and factual detail are required')
    number = event.get('issue')
    if not isinstance(number, int) or number < 0 or (number == 0 and event['event'] != 'enabled'):
        raise ValueError('A positive issue number is required (zero is reserved for setup)')
    if not event.get('title'):
        raise ValueError('Issue title is required')
    if event.get('version') and not re.fullmatch(r'\d+\.\d+\.\d+', event['version']):
        raise ValueError('Version must be X.Y.Z')
    if event.get('pr') is not None and (not isinstance(event['pr'], int) or event['pr'] <= 0):
        raise ValueError('PR number must be positive')
    identity = [number, event['event'], event['fact']]
    key = hashlib.sha256(json.dumps(identity, ensure_ascii=False).encode()).hexdigest()
    lines = [f'Pir · {EVENTS[event["event"]]}',
             f'#{number} {event["title"][:300]}' if number else event['title'][:300],
             event['detail'][:2500]]
    if number: lines.append(f'https://github.com/Caldis/Pir/issues/{number}')
    if event.get('pr'): lines.append(f'https://github.com/Caldis/Pir/pull/{event["pr"]}')
    if event.get('version'):
        lines += [f'版本：{event["version"]}', f'https://github.com/Caldis/Pir/releases/tag/{event["version"]}']
    return key, '\n'.join(lines)


def configuration(path):
    try:
        if path.stat().st_mode & 0o077 or path.parent.stat().st_mode & 0o077:
            raise ValueError()
        data = json.loads(path.read_text())
        if not re.fullmatch(r'\d+:[A-Za-z0-9_-]+', data['bot_token']): raise ValueError()
        chat = int(data['chat_id'])
        if chat <= 0 or chat != int(data['user_id']): raise ValueError()
        return data['bot_token'], chat
    except (OSError, ValueError, KeyError, TypeError):
        return None


def deliver(config, text):
    credentials = configuration(config)
    if credentials is None: return {'status': 'failed', 'error': 'configuration-unavailable'}
    token, chat = credentials
    payload = {'chat_id': chat, 'text': text.replace(token, '[redacted]'),
               'link_preview_options': {'is_disabled': True}}
    request = urllib.request.Request(f'https://api.telegram.org/bot{token}/sendMessage',
                                     data=json.dumps(payload).encode(),
                                     headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            body = json.loads(response.read(65536))
        if body.get('ok') is not True:
            return {'status': 'failed', 'error': 'telegram-rejected'}
        message_id = body['result']['message_id']
        if not isinstance(message_id, int): raise ValueError()
        return {'status': 'sent', 'message_id': message_id}
    except urllib.error.HTTPError as error:
        # A server error can occur after delivery; only explicit client rejection is safe to retry.
        return {'status': 'failed' if 400 <= error.code < 500 else 'unknown',
                'error': 'telegram-http-' + str(error.code)}
    except Exception:
        # URL errors include the token-bearing URL. Never persist or print exception text.
        return {'status': 'unknown', 'error': 'delivery-result-unknown'}


def public(record):
    return {k: record[k] for k in ('status', 'error', 'message_id', 'attempts') if k in record}


def notify(store, run_id, event, config=CONFIG, *, now=None, dry_run=False):
    now = time.time() if now is None else now
    key, text = prepare(event)
    store.guard(run_id, now=now)
    if dry_run: return {'status': 'dry-run'}
    with store.transaction() as data:
        store.require(data, run_id, now)
        records = data.setdefault('notifications', {})
        previous = records.get(key, {})
        if previous.get('status') == 'sending':
            previous.update(status='unknown', error='interrupted-delivery-result-unknown')
        if previous and (previous['status'] != 'failed' or previous['attempts'] >= 3
                         or previous['runId'] == run_id or now < previous['updatedAt'] + 3600):
            return public(previous)
        record = {'event': event, 'status': 'sending', 'attempts': previous.get('attempts', 0) + 1,
                  'runId': run_id, 'updatedAt': now}
        records[key] = record
    result = deliver(config, text)
    with store.transaction() as data:
        data['notifications'][key].update(result)
    return {**result, 'attempts': record['attempts']}


def retry(store, run_id, config=CONFIG, *, now=None):
    results = []
    for record in store.read().get('notifications', {}).values():
        if record['status'] in ('failed', 'sending'):
            results.append(notify(store, run_id, record['event'], config, now=now))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, default=Path.home() / '.config/pir/maintenance')
    parser.add_argument('--run-id', required=True)
    commands = parser.add_subparsers(dest='command', required=True)
    send = commands.add_parser('send')
    send.add_argument('--issue', required=True, type=int)
    send.add_argument('--title', required=True)
    send.add_argument('--event', required=True, choices=EVENTS)
    send.add_argument('--fact', required=True)
    send.add_argument('--detail', required=True)
    send.add_argument('--pr', type=int)
    send.add_argument('--version')
    send.add_argument('--dry-run', action='store_true')
    commands.add_parser('retry')
    args = parser.parse_args()
    store = Store(args.state_dir)
    if args.command == 'retry': result = retry(store, args.run_id)
    else:
        event = {k: v for k, v in vars(args).items()
                 if k in ('issue', 'title', 'event', 'fact', 'detail', 'pr', 'version') and v is not None}
        result = notify(store, args.run_id, event, dry_run=args.dry_run)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    try: main()
    except Busy:
        print('{"error":"maintenance-lease-required"}')
        raise SystemExit(75)
    except Exception:
        print('{"error":"notification-helper-failed"}')
        raise SystemExit(1)
