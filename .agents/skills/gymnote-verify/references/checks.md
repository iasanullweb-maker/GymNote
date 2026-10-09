# 검사 선택표

모든 경로·명령은 GymNote 루트 기준이며 현재 파일을 확인해 사용한다. 이 표는 CI를 복제하지 않고 검사 위치를 안내한다.

| 변경 영향 | 우선 확인할 기존 검사 | 범위와 한계 |
|---|---|---|
| 문서·스킬 | 본인 diff, git diff --check; 사용 가능한 skill-creator의 quick_validate.py | 링크·현재 규칙·완성된 내용도 검토. 앱 빌드 불필요 |
| 작은 SwiftUI 표시·탭/편집 흐름 | 관련 Tests의 XCTest, 제품 코드 검토, 필요 시 UX 절차 | 웹 모사는 Swift View를 검사하지 않음 |
| 모델·마이그레이션·운동·일지 | scripts/test_models.swift, test_manual_workout.swift, test_records.swift; 관련 XCTest | 정확한 swiftc 입력은 check.yml/build.yml에서 확인 |
| 일상·계획·일정 | scripts/test_daily.swift, 관련 XCTest | 실제 알림 전달·위젯 표시는 실기기 확인 필요 |
| 계정·기록 보존·동기화 | scripts/test_accounts.swift, 계정 XCTest, scripts/test_auth_policies.sql | 계정 전환·실패 후 개인 기록 보존 검토 |
| 계정 삭제·서버 함수 인증 | node scripts/test_delete_account.mjs, 관련 계정·SQL 검사 | 운영 계정 삭제를 테스트로 수행하지 않음 |
| 공통 종목·친구·그룹·탈퇴 | scripts/test_social_ranking.swift, test_record_catalog.sql, test_social.sql, test_integer_records.sql, test_social_withdraw.sql | 탈퇴·공개 해제와 개인 기록 보존, 두 계정 권한 검토 |
| DB 마이그레이션·RLS·RPC | check.yml의 database job과 테스트 SQL | 격리 PostgreSQL에 auth_test_schema 및 현재 마이그레이션을 순서대로 적용. 운영 적용은 별도 |
| 웹 행동 프로토타입 | node simulation/web/tests.mjs, node simulation/web/test-ui.mjs | 제품 코드와 분리된 합성 상태/DOM 검사 |
| UX 규격·시나리오·캡처·실행기 | 아래 Node 명령과 해당 README | dry-run·pending·증거 조건을 구분 |
| 텔레그램·워커·관리자·저장/API | python -m unittest discover -s automation/tests -v | 가짜 Telegram/에이전트, 격리 Git·SQLite·HTTP. 실제 전달/유료 실행 근거 아님 |
| IPA·클라우드 설치 사전 검사 | python -m unittest discover -s simulation/cloud -p "test_*.py" -v; cloud README | IPA 구조 검사는 설치·실행 성공을 보장하지 않음 |
| project.yml·의존성·공유 Swift·앱/위젯 통합 | check.yml iPad XCTest, build.yml Release 앱/위젯 빌드 | XCTest, Release 빌드, 배포, 실기기 동작은 각기 다른 결과 |

## UX Node 검사

Node 24 이상을 우선 사용한다. PATH와 다르면 실행기의 실제 절대 경로로 호출한다.

```powershell
node simulation/contracts/test_validate.mjs
node simulation/contracts/audit.mjs --require-panel
node simulation/scenarios/tests/validate.mjs
node simulation/capture/test-collect.mjs
node --test "simulation/runner/tests/*.test.mjs"
node scripts/ux-sim/run.mjs --validate-only
```

변경 영역에 해당하는 명령만 선택한다. audit의 기본 정상 종료는 입력 대기일 수 있으므로 요약을 읽는다. 캡처 증거 검사에는 실제 manifest와 --require-captures를 사용하며 pending을 임의로 captured로 변경하지 않는다.

## CI와 외부 실행

`.github/workflows/check.yml`은 검증, `build.yml`은 IPA 생성과 main의 릴리스·AltStore 소스 갱신을 담당한다. 독립 워크플로라 main push가 XCTest 성공을 기다리는 장치라고 가정하지 않는다. 원격 실행 전 대상 브랜치·트리거·승인 범위를 확인한다. 이미 승인된 검사는 재승인을 요구하지 않되 승인되지 않은 push·배포를 검증의 부수 작업으로 수행하지 않는다.
