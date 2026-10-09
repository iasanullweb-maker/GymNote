# C: 가상 사용자·시나리오 결과

작업 기준: 2026-10-09. 담당 워크트리 `C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/ux-scenarios`, 브랜치 `codex/ux-scenarios`, 준비 커밋 `174da81`에서 시작했다. 시작 시 브랜치·실제 경로·git status·git worktree list를 확인했고 워크트리는 깨끗했다.

## 변경

- simulation/personas/: 합성 사용자 4개. 앱 첫 기록, 운동 중 주의 분산, 지난 운동 일괄 기록, 친구 경쟁 첫 사용의 경험·목표·주의·읽기 조건만 지정했다. 연령·성별 고정관념을 사용하지 않았다.
- simulation/scenarios/: 계약 스키마에 맞는 5개 JSON과 평가자 전용 README. 운동 시작/실제 횟수/세트 완료, 다른 분야 확인 후 계획 복귀, 지난 운동 입력, 편집 취소, 친구 요청/공개 끄기를 다룬다.
- simulation/prompts/: user-v1.md, planner-v1.md. 사용자 입력은 persona+현재 화면+userGoal만이며 checks·평가자 사전조건·구현·정답 경로는 제외한다. 기획 검토는 실행 후 증거·짧은 관찰 메모만 받아 문제/근거/개선안/재검증으로 작성한다.
- simulation/scenarios/tests/validate.mjs: 외부 패키지 없는 Node 검사기. 현재 persona/scenario v1 스키마의 모든 사용 키워드를 검사하며 새 미지원 키워드는 거부한다. 범용 JSON Schema 2020-12 엔진은 아니다.

4개 사용자와 5개 시나리오를 연결하는 권장 7개 조합은 simulation/scenarios/README.md에 있다. 공통 시나리오 스키마에 personaId가 없으므로 JSON에 임의 필드를 추가하지 않았다. D의 실행 계획에서 조합을 선택하는 자료이지 새로운 공통 입력 형식이 아니다.

## 성공 조건과 근거

전체 16개 검사: observation-only 5개, app-state 10개, manual 1개. app-state는 저장 스냅샷 차이 또는 실제 조작/화면 상태 덤프로 확인하도록 명시했다. 캡처·문구만으로 저장·탭 이동·개인정보 보호를 pass로 판정하지 않는다.

demo-v1 기준은 2026-10-12T09:00:00+09:00이며 어제는 2026-10-11, 계획 복귀 대상은 2026-10-14로 고정했다. captureIds에는 계약의 10개 ID만 사용하며 합집합이 10개 전체를 포함한다. captureIds는 관련 증거 목록이지 조작 순서가 아니다.

편집 화면은 계약의 새 ID를 만들지 않고 records-overview와 별도 단계 evidencePath로 구분하도록 적었다. 실제 입력/취소 흔적 없이 저장 상태만 동일한 경우는 편집 취소 성공으로 인정하지 않는다. 친구 요청은 수락 대기를 확인하고, 공개 끄기는 합성 저장소의 공개 행 삭제와 갱신 후 미공개를 검사한다.

코드 검토로 수동 지난 운동은 경과시간을 만들지 않으며 endedAt이 없는 정상 저장 형식임을 확인했다. 해당 성공 조건은 endedAt 존재를 요구하지 않는다. 기존 모델·앱·계약은 수정하지 않았다.

## 수행한 검사

명령은 모두 담당 워크트리에서 실행했다.

```powershell
node simulation/scenarios/tests/validate.mjs
git diff --check
```

