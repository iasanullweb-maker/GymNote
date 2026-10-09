// persona / scenario / capture manifest 입력을 읽고 공통 계약 v1로 검증한다.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertSupportedSchema, validate } from './schema.mjs';
import {
  RunnerError, assertNoLinks, resolveInput, resolveManifestRelative, toPosixRelative,
} from './paths.mjs';

export const CODE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
export const CONTRACTS_DIR = path.join(CODE_ROOT, 'simulation', 'contracts');

/** CONTRACT.md의 고정 화면 ID 10개. */
export const FIXED_CAPTURE_IDS = Object.freeze([
  'workout-ready', 'workout-active', 'workout-rest',
  'plan-month', 'plan-date-detail',
  'records-overview',
  'journal-calendar', 'journal-entry',
  'friends-home', 'friends-ranking',
]);
export const DEFAULT_VARIANT = Object.freeze({ width: 834, height: 1194, textScale: 'standard' });

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** 입력에 토큰·개인정보로 보이는 문자열이 섞이면 거부한다(합성 데이터만 받는다). */
const SENSITIVE_PATTERNS = [
  ['JWT 형태 토큰', /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/],
  ['API 키 형태 문자열', /\b(?:sk|rk|pk)-[A-Za-z0-9_-]{16,}/],
  ['GitHub 토큰 형태 문자열', /\bgh[pousr]_[A-Za-z0-9]{20,}/],
  ['Supabase 비밀 키 형태 문자열', /\bsb_secret_[A-Za-z0-9_-]{8,}|service_role/i],
  ['AWS 액세스 키 형태 문자열', /\bAKIA[0-9A-Z]{16}\b/],
  ['이메일 주소', /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/],
  ['전화번호', /\b01[016789][-\s]?\d{3,4}[-\s]?\d{4}\b/],
];

const schemaCache = new Map();
export function loadSchema(name) {
  if (!schemaCache.has(name)) {
    const file = path.join(CONTRACTS_DIR, `${name}.schema.json`);
    let schema;
    try {
      schema = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (err) {
      throw new RunnerError('contract-missing', `공통 계약 스키마를 읽을 수 없다: simulation/contracts/${name}.schema.json (${err.message})`);
    }
    assertSupportedSchema(schema, `${name}.schema.json`);
    schemaCache.set(name, schema);
  }
  return schemaCache.get(name);
}

export function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function readJsonFile(root, file) {
  const rel = toPosixRelative(root, file);
  const st = fs.lstatSync(file);
  if (st.isSymbolicLink()) throw new RunnerError('symlink', `${rel}: 심볼릭 링크는 읽지 않는다`);
  if (!st.isFile()) throw new RunnerError('invalid-input', `${rel}: 일반 파일이 아니다`);
  const bytes = fs.readFileSync(file);
  let text = bytes.toString('utf8');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  let data;
  try {
    data = JSON.parse(text);
  } catch (err) {
    throw new RunnerError('invalid-json', `${rel}: JSON 형식 오류 (${err.message})`);
  }
  return { file, rel, sha256: sha256(bytes), data };
}

function scanSensitive(value, where, errors) {
  if (typeof value === 'string') {
    for (const [label, re] of SENSITIVE_PATTERNS) {
      if (re.test(value)) errors.push(`${where}: ${label}로 보이는 값이 있다. 합성 데이터만 입력한다`);
    }
  } else if (Array.isArray(value)) {
    value.forEach((v, i) => scanSensitive(v, `${where}[${i}]`, errors));
  } else if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      scanSensitive(k, `${where}{key}`, errors);
      scanSensitive(v, `${where}.${k}`, errors);
    }
  }
}

