"""Prepare a local manual-relay pilot; never contact a device or model."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', default='usb-pilot-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    args = parser.parse_args()
    if not re.fullmatch(r'usb-pilot-[A-Za-z0-9-]+', args.run_id):
        parser.error('run-id must start with usb-pilot- and contain only letters, numbers or hyphens')
    root = Path(__file__).resolve().parent.parent
    source = root / 'docs/ux-simulation/pilot'
    plan = json.loads((source / 'plan.json').read_text(encoding='utf-8'))
    user_prompt = (source / 'user.md').read_text(encoding='utf-8')
    viewer_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    output = root / 'simulation/runs' / args.run_id
    output.mkdir(parents=True, exist_ok=False)
    metadata = {
        'format': plan['format'], 'runId': args.run_id, 'synthetic': True,
        'status': 'prepared', 'outcome': 'not-evaluated',
        'createdAt': datetime.now(timezone.utc).isoformat(),
        'appCommit': None, 'viewerCommit': viewer_commit,
        'environment': {'appBuild': None, 'osBuild': None, 'screenSize': None,
                        'textScale': None, 'inputRotation': 270, 'initialStateVerified': False},
        'model': None, 'usage': {'requests': None, 'tokens': None},
        'plan': plan,
    }
    (output / 'pilot.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output / 'actions.jsonl').write_text('', encoding='utf-8')
    for user in plan['users']:
        for index, goal in enumerate(user['goals'], 1):
            # Only role, current screen placeholder and goal; no evaluator checks.
            text = user_prompt + '\n<persona>\n' + user['context'] + '\n</persona>\n'
            text += '<currentScreen>\n미제공: 현재 화면이 없으면 stop. 부모가 검증한 화면으로 교체한다.\n</currentScreen>\n'
            text += '<userGoal>\n' + goal + '\n</userGoal>\n'
            (output / f"{user['id']}-task-{index}.md").write_text(text, encoding='utf-8')
    (output / 'planner.md').write_text((source / 'planner.md').read_text(encoding='utf-8'), encoding='utf-8')
    print(output)
    print('Prepared only: no model requests, device input, screenshots or UX results.')


if __name__ == '__main__':
    main()
