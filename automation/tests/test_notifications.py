import json
import sqlite3
import unittest
from unittest.mock import patch

from automation.store import Store
from automation.ingress.telegram import Telegram
from automation.tests import test_automation as baseline


class NotificationTests(unittest.TestCase):
    setUp = baseline.Tests.setUp
    tearDown = baseline.Tests.tearDown
    update = baseline.Tests.update
    repository = baseline.Tests.repository
    runner = baseline.Tests.runner

    def queued(self, event=1, chat=456):
        self.bot.accept(self.update('/run synthetic change', event=event, chat=chat))
        return self.store.list()[0]['id']

    def completed(self, task):
        self.store.claim()
        for status in ('running', 'reviewing', 'validating'):
            self.store.state(task, status)
        self.store.state(task, 'completed', {'integrated': True, 'commit': 'a' * 40,
            'checks': ['synthetic passed'], 'notRun': [], 'summary': 'DO NOT SEND PRIVATE SUMMARY'})

    def test_success_records_event_and_sends_once_to_original_chat(self):
        task = self.queued()
        self.completed(task)
        event = self.store.notification_due()[0]
        self.assertEqual((event['task'], event['chat'], event['status']), (task, 456, 'completed'))
        sent = []
        self.bot.call = lambda method, data: sent.append((method, data))
        self.assertEqual(self.bot.deliver_notifications(), 1)
        self.assertEqual(self.bot.deliver_notifications(), 0)
        self.assertEqual(sent[0][0], 'sendMessage')
        self.assertEqual(sent[0][1]['chat_id'], 456)
        self.assertIn('로컬 main 통합 완료', sent[0][1]['text'])
        self.assertNotIn('PRIVATE', sent[0][1]['text'])
        self.assertEqual(self.store.notification_due(), [])

    def test_real_isolated_git_flow_enqueues_completion_after_merge(self):
        task = self.queued()
        root = self.repository()
        self.runner(root).once()
        event = self.store.notification_due()[0]
        self.assertEqual(self.store.get(task)['status'], 'completed')
        self.assertTrue(event['payload']['integrated'])
        self.assertEqual(len(event['payload']['commit']), 40)
        self.assertEqual((root / 'file.txt').read_text(), 'changed')

    def test_failed_review_notifies_waiting_user_without_private_findings(self):
        task = self.queued()
        self.runner(self.repository(), approved=False).once()
        event = self.store.notification_due()[0]
        self.assertEqual(event['status'], 'waiting_user')
        text = self.bot.notification_text(event)
        self.assertIn('사용자 확인 필요', text)
        self.assertNotIn('unsafe change', text)
        self.assertNotIn(str(self.root), text)
        self.assertEqual(self.store.get(task)['status'], 'waiting_user')

    def test_web_and_memo_tasks_do_not_send_automatic_alerts(self):
        web = self.store.create('web', 'web-event', 'admin', 'gymnote', 'synthetic', 'execute')['id']
        self.completed(web)
        self.bot.accept(self.update('synthetic memo', event=2))
        memo = next(t for t in self.store.list() if t['status'] == 'memo')
        self.store.cancel(memo['id'])
        self.assertEqual(self.store.notification_due(), [])

    def test_cancel_only_alerts_after_actual_stop(self):
        task = self.queued()
        self.store.claim()
        self.store.cancel(task)
        self.assertEqual(self.store.notification_due(), [])
        self.store.state(task, 'cancelled')
        self.assertEqual(self.store.notification_due()[0]['status'], 'cancelled')
        self.store.cancel(task)
        self.assertEqual(len(self.store.notification_due()), 1)

    def test_queued_cancel_persists_alert(self):
        task = self.queued()
        self.store.cancel(task)
        self.assertEqual(self.store.notification_due()[0]['status'], 'cancelled')

    def test_failure_backoff_and_restart_preserve_notification(self):
        task = self.queued()
        self.completed(task)
        self.bot.call = lambda method, data: (_ for _ in ()).throw(RuntimeError('synthetic offline'))
        with patch('automation.store.time.time', return_value=100):
            self.assertEqual(self.bot.deliver_notifications(), 0)
        reloaded = Store(self.root / 'data.sqlite3')
        self.assertEqual(reloaded.notification_due(at=109), [])
        due = reloaded.notification_due(at=110)
        self.assertEqual(due[0]['tries'], 1)
        reloaded.notification_failed(due[0]['id'], at=110)
        self.assertEqual(reloaded.notification_due(at=129), [])
        self.assertEqual(reloaded.notification_due(at=130)[0]['tries'], 2)
        self.assertEqual(reloaded.get(task)['status'], 'completed')

    def test_current_allowlists_are_rechecked_without_sending(self):
        for index, (users, chats) in enumerate([([999], [456]), ([123], [999])], 1):
            task = self.queued(event=index)
            self.completed(task)
            with self.subTest(users=users):
                bot = Telegram('synthetic-token', users, chats, 'gymnote', self.store)
                bot.call = lambda *args: self.fail('Revoked route must not send')
                self.assertEqual(bot.deliver_notifications(), 0)
        self.assertEqual(self.store.notification_due(), [])
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT delivery FROM telegram_notifications').fetchone()[0], 'suppressed')

    def test_retry_keeps_separate_attempt_alerts_and_safe_snapshots(self):
        task = self.queued()
        self.store.claim()
        first = self.store.get(task)['attempt']
        self.store.state(task, 'waiting_user', {'summary': 'private log'}, attempt=first)
        self.store.retry(task)
        self.completed(task)
        events = self.store.notification_due()
        self.assertEqual([e['status'] for e in events], ['waiting_user', 'completed'])
        self.assertNotEqual(events[0]['attempt'], events[1]['attempt'])
        self.assertNotIn('private log', json.dumps(events))
        self.assertFalse(events[0]['payload']['integrated'])
        self.assertTrue(events[1]['payload']['integrated'])

    def test_route_replay_cannot_redirect_and_legacy_tasks_do_not_get_routes(self):
        task = self.queued()
        self.bot.chats.add(789)
        with self.assertRaises(ValueError):
            self.bot.accept(self.update('/run synthetic change', event=1, chat=789))
        self.bot.accept(self.update('/run synthetic change', event=1))
        self.completed(task)
        self.assertEqual(len(self.store.notification_due()), 1)
        legacy = self.store.create('telegram', 2, 'telegram:123', 'gymnote', 'legacy', 'execute')['id']
        self.bot.accept(self.update('/run legacy', event=2))
        self.completed(legacy)
        self.assertEqual(len(self.store.notification_due()), 1)

    def test_atomic_state_and_outbox_rollback_when_recording_fails(self):
        task = self.queued()
        self.store.claim()
        with self.store.connect() as db:
            db.execute("CREATE TRIGGER fail_outbox BEFORE INSERT ON telegram_notifications BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.state(task, 'waiting_user')
        self.assertEqual(self.store.get(task)['status'], 'planning')
        self.assertEqual(self.store.history(task)[-1]['status'], 'planning')
        self.assertEqual(self.store.notification_due(), [])

    def test_restart_recovery_enqueues_once_and_keeps_existing_artifacts(self):
        task = self.queued()
        self.store.claim()
        self.store.state(task, 'running', {'worktree': 'synthetic-path', 'base': 'synthetic-base'})
        self.store.recover()
        Store(self.root / 'data.sqlite3').recover()
        self.assertEqual(len(self.store.notification_due()), 1)
        self.assertEqual(self.store.get(task)['result']['worktree'], 'synthetic-path')

    def test_failed_status_and_untrusted_commit_do_not_leak_text(self):
        task = self.queued()
        self.store.claim()
        self.store.state(task, 'failed', {'commit': 'bot-token-secret', 'summary': 'private',
            'checks': ['private check'], 'notRun': ['private reason']})
        event = self.store.notification_due()[0]
        self.assertEqual(event['payload']['commit'], None)
        self.assertNotIn('private', self.bot.notification_text(event))
        self.assertIn('작업 실패', self.bot.notification_text(event))

    def test_invalid_allowlists_rejected_when_constructing_live_receiver(self):
        for users, chats in [([True], [456]), ([123], [False]), (['123'], [456]), ([123], ['456'])]:
            with self.assertRaises(ValueError):
                Telegram('synthetic-token', users, chats, 'gymnote', self.store)

    def test_invalid_route_metadata_rejected_before_task_creation(self):
        for value in [True, 0, '456', 2**63]:
            with self.assertRaises(ValueError):
                self.store.create('telegram', 'event', 'telegram:123', 'gymnote', 'idea', 'execute', telegram_chat=value)
        with self.assertRaises(ValueError):
            self.store.create('web', 'event', 'admin', 'gymnote', 'idea', 'execute', telegram_chat=456)
        self.assertEqual(self.store.list(), [])


if __name__ == '__main__':
    unittest.main()
