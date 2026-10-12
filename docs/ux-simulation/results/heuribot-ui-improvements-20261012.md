# 휴리봇 화면 검증 후 UI 개선 — 2026-10-12

사용자가 [0.1.107 가상 사용자 검증](heuribot-107-pilot-20261012.md)의 개선 후보 구현을 요청했다. 작업 폴더 `.worktrees/heuribot-ui`, 브랜치 `codex/heuribot-ui-20261012`, 시작 main `35a7a97`에서 제품 커밋 `c78511c`를 만들고 로컬 main에 통합했다. 후속 사용자 승인으로 0.1.109/build 109 배포까지 완료했다. 아래 구현 시점의 미실행·미배포 기록은 당시 상태이며 후속 결과는 배포 절을 따른다. 109 기기 설치와 화면 재검증은 미확인이다.

## 변경

| 화면 | 개선과 기존 흐름 |
|---|---|
| 실행 | 시작 전·완료·측정값 무효·부모 비활성 상태의 세트 조작은 회색, 유효한 진행 중 조작은 주황색. 시작 안내와 버튼의 ‘운동 시작/새 운동 시작’ 이름을 맞춤. 원 표식 위에 완료/전체 세트 수 표시, 진행 중 ±는 이번 세트 횟수를 조절한다는 안내. 기존 완료 조건·콜백·횟수 범위·신디 세트 경로 유지 |
| 계획 | 동일 선택 날짜 계획 설정 링크를 달력 위로 이동하고 대상 날짜 표시. 아래 중복 링크 없이 같은 ScheduledDayEditor·selectedDate를 사용. 날짜 변경·주간 목록·함께 보기·길게 누르기 흐름 유지 |
| 일지 달력 | workouts.count의 ‘회’를 ‘일지 N개’로 표시하여 반복 횟수와 구분. 완료 세트 합계 유지. compact 달력은 두 줄과 기존 글자 축소를 허용 |
| 최고기록 | 기존 최고 보관·오늘 실행 중 반영 가능한 종목 갱신·과거 일지 수정/삭제의 영향, 한 세트 최고와 하루 반복 횟수 합계를 설명. 그래프는 ‘저장된 종목 기록 추이’이며 일지의 세트별 반복 횟수·하루 총량과 구분. 예전 신디 추가 횟수의 일부 세트 표현을 안내. 좁은 화면/접근성 글자 크기의 기록 행은 세로 배치, 빈 상태 높이는 늘어날 수 있도록 조정 |

담당 Swift 4개: TodayView, RoutineView, PlanCalendarView, RecordsView. Shared·모델·서버·저장·동기화·차트 입력 데이터를 변경하지 않았다. 새 최고기록 정책을 새로 도입하거나 신디 실행에서 최고를 갱신하게 만들지 않았다.

## 검토·검증

- 독립 `improve_plan`이 계획/일지 문구를 구현하고 TodayView 상태 조건을 읽기 전용 교차 검토했다. 주 에이전트는 실행 표시와 문서·통합을 담당했다. `improve_records`는 최고기록·그래프 실제 입력을 확인하여 문구를 구현하고 계획/달력을 교차 검토했다.
- canComplete는 기존 시작 여부·완료·유효 측정값 조건에 부모 isEnabled를 포함한다. 횟수 0에서는 감소만, 9999에서는 증가만 비활성인 기존 경계를 유지한다. 신디는 ±/측정 입력 없이 세트 완료 경로를 유지한다. 진행 숫자 Text는 기존 원 표식의 VoiceOver 안내와 중복되지 않게 했다. 실제 세트 저장을 새로 실행한 검사는 아니다.
- 계획 링크의 동일 선택 날짜 전달과 편집 진입, 일지 개수·세트 합계 계산, 기록 데이터의 `recordProjection`/`entries`/`combinedBestSet`/하루 총량 사용을 코드로 대조했다. 기록 집계 문구의 ‘완료 횟수’를 ‘반복 횟수 합계’로 구체화했다.
- Windows Python 3.12/tree-sitter-swift: 변경 Swift 4개 문법 오류 0. git diff --check·본인 diff·새 파일·로컬 문서 링크 검토 통과.
- **미실행:** 전체 iOS 빌드·XCTest·새 네이티브 렌더/실기기·작은 화면/큰 글자 조작·변경 후 가상 사용자 비교. 작은 UI 변경이므로 전체 검사는 후속 통합 검증 또는 배포 직전에 실행한다. 기존 107의 빌드/테스트 성공을 새 코드의 검사 결과로 쓰지 않는다. 이번 코드에 맞춘 동작/레이아웃 검사는 아직 실행하지 않았다.
- 본인 파일만 커밋하고 기존 main의 브랜치·미커밋 변경·진행 중 작업을 확인한 뒤 공통 UX 잠금으로 로컬 통합한다. 원본 미추적 `%SystemDrive%/`는 보존한다. 원격 push·CI 실행·배포·운영 DB 적용은 이번 작업에서 하지 않는다.

