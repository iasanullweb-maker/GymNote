// JSON Schema 2020-12의 "부분 집합" 검증기.
// simulation/contracts/*.schema.json 이 실제로 사용하는 키워드만 지원한다.
// 지원하지 않는 키워드가 스키마에 추가되면 조용히 무시하지 않고 예외를 던져
// 계약 변경을 실행기가 놓치지 않도록 한다.

export const SUPPORTED_KEYWORDS = Object.freeze([
  '$schema', 'title',
  'type', 'const', 'enum',
  'pattern', 'minLength',
  'minimum', 'maximum',
  'minItems', 'uniqueItems', 'items',
  'required', 'properties', 'additionalProperties',
  'allOf', 'if', 'then',
]);

const SUPPORTED = new Set(SUPPORTED_KEYWORDS);
const SCHEMA_VALUED = new Set(['items', 'if', 'then']);

export class UnsupportedSchemaError extends Error {}

/** 스키마 전체에 지원하지 않는 키워드가 없는지 확인한다. */
export function assertSupportedSchema(schema, at = '#') {
  if (typeof schema !== 'object' || schema === null || Array.isArray(schema)) {
    throw new UnsupportedSchemaError(`${at}: 스키마는 객체여야 한다`);
  }
  for (const key of Object.keys(schema)) {
    if (!SUPPORTED.has(key)) {
      throw new UnsupportedSchemaError(`${at}: 지원하지 않는 스키마 키워드 '${key}'`);
    }
  }
  if (schema.additionalProperties !== undefined && schema.additionalProperties !== false) {
    throw new UnsupportedSchemaError(`${at}: additionalProperties는 false만 지원한다`);
  }
  for (const key of SCHEMA_VALUED) {
    if (schema[key] !== undefined) assertSupportedSchema(schema[key], `${at}/${key}`);
  }
  if (schema.properties) {
    for (const [name, sub] of Object.entries(schema.properties)) {
      assertSupportedSchema(sub, `${at}/properties/${name}`);
    }
  }
  if (schema.allOf) {
    schema.allOf.forEach((sub, i) => assertSupportedSchema(sub, `${at}/allOf/${i}`));
  }
}

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (typeof value === 'number') return Number.isInteger(value) ? 'integer' : 'number';
  return typeof value; // string, boolean, object
}

function matchesType(value, type) {
  const actual = typeOf(value);
  if (type === 'number') return actual === 'number' || actual === 'integer';
  return actual === type;
}

function same(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

/**
 * value를 schema로 검사하고 오류 메시지 배열을 돌려준다(비어 있으면 통과).
 * 타입별 키워드(pattern, minimum 등)는 JSON Schema 의미대로 해당 타입일 때만 적용한다.
 */
export function validate(schema, value, at = '$') {
  const errors = [];
  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((t) => matchesType(value, t))) {
      errors.push(`${at}: 타입은 ${types.join('|')} 이어야 한다 (실제 ${typeOf(value)})`);
      return errors;
    }
  }
  if (schema.const !== undefined && !same(schema.const, value)) {
    errors.push(`${at}: 값은 ${JSON.stringify(schema.const)} 이어야 한다`);
  }
  if (schema.enum !== undefined && !schema.enum.some((v) => same(v, value))) {
    errors.push(`${at}: 허용 값 ${schema.enum.map((v) => JSON.stringify(v)).join(', ')} 중 하나여야 한다`);
  }
  if (typeof value === 'string') {
    if (schema.minLength !== undefined && [...value].length < schema.minLength) {
      errors.push(`${at}: 길이는 ${schema.minLength} 이상이어야 한다`);
    }
    if (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value)) {
      errors.push(`${at}: 형식 ${schema.pattern} 와 맞지 않는다`);
    }
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${at}: ${schema.minimum} 이상이어야 한다`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${at}: ${schema.maximum} 이하여야 한다`);
    }
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${at}: 항목이 ${schema.minItems}개 이상이어야 한다`);
    }
    if (schema.uniqueItems === true) {
      const seen = new Set();
      value.forEach((item, i) => {
        const key = JSON.stringify(item);
        if (seen.has(key)) errors.push(`${at}[${i}]: 중복 항목`);
        seen.add(key);
      });
    }
    if (schema.items !== undefined) {
      value.forEach((item, i) => errors.push(...validate(schema.items, item, `${at}[${i}]`)));
    }
  }
  if (typeOf(value) === 'object') {
    for (const key of schema.required ?? []) {
      if (!Object.hasOwn(value, key)) errors.push(`${at}: 필수 필드 '${key}' 누락`);
    }
    const props = schema.properties ?? {};
    for (const [key, sub] of Object.entries(props)) {
      if (Object.hasOwn(value, key)) errors.push(...validate(sub, value[key], `${at}.${key}`));
    }
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) {
        if (!Object.hasOwn(props, key)) errors.push(`${at}: 허용되지 않은 필드 '${key}'`);
      }
    }
  }
  for (const sub of schema.allOf ?? []) {
    errors.push(...validate(sub, value, at));
  }
  if (schema.if !== undefined && validate(schema.if, value, at).length === 0 && schema.then !== undefined) {
    errors.push(...validate(schema.then, value, at));
  }
  return errors;
}
