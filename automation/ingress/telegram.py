import json
import urllib.request


class Telegram:
    def __init__(self, token, users, chats, project, store):
        if not token or not users or not chats:
            raise ValueError('Bot token, allowed users and allowed chats are required')
        self.token, self.users, self.chats = token, set(users), set(chats)
        self.project, self.store = project, store

    def call(self, method, data):
        request = urllib.request.Request(
            f'https://api.telegram.org/bot{self.token}/{method}',
            json.dumps(data).encode(), {'Content-Type': 'application/json'})
        # Never propagate URL-bearing HTTP errors (the URL contains the token).
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                result = json.load(response)
            if not result.get('ok'):
                raise RuntimeError('Telegram API rejected request')
            return result['result']
        except Exception:
            raise RuntimeError('Telegram request failed; check network and local configuration') from None

    def accept(self, update):
        message = update.get('message', {})
        sender, chat = message.get('from', {}), message.get('chat', {})
        if sender.get('is_bot') or sender.get('id') not in self.users or chat.get('id') not in self.chats:
            return None
        text = message.get('text', '').strip()
        if not text:
            return None
        actor = f"telegram:{sender['id']}"
        command, _, body = text.partition(' ')
        if command in ('/status', '/cancel', '/retry'):
            task = self.store.get(body.strip())
            if not task or task['actor'] != actor:
                return '해당 작업을 찾을 수 없습니다.'
            if command == '/cancel':
                self.store.cancel(task['id'])
            elif command == '/retry':
                try:
                    self.store.retry(task['id'], event=update['update_id'])
                except ValueError:
                    return '현재 상태에서는 재시도할 수 없습니다.'
            task = self.store.get(task['id'])
            return f"{task['id']}\n상태: {task['status']}"
        if command in ('/start', '/help'):
            return '일반 메시지: 아이디어 저장\n/run 내용: 실행\n/status 작업ID\n/cancel 작업ID\n/retry 작업ID'
        intent = 'execute' if command == '/run' else 'memo'
        if command in ('/run', '/memo'):
            text = body.strip()
        elif text.startswith('/'):
            return '지원하지 않는 명령입니다. /help를 확인하세요.'
        if not text or len(text) > 8000:
            return '아이디어 내용을 1~8000자로 입력하세요.'
        task = self.store.create('telegram', update['update_id'], actor, self.project, text, intent)
        return f"{'실행 요청 접수' if intent == 'execute' else '아이디어 저장'}\n{task['id']}\n상태: {task['status']}"

    def poll(self):
        updates = self.call('getUpdates', {'offset': self.store.offset(), 'timeout': 25,
                                          'allowed_updates': ['message']})
        for update in updates:
            reply = self.accept(update)
            # Persist accepted ideas before acknowledging updates. A replay cannot enqueue twice.
            self.store.offset(update['update_id'] + 1)
            if reply:
                self.call('sendMessage', {'chat_id': update['message']['chat']['id'], 'text': reply})