- 사용자 4개·시나리오 5개 v1 구조, 필수 값, 허용 필드/열거형/범위, ID와 파일명: 통과.
- 사용자/시나리오 연결 7개, 시작 화면 포함, 계약 capture ID 10개, 중복 검사 ID, 성공 조건 누락: 통과.
- 고정 날짜, 연령·성별 표현, 목표의 위치/클릭 순서 힌트, 사용자 프롬프트 입력 3개, screen-review/dry-run 경계: 통과.
- 합성 입력 변조 11개(필수 값 누락, synthetic=false, 임의 필드, 잘못된 fixture/화면, 정답 누출, 성공 조건 제거, 실제 발생률 주장 등) 거부: 통과. 모두 메모리 안의 명시적 합성 테스트 입력이며 앱 실행 결과가 아니다.
- 목표·페르소나·프롬프트 문구를 직접 검토했다. 숫자·날짜·합성 친구 코드는 사용자 작업 데이터이고 버튼 위치·클릭 순서는 제공하지 않는다. 반복 결과를 실제 사용자 수/발생률로 해석하지 못하도록 명시했다.
- git diff --check: 통과.

기계적 문구 검사는 모든 자연어 정답 누출·고정관념·잘못된 통계 표현을 증명하지 않는다. 현재 작성된 자료의 코드/문구 검토와 함께 사용하는 회귀 검사다.

## 미실행과 통합 요청

- 실제 UX 실행은 not-run, outcome=not-evaluated. 화면 리뷰/모델 API 호출/유료 호출은 하지 않았다. 모델 요청 0회이며 실제 사용자 의견·발생률·작업시간은 수집하지 않았다.
- B의 실제 demo-v1/10개 화면 캡처와 D의 실행기 산출물은 담당 워크트리에 없어 교차 산출물 통합 검증은 미실행이다. 공통 계약 예시는 읽었으나 실제 캡처로 사용하거나 captured로 승격하지 않았다.
- A/B 요청: README의 사전조건을 실제 demo-v1와 대조한다. 오늘 첫 운동 최소 2세트/완료 0, 2026-10-14 계획, 원래 값이 50이 아닌 수동 푸쉬업 기록, 합성 친구 코드 ABCD2345와 공개 기록이 있는 합성 계정이 필요하다. 요구를 충족하지 못하면 사전조건 미충족으로 blocked/not-evaluated를 남긴다.
- A/D 요청: 현재 screen-review만으로 10개 app-state와 1개 manual을 pass로 판정하지 않는다. 선택 날짜는 일시 UI 상태일 수 있어 저장 스냅샷만으로 확인할 수 없으며 실제 조작 증거/화면 상태 덤프가 필요하다. 친구 저장소/관찰자도 네트워크 차단 합성 환경이어야 한다.
- 새로운 공통 규격 필드가 필요하면 A가 결정한다. 사용자 입력에 평가자 조건을 끼워 넣어 검사 환경 부족을 보완하지 않는다.
- Windows에서 실제 iOS 렌더·Swift/XCTest·전체 iOS 빌드는 미실행. 이번 변경은 시나리오 자료·프롬프트·검증기이며 제품 코드/CI/운영 데이터는 변경하지 않았다.
- HANDOFF.md, 다른 담당 경로, 공통 스키마를 수정하지 않았다. 원격 push·Actions 실행·배포·운영 DB 변경 없음.

## 커밋과 로컬 통합

아래 명령으로 이번 담당 파일만 선택해 커밋한다. 커밋 SHA는 자기 문서에 자기 SHA를 넣는 순환 참조를 피하기 위해 이 파일을 포함한 Git 기록으로 확인한다.

```powershell
git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit -m "feat: add synthetic UX personas and scenarios [skip ci]" -- simulation/personas simulation/scenarios simulation/prompts docs/ux-simulation/results/scenarios.md
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ux_simulation_integrate.ps1 -SourceBranch codex/ux-scenarios
```

로컬 통합은 검토·검증·커밋 후 지정 스크립트의 잠금과 main 상태 검사로 수행하며, 실제 통합 결과와 커밋 SHA는 완료 응답에 보고한다. 잠금이나 추적 파일 미커밋 변경으로 중단되면 그대로 보존한다. C 코드의 main 병합은 B/D 실제 산출물 검증이나 앱 실행 성공을 뜻하지 않는다.
