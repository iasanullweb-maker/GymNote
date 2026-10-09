// dry-run 결과를 사람이 읽는 Markdown 요약으로 만든다.
// 실행 결과가 없으므로 문제·개선안·성공률을 만들어 내지 않는다.

function cell(value) {
  return String(value ?? '—').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function table(headers, rows) {
  return [
    `| ${headers.join(' | ')} |`,
    `| ${headers.map(() => '---').join(' | ')} |`,
    ...rows.map((r) => `| ${r.map(cell).join(' | ')} |`),
  ].join('\n');
}

export function renderSummary(run, plan) {
  const code = run.code.status === 'ok'
    ? `${run.code.commit}${run.code.dirty ? ' (추적 파일에 미커밋 변경 있음)' : ''}`
    : `확인 불가 — ${run.code.reason}`;
  const captureStatus = { pending: 0, captured: 0, failed: 0 };
  for (const c of run.captures) captureStatus[c.status] += 1;

  const lines = [];
  lines.push(`# UX 시뮬레이션 dry-run 요약: ${run.runId}`);
  lines.push('');
  lines.push('> 이 문서는 **가상(합성) 실행 계획**이다. 모델 호출과 앱 조작을 하지 않았고 평가 결과가 없다.');
  lines.push('> 세션 수는 합성 실행 수이며 실제 사용자 수·비율·만족도·작업 소요시간이 아니다.');
  lines.push('> 이후 실행 결과가 생기더라도 결론에는 사람 검증이 필요하다.');
  lines.push('');
  lines.push('## 실행 정보');
  lines.push('');
  lines.push(table(['항목', '값'], [
    ['실행 모드', run.mode],
    ['생성 시각(UTC)', run.createdAt],
    ['실행 코드 SHA', code],
    ['캡처 manifest appCommit', run.inputs.captureManifest.appCommit ?? 'null (캡처 미실행 또는 미기록)'],
    ['프롬프트 버전', run.promptVersion],
    ['모델', 'null (호출 안 함)'],
    ['실행기', `${run.generator.name} ${run.generator.version}, Node ${run.generator.node}`],
  ]));
  lines.push('');
  lines.push('## 합성 실행 수');
  lines.push('');
  lines.push(table(['항목', '수'], [
    ['persona', run.plan.personaCount],
    ['scenario', run.plan.scenarioCount],
    ['반복', run.plan.repeat],
    ['계획된 합성 세션', run.plan.sessionCount],
    ['실행된 세션', 0],
    ['미실행(not-run) 세션', run.plan.sessionCount],
    ['모델 요청', 0],
  ]));
  lines.push('');
  lines.push('## 입력 파일');
  lines.push('');
  const inputRows = [
    ...run.inputs.personas.map((p) => ['persona', p.id, p.path, p.sha256]),
    ...run.inputs.scenarios.map((s) => ['scenario', s.id, s.path, s.sha256]),
    ['capture manifest', '—', run.inputs.captureManifest.path, run.inputs.captureManifest.sha256],
    ...run.prompts.map((p) => [`${p.role} 프롬프트`, p.status, p.path, p.sha256 ?? '없음']),
  ];
  lines.push(table(['종류', 'ID/상태', '경로', 'SHA-256'], inputRows));
  lines.push('');
  lines.push(`## 캡처 상태 (captured ${captureStatus.captured}, pending ${captureStatus.pending}, failed ${captureStatus.failed})`);
  lines.push('');
  lines.push(`계획에 사용한 변형: ${run.captureVariant.width}×${run.captureVariant.height}pt, textScale=${run.captureVariant.textScale}`);
  lines.push('');
  lines.push(table(['capture ID', '변형', '상태', '증거'], run.captures.map((c) => [
    c.id,
    `${c.width}×${c.height}/${c.textScale}`,
    c.status,
    c.status === 'captured' ? `${c.evidencePath} (SHA 확인)` : `${c.status} — 이미지 없음${c.error ? `: ${c.error}` : ''}`,
  ])));
  lines.push('');
  lines.push('## 미실행 검사');
  lines.push('');
  lines.push('모든 검사는 근거가 없으므로 `not-evaluated`다. 화면 증거만으로 app-state·manual 검사를 통과 처리하지 않는다.');
  lines.push('');
  lines.push(table(['scenario', 'check', 'kind', '결과', '사유'], run.notRunChecks.map((c) => [
    c.scenarioId, c.checkId, c.kind, 'not-evaluated', c.reason,
  ])));
  lines.push('');
  lines.push('## 발견한 문제와 개선안');
  lines.push('');
  lines.push('없음. 실행 결과가 없어 문제나 개선안을 작성하지 않았다.');
  lines.push('');
  if (run.warnings.length > 0) {
    lines.push('## 경고');
    lines.push('');
    for (const w of run.warnings) lines.push(`- ${cell(w)}`);
    lines.push('');
  }
  lines.push('## 세션 파일');
  lines.push('');
  lines.push(`sessions/ 아래 ${plan.entries.length}개. 전체 목록과 화면별 캡처 상태는 plan.json에 있다.`);
  lines.push('');
  lines.push('## 후속 연결 경계');
  lines.push('');
  for (const b of run.boundaries) lines.push(`- ${b}`);
  lines.push('');
  return lines.join('\n');
}
