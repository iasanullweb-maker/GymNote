import concurrent.futures
import json
import os
import http.client
import socket
import time
from unittest.mock import patch
import threading
import unittest
import urllib.error
import urllib.request

from automation.ingress.kakao import Kakao, SkillServer, handler, validate_config
from automation.service import load_config
from automation.check import inspect
from automation.store import Store
from automation.tests import test_automation as baseline


class KakaoTests(unittest.TestCase):
    setUp = baseline.Tests.setUp
    tearDown = baseline.Tests.tearDown
    repository = baseline.Tests.repository
    runner = baseline.Tests.runner

    def client(self, **overrides):
        config = {'defaultProject': 'gymnote', 'kakaoBotIds': ['bot-1'],
                  'kakaoUserKeys': ['user-1'], 'kakaoDiscoveryEnabled': False,
                  'executionEnabled': True}
        config.update(overrides)
        return Kakao(self.store, config)

    @staticmethod
    def payload(text, user='user-1', bot='bot-1'):
        return {'bot': {'id': bot}, 'userRequest': {
            'user': {'id': user, 'type': 'botUserKey'}, 'utterance': text}}

    def response_text(self, response):
        self.assertEqual(response['version'], '2.0')
        outputs = response['template']['outputs']
        self.assertTrue(outputs)
        return '\n'.join(output['simpleText']['text'] for output in outputs)

    def accept(self, text, **identity):
        return self.client().accept(self.payload(text, **identity))

    def test_memo_persists_without_executing(self):
        text = self.response_text(self.accept('운동 아이디어'))
        task = self.store.list()[0]
        self.assertIn(task['id'], text)
        self.assertEqual(task['source'], 'kakao')
        self.assertEqual(task['status'], 'memo')
        self.assertEqual(task['text'], '운동 아이디어')
        self.assertIsNone(self.store.claim())
        self.response_text(self.accept('/memo 두 번째 아이디어'))
        self.assertEqual(len(Store(self.root / 'data.sqlite3').list()), 2)

    def test_memo_replay_is_concurrent_and_restart_durable(self):
        payload = self.payload('같은 메모')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.client().accept(payload), range(20)))
        reopened = Kakao(Store(self.root / 'data.sqlite3'), {
            'defaultProject': 'gymnote', 'kakaoBotIds': ['bot-1'],
            'kakaoUserKeys': ['user-1'], 'executionEnabled': True})
        reopened.accept(payload)
        self.assertEqual(len(self.store.list()), 1)
        with self.store.connect() as db:
            db.execute('UPDATE kakao_memo_receipts SET expires=0')
        reopened = Kakao(Store(self.root / 'data.sqlite3'), {
            'defaultProject': 'gymnote', 'kakaoBotIds': ['bot-1'],
            'kakaoUserKeys': ['user-1'], 'executionEnabled': True})
        reopened.accept(payload)
        self.assertEqual(len(self.store.list()), 2)

    def test_run_explicit_key_deduplicates_and_rejects_changed_text(self):
        payload = self.payload('/run key_1-Hi 기능 수정')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.client().accept(payload), range(20)))
        self.assertEqual(len(self.store.list()), 1)
        task = self.store.list()[0]
        self.assertEqual(task['text'], '기능 수정')
        self.assertEqual(task['status'], 'queued')
        with self.assertRaises(ValueError):
            self.accept('/run key_1-Hi 다른 기능 수정')
        self.assertEqual(self.store.get(task['id'])['text'], '기능 수정')

    def test_korean_run_alias(self):
        self.response_text(self.accept('실행 request-2 기능 변경'))
        self.assertEqual(self.store.list()[0]['status'], 'queued')
        self.assertEqual(self.store.list()[0]['text'], '기능 변경')

    def test_execution_disabled_never_queues(self):
        for text in ['/run k1 작업', '실행 k2 작업']:
            try:
                self.client(executionEnabled=False).accept(self.payload(text))
            except (PermissionError, ValueError):
                pass
        self.assertEqual(self.store.list(), [])

    def test_invalid_execution_keys_never_queue(self):
        for text in ['/run', '/run key', '/run 키 내용', '/run ../escape 내용',
                     '/run ' + 'x' * 65 + ' 내용', '/run k ' + 'x' * 8001]:
            with self.subTest(text=text[:40]):
                try:
                    self.accept(text)
                except ValueError:
                    pass
        self.assertEqual(self.store.list(), [])

    def test_malformed_payloads_raise_value_error(self):
        values = [None, [], {}, {'bot': []}, {'bot': {'id': 'bot-1'}, 'userRequest': []},
                  {'bot': {'id': 'bot-1'}, 'userRequest': {'user': []}},
                  self.payload(None), self.payload(42), self.payload(''),
                  self.payload('x' * 8001)]
        for value in values:
            with self.subTest(value=str(value)[:80]):
                with self.assertRaises(ValueError):
                    self.client().accept(value)
        self.assertEqual(self.store.list(), [])

    def test_bot_user_and_user_type_all_required(self):
        for payload in [self.payload('hi', bot='other'), self.payload('hi', user='other')]:
            with self.assertRaises(PermissionError):
                self.client().accept(payload)
        payload = self.payload('hi')
        payload['userRequest']['user']['type'] = 'plusfriendUserKey'
        with self.assertRaises((ValueError, PermissionError)):
            self.client().accept(payload)
        self.assertEqual(self.store.list(), [])

    def test_discovery_is_explicit_and_bot_scoped(self):
        for text in ['/whoami', '내정보']:
            with self.assertRaises(PermissionError):
                self.client().accept(self.payload(text, user='new-user'))
            client = self.client(kakaoDiscoveryEnabled=True, kakaoUserKeys=[])
            self.assertIn('new-user', self.response_text(client.accept(self.payload(text, user='new-user'))))
            with self.assertRaises(PermissionError):
                client.accept(self.payload(text, user='new-user', bot='other'))
            with self.assertRaises(PermissionError):
                client.accept(self.payload('메모', user='new-user'))
        self.assertEqual(self.store.list(), [])

    def test_status_lists_only_latest_five_owned_tasks(self):
        for index in range(6):
            self.accept('/memo private-idea-' + str(index))
        tasks = self.store.list()
        other = self.client(kakaoUserKeys=['user-1', 'user-2'])
        other.accept(self.payload('/memo foreign-secret', user='user-2'))
        foreign = self.store.list()[0]
        for command in ['/status', '상태']:
            text = self.response_text(self.accept(command))
            for task in tasks[:5]:
                self.assertIn(task['id'], text)
            self.assertNotIn(tasks[-1]['id'], text)
            self.assertNotIn(foreign['id'], text)
            self.assertNotIn('private-idea-', text)
            self.assertNotIn('foreign-secret', text)

    def test_status_cancel_retry_are_bot_and_user_scoped(self):
        self.accept('/run own-key private idea')
        task = self.store.list()[0]
        client = self.client(kakaoBotIds=['bot-1', 'bot-2'], kakaoUserKeys=['user-1', 'user-2'])
        for identity in [{'user': 'user-2'}, {'bot': 'bot-2'}]:
            for command in ['/status ' + task['id'], '/cancel ' + task['id'], '/retry k1 ' + task['id']]:
                try:
                    text = self.response_text(client.accept(self.payload(command, **identity)))
                    self.assertNotIn('private idea', text)
                    self.assertNotIn('queued', text)
                except PermissionError:
                    pass
                self.assertEqual(self.store.get(task['id'])['status'], 'queued')
        self.accept('/cancel ' + task['id'])
        self.assertEqual(self.store.get(task['id'])['status'], 'cancelled')

    def test_retry_replay_does_not_requeue_later_attempt(self):
        self.accept('/run initial 작업')
        task = self.store.list()[0]
        self.accept('/cancel ' + task['id'])
        retry = '/retry retry-1 ' + task['id']
        self.accept(retry)
        self.assertEqual(self.store.get(task['id'])['status'], 'queued')
        self.store.claim()
        self.store.state(task['id'], 'waiting_user')
        self.client().accept(self.payload(retry))
        self.assertEqual(self.store.get(task['id'])['status'], 'waiting_user')
        self.assertIsNone(self.store.claim())
        self.accept('/retry retry-2 ' + task['id'])
        self.assertEqual(self.store.get(task['id'])['status'], 'queued')

    def test_retry_disabled_does_not_resume(self):
        self.accept('/run initial 작업')
        task = self.store.list()[0]
        self.accept('/cancel ' + task['id'])
        try:
            self.client(executionEnabled=False).accept(self.payload('/retry retry-1 ' + task['id']))
        except (PermissionError, ValueError):
            pass
        self.assertEqual(self.store.get(task['id'])['status'], 'cancelled')

    def test_active_cancel_reports_request_pending_until_runner_stops(self):
        self.accept('/run active change file')
        task = self.store.list()[0]
        self.store.claim()
        text = self.response_text(self.accept('/cancel ' + task['id']))
        self.assertTrue(self.store.get(task['id'])['cancel'])
        self.assertEqual(self.store.get(task['id'])['status'], 'planning')
        self.assertIn('중지 요청', text)
        self.assertIn('확인 대기', text)
        self.assertNotIn('중지 완료', text)
        self.store.state(task['id'], 'cancelled')
        text = self.response_text(self.accept('/status ' + task['id']))
        self.assertIn('중지 완료', text)

    def test_cancelled_memo_cannot_be_retried_into_execution(self):
        self.accept('memo only')
        task = self.store.list()[0]
        self.accept('/cancel ' + task['id'])
        self.accept('/retry memo-retry ' + task['id'])
        self.assertEqual(self.store.get(task['id'])['status'], 'cancelled')
        self.assertIsNone(self.store.claim())

    def test_execution_paused_blocks_new_run_and_retry(self):
        paused = self.client(executionPaused=True)
        paused.accept(self.payload('/run pause-new change file'))
        self.assertEqual(self.store.list(), [])
        self.accept('/run pause-old change file')
        task = self.store.list()[0]
        self.accept('/cancel ' + task['id'])
        paused.accept(self.payload('/retry pause-retry ' + task['id']))
        self.assertEqual(self.store.get(task['id'])['status'], 'cancelled')
        self.assertIsNone(self.store.claim())

    def test_status_filters_results_and_idea_secrets(self):
        self.accept('/run initial idea-secret')
        task = self.store.list()[0]
        self.store.claim()
        result = {'summary': 'summary-secret', 'logs': 'logs-secret', 'token': 'token-secret',
                  'checks': ['check-secret'], 'notRun': ['not-run-secret'],
                  'commit': 'a' * 40, 'integrated': False}
        self.store.state(task['id'], 'waiting_user', result)
        text = self.response_text(self.accept('/status ' + task['id']))
        self.assertIn(task['id'], text)
        for secret in ['idea-secret', 'summary-secret', 'logs-secret', 'token-secret',
                       'check-secret', 'not-run-secret']:
            self.assertNotIn(secret, text)

    def test_fake_runner_completes_and_integrates_kakao_task(self):
        root = self.repository()
        self.accept('/run e2e 파일 수정')
        task = self.store.list()[0]
        self.assertTrue(self.runner(root).once())
        result = self.store.get(task['id'])
        self.assertEqual(result['status'], 'completed')
        self.assertTrue(result['result']['integrated'])
        self.assertEqual((root / 'file.txt').read_text(), 'changed')
        text = self.response_text(self.accept('/status ' + task['id']))
        self.assertIn(task['id'], text)
        self.assertNotIn('done', text)
        self.assertEqual(self.store.notification_due(), [])

    def test_config_validation_is_fail_closed(self):
        valid = {'kakaoEnabled': True, 'kakaoBotIds': ['bot-1'],
                 'kakaoUserKeys': ['user-1'], 'kakaoDiscoveryEnabled': False,
                 'port': 8765, 'kakaoPort': 8766}
        validate_config(valid, 's' * 32)
        validate_config({'kakaoEnabled': False, 'port': 8766})
        validate_config({**valid, 'kakaoDiscoveryEnabled': True, 'kakaoUserKeys': []}, 's' * 32)
        invalid = [{'kakaoBotIds': []}, {'kakaoUserKeys': []},
                   {'kakaoBotIds': [], 'kakaoDiscoveryEnabled': True},
                   {'kakaoEnabled': 'true'}, {'kakaoDiscoveryEnabled': 'false'},
                   {'kakaoPort': True}, {'kakaoPort': 0}, {'kakaoPort': 65536},
                   {'kakaoPort': '8766'}, {'kakaoPort': 8765},
                   {'kakaoBotIds': 'bot-1'}, {'kakaoUserKeys': [42]}]
        for override in invalid:
            with self.subTest(override=override):
                with self.assertRaises(ValueError):
                    validate_config({**valid, **override}, 's' * 32)
        for token in ['', 'short', 's' * 129, '!' * 32]:
            with self.assertRaises(ValueError):
                validate_config(valid, token)

    def test_load_config_and_preflight_are_local_and_secret_free(self):
        root = self.repository()
        config = {'defaultProject': 'gymnote', 'projects': {'gymnote': {'path': str(root)}},
                  'kakaoEnabled': True, 'kakaoBotIds': ['bot-1'], 'kakaoUserKeys': ['user-1'],
                  'kakaoPort': 8766, 'port': 8765, 'executionEnabled': False,
                  'telegramEnabled': False}
        config_path = self.root / 'config.json'
        config_path.write_text(json.dumps(config), encoding='utf-8')
        loaded = load_config(config_path)
        environment = {'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'admin-sentinel-' + 'a' * 32,
                       'KAKAO_SKILL_TOKEN': 'kakao-sentinel-' + 's' * 32}
        with patch('urllib.request.urlopen', side_effect=AssertionError('No network permitted')):
            ready = inspect(loaded, {**os.environ, **environment})
            self.assertTrue(ready['ok'], ready)
            missing = inspect(loaded, {**os.environ, **environment, 'KAKAO_SKILL_TOKEN': ''})
            self.assertFalse(missing['ok'])
            disabled = inspect({**loaded, 'kakaoEnabled': False},
                               {**os.environ, **environment, 'KAKAO_SKILL_TOKEN': ''})
            self.assertTrue(disabled['ok'], disabled)
        output = json.dumps([ready, missing, disabled])
        for secret in environment.values():
            self.assertNotIn(secret, output)
        for override in [{'kakaoPort': True}, {'kakaoDiscoveryEnabled': 'true'}, {'kakaoPort': 8765}]:
            config_path.write_text(json.dumps({**config, **override}), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_config(config_path)

    def test_duplicate_auth_header_is_rejected(self):
        token = 's' * 32
        server = SkillServer(('127.0.0.1', 0), handler(self.client(), token))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        try:
            body = json.dumps(self.payload('must not save')).encode()
            connection.putrequest('POST', '/kakao/skill')
            connection.putheader('Content-Type', 'application/json')
            connection.putheader('Content-Length', str(len(body)))
            connection.putheader('x-api-key', token)
            connection.putheader('x-api-key', token)
            connection.endheaders(body)
            with connection.getresponse() as response:
                self.assertEqual(response.status, 401)
                response.read()
            self.assertEqual(self.store.list(), [])
        finally:
            connection.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_slow_trickle_body_has_total_deadline(self):
        token = 's' * 32
        server = SkillServer(('127.0.0.1', 0), handler(self.client(), token))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        connection = socket.create_connection(('127.0.0.1', server.server_port), timeout=5)
        connection.settimeout(5)
        stop = threading.Event()
        def trickle():
            while not stop.wait(.4):
                try:
                    connection.sendall(b' ')
                except OSError:
                    break
        sender = threading.Thread(target=trickle, daemon=True)
        try:
            header = ('POST /kakao/skill HTTP/1.1\r\nHost: localhost\r\nx-api-key: ' + token +
                      '\r\nContent-Type: application/json\r\nContent-Length: 32000\r\n\r\n')
            connection.sendall(header.encode() + b'{')
            started = time.monotonic()
            sender.start()
            try:
                response = connection.recv(4096)
            except ConnectionResetError:
                response = b''
            elapsed = time.monotonic() - started
            self.assertLess(elapsed, 5)
            self.assertTrue(not response or b'503' in response or b'408' in response)
            self.assertEqual(self.store.list(), [])
        finally:
            stop.set()
            connection.close()
            sender.join(timeout=1)
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_http_endpoint_auth_origin_routes_and_payload_bounds(self):
        token = 's' * 32
        server = SkillServer(('127.0.0.1', 0), handler(self.client(), token))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}'

        def request(data=None, path='/kakao/skill', method='POST', secret=token,
                    origin=None, content_type='application/json'):
            headers = {'Content-Type': content_type}
            if secret is not None:
                headers['x-api-key'] = secret
            if origin is not None:
                headers['Origin'] = origin
            raw = json.dumps(data).encode() if not isinstance(data, bytes) else data
            req = urllib.request.Request(url + path, raw if method == 'POST' else None,
                                         headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=3) as response:
                    return response.status, json.load(response)
            except urllib.error.HTTPError as error:
                try:
                    return error.code, error.read()
                finally:
                    error.close()

        try:
            self.assertEqual(request(self.payload('hi'), secret=None)[0], 401)
            self.assertEqual(request(self.payload('hi'), secret='wrong')[0], 401)
            self.assertEqual(request(self.payload('hi'), origin='https://evil.example')[0], 403)
            self.assertEqual(request(self.payload('hi', user='other'))[0], 403)
            self.assertEqual(request(self.payload('hi', bot='other'))[0], 403)
            for malformed in [b'{', [], {}, self.payload(None), b'x' * 32769, b'[' * 1200 + b'0' + b']' * 1200]:
                self.assertEqual(request(malformed)[0], 400)
            self.assertEqual(request(self.payload('hi'), content_type='text/plain')[0], 400)
            self.assertEqual(request(self.payload('hi'), path='/other')[0], 404)
            self.assertEqual(request(method='GET')[0], 404)
            self.assertEqual(self.store.list(), [])
            status, response = request(self.payload('정상 메모'))
            self.assertEqual(status, 200)
            self.response_text(response)
            self.assertEqual(self.store.list()[0]['status'], 'memo')
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == '__main__':
    unittest.main()
