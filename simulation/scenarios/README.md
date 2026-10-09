# 시나리오 v1 적용 메모

기준은 demo-v1, 2026-10-12T09:00:00+09:00, Asia/Seoul, ko_KR이다. 모든 세션은 독립된 fixture 사본으로 시작한다. 전 세션 결과를 다음 초기 상태로 재사용하지 않는다.

## 사용자 참조

스키마에는 personaId 필드가 없으므로 시나리오 JSON에 임의 필드를 추가하지 않는다. 아래는 실행기 입력을 구성할 때 쓰는 권장 연결이며, 순서는 정답 경로가 아니다.

| personaId | scenarioId |
|---|---|
| first-time-recorder | start-and-record-set |
| distracted-exerciser | start-and-record-set |
| first-time-recorder | return-to-selected-plan |
| distracted-exerciser | return-to-selected-plan |
| retrospective-recorder | record-previous-workout |
| retrospective-recorder | cancel-record-edit |
| first-time-competitor | friend-request-and-private-records |

## 평가자 전용 사전조건

이 문서와 JSON의 checks는 사용자 프롬프트에 전달하지 않는다.
- 운동 시작: 2026-10-12의 첫 운동은 최소 2세트이며 완료 0세트, 진행 중 운동은 없다. 기존 일지·계획의 실행 전 스냅샷을 확보한다.
- 계획 복귀: 2026-10-14에 식별 가능한 합성 계획이 있다. 선택 날짜/화면 이동 상태를 실제 실행기가 관찰할 수 있어야 한다.
- 지난 운동: 새 입력 세션은 2026-10-11 푸쉬업 3세트 10/8/6, 제목 ‘어제 푸쉬업’이다. 이미 같은 날짜의 일지가 있어도 그것을 유지하고 새 ID 한 개만 추가하는지 비교한다.
- 편집 취소: 편집 가능한 기존 수동 공통 푸쉬업 기록이 한 개 이상 있고 원래 값은 50이 아니다. 자동 일지 최고기록을 수동 기록 편집 대상으로 오인하지 않도록 평가자가 대상 ID를 미리 확보한다.
- 친구: 초기 합성 사용자 프로필이 있고 share_records=true, 공개 기록이 한 개 이상 있다. ABCD2345는 본인이 아닌 아직 친구가 아닌 합성 대상 코드다. 실제 서버는 차단하고 합성 저장소/응답만 사용한다. 친구·그룹 관찰자 확인 환경이 없으면 manual은 not-evaluated다.

B의 demo-v1와 실행기 상태 관찰 기능은 아직 대조하지 않았다. 이 사전조건은 fixture 요구사항이지 해당 상태가 실제 구현됐다는 선언이 아니다. 충족하지 못하면 해당 시나리오를 blocked/not-evaluated로 남기고 사전조건을 사용자 목표의 힌트로 바꾸지 않는다.

captureIds는 관련 화면 증거 목록이며 클릭 순서나 강제 탐색 경로가 아니다. 편집 화면처럼 별도 계약 ID가 없는 단계는 가장 가까운 계약 화면 ID와 단계별 evidencePath로 구분한다. 임의 새 capture ID를 만들지 않는다. 화면 이미지가 없으면 pending으로 두고 실행 성공을 꾸미지 않는다.

## 검사

`node simulation/scenarios/tests/validate.mjs`

검사기는 현재 v1 persona/scenario 스키마의 사용 키워드를 검증하고, 참조 ID·성공 조건·정답 누출 문구·고정 날짜·프롬프트 경계 및 거짓 성공 방지를 확인한다. 문구 검사는 기계적 탐지이므로 목표를 사람이 읽어 순서/위치 힌트가 없음을 별도 검토해야 한다. 실제 사용성·저장 성공·캡처 렌더 검사는 수행하지 않는다.
