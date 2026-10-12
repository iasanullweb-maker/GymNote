"""Service lifecycle checks using real localhost skills and synthetic credentials."""
import json
import os
from pathlib import Path
import socket
import threading
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

from automation.service import InstanceLock, run
from automation.tests import test_automation as baseline
from http.server import ThreadingHTTPServer


class KakaoServiceTests(unittest.TestCase):
    setUp = baseline.Tests.setUp
    tearDown = baseline.Tests.tearDown

    def config(self):
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            skill_port = reservation.getsockname()[1]
        return {'runtimeDir': str(self.root / 'runtime'), 'projects': {'gymnote': {}},
                'defaultProject': 'gymnote', 'port': 0, 'kakaoPort': skill_port,
                'kakaoEnabled': True, 'kakaoBotIds': ['bot-1'], 'kakaoUserKeys': ['user-1'],
                'executionEnabled': False, 'telegramEnabled': False}

    def credentials(self):
        return patch.dict(os.environ, {'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'admin-' + 'a' * 32,
                                      'KAKAO_SKILL_TOKEN': 'skill-' + 'b' * 32})

    def assert_lock_released(self, config):
        lock = InstanceLock(Path(config['runtimeDir']) / 'service.lock')
        lock.close()

    def test_run_wires_separate_skill_port_and_shuts_down(self):
        config = self.config()
        case = self
        class ProbeAdmin(ThreadingHTTPServer):
            def serve_forever(inner, **kwargs):
                admin_thread = threading.Thread(target=super(ProbeAdmin, inner).serve_forever, daemon=True)
                admin_thread.start()
                url = f"http://127.0.0.1:{config['kakaoPort']}"
                body = {'bot': {'id': 'bot-1'}, 'userRequest': {'user': {'id': 'user-1', 'type': 'botUserKey'}, 'utterance': 'memo fixture'}}
                req = urllib.request.Request(url + '/kakao/skill', json.dumps(body).encode(),
                    {'Content-Type': 'application/json', 'x-api-key': 'skill-' + 'b' * 32})
                try:
                    with urllib.request.urlopen(req, timeout=5) as reply:
                        case.assertEqual(json.load(reply)['version'], '2.0')
                    with case.assertRaises(urllib.error.HTTPError) as error:
                        urllib.request.urlopen(url + '/api/tasks', timeout=5)
                    case.assertEqual(error.exception.code, 404)
                    error.exception.close()
                    admin_req = urllib.request.Request(f'http://127.0.0.1:{inner.server_port}/api/tasks',
                        headers={'Authorization': 'Bearer admin-' + 'a' * 32})
                    with urllib.request.urlopen(admin_req, timeout=5) as reply:
                        tasks = json.load(reply)['tasks']
                    case.assertEqual(len(tasks), 1)
                    case.assertEqual(tasks[0]['source'], 'kakao')
                    case.assertEqual(tasks[0]['status'], 'memo')
                finally:
                    inner.shutdown()
                    admin_thread.join(timeout=5)
                raise KeyboardInterrupt
        with self.credentials(), patch('automation.service.ThreadingHTTPServer', ProbeAdmin):
            run(config)
        self.assert_lock_released(config)
        with socket.socket() as connection:
            connection.settimeout(1)
            self.assertNotEqual(connection.connect_ex(('127.0.0.1', config['kakaoPort'])), 0)

    def test_startup_failure_releases_instance_lock_and_admin_port(self):
        config = self.config()
        servers = []
        class SpyAdmin(ThreadingHTTPServer):
            def __init__(inner, *args):
                super().__init__(*args)
                servers.append(inner)
        with self.credentials(), patch('automation.service.ThreadingHTTPServer', SpyAdmin), patch('automation.service.SkillServer', side_effect=OSError('synthetic bind failure')):
            with self.assertRaises(OSError):
                run(config)
        self.assertEqual(servers[0].socket.fileno(), -1)
        self.assert_lock_released(config)
        with self.credentials(), patch('automation.service.Store', side_effect=ValueError('synthetic DB failure')):
            with self.assertRaises(ValueError):
                run(config)
        self.assert_lock_released(config)
