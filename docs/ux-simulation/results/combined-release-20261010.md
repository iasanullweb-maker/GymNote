# 다른 대화 변경 통합 배포 — 2026-10-10

## 현재 상태

사용자가 다른 대화의 변경을 검토·통합하고 배포하도록 승인했다. 배포 후보는 `codex/ux-coordinator`에 커밋했으며, GitHub 재인증 문제로 최종 후보 업로드와 CI 재검증이 대기 중이다. 새 릴리스 공개, AltStore 소스 갱신, 기기 설치를 완료한 상태가 아니다.

최종 제품 코드 수정 커밋은 `c1bb52ea3fe2141410041d3fbd67dbe329e0c2b7`이다. 원본 로컬 `main`은 확인 시점에 `cc09fbe`이며, 최종 후보의 전체 검증을 통과한 뒤 공통 통합 잠금을 사용해 합칠 예정이다. 원본의 기존 미추적 `%SystemDrive%/` 폴더는 보존했다.

## 검토·병합 범위

- `codex/shared-exercise-catalog`: 운동 안내, 시작 루틴, 운동 요약, 종목 대체와 동시 진행 보존. `codex/planfit-workout-improvements`의 작업을 포함한다. 후보 병합 커밋 `728efa1`.
- `codex/login`: 기존 구현 이후의 빈 검증 표시 커밋까지 병합했다. 후보 병합 커밋 `4570ec6`.
- `origin/codex/multi-device-sync`: 다중 기기 동기화, 모바일 데이터 연결, 요일에 의존하던 테스트 수정까지 병합했다. 후보 병합 커밋 `f6ca53f`.
- 기존 로컬 main에 통합된 UI·계획·기록 변경과 파일럿 후속 UI 수정 `cc09fbe`를 보존했다. 다른 작업 브랜치와 워크트리의 추적 파일 상태를 확인했고, 이미 포함된 변경은 중복 구현하지 않았다.

제품·저장 로직과 UI를 별도 읽기 전용 subagent 두 개로 검토했다. 아래 수정 뒤 코드 검토에서 추가 차단 문제는 발견되지 않았다. 코드 검토는 컴파일·XCTest 통과를 대신하지 않는다.

## 배포 준비 중 수정

1. `506dbe1`: 종목 대체 화면을 연 뒤 위젯에서 새 운동을 시작한 경우, 오래된 화면의 대체 저장이 최신 진행을 덮어쓰지 않도록 차단했다. 이를 재현하는 회귀 테스트를 추가했다. 기존 병합 테스트의 기대값에는 실제 저장 형식에서 유지하는 빈 반복 배열을 포함시켜 전체 데이터 비교를 유지했다.
2. `09001e9`: 기존 `scripts/test_cloud_merge.swift`의 다중 기기 병합 회귀 검사를 Validate와 Build IPA 워크플로 모두에 추가했다.
3. `c1bb52e`: CI에서 확인한 `App/RoutineView.swift:228`의 SwiftUI Section 컴파일 오류를 수정했다. 제목 문자열과 footer를 함께 쓰던 호출을 명시적 content/header/footer 초기화로 변경했다.

## 검증 근거와 남은 단계

`git diff --check`와 변경 검토는 통과했다. Windows에는 Swift/Xcode 도구가 없어 로컬 전체 iOS 빌드와 XCTest는 실행하지 않았다.

| 대상 | Validate | Build IPA | 결과 |
|---|---|---|---|
| `506dbe1` | [#61](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044213001) | [#94](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044213003) | Section 컴파일 오류로 실패. Validate의 계정 삭제·DB 작업은 성공 |
| `09001e9` | [#62](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044383690) | [#95](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044383703) | 같은 Section 컴파일 오류로 실패 |
| `c1bb52e` 이후 최종 후보 | 업로드 대기 | 업로드 대기 | GitHub 인증 필요. 수정 후 컴파일 성공은 아직 미확인 |

GitHub 공개 check annotations로 컴파일 오류를 확인했다. 일반 Git 인증이 실패해 공식 Git Credential Manager 로그인으로 재인증을 요청했다. 추가 인증 헤더·환경 토큰 탐색은 자동 승인 검토가 거부했으며 실행하지 않았다. 인증 정보와 토큰을 문서·채팅에 기록하지 않는다.

남은 단계는 최종 후보 업로드 → 해당 SHA의 Validate 전체 작업·Release 앱/위젯 빌드 성공 확인 → 잠금 아래 로컬 main 통합 및 원격 차이 재확인 → main push → 대상 배포 run, build-N/latest, IPA 버전·빌드·크기·SHA-256 및 AltStore source 대조다. 검증 SHA와 배포 SHA가 다르면 제품·리소스·설정·테스트·CI 트리까지 비교하고 필요한 검사를 다시 실행한다.

후보와 기존 원격 main 사이에 Supabase 마이그레이션 변경은 없다. 운영 SQL을 별도 적용하지 않았으며, 기존 운영 서버 미확인 항목이 앱 빌드 성공으로 해소됐다고 보고하지 않는다. 현재 설치된 iPad 앱의 SHA는 미확인이고, 이번 수정 화면의 실제 기기 재검증은 배포·설치 후 수행해야 한다.
