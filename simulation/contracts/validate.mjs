import { readFileSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';

export const CAPTURE_IDS = Object.freeze([
  'workout-ready', 'workout-active', 'workout-rest', 'plan-month',
  'plan-date-detail', 'records-overview', 'journal-calendar', 'journal-entry',
  'friends-home', 'friends-ranking',
]);
const schemaNames = ['persona', 'scenario', 'capture-manifest', 'session'];
const schemas = new Map(schemaNames.map(name => [name,
  JSON.parse(readFileSync(new URL(name + '.schema.json', import.meta.url), 'utf8'))]));
const supported = new Set(['$schema', 'title', 'description', 'type', 'const', 'enum',
  'required', 'properties', 'additionalProperties', 'items', 'minItems', 'maxItems',
  'uniqueItems', 'minLength', 'pattern', 'minimum', 'maximum', 'allOf', 'if', 'then']);

export class ContractError extends Error {
  constructor(message) { super(message); this.name = 'ContractError'; }
}
const fail = (path, message) => { throw new ContractError(path + ': ' + message); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const has = (value, key) => Object.prototype.hasOwnProperty.call(value, key);

// Implements the keywords used by these four contracts, not general JSON Schema.
// Reject unsupported schema keywords before evaluating conditional branches.
function assertSupported(schema, path = '$schema') {
  if (!object(schema)) fail(path, 'schema must be an object');
  for (const key of Object.keys(schema)) if (!supported.has(key)) fail(path, 'unsupported keyword ' + key);
  for (const [key, child] of Object.entries(schema.properties ?? {})) assertSupported(child, path + '.' + key);
  if (schema.items) assertSupported(schema.items, path + '.items');
  for (const child of schema.allOf ?? []) assertSupported(child, path + '.allOf');
  for (const key of ['if', 'then']) if (schema[key]) assertSupported(schema[key], path + '.' + key);
}
function matchesType(value, kind) {
  if (kind === 'null') return value === null;
  if (kind === 'array') return Array.isArray(value);
  if (kind === 'object') return object(value);
  if (kind === 'integer') return Number.isInteger(value);
  if (kind === 'number') return typeof value === 'number' && Number.isFinite(value);
  return typeof value === kind;
}
function check(schema, value, path) {
  if (schema.type && ![].concat(schema.type).some(kind => matchesType(value, kind))) fail(path, 'wrong type');
  if (has(schema, 'const') && !isDeepStrictEqual(value, schema.const)) fail(path, 'wrong constant');
  if (schema.enum && !schema.enum.some(item => isDeepStrictEqual(value, item))) fail(path, 'unknown enum value');
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && [...value].length < schema.minLength) fail(path, 'string too short');
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) fail(path, 'invalid string pattern');
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) fail(path, 'non-finite number');
    if (schema.minimum !== undefined && value < schema.minimum) fail(path, 'below minimum');
    if (schema.maximum !== undefined && value > schema.maximum) fail(path, 'above maximum');
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) fail(path, 'too few items');
    if (schema.maxItems !== undefined && value.length > schema.maxItems) fail(path, 'too many items');
    if (schema.uniqueItems && value.some((item, i) => value.slice(0, i).some(prior => isDeepStrictEqual(item, prior)))) fail(path, 'duplicate item');
    if (schema.items) value.forEach((item, i) => check(schema.items, item, path + '[' + i + ']'));
  }
  if (object(value)) {
    for (const key of schema.required ?? []) if (!has(value, key)) fail(path, 'missing ' + key);
    for (const [key, item] of Object.entries(value)) {
      if (has(schema.properties ?? {}, key)) check(schema.properties[key], item, path + '.' + key);
      else if (schema.additionalProperties === false) fail(path, 'unexpected ' + key);
    }
  }
  for (const child of schema.allOf ?? []) check(child, value, path);
  if (schema.if) {
    let condition = true;
    try { check(schema.if, value, path); } catch (error) { if (!(error instanceof ContractError)) throw error; condition = false; }
    if (condition && schema.then) check(schema.then, value, path);
  }
}
export function validateSchema(schema, value) {
  assertSupported(schema); check(schema, value, '$'); return value;
}
function uniqueIds(items, path) {
  const ids = new Set();
  for (const item of items) { if (ids.has(item.id)) fail(path, 'duplicate ID ' + item.id); ids.add(item.id); }
  return ids;
}
export function validateRelativePath(value) {
  if (typeof value !== 'string' || !value.trim() || /[:\\]/.test(value) || value.startsWith('/') || value.includes('\0')
      || value.split('/').some(part => !part || part === '..' || part === '.')) fail('relativePath', 'must be a contained POSIX relative path');
  return value;
}
export function validateDocument(kind, value) {
  if (!schemas.has(kind)) fail('kind', 'unknown document type');
  validateSchema(schemas.get(kind), value);
  if (kind === 'scenario') {
    uniqueIds(value.checks, 'checks');
    if (!value.captureIds.includes(value.startCaptureId)) fail('startCaptureId', 'not listed in captureIds');
    for (const id of value.captureIds) if (!CAPTURE_IDS.includes(id)) fail('captureIds', 'unknown screen ' + id);
  }
  if (kind === 'capture-manifest') {
    const variants = new Set();
    const groups = new Map();
    for (const capture of value.captures) {
      if (!CAPTURE_IDS.includes(capture.id)) fail('captures', 'unknown screen ' + capture.id);
      const variant = [capture.id, capture.width, capture.height, capture.textScale].join(':');
      if (variants.has(variant)) fail('captures', 'duplicate variant ' + variant);
      variants.add(variant);
      const group = [capture.width, capture.height, capture.textScale].join(':');
      if (!groups.has(group)) groups.set(group, new Set());
      groups.get(group).add(capture.id);
      if (capture.relativePath !== undefined) validateRelativePath(capture.relativePath);
      if (capture.status === 'captured' && value.appCommit === null) fail('appCommit', 'captured image needs actual app commit');
    }
    if (![...groups.values()].some(ids => CAPTURE_IDS.every(id => ids.has(id)))) fail('captures', 'no complete ten-screen device variant');
  }
  if (kind === 'session') {
    uniqueIds(value.checks, 'checks');
    if (value.status === 'not-run' && (value.outcome !== 'not-evaluated' || value.observations.length || value.checks.some(c => c.result !== 'not-evaluated'))) fail('status', 'not-run cannot contain evaluated results');
    if (value.mode === 'dry-run' && (value.status !== 'not-run' || value.model !== null || value.usage.requests !== 0
        || [value.usage.inputTokens, value.usage.outputTokens].some(n => n !== null && n !== 0))) fail('mode', 'dry-run cannot claim model calls or completed evaluation');
    for (const result of value.checks) if (result.result !== 'not-evaluated' && !result.evidence.length) fail('checks', 'evaluated result needs evidence');
    if (value.outcome === 'success' && (value.status !== 'completed' || !value.checks.length || value.checks.some(c => c.result !== 'pass'))) fail('outcome', 'success needs completed passing checks');
  }
  return value;
}
export function validatePanel({ personas, scenarios, manifest }) {
  if (!Array.isArray(personas) || !personas.length || !Array.isArray(scenarios) || !scenarios.length) fail('panel', 'requires personas and scenarios');
  personas.forEach(p => validateDocument('persona', p));
  scenarios.forEach(s => validateDocument('scenario', s));
  validateDocument('capture-manifest', manifest);
  uniqueIds(personas, 'personas'); uniqueIds(scenarios, 'scenarios');
  const captureIds = new Set(manifest.captures.map(c => c.id));
  for (const scenario of scenarios) for (const id of scenario.captureIds) if (!captureIds.has(id)) fail('captureIds', 'missing screen ' + id);
  return { personas: personas.length, scenarios: scenarios.length, combinations: personas.length * scenarios.length };
}
export function validateSession(session, scenario) {
  validateDocument('session', session); validateDocument('scenario', scenario);
  if (session.scenarioId !== scenario.id) fail('scenarioId', 'does not match scenario');
  if (session.checks.length !== scenario.checks.length || scenario.checks.some(check => !session.checks.some(result => result.id === check.id))) fail('checks', 'must include every scenario check exactly once');
  for (const result of session.checks) {
    const definition = scenario.checks.find(check => check.id === result.id);
    if (session.mode === 'screen-review' && definition.kind === 'app-state' && result.result !== 'not-evaluated') fail('checks', 'screen-review cannot evaluate app-state');
  }
  let prior = 0;
  for (const observation of session.observations) {
    if (observation.step <= prior || observation.step > scenario.maxSteps) fail('observations', 'steps must increase and stay within budget');
    if (!scenario.captureIds.includes(observation.captureId) || !scenario.allowedActionTypes.includes(observation.action)) fail('observations', 'screen or action not allowed by scenario');
    prior = observation.step;
  }
  return session;
}
