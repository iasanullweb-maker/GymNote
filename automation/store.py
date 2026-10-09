import json
import sqlite3
import uuid
import time
from contextlib import contextmanager
from datetime import datetime, timezone

from automation.contracts.tasks import validate_input, validate_transition


def now():
    return datetime.now(timezone.utc).isoformat()


class Store:
    def __init__(self, path):
        self.path = str(path)
        with self.connect() as db:
            db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS tasks (
              id TEXT PRIMARY KEY, source TEXT NOT NULL, event TEXT NOT NULL,
              actor TEXT NOT NULL, project TEXT NOT NULL, text TEXT NOT NULL,
              status TEXT NOT NULL, created TEXT NOT NULL, updated TEXT NOT NULL,
              attempt TEXT, result TEXT, cancel INTEGER NOT NULL DEFAULT 0,
              UNIQUE(source,event));
            CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS history (
              task TEXT NOT NULL, time TEXT NOT NULL, status TEXT NOT NULL, attempt TEXT);
            CREATE TABLE IF NOT EXISTS commands (event TEXT PRIMARY KEY);
            CREATE TABLE IF NOT EXISTS telegram_targets (
              task TEXT PRIMARY KEY, chat INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS telegram_notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT, task TEXT NOT NULL, chat INTEGER NOT NULL,
              status TEXT NOT NULL, attempt TEXT, payload TEXT NOT NULL, created TEXT NOT NULL,
              delivery TEXT NOT NULL DEFAULT 'pending', tries INTEGER NOT NULL DEFAULT 0,
              next_try REAL NOT NULL DEFAULT 0);
            ''')
            columns = {row['name'] for row in db.execute('PRAGMA table_info(history)')}
            if 'result' not in columns:
                db.execute('ALTER TABLE history ADD COLUMN result TEXT')
            if 'intent' not in {row['name'] for row in db.execute('PRAGMA table_info(tasks)')}:
                db.execute('ALTER TABLE tasks ADD COLUMN intent TEXT')
                db.execute("UPDATE tasks SET intent=CASE WHEN status='memo' THEN 'memo' WHEN status!='cancelled' THEN 'execute' END")

    @staticmethod
    def record(db, task, status, attempt=None, result=None):
        db.execute('INSERT INTO history (task,time,status,attempt,result) VALUES (?,?,?,?,?)',
                   (task, now(), status, attempt,
                    json.dumps(result, ensure_ascii=False) if result is not None else None))
        if status not in ('completed', 'failed', 'waiting_user', 'cancelled'):
            return
        target = db.execute('SELECT chat FROM telegram_targets JOIN tasks ON task=id WHERE task=? AND intent=?',
                            (task, 'execute')).fetchone()
        if target:
            # Snapshot the event in the SAME transaction as task/history updates.
            # Do not copy summaries, ideas, findings or logs into notification payloads.
            value = result if isinstance(result, dict) else {}
            commit = value.get('commit')
            safe_commit = commit if isinstance(commit, str) and len(commit) == 40 and all(c in '0123456789abcdef' for c in commit) else None
            payload = {'integrated': value.get('integrated') is True, 'commit': safe_commit,
                       'checks': len(value['checks']) if isinstance(value.get('checks'), list) else 0,
                       'notRun': len(value['notRun']) if isinstance(value.get('notRun'), list) else 0}
            db.execute('INSERT INTO telegram_notifications (task,chat,status,attempt,payload,created) VALUES (?,?,?,?,?,?)',
                       (task, target['chat'], status, attempt, json.dumps(payload), now()))

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=30)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def create(self, source, event, actor, project, text, intent, *, telegram_chat=None):
        event, text = validate_input(source, event, actor, project, text, intent)
        if telegram_chat is not None and (source != 'telegram' or isinstance(telegram_chat, bool)
                or not isinstance(telegram_chat, int) or telegram_chat == 0 or not -(2**63) <= telegram_chat < 2**63):
            raise ValueError('Invalid Telegram notification chat')
        stamp = now()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            existing = db.execute('SELECT * FROM tasks WHERE source=? AND event=?', (source, event)).fetchone()
            if existing:
                item = self.decode(existing)
                if (item['actor'], item['project'], item['text']) != (actor, project, text) or (
                        item['intent'] is not None and item['intent'] != intent):
                    raise ValueError('Event already used for different input')
                target = db.execute('SELECT chat FROM telegram_targets WHERE task=?', (item['id'],)).fetchone()
                if target and telegram_chat is not None and target['chat'] != telegram_chat:
                    raise ValueError('Event already used in a different chat')
                # Do not attach routes to legacy tasks on replay or send historical alerts.
                return item
            db.execute('INSERT INTO tasks (id,source,event,actor,project,text,status,created,updated,attempt,intent) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                       (str(uuid.uuid4()), source, str(event), actor, project, text.strip(),
                        'memo' if intent == 'memo' else 'queued', stamp, stamp, None, intent))
            row = db.execute('SELECT * FROM tasks WHERE source=? AND event=?',
                             (source, str(event))).fetchone()
            if telegram_chat is not None:
                db.execute('INSERT INTO telegram_targets VALUES (?,?)', (row['id'], telegram_chat))
            self.record(db, row['id'], row['status'])
            return self.decode(row)

    @staticmethod
    def decode(row):
        if not row:
            return None
        item = dict(row)
        item['result'] = json.loads(item['result']) if item['result'] else None
        return item

    def get(self, task):
        with self.connect() as db:
            return self.decode(db.execute('SELECT * FROM tasks WHERE id=?', (task,)).fetchone())

    def list(self):
        with self.connect() as db:
            return [self.decode(r) for r in db.execute('SELECT * FROM tasks ORDER BY created DESC LIMIT 200')]

    def history(self, task):
        with self.connect() as db:
            return [self.decode(r) for r in db.execute(
                'SELECT time,status,attempt,result FROM history WHERE task=? ORDER BY rowid', (task,))]

    def claim(self):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute("SELECT id FROM tasks WHERE status='queued' AND cancel=0 ORDER BY created LIMIT 1").fetchone()
            if not row:
                return None
            attempt = str(uuid.uuid4())
            db.execute("UPDATE tasks SET status='planning',attempt=?,result=NULL,updated=? WHERE id=?", (attempt, now(), row['id']))
            self.record(db, row['id'], 'planning', attempt)
            return row['id']

    def state(self, task, status, result=None, *, attempt=None):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT * FROM tasks WHERE id=?', (task,)).fetchone()
            if not row:
                raise ValueError('Unknown task')
            if attempt is not None and row['attempt'] != attempt:
                raise ValueError('Stale execution attempt')
            validate_transition(row['status'], status, bool(row['cancel']))
            db.execute('UPDATE tasks SET status=?,updated=?,result=COALESCE(?,result) WHERE id=?',
                       (status, now(), json.dumps(result, ensure_ascii=False) if result is not None else None, task))
            self.record(db, task, status, row['attempt'], result)

    def cancel(self, task):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT * FROM tasks WHERE id=?', (task,)).fetchone()
            if not row:
                raise ValueError('Unknown task')
            db.execute("UPDATE tasks SET cancel=1,updated=?,status=CASE WHEN status IN ('memo','queued','waiting_user') THEN 'cancelled' ELSE status END WHERE id=? AND status NOT IN ('completed','failed','cancelled')", (now(), task))
            if row['status'] in ('memo', 'queued', 'waiting_user'):
                self.record(db, task, 'cancelled', row['attempt'])

    def recover(self):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            rows = db.execute("SELECT * FROM tasks WHERE status IN ('planning','running','reviewing','validating')").fetchall()
            for row in rows:
                result = json.loads(row['result']) if row['result'] else {}
                result.update(summary='Service restarted; inspect saved worktree before retry. No automatic replay.')
                result.setdefault('integrated', False)
                db.execute("UPDATE tasks SET status='waiting_user',updated=?,result=? WHERE id=?",
                           (now(), json.dumps(result), row['id']))
                self.record(db, row['id'], 'waiting_user', row['attempt'], result)

    def retry(self, task, event=None):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if event is not None:
                if not db.execute('INSERT OR IGNORE INTO commands VALUES (?)', (str(event),)).rowcount:
                    return
            changed = db.execute("UPDATE tasks SET status='queued',cancel=0,updated=? WHERE id=? AND status IN ('failed','waiting_user','cancelled')", (now(), task)).rowcount
            if not changed:
                raise ValueError('Task cannot be retried')
            row = db.execute('SELECT attempt,result FROM tasks WHERE id=?', (task,)).fetchone()
            self.record(db, task, 'queued', row['attempt'], json.loads(row['result']) if row['result'] else None)

    def offset(self, value=None):
        with self.connect() as db:
            if value is not None:
                db.execute("INSERT INTO settings VALUES ('telegram_offset',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (str(value),))
            row = db.execute("SELECT value FROM settings WHERE key='telegram_offset'").fetchone()
            return int(row[0]) if row else 0

    def notification_due(self, limit=10, *, at=None):
        at = time.time() if at is None else at
        with self.connect() as db:
            rows = db.execute("SELECT * FROM telegram_notifications WHERE delivery='pending' AND next_try<=? ORDER BY id LIMIT ?",
                              (at, limit)).fetchall()
            return [{**dict(row), 'payload': json.loads(row['payload'])} for row in rows]

    def notification_delivered(self, notification, *, suppressed=False):
        with self.connect() as db:
            db.execute("UPDATE telegram_notifications SET delivery=? WHERE id=? AND delivery='pending'",
                       ('suppressed' if suppressed else 'sent', notification))

    def notification_failed(self, notification, *, at=None):
        at = time.time() if at is None else at
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute("SELECT tries FROM telegram_notifications WHERE id=? AND delivery='pending'", (notification,)).fetchone()
            if row:
                # Persist retry delay, capped at five minutes. No raw API errors/tokens.
                tries = row['tries'] + 1
                delay = min(300, 10 * (2 ** min(tries - 1, 5)))
                db.execute('UPDATE telegram_notifications SET tries=?,next_try=? WHERE id=?', (tries, at + delay, notification))
