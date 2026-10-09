import json
import sqlite3
import threading
import unittest
import urllib.error
import urllib.request
from contextlib import closing
from http.server import ThreadingHTTPServer

from automation.service import handler
from automation.store import Store
from automation.tests import test_automation


class ContractTests(unittest.TestCase):
    setUp = test_automation.Tests.setUp
    tearDown = test_automation.Tests.tearDown
    task = test_automation.Tests.task
    def test_invalid_input_cannot_reach_storage(self):
        values = ['mock', 'event', 'admin', 'gymnote', 'idea', 'execute']
        for position, bad in [(0, 'unknown'), (1, True), (1, {}), (2, ''),
                              (3, []), (4, ' '), (4, '\x00'), (5, [])]:
            with self.subTest(position=position, value=bad):
                candidate = values.copy()
                candidate[position] = bad
                with self.assertRaises(ValueError):
                    self.store.create(*candidate)
        self.assertEqual(self.store.list(), [])

    def test_duplicate_event_cannot_change_owner_project_or_intent(self):
        original = self.store.create('web', 'request', 'admin', 'gymnote', 'idea', 'memo')
        for actor, project, text, intent in [('other', 'gymnote', 'idea', 'memo'),
                                            ('admin', 'other', 'idea', 'memo'),
                                            ('admin', 'gymnote', 'changed', 'memo'),
                                            ('admin', 'gymnote', 'idea', 'execute')]:
            with self.assertRaises(ValueError):
                self.store.create('web', 'request', actor, project, text, intent)
        self.assertEqual(original['id'], self.store.create('web', 'request', 'admin', 'gymnote', 'idea', 'memo')['id'])
        self.assertEqual(len(self.store.history(original['id'])), 1)

    def test_terminal_and_stale_attempt_updates_rejected(self):
        task = self.task()['id']
        self.store.claim()
        first = self.store.get(task)['attempt']
        self.store.state(task, 'waiting_user', {'worktree': 'saved', 'checks': ['first']}, attempt=first)
        self.store.retry(task)
        self.store.claim()
        second = self.store.get(task)['attempt']
        self.assertNotEqual(first, second)
        self.assertIsNone(self.store.get(task)['result'])
        with self.assertRaisesRegex(ValueError, 'Stale'):
            self.store.state(task, 'running', attempt=first)
        for status in ('running', 'reviewing', 'validating', 'completed'):
            self.store.state(task, status, attempt=second)
        with self.assertRaises(ValueError):
            self.store.state(task, 'running', attempt=second)
        history = self.store.history(task)
        self.assertTrue(any(step['result'] and step['result'].get('checks') == ['first'] for step in history))

    def test_restart_keeps_recovery_artifacts_and_cancel_blocks_progress(self):
        task = self.task()['id']
        self.store.claim()
        self.store.state(task, 'running', {'worktree': 'saved', 'base': 'base', 'integrated': False})
        self.store.recover()
        self.assertEqual(self.store.get(task)['result']['worktree'], 'saved')
        self.assertEqual(self.store.history(task)[-1]['status'], 'waiting_user')
        self.store.retry(task)
        self.store.claim()
        self.store.cancel(task)
        with self.assertRaises(ValueError):
            self.store.state(task, 'running')
        self.store.state(task, 'cancelled')
        self.assertEqual(self.store.get(task)['status'], 'cancelled')

    def test_existing_database_upgrade_preserves_tasks_and_history(self):
        path = self.root / 'old.sqlite3'
        with closing(sqlite3.connect(path)) as db:
            db.executescript('''
            CREATE TABLE tasks (id TEXT PRIMARY KEY, source TEXT, event TEXT, actor TEXT,
              project TEXT, text TEXT, status TEXT, created TEXT, updated TEXT, attempt TEXT,
              result TEXT, cancel INTEGER DEFAULT 0, UNIQUE(source,event));
            CREATE TABLE history (task TEXT,time TEXT,status TEXT,attempt TEXT);
            INSERT INTO tasks VALUES ('old','web','event','admin','gymnote','idea','memo','then','then',NULL,NULL,0);
            INSERT INTO history VALUES ('old','then','memo',NULL);
            ''')
            db.commit()
        upgraded = Store(path)
        self.assertEqual(upgraded.get('old')['intent'], 'memo')
        self.assertEqual(upgraded.history('old')[0]['time'], 'then')
        upgraded.cancel('old')
        self.assertEqual(Store(path).history('old')[-1]['status'], 'cancelled')

    def test_http_idempotency_detail_and_malformed_project(self):
        token = 'a' * 32
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler(
            self.store, {'projects': {'gymnote': {}}, 'defaultProject': 'gymnote'}, token))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def request(path, body=None):
            req = urllib.request.Request(f'http://127.0.0.1:{server.server_port}' + path,
                None if body is None else json.dumps(body).encode(),
                {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=5) as response:
                return json.load(response)
        try:
            body = {'text': 'idea', 'intent': 'execute', 'requestId': 'stable-request', 'actor': 'forged'}
            first = request('/api/tasks', body)
            self.assertEqual(first['actor'], 'admin')
            self.assertEqual(first['id'], request('/api/tasks', body)['id'])
            detail = request('/api/tasks/' + first['id'])
            self.assertEqual(detail['history'][0]['status'], 'queued')
            for invalid in [dict(body, text='different'), dict(body, project=[]), dict(body, requestId=True)]:
                with self.assertRaises(urllib.error.HTTPError) as error:
                    request('/api/tasks', invalid)
                self.assertEqual(error.exception.code, 400)
            with self.assertRaises(urllib.error.HTTPError) as error:
                request('/api/tasks/missing')
            self.assertEqual(error.exception.code, 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