## 후속 확인

수정 앱 배포 후 같은 기기·방향·화면 상태에서 첫인상/다음 행동을 먼저 묻고, 그 뒤 ±·완료 의미를 묻는 순서로 비교한다. 계획 첫 화면에서 진입점·대상 날짜를 식별하는지, 일지 ‘개’와 종목 반복 횟수 ‘회’·최고값/그래프를 구분하는지 확인한다. 사용자 확인은 [TODOLIST_HANDOFF](../../../TODOLIST_HANDOFF.md)에 미완료로 유지하며 기존 확인 항목도 보존한다.

## 전체 검증·정식 배포 — 2026-10-12

- 사용자 승인: ‘그럼 빌드 배포 업데이트 먼저 진행해’. 검증 브랜치에 제품 SHA `c78511c614e82551ef0413ee4fcb4c159bd4c743`를 push했다.
- [Validate 38202458082](https://github.com/iasanullweb-maker/GymNote/actions/runs/38202458082) 전체 성공. XCTest 144개 중 140개 통과·기존 UX 캡처 4개 건너뜀·실패 0. Swift 모델·계정·클라우드·일상·기록·순위와 격리 DB 권한·동시 백업·계정 삭제 검사 성공. [Build 38202458083](https://github.com/iasanullweb-maker/GymNote/actions/runs/38202458083) 앱/위젯 Release 빌드 성공(108은 브랜치 artifact이며 정식 설치 대상이 아님).
- 배포 SHA `35ed59652e9edc60e79c0cadd7c158b374f3a53f`. 다른 대화의 `cf21103` 운영 DB 적용 문서·`35ed596` 작업 규칙 문서를 보존했다. `git diff --name-only c78511c 35ed596`의 차이는 Markdown 문서 12개뿐이며 전체 diff와 제품·검사·빌드 경로 diff를 대조해 제품 입력 동일성을 확인했다. 운영 SQL·앱/서버 데이터 변경은 이번 배포 작업에서 실행하지 않았다.
- 자동 승인 검토가 후속 문서를 제외한 `c78511c` main push를 거부해 최신 문서를 포함했다. 이후 HEAD 변경을 감지한 잠금 검사도 push를 중단했으며 최신 기준을 재확인했다. 공통 잠금 아래 전체 최신 main을 fast-forward push했고, `[skip ci]` 때문에 지원되는 workflow_dispatch로 정식 빌드를 실행했다. 강제 push·reset·stash 없이 타 작업을 보존했다.
- [정식 Build 38203068870](https://github.com/iasanullweb-maker/GymNote/actions/runs/38203068870), main, 위 배포 SHA: 모델 검사·앱/위젯 Release 빌드·IPA·릴리스 게시·AltStore 갱신 성공. **0.1.109/build 109**. [build-109](https://github.com/iasanullweb-maker/GymNote/releases/tag/build-109)와 latest 태그 모두 배포 SHA이며 두 IPA asset의 크기·해시가 일치한다.
- 실제 다운로드 IPA: 2,179,504바이트, SHA-256 `dc2cef670ac4ab2db6cda891fcb41ecc687a336f29f79522ba7d53ff29c73809`. 앱 `com.gymnote.app`와 위젯 `com.gymnote.app.widget` Info.plist 모두 버전 `0.1.109`, 빌드 `109`. 두 Mach-O LC_CODE_SIGNATURE의 XML entitlements에서 `group.com.gymnote.app` 확인.
- AltStore 브랜치 `a9bc3507588b8b02d0faea1670513a7d32c28231`의 source.json: bundle ID `com.gymnote.app`, 버전 `0.1.109`, buildVersion `109`, 고정 build-109 다운로드 URL·size 2179504 일치. Git 제외 `.validation-tools/GymNote-build-109.ipa`에 확인한 파일 보관.
- 기기 업데이트는 별도 미완료다. 배포 중 USB 설치 조회가 일반/기기 접근 실행 모두 NoDeviceConnectedError로 실패했다. 연결·잠금 해제와 AltStore 소스 새로고침→헬스노트 UPDATE→앱 설정 `0.1.109 (109)` 확인을 요청했다. 앞선 107 설치 확인을 109 설치로 재사용하지 않는다.
- 전체 iOS 검사 유예는 이번 CI로 해소했다. 109 실기기 화면·큰 글자/작은 화면 조작·변경 후 가상 사용자 비교·사용자 직접 확인은 실행하지 않았으며 체크리스트에 남겼다. 후속 문서는 diff·링크 검사 후 본인 파일만 `[skip ci]`로 커밋하고 최신 대상 기준 확인·fast-forward·공통 잠금으로 로컬 통합한다.
