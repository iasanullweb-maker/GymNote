import json
import os
from pathlib import Path
import signal
import subprocess
import time


class FileLock:
    """Use the repository integration lock convention; never remove another owner."""
    def __init__(self, path):
        self.path = Path(path)
        self.fd = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.write(self.fd, f'idea-automation pid={os.getpid()}'.encode())
        return self

    def __exit__(self, *args):
        if self.fd is not None:
            os.close(self.fd)
            self.path.unlink()


def git(root, *args):
    result = subprocess.run(['git', '-C', str(root), *args], capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError('Git command failed: ' + ' '.join(args[:2]))
    return result.stdout.strip()


def terminate(process):
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, timeout=30)
    else:
        os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        if os.name != 'nt':
            os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=10)


class Runner:
    def __init__(self, store, projects, runtime, codex, timeout=900):
        self.store, self.projects = store, projects
        self.runtime, self.codex, self.timeout = Path(runtime), codex, timeout

    def agent(self, task, root, prompt, output, readonly=False):
        if self.store.get(task)['cancel']:
            raise RuntimeError('cancelled')
        output.parent.mkdir(parents=True, exist_ok=True)
        args = [self.codex, 'exec', '--cd', str(root), '--sandbox',
                'read-only' if readonly else 'workspace-write', '--color', 'never',
                '--output-last-message', str(output), '-']
        schema = {'type': 'object', 'additionalProperties': False, 'properties': {
            'approved' if readonly else 'ready': {'type': 'boolean'},
            'findings' if readonly else 'checks': {'type': 'array', 'items': {'type': 'string'}}}}
        if not readonly:
            schema['properties'].update({'summary': {'type': 'string'}, 'notRun': {'type': 'array', 'items': {'type': 'string'}}})
        schema['required'] = list(schema['properties'])
        schema_path = output.with_suffix('.schema.json')
        schema_path.write_text(json.dumps(schema), encoding='utf-8')
        args[-1:-1] = ['--output-schema', str(schema_path)]
        if not readonly:
            args[-1:-1] = ['--approve-for-me']
        env = {k: v for k, v in os.environ.items() if k not in
               ('TELEGRAM_BOT_TOKEN', 'GYMNOTE_AUTOMATION_ADMIN_TOKEN')}
        # Agent output stays local; never send code/log contents to Telegram automatically.
        with output.with_suffix('.log').open('wb') as log:
            process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=log, stderr=log,
                                       env=env, start_new_session=(os.name != 'nt'))
            try:
                process.stdin.write(prompt.encode('utf-8'))
                process.stdin.close()
            except OSError:
                if process.poll() is None:
                    terminate(process)
                raise RuntimeError('Could not send request to Codex') from None
            deadline = time.monotonic() + self.timeout
            while process.poll() is None:
                if self.store.get(task)['cancel'] or time.monotonic() > deadline:
                    terminate(process)
                    raise RuntimeError('cancelled' if self.store.get(task)['cancel'] else 'Agent time limit exceeded')
                time.sleep(.25)
            if process.returncode:
                raise RuntimeError('Codex execution failed; inspect local attempt log')
        if not output.exists():
            raise RuntimeError('Codex did not produce a final response')
        return output.read_text(encoding='utf-8')

    def integrate(self, project, root, commit):
        main = Path(project['path']).resolve()
        with FileLock(main / '.validation-tools/ux-integration.lock'):
            if git(main, 'branch', '--show-current') != project.get('branch', 'main'):
                raise RuntimeError('Integration branch changed')
            if git(main, 'status', '--porcelain', '--untracked-files=no'):
                raise RuntimeError('Integration workspace has tracked uncommitted changes')
            for marker in ('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply'):
                if Path(git(main, 'rev-parse', '--path-format=absolute', '--git-path', marker)).exists():
                    raise RuntimeError('Integration workspace has an unfinished Git operation')
            base = git(main, 'rev-parse', 'HEAD')
            git(root, 'merge-base', '--is-ancestor', base, commit)
            # FF only: new main changes require a new review, never an unreviewed merge.
            git(main, 'merge', '--ff-only', commit)

    def once(self):
        task = self.store.claim()
        if not task:
            return False
        item = self.store.get(task)
        root = None
        integration_attempted = False
        commit = None
        result = {}
        try:
            project = self.projects[item['project']]
            main = Path(project['path']).resolve()
            base = git(main, 'rev-parse', project.get('branch', 'main'))
            root = self.runtime / 'worktrees' / item['attempt']
            root.parent.mkdir(parents=True, exist_ok=True)
            branch = 'codex/idea-' + item['attempt']
            git(main, 'worktree', 'add', '-b', branch, str(root), base)
            self.store.state(task, 'running', {'worktree': str(root), 'base': base, 'integrated': False}, attempt=item['attempt'])
            prompt = ('사용자가 텔레그램에서 승인한 로컬 저장소 작업입니다. 다음 아이디어를 구현하고 변경을 검토하고 '
                      '필요한 검사를 실행하세요. 담당 파일만 커밋하세요. 이 실행에서는 오케스트레이터가 통합하므로 '
                      'main 병합, 원격 push, 배포, 운영 DB 변경, 외부 메시지 발송은 수행하지 마세요. '
                      '판단이 필요하거나 검사할 수 없으면 변경을 보존하고 그 이유를 보고하세요. '
                      '최종 응답은 JSON만: {"ready":true/false,"summary":"...","checks":["실행한 검사와 결과"],'
                      '"notRun":["미실행 검사"]}. ready는 필요한 검사에 통과하고 커밋이 완료된 경우만 true.\n\n아이디어:\n' + item['text'])
            out = self.runtime / 'attempts' / item['attempt'] / 'result.json'
            result = json.loads(self.agent(task, root, prompt, out))
            if not isinstance(result, dict) or result.get('ready') is not True or not result.get('checks'):
                raise RuntimeError('Agent requires user review or has no validation evidence')
            if git(root, 'status', '--porcelain'):
                raise RuntimeError('Agent left uncommitted changes; inspect worktree')
            commit = git(root, 'rev-parse', 'HEAD')
            git(root, 'merge-base', '--is-ancestor', base, commit)
            git(root, 'diff', '--check', base, commit)
            self.store.state(task, 'reviewing', attempt=item['attempt'])
            review = json.loads(self.agent(task, root,
                f'Review all changes from {base} to HEAD. Check correctness, data preservation and security. '
                'Do not change files or execute external writes. Return JSON only: '
                '{"approved":true/false,"findings":["actionable findings"]}. Approve only with no actionable findings.',
                out.with_name('review.json'), readonly=True))
            if review.get('approved') is not True or review.get('findings') != []:
                raise RuntimeError('Independent review requires attention')
            if git(root, 'rev-parse', 'HEAD') != commit or git(root, 'status', '--porcelain'):
                raise RuntimeError('Worktree changed during review; inspect before integration')
            git(root, 'diff', '--check', base, commit)
            self.store.state(task, 'validating', attempt=item['attempt'])
            if self.store.get(task)['cancel']:
                raise RuntimeError('cancelled')
            integrated = False
            if project.get('autoIntegrate', False):
                integration_attempted = True
                self.integrate(project, root, commit)
                integrated = True
            self.store.state(task, 'completed' if integrated else 'waiting_user',
                             {'summary': result.get('summary'), 'checks': result['checks'],
                              'notRun': result.get('notRun', []), 'commit': commit,
                              'worktree': str(root), 'integrated': integrated}, attempt=item['attempt'])
        except Exception as error:
            cancelled = self.store.get(task)['cancel']
            # Subprocess/OSError strings may include paths; all artifacts stay on disk.
            summary = str(error)[:300] if isinstance(error, RuntimeError) else 'Execution failed; inspect local attempt artifacts'
            integrated = False
            if integration_attempted and commit:
                try:
                    git(main, 'merge-base', '--is-ancestor', commit, 'HEAD')
                    integrated = True
                except Exception:
                    pass
            self.store.state(task, 'cancelled' if cancelled else 'waiting_user',
                             {'summary': summary, 'worktree': str(root) if root else None,
                              'commit': commit, 'checks': result.get('checks', []) if isinstance(result, dict) else [],
                              'notRun': result.get('notRun', []) if isinstance(result, dict) else [],
                              'integrated': integrated}, attempt=item['attempt'])
        return True
