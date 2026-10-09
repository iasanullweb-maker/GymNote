import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest.mock import patch
import sys

from automation.store import Store
from automation.ingress.telegram import Telegram
from automation.worker.runner import FileLock, Runner, git
from automation.service import handler, InstanceLock


class Tests(unittest.TestCase):
    def setUp(self):
        test_root = Path(__file__).resolve().parents[2] / '.validation-tools'
        test_root.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='automation-test-', dir=test_root)
        self.root = Path(self.temp.name)
        self.store = Store(self.root / 'data.sqlite3')
        self.bot = Telegram('test-secret', [123], [456], 'gymnote', self.store)

    def tearDown(self):
        assert self.root.resolve().is_relative_to(Path(__file__).resolve().parents[2] / '.validation-tools')
        self.temp.cleanup()

    def update(self, text, event=1, user=123, chat=456):
        return {'update_id': event, 'message': {'text': text, 'from': {'id': user}, 'chat': {'id': chat}}}

    def task(self, intent='execute'):
        return self.store.create('mock', '1', 'admin', 'gymnote', 'Change a file', intent)

    def test_plain_text_is_persistent_memo(self):
        self.bot.accept(self.update('운동 아이디어'))
        self.assertEqual(Store(self.root / 'data.sqlite3').list()[0]['status'], 'memo')
        self.assertIsNone(self.store.claim())

    def test_run_deduplicates_concurrent_delivery(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.bot.accept(self.update('/run 아이디어')), range(20)))
        self.assertEqual(len(self.store.list()), 1)
        self.assertIsNotNone(self.store.claim())
        self.assertIsNone(self.store.claim())

    def test_sender_and_chat_both_required(self):
        self.assertIsNone(self.bot.accept(self.update('/run hi', user=999)))
        self.assertIsNone(self.bot.accept(self.update('/run hi', chat=999)))
        self.assertEqual(self.store.list(), [])

    def test_unknown_commands_and_empty_run_do_not_enqueue(self):
        self.bot.accept(self.update('/unknown'))
        self.bot.accept(self.update('/run', event=2))
        self.assertEqual(self.store.list(), [])

    def test_task_ownership(self):
        task = self.task()
        self.bot.accept(self.update('/cancel ' + task['id']))
        self.assertEqual(self.store.get(task['id'])['status'], 'queued')

    def test_cancel_active_not_reported_stopped_until_runner_confirms(self):
        task = self.task()
        self.store.claim()
        self.store.cancel(task['id'])
        self.assertEqual(self.store.get(task['id'])['status'], 'planning')
        self.assertTrue(self.store.get(task['id'])['cancel'])

    def test_cancel_queue_never_claimed(self):
        self.store.cancel(self.task()['id'])
        self.assertIsNone(self.store.claim())

    def test_restart_requires_explicit_retry(self):
        task = self.task()
        self.store.claim()
        attempt = self.store.get(task['id'])['attempt']
        self.store.recover()
        self.assertEqual(self.store.get(task['id'])['status'], 'waiting_user')
        self.assertIsNone(self.store.claim())
        self.store.retry(task['id'], event=90)
        self.store.claim()
        self.assertNotEqual(attempt, self.store.get(task['id'])['attempt'])
        self.store.state(task['id'], 'waiting_user')
        self.store.retry(task['id'], event=90)
        self.assertIsNone(self.store.claim())

    def test_poll_durably_acknowledges_before_failed_reply(self):
        def call(method, data):
            if method == 'getUpdates':
                return [self.update('/run hi', event=9)]
            raise RuntimeError('offline')
        self.bot.call = call
        with self.assertRaises(RuntimeError):
            self.bot.poll()
        self.assertEqual(self.store.offset(), 10)
        self.assertEqual(len(self.store.list()), 1)

    def test_foreign_lock_preserved(self):
        path = self.root / 'integration.lock'
        with FileLock(path):
            with self.assertRaises(FileExistsError):
                with FileLock(path):
                    pass
            self.assertTrue(path.exists())
        self.assertFalse(path.exists())

    def test_single_service_instance(self):
        first = InstanceLock(self.root / 'service.lock')
        try:
            with self.assertRaises(OSError):
                InstanceLock(self.root / 'service.lock')
        finally:
            first.close()
        second = InstanceLock(self.root / 'service.lock')
        second.close()

    def test_admin_auth_origin_input_and_html(self):
        token = 'a' * 32
        config = {'projects': {'gymnote': {}}, 'defaultProject': 'gymnote'}
        server = ThreadingHTTPServer(('127.0.0.1', 0), handler(self.store, config, token))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}'
        def request(path, data=None, auth=True, origin=None):
            headers = {'Content-Type': 'application/json'}
            if auth:
                headers['Authorization'] = 'Bearer ' + token
            if origin:
                headers['Origin'] = origin
            req = urllib.request.Request(url + path, None if data is None else json.dumps(data).encode(), headers)
            return urllib.request.urlopen(req)
        try:
            with request('/', auth=False) as response:
                self.assertIn('아이디어'.encode(), response.read())
            with self.assertRaises(urllib.error.HTTPError) as error:
                request('/api/tasks', auth=False)
            self.assertEqual(error.exception.code, 401)
            with self.assertRaises(urllib.error.HTTPError) as error:
                request('/api/tasks', {}, origin='https://evil.example')
            self.assertEqual(error.exception.code, 403)
            with self.assertRaises(urllib.error.HTTPError) as error:
                request('/api/tasks', {'text': 'hi', 'project': '../escape'})
            self.assertEqual(error.exception.code, 400)
            with request('/api/tasks', {'text': '<script>bad</script>', 'intent': 'memo'}) as response:
                self.assertEqual(json.load(response)['status'], 'memo')
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def repository(self):
        root = self.root / 'repo'
        root.mkdir()
        git(root, 'init', '-b', 'main')
        git(root, 'config', 'user.name', 'Test')
        git(root, 'config', 'user.email', 'test@example.invalid')
        (root / 'file.txt').write_text('base')
        git(root, 'add', 'file.txt')
        git(root, 'commit', '-m', 'base')
        return root

    def runner(self, root, approved=True):
        class FakeRunner(Runner):
            def agent(inner, task, worktree, prompt, output, readonly=False):
                if readonly:
                    return json.dumps({'approved': approved, 'findings': [] if approved else ['unsafe change']})
                (worktree / 'file.txt').write_text('changed')
                git(worktree, 'add', 'file.txt')
                git(worktree, 'commit', '-m', 'change')
                return json.dumps({'ready': True, 'summary': 'done', 'checks': ['fixture check passed'], 'notRun': []})
        return FakeRunner(self.store, {'gymnote': {'path': str(root), 'autoIntegrate': True}}, self.root / 'runtime', 'unused')

    def test_execution_review_and_ff_integration(self):
        root = self.repository()
        task = self.task()
        self.assertTrue(self.runner(root).once())
        result = self.store.get(task['id'])
        self.assertEqual(result['status'], 'completed')
        self.assertTrue(result['result']['integrated'])
        self.assertEqual((root / 'file.txt').read_text(), 'changed')

    def test_failed_review_preserves_work_without_merge(self):
        root = self.repository()
        task = self.task()
        self.runner(root, approved=False).once()
        self.assertEqual(self.store.get(task['id'])['status'], 'waiting_user')
        self.assertEqual((root / 'file.txt').read_text(), 'base')
        self.assertTrue(Path(self.store.get(task['id'])['result']['worktree']).exists())

    def test_dirty_main_preserved(self):
        root = self.repository()
        (root / 'file.txt').write_text('another chat')
        task = self.task()
        self.runner(root).once()
        self.assertEqual(self.store.get(task['id'])['status'], 'waiting_user')
        self.assertEqual((root / 'file.txt').read_text(), 'another chat')

    def test_advanced_main_refuses_unreviewed_merge(self):
        root = self.repository()
        base = git(root, 'rev-parse', 'HEAD')
        worktree = self.root / 'candidate'
        git(root, 'worktree', 'add', '-b', 'candidate', str(worktree), base)
        (root / 'other.txt').write_text('new main')
        git(root, 'add', 'other.txt')
        git(root, 'commit', '-m', 'concurrent change')
        with self.assertRaises(RuntimeError):
            self.runner(root).integrate({'path': str(root)}, worktree, base)
        self.assertTrue((root / 'other.txt').exists())

    def test_cancel_terminates_real_agent_process(self):
        task = self.task()
        self.store.claim()
        fake = self.root / 'fake_agent.py'
        fake.write_text('import sys,time\nsys.stdin.read()\ntime.sleep(30)\n')
        real_popen = subprocess.Popen
        processes = []
        def spawn(args, **kwargs):
            process = real_popen([sys.executable, str(fake)], **kwargs)
            processes.append(process)
            return process
        runner = Runner(self.store, {}, self.root, 'fake', timeout=5)
        errors = []
        def run():
            try:
                runner.agent(task['id'], self.root, 'test', self.root / 'out.json')
            except RuntimeError as error:
                errors.append(str(error))
        with patch('automation.worker.runner.subprocess.Popen', side_effect=spawn):
            # taskkill also uses Popen internally; only substitute the fake executable.
            def routed(args, **kwargs):
                return spawn(args, **kwargs) if args[0] == 'fake' else real_popen(args, **kwargs)
            with patch('automation.worker.runner.subprocess.Popen', side_effect=routed):
                thread = threading.Thread(target=run)
                thread.start()
                import time
                deadline = time.monotonic() + 5
                while not processes and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(processes)
                self.store.cancel(task['id'])
                thread.join(timeout=15)
        self.assertFalse(thread.is_alive())
        self.assertIsNotNone(processes[0].poll())
        self.assertEqual(errors, ['cancelled'])

    def test_agent_contract_and_secret_environment(self):
        task = self.task()
        self.store.claim()
        fake = self.root / 'contract_agent.py'
        fake.write_text('''import os,sys,json,pathlib
assert 'TELEGRAM_BOT_TOKEN' not in os.environ
assert 'GYMNOTE_AUTOMATION_ADMIN_TOKEN' not in os.environ
assert sys.argv[-1] == '-'
assert sys.stdin.read() == 'private idea'
schema=json.loads(pathlib.Path(sys.argv[sys.argv.index('--output-schema')+1]).read_text())
assert schema['required'] == ['ready','checks','summary','notRun']
pathlib.Path(sys.argv[sys.argv.index('--output-last-message')+1]).write_text('{"ready":true,"checks":["passed"],"summary":"done","notRun":[]}')
''')
        real_popen = subprocess.Popen
        def routed(args, **kwargs):
            return real_popen([sys.executable, str(fake), *args[1:]], **kwargs)
        with patch.dict(os.environ, {'TELEGRAM_BOT_TOKEN': 'sentinel-bot', 'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'sentinel-admin'}), patch('automation.worker.runner.subprocess.Popen', side_effect=routed):
            text = Runner(self.store, {}, self.root, 'fake').agent(task['id'], self.root, 'private idea', self.root / 'out.json')
        self.assertTrue(json.loads(text)['ready'])

    def test_agent_timeout_terminates_process(self):
        task = self.task()
        self.store.claim()
        fake = self.root / 'slow_agent.py'
        fake.write_text('import sys,time\nsys.stdin.read()\ntime.sleep(30)\n')
        real_popen = subprocess.Popen
        processes = []
        def routed(args, **kwargs):
            if args[0] == 'fake':
                process = real_popen([sys.executable, str(fake)], **kwargs)
                processes.append(process)
                return process
            return real_popen(args, **kwargs)
        with patch('automation.worker.runner.subprocess.Popen', side_effect=routed):
            with self.assertRaisesRegex(RuntimeError, 'time limit'):
                Runner(self.store, {}, self.root, 'fake', timeout=.05).agent(task['id'], self.root, 'test', self.root / 'out.json')
        self.assertIsNotNone(processes[0].poll())


if __name__ == '__main__':
    unittest.main()
