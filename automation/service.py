"""Run with: python -m automation.service --config <local-config.json>."""
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import threading
import time
from urllib.parse import urlparse

from automation.store import Store
from automation.ingress.telegram import Telegram
from automation.worker.runner import Runner


class InstanceLock:
    def __init__(self, path):
        self.file = open(path, 'a+b')
        self.file.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                self.file.write(b'0')
                self.file.flush()
                self.file.seek(0)
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.file.close()
            raise

    def close(self):
        self.file.close()


def load_config(path):
    config = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if not config.get('projects') or config.get('defaultProject') not in config['projects']:
        raise ValueError('Configure projects and defaultProject')
    for project in config['projects'].values():
        root = Path(project['path'])
        if not root.is_absolute() or not root.is_dir():
            raise ValueError('Project path must be an existing absolute directory')
    if not 1 <= config.get('port', 8765) <= 65535:
        raise ValueError('Invalid port')
    if not 10 <= config.get('timeoutSeconds', 900) <= 3600:
        raise ValueError('timeoutSeconds must be between 10 and 3600')
    if not 1 <= config.get('maxTasksPerSession', 10) <= 100:
        raise ValueError('maxTasksPerSession must be between 1 and 100')
    return config


def handler(store, config, token):
    page = (Path(__file__).parent / 'admin/index.html').read_bytes()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass  # URLs and request bodies may contain private data.

        def reply(self, status, value, html=False):
            data = value if html else json.dumps(value, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'text/html; charset=utf-8' if html else 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; connect-src 'self'")
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def authenticated(self):
            expected_host = f'127.0.0.1:{self.server.server_port}'
            if self.headers.get('Host') != expected_host:
                self.reply(403, {'error': 'Invalid host'})
                return False
            origin = self.headers.get('Origin')
            if origin and origin != 'http://' + expected_host:
                self.reply(403, {'error': 'Invalid origin'})
                return False
            supplied = self.headers.get('Authorization', '')
            if not hmac.compare_digest(supplied.encode('utf-8'), ('Bearer ' + token).encode('utf-8')):
                self.reply(401, {'error': 'Authentication required'})
                return False
            return True

        def do_GET(self):
            if self.path == '/':
                self.reply(200, page, html=True)
                return
            if not self.authenticated():
                return
            if self.path == '/api/tasks':
                self.reply(200, {'tasks': store.list(), 'projects': list(config['projects']),
                                 'defaultProject': config['defaultProject'],
                                 'executionEnabled': config.get('executionEnabled', False),
                                 'executionPaused': config.get('executionPaused', False)})
            else:
                self.reply(404, {'error': 'Not found'})

        def do_POST(self):
            if not self.authenticated():
                return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 32768:
                    raise ValueError('Invalid request size')
                data = json.loads(self.rfile.read(size))
                if not isinstance(data, dict):
                    raise ValueError('Expected object')
                if self.path == '/api/tasks':
                    project = data.get('project', config['defaultProject'])
                    if project not in config['projects']:
                        raise ValueError('Project is not allowed')
                    import uuid
                    task = store.create('web', str(uuid.uuid4()), 'admin', project,
                                        data.get('text', ''), data.get('intent', 'memo'))
                    self.reply(201, task)
                    return
                parts = urlparse(self.path).path.strip('/').split('/')
                if len(parts) == 4 and parts[:2] == ['api', 'tasks']:
                    task = store.get(parts[2])
                    if not task:
                        self.reply(404, {'error': 'Not found'})
                        return
                    if parts[3] == 'cancel':
                        store.cancel(task['id'])
                    elif parts[3] == 'retry':
                        store.retry(task['id'])
                    else:
                        raise ValueError('Unknown action')
                    self.reply(200, store.get(task['id']))
                    return
                self.reply(404, {'error': 'Not found'})
            except (ValueError, TypeError, AttributeError):
                self.reply(400, {'error': 'Invalid input or task state'})

    return Handler


def run(config):
    token = os.environ.get('GYMNOTE_AUTOMATION_ADMIN_TOKEN', '')
    if len(token) < 24:
        raise ValueError('Set GYMNOTE_AUTOMATION_ADMIN_TOKEN to a random value of at least 24 characters')
    runtime = Path(config.get('runtimeDir', str(Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'GymNoteAutomation'))).resolve()
    runtime.mkdir(parents=True, exist_ok=True)
    instance = InstanceLock(runtime / 'service.lock')
    stop = threading.Event()
    store = Store(runtime / 'ideas.sqlite3')
    store.recover()
    runner = Runner(store, config['projects'], runtime, config.get('codexExecutable', 'codex'), config.get('timeoutSeconds', 900))
    telegram = None
    if config.get('telegramEnabled'):
        telegram = Telegram(os.environ.get('TELEGRAM_BOT_TOKEN'), config.get('allowedUserIds'),
                            config.get('allowedChatIds'), config['defaultProject'], store)
    server = ThreadingHTTPServer(('127.0.0.1', config.get('port', 8765)), handler(store, config, token))
    server.daemon_threads = True

    def work():
        processed = 0
        while not stop.is_set():
            if processed >= config.get('maxTasksPerSession', 10):
                config['executionPaused'] = True
                stop.wait(1)
            else:
                try:
                    if runner.once():
                        processed += 1
                    else:
                        stop.wait(1)
                except Exception:
                    config['executionPaused'] = True
                    print('Worker stopped after a storage/runtime error; inspect local service before restarting.', flush=True)
                    return

    def receive():
        while not stop.is_set():
            try:
                telegram.poll()
            except Exception:
                print('Telegram polling failed; retrying in 10 seconds. No credentials logged.', flush=True)
                stop.wait(10)

    threads = []
    if config.get('executionEnabled'):
        threads.append(threading.Thread(target=work, daemon=True))
    if telegram:
        threads.append(threading.Thread(target=receive, daemon=True))
    for thread in threads:
        thread.start()
    print(f"Idea automation: http://127.0.0.1:{server.server_port} | Telegram={bool(telegram)} | execution={bool(config.get('executionEnabled'))}", flush=True)
    try:
        server.serve_forever(poll_interval=.25)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()
        # Stop current agent through the same cancellation path; keep lock until stopped.
        for task in store.list():
            if task['status'] in ('planning', 'running', 'reviewing', 'validating'):
                store.cancel(task['id'])
        for thread in threads:
            thread.join()
        instance.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    run(load_config(args.config))
