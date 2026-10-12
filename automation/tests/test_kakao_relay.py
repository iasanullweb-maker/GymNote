"""Cloud mailbox relay checks with a synthetic Supabase function (no network, Kakao or model calls)."""
import io
import json
import os
import sqlite3
import threading
import time
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from http.server import ThreadingHTTPServer
from unittest.mock import patch

from automation.ingress.kakao import Kakao
from automation.ingress.kakao_relay import Relay, validate_relay_config
from automation.check import inspect
from automation.service import run
from automation.store import Store
from automation.tests import test_automation as baseline

URL = 'https://example.supabase.co/functions/v1/kakao-skill'
TOKEN = 'relay-' + 'r' * 40


class FakeCloud:
    """Mirrors supabase/migrations/202610120001_kakao_relay.sql lease/ack/publish semantics."""

    def __init__(self, token=TOKEN):
        self.token, self.items, self.snapshots, self.requests = token, {}, {}, []
        self.fail_ack = False
        self.lock = threading.Lock()

    def add(self, utterance, user='user-1', bot='bot-1'):
        item = str(uuid.uuid4())
        self.items[item] = {'bot': bot, 'user': user, 'utterance': utterance, 'claim': None,
                            'received': datetime.now(timezone.utc).isoformat(), 'processed': False,
                            'task': None, 'reply': None}
        time.sleep(.001)
        return item

    def expire(self, item):
        self.items[item]['claim'] = None

    def urlopen(self, request, timeout):
        with self.lock:
            assert request.get_method() == 'POST'
            assert request.full_url.startswith(URL + '/relay/')
            assert request.get_header('X-relay-token') == self.token
            assert request.get_header('Content-type') == 'application/json'
            assert timeout <= 30
            action = request.full_url.rsplit('/', 1)[1]
            body = json.loads(request.data)
            self.requests.append((action, body))
            value = getattr(self, action)(body)
            return io.BytesIO(json.dumps(value).encode())

    def claim(self, body):
        picked = []
        for item, row in sorted(self.items.items(), key=lambda pair: pair[1]['received']):
            if not row['processed'] and row['claim'] is None and len(picked) < body['limit']:
                row['claim'] = str(uuid.uuid4())
                picked.append({'id': item, 'claim': row['claim'], 'bot': row['bot'], 'user': row['user'],
                               'utterance': row['utterance'], 'received': row['received']})
        return {'items': list(reversed(picked))}  # Order is not guaranteed by UPDATE ... RETURNING.

    def ack(self, body):
        if self.fail_ack:
            raise OSError('synthetic network failure')
        row = self.items[body['id']]
        if row['claim'] != body['claim']:
            return {'ok': False}
        if not row['processed']:
            row.update(processed=True, utterance=None, task=body['taskId'], reply=body['reply'])
        return {'ok': True}

    def publish(self, body):
        for task in body['tasks']:
            current = self.snapshots.get(task['id'])
            if current is None or current['actor'] == task['actor']:
                self.snapshots[task['id']] = task
        return {'count': len(body['tasks'])}


