"""Kakao channel skill ingress. Only persists requests; never waits for an agent."""
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import sqlite3
import socket
import threading

from automation.contracts.tasks import identifier


def response(text, task=None):
    template = {'outputs': [{'simpleText': {'text': text[:1000]}}]}
    if task:
        template['quickReplies'] = [{'label': '상태 확인', 'action': 'message',
                                     'messageText': '상태 ' + task['id']}]
    return {'version': '2.0', 'template': template}


def validate_config(config, token=None):
    for key in ('kakaoEnabled', 'kakaoDiscoveryEnabled'):
        if key in config and type(config[key]) is not bool:
            raise ValueError('Kakao feature flags must be JSON booleans')
    if not config.get('kakaoEnabled'):
        return
    port = config.get('kakaoPort', 8766)
    if type(port) is not int or not 1 <= port <= 65535 or port == config.get('port', 8765):
        raise ValueError('Kakao skill port must be valid and separate from administrator port')
    for key in ('kakaoBotIds', 'kakaoUserKeys'):
        values = config.get(key)
        if not isinstance(values, list):
            raise ValueError('Kakao allowlists must be lists')
        for value in values:
            identifier(value, key, 100)
        if not values and (key == 'kakaoBotIds' or not config.get('kakaoDiscoveryEnabled')):
            raise ValueError('Configure allowed Kakao bot and users, or explicit discovery mode')
    if token is not None and (not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', token)):
        raise ValueError('Set KAKAO_SKILL_TOKEN to a random URL-safe value of 32 to 128 characters')


class Kakao:
    def __init__(self, store, config):
        validate_config({**config, 'kakaoEnabled': True})
        self.store, self.config = store, config

    @staticmethod
    def key(value):
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', value):
            raise ValueError('Invalid request key')
        return value

    @staticmethod
    def event(actor, kind, key):
        return hashlib.sha256((actor + '\0' + kind + '\0' + key).encode()).hexdigest()

    def status(self, task):
        labels = {'memo': '메모 저장', 'queued': '실행 대기', 'planning': '준비 중',
                  'running': '구현 중', 'reviewing': '검토 중', 'validating': '검증 중',
                  'completed': '완료', 'waiting_user': '사용자 확인 필요',
                  'failed': '실패', 'cancelled': '중지 완료'}
        lines = [task['id'], '상태: ' + labels.get(task['status'], task['status'])]
        if task['cancel'] and task['status'] not in ('completed', 'failed', 'cancelled'):
            lines.append('중지 요청됨 · 실행 종료 확인 대기')
        value = task.get('result')
        if isinstance(value, dict):
            lines.append('로컬 통합: ' + ('완료' if value.get('integrated') is True else '미확인'))
            commit = value.get('commit')
            if isinstance(commit, str) and re.fullmatch(r'[0-9a-f]{40}', commit):
                lines.append('커밋: ' + commit[:12])
            checks, not_run = value.get('checks'), value.get('notRun')
            lines.append(f"검사 기록 {len(checks) if isinstance(checks, list) else 0}개 · 미실행 {len(not_run) if isinstance(not_run, list) else 0}개")
        if task['status'] == 'queued' and (not self.config.get('executionEnabled') or self.config.get('executionPaused')):
            lines.append('실행기가 꺼져 있거나 작업 수 한도에 도달했습니다.')
        return '\n'.join(lines)

    def accept(self, payload):
        text, task = self.handle(payload)
        return response(text, task)

    def handle(self, payload, *, memo_event=None):
        """Return (reply text, task or None). memo_event makes relay replays idempotent."""
        try:
            if not isinstance(payload, dict):
                raise ValueError('Expected object')
            bot = identifier(payload['bot']['id'], 'bot', 100)
            request = payload['userRequest']
            user = request['user']
            user_id = identifier(user['id'], 'user', 100)
            if user['type'] != 'botUserKey':
                raise ValueError('Expected botUserKey')
            text = request['utterance']
            if not isinstance(text, str) or not text.strip() or len(text) > 8200 or '\x00' in text:
                raise ValueError('Invalid utterance')
        except (KeyError, TypeError, AttributeError):
            raise ValueError('Invalid skill payload') from None
        if bot not in self.config['kakaoBotIds']:
            raise PermissionError('Bot is not allowed')
        command, *rest = text.strip().split(maxsplit=1)
        body = rest[0].strip() if rest else ''
        aliases = {'도움말': '/help', '내정보': '/whoami', '메모': '/memo', '실행': '/run',
                   '상태': '/status', '중지': '/cancel', '재시도': '/retry'}
        command = aliases.get(command, command)
        if command == '/whoami' and self.config.get('kakaoDiscoveryEnabled'):
            return '연결 식별자\nbot.id: ' + bot + '\nbotUserKey: ' + user_id + '\nPC 로컬 설정의 허용 목록에 등록하세요.', None
        if user_id not in self.config['kakaoUserKeys']:
            raise PermissionError('User is not allowed')
        actor = 'kakao:' + hashlib.sha256((bot + '\0' + user_id).encode()).hexdigest()
        if command in ('/help', '/start'):
            return '일반 메시지 / 메모 내용: 메모 저장\n실행 요청키 내용: 자동 작업\n상태 [작업ID]: 결과 조회\n중지 작업ID\n재시도 요청키 작업ID\n요청키는 영문·숫자·_·-로 1~64자입니다. 새 작업은 새 키를 쓰세요.', None
        if command == '/whoami':
            return '연결 식별자 확인은 PC에서 발견 모드를 켠 동안만 가능합니다.', None
        if command == '/status' and not body:
            tasks = self.store.list_actor(actor)
            return '\n\n'.join(self.status(task) for task in tasks) if tasks else '등록한 작업이 없습니다.', None
        if command in ('/status', '/cancel', '/retry'):
            retry_key = None
            if command == '/retry':
                parts = body.split()
                if len(parts) != 2:
                    return '재시도 요청키 작업ID 형식으로 입력하세요.', None
                retry_key, body = self.key(parts[0]), parts[1]
            task = self.store.get(body)
            if not task or task['actor'] != actor or task['source'] != 'kakao':
                return '해당 작업을 찾을 수 없습니다.', None
            if command == '/cancel':
                self.store.cancel(task['id'])
            elif command == '/retry':
                if not self.config.get('executionEnabled') or self.config.get('executionPaused'):
                    return '자동 작업 실행이 꺼져 있거나 일시 중지되어 있습니다. PC 설정을 확인하세요.', None
                if task['intent'] != 'execute':
                    return '메모는 재시도로 실행할 수 없습니다. 실행 요청키 내용으로 새로 요청하세요.', None
                self.store.retry(task['id'], event='kakao:retry:' + self.event(actor, task['id'], retry_key))
            return self.status(self.store.get(task['id'])), task
        if command == '/run':
            if not self.config.get('executionEnabled') or self.config.get('executionPaused'):
                return '자동 작업 실행이 꺼져 있거나 일시 중지되어 있습니다. 먼저 메모 수신을 확인하고 PC에서 실행을 켜세요.', None
            parts = body.split(maxsplit=1)
            if len(parts) != 2:
                return '실행 요청키 내용 형식으로 입력하세요. 예: 실행 test-1 문서에 연결 확인 문장 추가', None
            key, idea = self.key(parts[0]), parts[1]
            task = self.store.create('kakao', self.event(actor, 'run', key), actor,
                                     self.config['defaultProject'], idea, 'execute')
            return '실행 요청 접수\n' + self.status(task) + '\n상태 확인 버튼으로 결과를 조회하세요.', task
        if command.startswith('/') and command != '/memo':
            return '지원하지 않는 명령입니다. 도움말을 입력하세요.', None
        idea = body if command == '/memo' else text.strip()
        if memo_event is not None:
            # Relay mailbox IDs are stable across lease expiry and restarts: exactly one memo per item.
            task = self.store.create('kakao', memo_event, actor, self.config['defaultProject'], idea, 'memo')
        else:
            fingerprint = self.event(actor, 'memo', idea)
            task = self.store.create('kakao', fingerprint, actor, self.config['defaultProject'], idea,
                                     'memo', memo_replay_seconds=60)
        return '아이디어 저장\n' + self.status(task), task


class SkillServer(ThreadingHTTPServer):
    """Bound request concurrency; each handler has a total lifetime deadline."""
    daemon_threads = False

    def __init__(self, address, request_handler):
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(address, request_handler)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            try:
                request.settimeout(.1)
                request.sendall(b'HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
            except OSError:
                pass
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


def handler(kakao, token):
    validate_config({**kakao.config, 'kakaoEnabled': True}, token)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(2)
            # An idle timeout alone can be kept alive by a slow byte stream.
            self.deadline = threading.Timer(3.5, self.expire)
            self.deadline.daemon = True
            self.deadline.start()

        def expire(self):
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        def finish(self):
            self.deadline.cancel()
            try:
                super().finish()
            except OSError:
                pass

        def log_message(self, *args):
            pass  # No IDs, headers, URLs or private utterances in access logs.

        def reply(self, status, text=None, value=None):
            data = json.dumps(value if value is not None else response(text), ensure_ascii=False).encode('utf-8')
            try:
                self.send_response(status)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except OSError:
                self.close_connection = True

        def do_GET(self):
            self.reply(404, '등록된 스킬 경로가 아닙니다.')

        def do_POST(self):
            if self.path != '/kakao/skill':
                self.reply(404, '등록된 스킬 경로가 아닙니다.')
                return
            supplied = self.headers.get('x-api-key', '')
            if len(self.headers.get_all('x-api-key') or []) != 1 or not hmac.compare_digest(supplied.encode(), token.encode()):
                self.reply(401, '스킬 인증이 필요합니다.')
                return
            if self.headers.get('Origin'):
                self.reply(403, '허용되지 않은 요청입니다.')
                return
            try:
                lengths = self.headers.get_all('Content-Length') or []
                if len(lengths) != 1 or self.headers.get('Transfer-Encoding'):
                    raise ValueError('Invalid framing')
                size = int(lengths[0])
                if not 0 < size <= 32768 or self.headers.get('Content-Type', '').split(';')[0].strip().lower() != 'application/json':
                    raise ValueError('Invalid body')
                raw = self.rfile.read(size)
                if len(raw) != size:
                    raise ValueError('Incomplete body')
                payload = json.loads(raw)
                value = kakao.accept(payload)
            except PermissionError:
                self.reply(403, '허용된 봇과 사용자만 이용할 수 있습니다.')
            except (ValueError, TypeError, UnicodeError, RecursionError):
                self.reply(400, '입력 형식이나 요청키·작업 상태를 확인하세요.')
            except OSError:
                self.close_connection = True
                return
            except sqlite3.Error:
                self.reply(503, '잠시 후 같은 요청키로 다시 시도하세요.')
            else:
                self.reply(200, value=value)

    return Handler
