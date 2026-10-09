import os
import json
from automation.service import load_config
from pathlib import Path
import unittest
from unittest.mock import patch

from automation.check import inspect
from automation.tests import test_automation as baseline


class PreflightTests(unittest.TestCase):
    setUp = baseline.Tests.setUp
    tearDown = baseline.Tests.tearDown
    repository = baseline.Tests.repository

    def config(self):
        return {'projects': {'gymnote': {'path': str(self.repository()), 'branch': 'main'}},
                'telegramEnabled': False, 'executionEnabled': False}

    def environment(self):
        return {**os.environ, 'GYMNOTE_AUTOMATION_ADMIN_TOKEN': 'synthetic-secret-token-123456'}

    def test_disabled_features_check_without_network_or_agents_and_hide_token(self):
        with patch('urllib.request.urlopen', side_effect=AssertionError('No network')):
            result = inspect(self.config(), self.environment())
        self.assertTrue(result['ok'])
        self.assertNotIn('synthetic-secret-token', str(result))
        self.assertIn('notChecked', result)

    def test_missing_enabled_credentials_and_invalid_allowlists_fail(self):
        config = self.config()
        config.update(telegramEnabled=True, executionEnabled=True, allowedUserIds=[True], allowedChatIds=[0], codexExecutable='missing')
        environment = self.environment()
        environment.pop('TELEGRAM_BOT_TOKEN', None)
        result = inspect(config, environment)
        self.assertFalse(result['ok'])
        failures = {entry['name'] for entry in result['checks'] if not entry['ok']}
        self.assertTrue({'telegram-users', 'telegram-chats', 'telegram-token', 'codex-executable'} <= failures)

    def test_valid_local_configuration_does_not_claim_real_authentication(self):
        config = self.config()
        executable = self.root / 'synthetic-agent.exe'
        executable.write_text('not executable: existence check only')
        config.update(telegramEnabled=True, executionEnabled=True, allowedUserIds=[123], allowedChatIds=[-456], codexExecutable=str(executable))
        environment = {**self.environment(), 'TELEGRAM_BOT_TOKEN': 'synthetic-bot-secret'}
        result = inspect(config, environment)
        self.assertTrue(result['ok'])
        self.assertNotIn('synthetic-bot-secret', str(result))
        self.assertTrue(any('actual execution' in value for value in result['notChecked']))

    def test_wrong_integration_branch_and_nonboolean_flags_fail(self):
        config = self.config()
        config['projects']['gymnote']['branch'] = 'wrong-branch'
        config['executionEnabled'] = 'true'
        result = inspect(config, self.environment())
        self.assertFalse(result['ok'])
        self.assertFalse(next(entry for entry in result['checks'] if entry['name'] == 'project:gymnote')['ok'])

    def test_service_rejects_string_flags_before_starting(self):
        config = self.config()
        config['defaultProject'] = 'gymnote'
        config['telegramEnabled'] = 'false'
        file = self.root / 'synthetic-config.json'
        file.write_text(json.dumps(config))
        with self.assertRaisesRegex(ValueError, 'JSON booleans'):
            load_config(file)

    def test_inherited_git_overrides_do_not_redirect_preflight(self):
        config = self.config()
        environment = {**self.environment(), 'GIT_DIR': str(self.root / 'nonexistent')}
        self.assertTrue(inspect(config, environment)['ok'])


if __name__ == '__main__':
    unittest.main()
