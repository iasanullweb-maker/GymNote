"""Shared v1 task validation and state transitions (no channel or agent dependencies)."""

SOURCES = frozenset(('telegram', 'web', 'mock'))
ACTIVE = frozenset(('planning', 'running', 'reviewing', 'validating'))
TRANSITIONS = {
    'memo': {'cancelled'},
    'queued': {'planning', 'cancelled'},
    'planning': {'running', 'waiting_user', 'failed', 'cancelled'},
    'running': {'reviewing', 'waiting_user', 'failed', 'cancelled'},
    'reviewing': {'validating', 'waiting_user', 'failed', 'cancelled'},
    'validating': {'completed', 'waiting_user', 'failed', 'cancelled'},
    'waiting_user': {'queued', 'cancelled'},
    'failed': {'queued'},
    'cancelled': {'queued'},
    'completed': set(),
}


def identifier(value, name, maximum=200):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise ValueError('Invalid ' + name)
    if value != value.strip() or any(ord(char) < 32 for char in value):
        raise ValueError('Invalid ' + name)
    return value


def validate_input(source, event, actor, project, text, intent):
    if not isinstance(source, str) or source not in SOURCES:
        raise ValueError('Invalid source')
    # Telegram update IDs are integers; booleans are never valid event IDs.
    if isinstance(event, int) and not isinstance(event, bool) and event >= 0:
        event = str(event)
    event = identifier(event, 'event')
    identifier(actor, 'actor')
    identifier(project, 'project', 100)
    if not isinstance(text, str) or not text.strip() or len(text) > 8000 or '\x00' in text:
        raise ValueError('Invalid idea')
    if not isinstance(intent, str) or intent not in ('memo', 'execute'):
        raise ValueError('Invalid intent')
    return event, text.strip()


def validate_transition(current, target, cancelled=False):
    if not isinstance(target, str) or target not in TRANSITIONS.get(current, set()):
        raise ValueError('Invalid task transition')
    if cancelled and target not in ('cancelled', 'waiting_user', 'failed'):
        raise ValueError('Cancellation pending')