class RelayTests(unittest.TestCase):
    setUp = baseline.Tests.setUp
    tearDown = baseline.Tests.tearDown
    repository = baseline.Tests.repository
    runner = baseline.Tests.runner

    def config(self, **overrides):
        config = {'defaultProject': 'gymnote', 'kakaoBotIds': ['bot-1'], 'kakaoUserKeys': ['user-1'],
                  'executionEnabled': True, 'kakaoRelayEnabled': True, 'kakaoRelayUrl': URL}
        config.update(overrides)
        return config

    def relay(self, cloud=None, **overrides):
        self.cloud = cloud or FakeCloud()
        return Relay(Kakao(self.store, self.config(**overrides)), self.store, URL, TOKEN, urlopen=self.cloud.urlopen)

    def acks(self):
        return [body for action, body in self.cloud.requests if action == 'ack']

    def test_offline_memo_is_pulled_acknowledged_and_published(self):
        relay = self.relay()
        item = self.cloud.add('메모 PC 꺼진 동안 남긴 아이디어')
        self.assertEqual(relay.step(), 1)
        task = self.store.list()[0]
        self.assertEqual((task['source'], task['status'], task['text']), ('kakao', 'memo', 'PC 꺼진 동안 남긴 아이디어'))
        self.assertIsNone(self.store.claim(), 'A memo never runs')
        row = self.cloud.items[item]
        self.assertTrue(row['processed'])
        self.assertIsNone(row['utterance'], 'Cloud copy of the idea is dropped after acknowledgement')
        self.assertEqual(row['task'], task['id'])
        self.assertIn('아이디어 저장', row['reply'])
        snapshot = self.cloud.snapshots[task['id']]
        self.assertEqual(snapshot['actor'], task['actor'])
        self.assertTrue(snapshot['statusText'].startswith(task['id']))
        self.assertNotIn('아이디어', snapshot['statusText'], 'Status text never carries the idea')
        self.assertEqual(relay.step(), 0)

    def test_lease_replay_never_duplicates_memo_or_run(self):
        relay = self.relay()
        memo = self.cloud.add('같은 메모')
        run = self.cloud.add('실행 key-1 문서에 한 줄 추가')
        self.cloud.fail_ack = True
        with self.assertRaises(OSError):
            relay.pull()
        self.assertEqual(len(self.store.list()), 1, 'Stopped at the first failed acknowledgement')
        self.cloud.fail_ack = False
        self.cloud.expire(memo)
        self.cloud.expire(run)
        relay.pull()
        tasks = self.store.list()
        self.assertEqual(sorted(task['intent'] for task in tasks), ['execute', 'memo'])
        self.assertTrue(all(row['processed'] for row in self.cloud.items.values()))
        # A later identical memo is a new idea, not a 60-second merge of mailbox items.
        self.cloud.add('같은 메모')
        relay.pull()
        self.assertEqual(sum(task['intent'] == 'memo' for task in self.store.list()), 2)
        # Same run key from a new message keeps pointing at the first task.
        self.cloud.add('실행 key-1 문서에 한 줄 추가')
        relay.pull()
        self.assertEqual(sum(task['intent'] == 'execute' for task in self.store.list()), 1)
        self.cloud.add('실행 key-1 다른 내용')
        relay.pull()
        self.assertIn('입력 형식이나 요청키', self.acks()[-1]['reply'])
        self.assertIsNone(self.acks()[-1]['taskId'])

    def test_stale_lease_ack_is_reported_and_replay_is_idempotent(self):
        relay = self.relay()
        item = self.cloud.add('메모 경쟁')
        original = self.cloud.urlopen

        def expire_before_ack(request, timeout):
            if request.full_url.endswith('/ack'):
                self.cloud.expire(item)
                self.cloud.claim({'limit': 1})  # Another pull took the item after the lease expired.
            return original(request, timeout)
        relay.urlopen = expire_before_ack
        relay.pull()
        self.assertFalse(self.cloud.items[item]['processed'])
        relay.urlopen = original
        self.cloud.expire(item)
        relay.pull()
        self.assertTrue(self.cloud.items[item]['processed'])
        self.assertEqual(len(self.store.list()), 1)

    def test_run_respects_local_execution_switch(self):
        relay = self.relay(executionEnabled=False)
        self.cloud.add('실행 smoke-1 문서에 연결 확인 문장 추가')
        relay.pull()
        self.assertEqual(self.store.list(), [])
        self.assertIn('자동 작업 실행이 꺼져', self.acks()[0]['reply'])
        relay = self.relay(executionEnabled=True)
        self.cloud.add('실행 smoke-1 문서에 연결 확인 문장 추가')
        relay.pull()
        task = self.store.list()[0]
        self.assertEqual(task['status'], 'queued')
        self.assertEqual(self.acks()[0]['taskId'], task['id'])

    def test_cancel_and_retry_through_mailbox_update_snapshots(self):
        relay = self.relay()
        self.cloud.add('실행 key-2 작업')
        relay.step()
        task = self.store.list()[0]
        self.cloud.add('중지 ' + task['id'])
        relay.step()
        self.assertEqual(self.store.get(task['id'])['status'], 'cancelled')
        self.assertIn('중지 완료', self.cloud.snapshots[task['id']]['statusText'])
        self.cloud.add('재시도 again-1 ' + task['id'])
        relay.step()
        self.assertEqual(self.store.get(task['id'])['status'], 'queued')
        self.assertIn('실행 대기', self.cloud.snapshots[task['id']]['statusText'])
        self.cloud.add('중지 other-users-task')
        relay.step()
        self.assertIn('찾을 수 없습니다', self.acks()[-1]['reply'])

    def test_allowlist_mismatch_and_malformed_items_are_acknowledged_without_tasks(self):
        relay = self.relay()
        self.cloud.add('메모 hi', user='user-x')
        self.cloud.add('메모 hi', bot='bot-x')
        self.cloud.add('x' * 8100)
        relay.pull()
        self.assertEqual(self.store.list(), [])
        replies = [body['reply'] for body in self.acks()]
        self.assertIn('허용 목록', replies[0])
        self.assertIn('허용 목록', replies[1])
        self.assertIn('입력 형식', replies[2])
        self.assertTrue(all(body['taskId'] is None for body in self.acks()))

    def test_storage_error_leaves_item_leased_for_retry(self):
        relay = self.relay()
        item = self.cloud.add('메모 잠긴 DB')
        with patch.object(Store, 'create', side_effect=sqlite3.OperationalError('locked')):
            with self.assertRaises(sqlite3.OperationalError):
                relay.pull()
        self.assertEqual(self.acks(), [])
        self.assertFalse(self.cloud.items[item]['processed'])
        self.cloud.expire(item)
        relay.pull()
        self.assertTrue(self.cloud.items[item]['processed'])

    def test_unexpected_cloud_shapes_process_nothing(self):
        relay = self.relay()
        for value in ({'items': {}}, {'items': [{'id': 'not-uuid', 'claim': str(uuid.uuid4()), 'received': 'x'}]},
                      {'items': [{}] * 11}, []):
            relay.urlopen = lambda request, timeout, value=value: io.BytesIO(json.dumps(value).encode())
            with self.assertRaises(ValueError):
                relay.pull()
        self.assertEqual(self.store.list(), [])

    def test_publish_uses_watermark_with_overlap_and_only_kakao_tasks(self):
        relay = self.relay()
        self.store.create('web', 'w1', 'admin', 'gymnote', '관리자 메모', 'memo')
        self.cloud.add('메모 첫째')
        relay.step()
        self.assertEqual(len(self.cloud.snapshots), 1, 'Admin/web tasks are never published')
        first = self.store.list()[0]
        old = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
        with self.store.connect() as db:
            db.execute('UPDATE tasks SET updated=? WHERE id=?', (old, first['id']))
        self.store.setting('kakao_relay_published', old)
        self.cloud.requests.clear()
        self.assertEqual(relay.publish(), 1, 'Overlap re-sends rows at the watermark')
        self.store.setting('kakao_relay_published', datetime.now(timezone.utc).isoformat())
        self.cloud.requests.clear()
        self.assertEqual(relay.publish(), 0)
        self.assertEqual(self.cloud.requests, [])

    def test_config_validation_is_fail_closed(self):
        validate_relay_config({'kakaoRelayEnabled': False})
        validate_relay_config(self.config(), TOKEN)
        bad = [{'kakaoRelayEnabled': 'true'}, {'kakaoRelayUrl': 'http://example.supabase.co/functions/v1/kakao-skill'},
               {'kakaoRelayUrl': URL + '?x=1'}, {'kakaoRelayUrl': 'https://example.com/other'},
               {'kakaoRelayPollSeconds': 1}, {'kakaoRelayPollSeconds': 5.0}, {'kakaoUserKeys': []},
               {'kakaoBotIds': []}, {'kakaoUserKeys': [' spaced']}]
        for override in bad:
            with self.assertRaises(ValueError, msg=override):
                validate_relay_config(self.config(**override))
        for token in ('', 'short', 'x' * 129, 'bad token with spaces ' + 'x' * 20):
            with self.assertRaises(ValueError):
                validate_relay_config(self.config(), token)
        with self.assertRaises(ValueError):
            Relay(Kakao(self.store, self.config()), self.store, URL, 'short')

    def test_preflight_reports_relay_without_printing_token(self):
        root = self.repository()
        config = {'projects': {'gymnote': {'path': str(root), 'branch': 'main'}}, 'defaultProject': 'gymnote',
                  **self.config(executionEnabled=False)}
        environment = {'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'admin-' + 'a' * 32, 'AUTOMATION_RELAY_TOKEN': TOKEN}
        result = inspect(config, environment)
        relay_check = next(check for check in result['checks'] if check['name'] == 'kakao-relay')
        self.assertTrue(relay_check['ok'])
        self.assertNotIn(TOKEN, json.dumps(result))
        environment['AUTOMATION_RELAY_TOKEN'] = 'short'
        self.assertFalse(next(check for check in inspect(config, environment)['checks'] if check['name'] == 'kakao-relay')['ok'])

    def test_service_runs_relay_thread_and_strips_token_from_agents(self):
        cloud = FakeCloud()
        item = cloud.add('메모 서비스 경유')
        config = {'runtimeDir': str(self.root / 'runtime'), 'projects': {'gymnote': {}}, 'defaultProject': 'gymnote',
                  'port': 0, 'telegramEnabled': False, 'kakaoEnabled': False, **self.config(executionEnabled=False),
                  'kakaoRelayPollSeconds': 2}
        case = self

        class ProbeAdmin(ThreadingHTTPServer):
            def serve_forever(inner, **kwargs):
                deadline = time.time() + 10
                while not cloud.items[item]['processed'] and time.time() < deadline:
                    time.sleep(.05)
                case.assertTrue(cloud.items[item]['processed'])
                raise KeyboardInterrupt
        credentials = {'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'admin-' + 'a' * 32, 'AUTOMATION_RELAY_TOKEN': TOKEN}
        with patch.dict(os.environ, credentials), patch('automation.service.ThreadingHTTPServer', ProbeAdmin), \
                patch('automation.ingress.kakao_relay.urllib.request.urlopen', cloud.urlopen):
            run(config)
        tasks = Store(self.root / 'runtime' / 'ideas.sqlite3').list()
        self.assertEqual([(task['source'], task['status']) for task in tasks], [('kakao', 'memo')])
        with patch.dict(os.environ, {'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'admin-' + 'a' * 32, 'AUTOMATION_RELAY_TOKEN': 'short'}):
            with self.assertRaises(ValueError):
                run(config)
        runner_source = (baseline.Path(__file__).resolve().parents[1] / 'worker' / 'runner.py').read_text(encoding='utf-8')
        self.assertIn("'AUTOMATION_RELAY_TOKEN'", runner_source, 'Agent child environment must not inherit the relay token')


if __name__ == '__main__':
    unittest.main()
