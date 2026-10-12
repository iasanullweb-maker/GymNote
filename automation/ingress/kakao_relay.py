"""Pull Kakao requests from the always-on cloud mailbox (Supabase kakao-skill function) into the local queue.

The cloud stores requests even while this PC is off. Each mailbox item is replayed through the same
Kakao handler as direct skill requests; memo replays use the mailbox ID as their event, run/retry use the
explicit request keys, so lease expiry or a restart never duplicates work. Safe status text is published
back so '상태' answers while the PC is off. No idea text, logs or credentials are sent to the cloud
except the original utterance, which the function already holds until acknowledgement.
"""
import json
import re
import urllib.request

from automation.contracts.tasks import identifier
from automation.ingress.kakao import validate_config as validate_kakao_config

SECRET = re.compile(r'[A-Za-z0-9_-]{32,128}')
UUID = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
URL = re.compile(r'https://[A-Za-z0-9.-]+(?::\d+)?(?:/[A-Za-z0-9._~-]+)*/kakao-skill')
WATERMARK = 'kakao_relay_published'
# Rows written by a transaction that started just before the last publish can carry an older timestamp.
OVERLAP_SECONDS = 120


def validate_relay_config(config, token=None):
    if 'kakaoRelayEnabled' in config and type(config['kakaoRelayEnabled']) is not bool:
        raise ValueError('kakaoRelayEnabled must be a JSON boolean')
    if not config.get('kakaoRelayEnabled'):
        return
    url = config.get('kakaoRelayUrl')
    if not isinstance(url, str) or not URL.fullmatch(url):
        raise ValueError('kakaoRelayUrl must be the HTTPS kakao-skill function URL')
    poll = config.get('kakaoRelayPollSeconds', 5)
    if type(poll) is not int or not 2 <= poll <= 300:
        raise ValueError('kakaoRelayPollSeconds must be an integer between 2 and 300')
    for key in ('kakaoBotIds', 'kakaoUserKeys'):
        values = config.get(key)
        if not isinstance(values, list) or not values:
            # Discovery happens in the cloud function; the PC always needs explicit allowlists.
            raise ValueError('Relay mode requires nonempty kakaoBotIds and kakaoUserKeys')
        for value in values:
            identifier(value, key, 100)
    validate_kakao_config({**config, 'kakaoEnabled': True, 'kakaoDiscoveryEnabled': False})
    if token is not None and (not isinstance(token, str) or not SECRET.fullmatch(token)):
        raise ValueError('Set AUTOMATION_RELAY_TOKEN to the same random 32-128 character value as the function secret')


class Relay:
    def __init__(self, kakao, store, url, token, *, urlopen=None, timeout=15):
        if not SECRET.fullmatch(token or ''):
            raise ValueError('Invalid relay token')
        self.kakao, self.store, self.url, self.token = kakao, store, url.rstrip('/'), token
        self.urlopen, self.timeout = urlopen, timeout

    def call(self, action, payload):
        request = urllib.request.Request(
            self.url + '/relay/' + action, data=json.dumps(payload, ensure_ascii=False).encode('utf-8'),
            method='POST', headers={'Content-Type': 'application/json', 'x-relay-token': self.token})
        opener = self.urlopen or urllib.request.urlopen
        with opener(request, timeout=self.timeout) as reply:
            value = json.loads(reply.read(1_048_577)[:1_048_576])
        if not isinstance(value, dict):
            raise ValueError('Unexpected relay response')
        return value

    def pull(self, limit=10):
        items = self.call('claim', {'limit': limit}).get('items')
        if not isinstance(items, list) or len(items) > limit:
            raise ValueError('Unexpected relay claim')
        for item in items:
            if not (isinstance(item, dict) and isinstance(item.get('id'), str) and UUID.fullmatch(item['id'])
                    and isinstance(item.get('claim'), str) and UUID.fullmatch(item['claim'])
                    and isinstance(item.get('received'), str)):
                raise ValueError('Unexpected relay item')
        handled = 0
        for item in sorted(items, key=lambda value: (value['received'], value['id'])):
            self.process(item)
            handled += 1
        return handled

    def process(self, item):
        payload = {'bot': {'id': item.get('bot')}, 'userRequest': {
            'user': {'id': item.get('user'), 'type': 'botUserKey'}, 'utterance': item.get('utterance')}}
        try:
            text, task = self.kakao.handle(payload, memo_event='relay:' + item['id'])
        except PermissionError:
            text, task = 'PC 허용 목록에 없는 봇 또는 사용자입니다. PC 로컬 설정을 확인하세요.', None
        except ValueError:
            text, task = '입력 형식이나 요청키·작업 상태를 확인하세요.', None
        # sqlite3/OS errors propagate: no acknowledgement, so the lease expires and the item is retried.
        self.call('ack', {'id': item['id'], 'claim': item['claim'],
                          'taskId': task['id'] if task else None, 'reply': text[:1000]})

    def publish(self):
        watermark = self.store.setting(WATERMARK)
        published = 0
        while True:
            tasks = self.store.updated_since('kakao', watermark, overlap_seconds=OVERLAP_SECONDS, limit=200)
            snapshots, seen = [], set()
            for task in tasks:
                if task['id'] in seen or not task['actor'].startswith('kakao:'):
                    continue
                seen.add(task['id'])
                snapshots.append({'id': task['id'], 'actor': task['actor'],
                                  'statusText': self.kakao.status(task)[:1000], 'created': task['created']})
            if snapshots:
                self.call('publish', {'tasks': snapshots})
                published += len(snapshots)
            if not tasks:
                return published
            newest = tasks[-1]['updated']
            self.store.setting(WATERMARK, newest)
            if len(tasks) < 200 or newest == watermark:
                return published
            watermark = newest

    def step(self):
        handled = self.pull()
        self.publish()
        return handled
