"""Read-only local preflight. No Telegram requests, agent execution, or token output."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from automation.service import load_config


def inspect(config, environment=None):
    environment = os.environ if environment is None else environment
    checks = []
    def record(name, ok, detail):
        checks.append({'name': name, 'ok': bool(ok), 'detail': detail})
    record('python', sys.version_info >= (3, 12), 'Python 3.12 or later required')
    for key in ('telegramEnabled', 'executionEnabled', 'telegramNotificationsEnabled'):
        record(key, isinstance(config.get(key, False if key != 'telegramNotificationsEnabled' else True), bool), 'Must be a JSON boolean')
    git_env = {key: value for key, value in environment.items() if not key.startswith('GIT_') and key not in ('TELEGRAM_BOT_TOKEN', 'GYMNOTE_AUTOMATION_ADMIN_TOKEN')}
    for project_id, project in config['projects'].items():
        try:
            result = subprocess.run(['git', '-C', project['path'], 'branch', '--show-current'],
                                    capture_output=True, text=True, timeout=10, env=git_env)
            ready = result.returncode == 0 and result.stdout.strip() == project.get('branch', 'main')
        except (OSError, subprocess.TimeoutExpired):
            ready = False
        record('project:' + project_id, ready, 'Configured Git integration branch must be checked out')
    token = environment.get('GYMNOTE_AUTOMATION_ADMIN_TOKEN', '')
    record('admin-token', len(token) >= 24, 'Set a random administrator token of at least 24 characters; value is never printed')
    if config.get('telegramEnabled') is True:
        users, chats = config.get('allowedUserIds'), config.get('allowedChatIds')
        record('telegram-users', isinstance(users, list) and bool(users) and all(type(v) is int and 0 < v < 2**63 for v in users), 'Nonempty numeric sender allowlist required')
        record('telegram-chats', isinstance(chats, list) and bool(chats) and all(type(v) is int and v != 0 and -(2**63) <= v < 2**63 for v in chats), 'Nonempty numeric chat allowlist required')
        record('telegram-token', bool(environment.get('TELEGRAM_BOT_TOKEN')), 'Bot token environment variable required; value is never printed')
    else:
        record('telegram', True, 'Disabled: no real bot reception or notification delivery')
    if config.get('executionEnabled') is True:
        executable = config.get('codexExecutable', '')
        record('codex-executable', isinstance(executable, str) and Path(executable).is_absolute() and Path(executable).is_file(), 'Existing absolute Codex executable path required')
    else:
        record('execution', True, 'Disabled: queued work will not launch an agent')
    return {'ok': all(item['ok'] for item in checks), 'checks': checks,
            'notChecked': ['Telegram token validity, webhook/polling conflicts and real delivery',
                           'Codex account authentication, quota and actual execution',
                           'Port availability, runtime directory permissions and live service status']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        result = inspect(load_config(args.config))
    except (OSError, ValueError, TypeError, KeyError):
        result = {'ok': False, 'error': 'Invalid or unreadable local configuration; no secrets were printed'}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