/** 폴더면 바로 아래의 *.json(하위 폴더 제외), 파일이면 그 파일 하나를 읽는다. */
function loadCollection(root, input, label) {
  const abs = resolveInput(root, input, label);
  const st = fs.statSync(abs);
  let files;
  if (st.isDirectory()) {
    files = fs.readdirSync(abs, { withFileTypes: true })
      .filter((d) => d.name.toLowerCase().endsWith('.json'))
      .map((d) => path.join(abs, d.name))
      .sort();
    for (const f of files) assertNoLinks(root, f, label);
  } else {
    files = [abs];
  }
  if (files.length === 0) {
    throw new RunnerError('missing-file', `${label}: JSON 파일이 없다 (${toPosixRelative(root, abs)})`);
  }
  return files.map((f) => readJsonFile(root, f));
}

function collect(errors, prefix, list) {
  for (const e of list) errors.push(`${prefix} ${e}`);
}

function checkUniqueIds(items, label, errors) {
  const seen = new Map();
  for (const item of items) {
    const id = item.data?.id;
    if (typeof id !== 'string') continue;
    if (seen.has(id)) errors.push(`${label} ID 중복 '${id}': ${seen.get(id)}, ${item.rel}`);
    else seen.set(id, item.rel);
  }
}

export function loadPersonas(root, input) {
  const schema = loadSchema('persona');
  const items = loadCollection(root, input, 'persona 입력');
  const errors = [];
  for (const item of items) {
    collect(errors, `${item.rel}`, validate(schema, item.data));
    scanSensitive(item.data, item.rel, errors);
  }
  checkUniqueIds(items, 'persona', errors);
  return { items, errors };
}

export function loadScenarios(root, input) {
  const schema = loadSchema('scenario');
  const items = loadCollection(root, input, 'scenario 입력');
  const errors = [];
  for (const item of items) {
    const before = errors.length;
    collect(errors, `${item.rel}`, validate(schema, item.data));
    scanSensitive(item.data, item.rel, errors);
    if (errors.length > before) continue;
    const s = item.data;
    if (!s.captureIds.includes(s.startCaptureId)) {
      errors.push(`${item.rel}: startCaptureId '${s.startCaptureId}'가 captureIds에 없다`);
    }
    const checkIds = new Set();
    for (const check of s.checks) {
      if (checkIds.has(check.id)) errors.push(`${item.rel}: 검사 ID 중복 '${check.id}'`);
      checkIds.add(check.id);
      if (check.description.trim().length === 0) {
        errors.push(`${item.rel}: 검사 '${check.id}'의 성공 조건 설명이 비어 있다`);
      }
    }
    if (s.userGoal.trim().length === 0) errors.push(`${item.rel}: userGoal이 비어 있다`);
  }
  checkUniqueIds(items, 'scenario', errors);
  return { items, errors };
}

export function variantKey(c) {
  return `${c.width}x${c.height}/${c.textScale}`;
}

/**
 * capture manifest를 검사한다. 같은 ID는 width/height/textScale 조합으로 구분하고,
 * captured 항목은 PNG 존재·서명·SHA-256을 실제 파일로 확인한다.
 */
