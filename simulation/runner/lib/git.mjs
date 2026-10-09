// 실제 코드 SHA 기록. git을 찾지 못하면 값을 지어내지 않고 unavailable로 남긴다.
import { execFileSync } from 'node:child_process';

function git(root, args) {
  return execFileSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  }).trim();
}

export function readCodeCommit(root) {
  try {
    const top = git(root, ['rev-parse', '--show-toplevel']);
    const commit = git(root, ['rev-parse', 'HEAD']);
    if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error('예상하지 못한 SHA 형식');
    const dirty = git(root, ['status', '--porcelain', '--untracked-files=no']).length > 0;
    return { status: 'ok', commit, dirty, toplevel: top, reason: null };
  } catch (err) {
    const reason = (err.stderr?.toString().trim() || err.message || 'git 실행 실패').split('\n')[0];
    return { status: 'unavailable', commit: null, dirty: null, toplevel: null, reason };
  }
}
