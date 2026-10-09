// 입력·출력 경로를 작업 루트 안으로 제한하고 심볼릭 링크를 거부한다.
import fs from 'node:fs';
import path from 'node:path';

export class RunnerError extends Error {
  /** @param {string} code 기계가 읽는 오류 분류 @param {string} message 사람이 읽는 설명 */
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/** target이 base와 같거나 그 아래에 있으면 true. */
export function isInside(base, target) {
  const rel = path.relative(base, target);
  if (rel === '') return true;
  if (path.isAbsolute(rel)) return false; // Windows에서 드라이브가 다른 경우
  return rel !== '..' && !rel.startsWith(`..${path.sep}`);
}

/** 보고서에 남길 루트 기준 POSIX 상대 경로. */
export function toPosixRelative(root, target) {
  return path.relative(root, target).split(path.sep).join('/');
}

export function realRoot(root) {
  let real;
  try {
    real = fs.realpathSync(path.resolve(root));
  } catch {
    throw new RunnerError('root-missing', `작업 루트를 찾을 수 없다: ${root}`);
  }
  if (!fs.statSync(real).isDirectory()) {
    throw new RunnerError('root-missing', `작업 루트가 폴더가 아니다: ${root}`);
  }
  return real;
}

/**
 * base부터 target까지의 기존 경로 요소 중 심볼릭 링크(Windows junction 포함)가 있으면 거부한다.
 * 존재하지 않는 요소에서 멈춘다(생성 예정 출력 경로 검사에 사용).
 */
export function assertNoLinks(base, target, label) {
  if (!isInside(base, target)) {
    throw new RunnerError('path-escape', `${label}: 허용된 루트 밖의 경로다 (${target})`);
  }
  const parts = path.relative(base, target).split(path.sep).filter(Boolean);
  let current = base;
  for (const part of parts) {
    current = path.join(current, part);
    let st;
    try {
      st = fs.lstatSync(current);
    } catch (err) {
      if (err.code === 'ENOENT') return;
      throw err;
    }
    if (st.isSymbolicLink()) {
      throw new RunnerError('symlink', `${label}: 심볼릭 링크는 허용하지 않는다 (${toPosixRelative(base, current)})`);
    }
  }
  // 위 검사로 대부분 막히지만, 해석 결과도 루트 안인지 한 번 더 확인한다.
  if (fs.existsSync(target)) {
    const real = fs.realpathSync(target);
    if (!isInside(base, real)) {
      throw new RunnerError('path-escape', `${label}: 실제 위치가 허용된 루트 밖이다`);
    }
  }
}

/** 사용자가 준 입력 경로(루트 기준 상대 또는 루트 안 절대)를 검사해 절대 경로로 돌려준다. */
export function resolveInput(root, input, label) {
  if (typeof input !== 'string' || input.length === 0 || input.includes('\0')) {
    throw new RunnerError('usage', `${label}: 경로가 비어 있거나 잘못됐다`);
  }
  const abs = path.resolve(root, input);
  if (!isInside(root, abs)) {
    throw new RunnerError('path-escape', `${label}: 작업 루트 밖의 입력은 읽지 않는다 (${input})`);
  }
  assertNoLinks(root, abs, label);
  if (!fs.existsSync(abs)) {
    throw new RunnerError('missing-file', `${label}: 파일 또는 폴더가 없다 (${toPosixRelative(root, abs)})`);
  }
  return abs;
}

const WINDOWS_ABSOLUTE = /^[a-zA-Z]:|^[\\/]{2}/;

/**
 * capture manifest의 relativePath를 manifest 폴더 기준으로 해석한다.
 * 절대 경로, 드라이브 문자, 역슬래시, '.'/'..' 요소, 심볼릭 링크를 모두 거부한다.
 */
export function resolveManifestRelative(root, manifestDir, relativePath, label) {
  if (typeof relativePath !== 'string' || relativePath.length === 0 || relativePath.includes('\0')) {
    throw new RunnerError('path-escape', `${label}: relativePath가 비어 있거나 잘못됐다`);
  }
  if (relativePath.includes('\\')) {
    throw new RunnerError('path-escape', `${label}: relativePath는 '/' 구분자만 사용한다 (${relativePath})`);
  }
  if (relativePath.startsWith('/') || WINDOWS_ABSOLUTE.test(relativePath) || path.isAbsolute(relativePath)) {
    throw new RunnerError('path-escape', `${label}: 절대 경로는 허용하지 않는다 (${relativePath})`);
  }
  const segments = relativePath.split('/');
  if (segments.some((s) => s === '' || s === '.' || s === '..')) {
    throw new RunnerError('path-escape', `${label}: '.', '..', 빈 경로 요소는 허용하지 않는다 (${relativePath})`);
  }
  const abs = path.resolve(manifestDir, ...segments);
  if (!isInside(manifestDir, abs) || !isInside(root, abs)) {
    throw new RunnerError('path-escape', `${label}: manifest 폴더 밖을 가리킨다 (${relativePath})`);
  }
  assertNoLinks(manifestDir, abs, label);
  return abs;
}