export function loadCaptureManifest(root, input) {
  const schema = loadSchema('capture-manifest');
  const manifestPath = resolveInput(root, input, 'capture manifest');
  if (!fs.statSync(manifestPath).isFile()) {
    throw new RunnerError('invalid-input', 'capture manifest: 파일 경로를 지정해야 한다');
  }
  const item = readJsonFile(root, manifestPath);
  const manifestDir = path.dirname(manifestPath);
  const errors = [];
  const warnings = [];
  collect(errors, item.rel, validate(schema, item.data));
  scanSensitive(item.data, item.rel, errors);
  const captures = [];
  if (errors.length > 0) return { item, captures, errors, warnings, variant: null };

  const known = new Set(FIXED_CAPTURE_IDS);
  const seenVariant = new Set();
  const byVariant = new Map();
  item.data.captures.forEach((c, i) => {
    const where = `${item.rel} captures[${i}] (${c.id} ${variantKey(c)})`;
    if (!known.has(c.id)) {
      errors.push(`${where}: 계약에 없는 capture ID`);
      return;
    }
    const key = `${c.id}@${variantKey(c)}`;
    if (seenVariant.has(key)) {
      errors.push(`${where}: 같은 ID·크기·글씨 조합이 중복됐다`);
      return;
    }
    seenVariant.add(key);
    if (!byVariant.has(variantKey(c))) {
      byVariant.set(variantKey(c), { width: c.width, height: c.height, textScale: c.textScale, ids: new Set() });
    }
    byVariant.get(variantKey(c)).ids.add(c.id);

    const record = {
      id: c.id, width: c.width, height: c.height, textScale: c.textScale,
      status: c.status, evidencePath: null, sha256: null, error: c.error ?? null,
    };
    if (c.status === 'captured') {
      try {
        const png = resolveManifestRelative(root, manifestDir, c.relativePath, where);
        let st;
        try {
          st = fs.lstatSync(png);
        } catch {
          throw new RunnerError('missing-file', `${where}: 이미지 파일이 없다 (${c.relativePath})`);
        }
        if (!st.isFile()) throw new RunnerError('invalid-input', `${where}: 이미지가 일반 파일이 아니다`);
        const bytes = fs.readFileSync(png);
        if (bytes.length < 8 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
          throw new RunnerError('invalid-input', `${where}: PNG 파일 서명이 아니다`);
        }
        const actual = sha256(bytes);
        if (actual !== c.sha256) {
          throw new RunnerError('sha-mismatch', `${where}: SHA-256 불일치 (manifest ${c.sha256}, 실제 ${actual})`);
        }
        record.evidencePath = toPosixRelative(root, png);
        record.sha256 = actual;
      } catch (err) {
        if (!(err instanceof RunnerError)) throw err;
        errors.push(err.message);
      }
    } else {
      if (c.relativePath !== undefined || c.sha256 !== undefined) {
        warnings.push(`${where}: status=${c.status} 이므로 relativePath/sha256을 증거로 사용하지 않는다`);
      }
      if (c.status === 'failed' && !c.error) warnings.push(`${where}: failed 캡처에 error 설명이 없다`);
    }
    captures.push(record);
  });

  // 최소 한 변형(크기·글씨 조합)에서 고정 ID 10개가 모두 있어야 한다. 기본 변형을 우선한다.
  const complete = [...byVariant.values()].filter((v) => FIXED_CAPTURE_IDS.every((id) => v.ids.has(id)));
  let variant = null;
  if (complete.length === 0) {
    errors.push(`${item.rel}: 고정 capture ID 10개를 모두 가진 크기·글씨 변형이 없다`);
  } else {
    const preferred = complete.find((v) => variantKey(v) === variantKey(DEFAULT_VARIANT)) ?? complete[0];
    variant = { width: preferred.width, height: preferred.height, textScale: preferred.textScale };
  }
  return { item, captures, errors, warnings, variant, manifestDir };
}

/** 시나리오의 capture 참조가 manifest에 있는지 확인한다. */
export function crossCheck(scenarios, manifest) {
  const errors = [];
  const ids = new Set(manifest.captures.map((c) => c.id));
  for (const item of scenarios.items) {
    for (const id of item.data.captureIds ?? []) {
      if (!ids.has(id)) errors.push(`${item.rel}: capture manifest에 없는 capture ID '${id}'`);
    }
  }
  return errors;
}

/** 프롬프트 파일을 해시한다. dry-run에서는 없어도 실패하지 않고 missing으로 기록한다. */
export function hashPrompts(root, promptVersion) {
  const out = [];
  for (const role of ['user', 'planner']) {
    const rel = `simulation/prompts/${role}-${promptVersion}.md`;
    const abs = path.join(root, ...rel.split('/'));
    assertNoLinks(root, abs, `${role} 프롬프트`);
    if (fs.existsSync(abs) && fs.statSync(abs).isFile()) {
      out.push({ role, path: rel, status: 'present', sha256: sha256(fs.readFileSync(abs)) });
    } else {
      out.push({ role, path: rel, status: 'missing', sha256: null });
    }
  }
  return out;
}
