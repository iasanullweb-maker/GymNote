// 세션 JSON 생성과 상태 판정 규칙 검사.
import { validate } from './schema.mjs';
import { loadSchema } from './inputs.mjs';

/** 세션 파일 이름과 세션 runId에 쓰는 반복 단위 식별자. */
export function sessionKey(personaId, scenarioId, iteration) {
  return `${personaId}--${scenarioId}--r${iteration}`;
}

/**
 * dry-run 세션. 모델·앱 조작을 수행하지 않았으므로 관찰은 비어 있고
 * 모든 검사는 근거 없이 not-evaluated로 남는다. 결과를 만들어 내지 않는다.
 */
export function buildDryRunSession({ runId, persona, scenario, iteration, appCommit, promptVersion }) {
  return {
    schemaVersion: 1,
    runId: `${runId}/${sessionKey(persona.id, scenario.id, iteration)}`,
    personaId: persona.id,
    scenarioId: scenario.id,
    mode: 'dry-run',
    synthetic: true,
    appCommit,
    promptVersion,
    model: null,
    status: 'not-run',
    outcome: 'not-evaluated',
    observations: [],
    checks: scenario.checks.map((check) => ({ id: check.id, result: 'not-evaluated', evidence: [] })),
    usage: { requests: 0, inputTokens: 0, outputTokens: 0 },
  };
}

/**
 * 세션이 계약 스키마와 CONTRACT.md의 평가 의미를 지키는지 검사한다.
 * 실행기가 만든 세션과 후속 단계(live 연결)에서 받을 세션 모두에 적용한다.
 * @returns {string[]} 오류 목록(비어 있으면 통과)
 */
export function assessSession(session, scenario, { personaId } = {}) {
  const errors = validate(loadSchema('session'), session).map((e) => `스키마 ${e}`);
  if (errors.length > 0) return errors;
  const s = session;

  if (personaId !== undefined && s.personaId !== personaId) errors.push(`personaId '${s.personaId}'가 계획 '${personaId}'와 다르다`);
  if (s.scenarioId !== scenario.id) errors.push(`scenarioId '${s.scenarioId}'가 시나리오 '${scenario.id}'와 다르다`);

  // 검사 목록은 시나리오의 검사와 정확히 일치해야 한다(누락·추가·중복 금지).
  const kinds = new Map(scenario.checks.map((c) => [c.id, c.kind]));
  const seen = new Set();
  for (const c of s.checks) {
    if (!kinds.has(c.id)) errors.push(`시나리오에 없는 검사 '${c.id}'`);
    if (seen.has(c.id)) errors.push(`검사 '${c.id}' 중복`);
    seen.add(c.id);
  }
  for (const id of kinds.keys()) if (!seen.has(id)) errors.push(`검사 '${id}' 결과 누락`);

  for (const c of s.checks) {
    const kind = kinds.get(c.id);
    if (c.result !== 'not-evaluated' && c.evidence.length === 0) {
      errors.push(`검사 '${c.id}'=${c.result} 인데 증거 경로가 없다`);
    }
    if (kind === 'manual' && c.result !== 'not-evaluated') {
      errors.push(`manual 검사 '${c.id}'는 사람 확인 전까지 not-evaluated여야 한다`);
    }
    if (kind === 'app-state' && c.result !== 'not-evaluated' && (s.mode === 'dry-run' || s.mode === 'screen-review')) {
      errors.push(`${s.mode}에서는 app-state 검사 '${c.id}'를 ${c.result}로 판정할 수 없다`);
    }
  }

  const results = s.checks.map((c) => c.result);
  if (s.status === 'not-run') {
    if (s.outcome !== 'not-evaluated') errors.push('status=not-run 이면 outcome=not-evaluated 여야 한다');
    if (s.observations.length > 0) errors.push('status=not-run 인데 관찰 기록이 있다');
    if (results.some((r) => r !== 'not-evaluated')) errors.push('status=not-run 인데 판정된 검사가 있다');
    if (s.usage.requests !== 0) errors.push('status=not-run 인데 모델 요청 수가 0이 아니다');
  }
  if ((s.outcome === 'success' || s.outcome === 'failure') && s.status !== 'completed') {
    errors.push(`outcome=${s.outcome} 은 status=completed 에서만 가능하다`);
  }
  if (s.outcome === 'success') {
    if (results.includes('fail')) errors.push('실패한 검사가 있는데 outcome=success 다');
    if (!results.includes('pass')) errors.push('통과한 검사 근거 없이 outcome=success 다');
  }
  if (s.outcome === 'failure' && !results.includes('fail')) {
    errors.push('실패한 검사 근거 없이 outcome=failure 다');
  }

  if (s.mode === 'dry-run') {
    if (s.status !== 'not-run') errors.push('dry-run 은 status=not-run 이어야 한다');
    if (s.model !== null) errors.push('dry-run 은 model=null 이어야 한다');
    if (s.usage.requests !== 0) errors.push('dry-run 은 usage.requests=0 이어야 한다');
    if (s.usage.inputTokens || s.usage.outputTokens) errors.push('dry-run 은 토큰 사용량이 0 또는 null 이어야 한다');
  } else if (s.usage.requests > 0 && s.model === null) {
    errors.push('모델 요청이 있는데 model 이 null 이다');
  }

  // 관찰은 1부터 순서대로, 시나리오가 허용한 화면·행동만 사용한다.
  if (s.observations.length > scenario.maxSteps) {
    errors.push(`관찰 단계 수 ${s.observations.length} 가 maxSteps ${scenario.maxSteps} 를 넘는다`);
  }
  s.observations.forEach((o, i) => {
    if (o.step !== i + 1) errors.push(`관찰 ${i}: step 은 ${i + 1} 이어야 한다`);
    if (!scenario.captureIds.includes(o.captureId)) errors.push(`관찰 ${o.step}: 시나리오에 없는 화면 '${o.captureId}'`);
    if (!scenario.allowedActionTypes.includes(o.action)) errors.push(`관찰 ${o.step}: 허용되지 않은 행동 '${o.action}'`);
  });
  return errors;
}
