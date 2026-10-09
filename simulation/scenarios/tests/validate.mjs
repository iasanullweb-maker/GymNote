import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

// Dependency-free validator for the keywords actually used by the v1 input schemas.
// Fail closed if the shared schemas introduce an unsupported keyword.
const root = fileURLToPath(new URL('../../../', import.meta.url));
const load = path => JSON.parse(readFileSync(root + path, 'utf8'));
const text = path => readFileSync(root + path, 'utf8');
const keywords = new Set(['$schema','title','type','additionalProperties','required','properties','const','enum','pattern','minLength','minItems','uniqueItems','items','minimum','maximum']);
function validate(schema, value, at = '$') {
  for (const key of Object.keys(schema)) assert(keywords.has(key), 'Unsupported schema keyword ' + key);
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (schema.type) assert(types.some(type =>
    type === 'object' ? value !== null && typeof value === 'object' && !Array.isArray(value) :
    type === 'array' ? Array.isArray(value) :
    type === 'integer' ? Number.isInteger(value) :
    type === 'null' ? value === null : typeof value === type), at + ' type');
  if ('const' in schema) assert(isDeepStrictEqual(value, schema.const), at + ' const');
  if (schema.enum) assert(schema.enum.some(item => isDeepStrictEqual(value, item)), at + ' enum');
  if (schema.pattern) assert(new RegExp(schema.pattern).test(value), at + ' pattern');
  if (schema.minLength !== undefined) assert([...value].length >= schema.minLength, at + ' minLength');
  if (schema.minimum !== undefined) assert(value >= schema.minimum, at + ' minimum');
  if (schema.maximum !== undefined) assert(value <= schema.maximum, at + ' maximum');
  if (schema.required) for (const key of schema.required) assert(Object.hasOwn(value, key), at + ' missing ' + key);
  if (schema.additionalProperties === false) for (const key of Object.keys(value)) assert(Object.hasOwn(schema.properties, key), at + ' unknown ' + key);
  if (schema.properties) for (const [key, child] of Object.entries(schema.properties)) if (Object.hasOwn(value, key)) validate(child, value[key], at + '.' + key);
  if (schema.minItems !== undefined) assert(value.length >= schema.minItems, at + ' minItems');
  if (schema.uniqueItems) assert.equal(new Set(value.map(item => JSON.stringify(item))).size, value.length, at + ' uniqueItems');
  if (schema.items) value.forEach((item, i) => validate(schema.items, item, at + '[' + i + ']'));
}
const contract = text('docs/ux-simulation/CONTRACT.md');
const captures = [...contract.matchAll(/^\| ([a-z][a-z0-9-]*) \|/gm)].map(match => match[1]);
assert.equal(captures.length, 10, 'Contract must define exactly 10 capture IDs');
const personaSchema = load('simulation/contracts/persona.schema.json');
const scenarioSchema = load('simulation/contracts/scenario.schema.json');
const readInputs = folder => readdirSync(root + folder).filter(name => name.endsWith('.json')).sort().map(name => {
  const data = load(folder + '/' + name); assert.equal(name, data.id + '.json'); return data;
});
const personas = readInputs('simulation/personas');
const scenarios = readInputs('simulation/scenarios');
assert.equal(personas.length, 4); assert.equal(scenarios.length, 5);
assert.equal(new Set(personas.map(p => p.id)).size, 4);
assert.equal(new Set(scenarios.map(s => s.id)).size, 5);
function validatePersona(persona) {
  validate(personaSchema, persona);
  assert(!/(?:남성|여성|소년|소녀|나이|[0-9]+세(?:의|인|\s))/u.test(JSON.stringify(persona)), 'Stereotyped demographic conditions');
}
function validateScenario(scenario) {
  validate(scenarioSchema, scenario);
  assert(captures.includes(scenario.startCaptureId), 'Unknown start capture');
  assert(scenario.captureIds.includes(scenario.startCaptureId), 'Missing starting screen');
  scenario.captureIds.forEach(id => assert(captures.includes(id), 'Unknown capture ' + id));
  assert.equal(new Set(scenario.checks.map(c => c.id)).size, scenario.checks.length, 'Duplicate check ID');
  assert(scenario.checks.some(c => c.kind === 'app-state'), 'Missing state check');
  assert(scenario.checks.some(c => c.kind === 'observation-only'), 'Missing observation check');
  assert(!/(?:왼쪽|오른쪽|상단|하단|버튼|클릭|누르|눌러|AppModel|captureIds|checks|→|①|\b(?:tap|click)\b)/iu.test(scenario.userGoal), 'User goal leaks an answer/path');
}
personas.forEach(validatePersona);
scenarios.forEach(validateScenario);
assert.equal(new Set(scenarios.flatMap(s => s.captureIds)).size, 10, 'Cover all contract screens');
assert(scenarios.find(s => s.id === 'start-and-record-set').userGoal.includes('2026년 10월 12일'));
assert(scenarios.find(s => s.id === 'record-previous-workout').userGoal.includes('2026년 10월 11일'));
assert(scenarios.find(s => s.id === 'return-to-selected-plan').userGoal.includes('2026년 10월 14일'));
const readme = text('simulation/scenarios/README.md');
const pairs = [...readme.matchAll(/^\| ([a-z][a-z0-9-]*) \| ([a-z][a-z0-9-]*) \|$/gm)].map(m => [m[1], m[2]]);
assert.equal(pairs.length, 7);
assert.equal(new Set(pairs.map(p => p.join('/'))).size, pairs.length);
pairs.forEach(([p,s]) => {
  assert(personas.some(persona => persona.id === p), 'Unknown persona reference ' + p);
  assert(scenarios.some(scenario => scenario.id === s), 'Unknown scenario reference ' + s);
});
assert.equal(new Set(pairs.map(p => p[0])).size, 4);
assert.equal(new Set(pairs.map(p => p[1])).size, 5);
const user = text('simulation/prompts/user-v1.md');
const planner = text('simulation/prompts/planner-v1.md');
assert.deepEqual([...user.matchAll(/\{\{([a-zA-Z]+)\}\}/g)].map(m => m[1]), ['persona','currentScreen','userGoal'], 'Only three permitted user inputs');
for (const required of ['screen-review','dry-run','내부 사고 과정','짧은 관찰','not-evaluated']) assert((user + planner).includes(required));
for (const required of ['status=not-run','outcome=not-evaluated','model=null','usage.requests=0','app-state','manual','재검증','합성 실행 수']) assert(planner.includes(required), 'Missing planner boundary ' + required);
function validateReportingText(value) {
  assert(!/(?:실제 사용자|발생률|성공률).{0,16}[0-9]+\s*%/u.test(value), 'Synthetic repetitions reported as real-user rates');
}
validateReportingText(JSON.stringify({personas,scenarios}) + user + planner + readme);
let negativeCases = 0;
function rejects(mutant, check) { assert.throws(() => check(mutant)); negativeCases++; }
const clone = value => structuredClone(value);
// Explicitly synthetic, in-memory mutations; these are validator tests, never UX outcomes.
rejects({...personas[0],synthetic:false}, validatePersona);
const missing = clone(personas[0]); delete missing.attention; rejects(missing, validatePersona);
rejects({...personas[0],age:30}, validatePersona);
rejects({...scenarios[0],fixtureId:'live'}, validateScenario);
rejects({...scenarios[0],captureIds:['secret-screen']}, validateScenario);
rejects({...scenarios[0],userGoal:'오른쪽 버튼을 클릭하세요'}, validateScenario);
rejects({...scenarios[0],checks:[]}, validateScenario);
rejects({...scenarios[0],checks:scenarios[0].checks.filter(c=>c.kind==='observation-only')}, validateScenario);
rejects({...scenarios[0],checks:scenarios[0].checks.filter(c=>c.kind==='app-state')}, validateScenario);
rejects({...scenarios[0],personaId:personas[0].id}, validateScenario);
rejects('실제 사용자 성공률 80%', validateReportingText);
console.log(JSON.stringify({validation:'pass',personas:4,scenarios:5,personaScenarioPairs:pairs.length,captureIds:captures.length,negativeCases,uxExecution:'not-run',outcome:'not-evaluated',model:null,requests:0}, null, 2));
