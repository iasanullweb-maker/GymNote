# Codex 친구·기록 UI 작업 상태

2026-10-09. 경로 `C:/Users/Donghyun/.codex/worktrees/346d/GymNote`, 브랜치 `codex/friends-records-ui`.

사용자 요청으로 Claude에 실행 탭을 분담했다. 실행 탭 초안은 `5c20bde` 및 별도 `codex/claude-workout-flow` 워크트리에 보존했다. 시작 메시지·소유 파일·완료 기준은 `docs/parallel-work/UI_HANDOFF.md`에 있다. 최초 가입 안내·튜토리얼·사용자 조사는 백로그에서 제외했다.

친구 가입·친구 추가 위치·탈퇴 UI/API/서버 정리, 기록 탭 순서·조회 경로, 공통 종목 메모리/캐시 처리, DB CI 경로의 Codex 담당 구현을 마쳤다. 탈퇴 중 새로고침/공개 및 늦게 도착하는 응답이 캐시를 복구하는 것을 막고 계정이 바뀌면 이전 프로필·가입 입력을 숨긴다. 탈퇴 RPC만 없는 서버는 기존 친구 기능을 유지하면서 업데이트 필요 안내를 표시한다.

초기 Codex 구현 검증 결과 (`d107b79` 당시):

- PGlite 0.3.14의 격리 PostgreSQL 엔진에서 테스트 스키마와 5개 마이그레이션 적용, `test_auth_policies.sql`, `test_record_catalog.sql`, `test_social.sql`, `test_integer_records.sql`, `test_social_withdraw.sql` 모두 통과. psql 전용 `\\echo` 출력 지시만 제거하고 SQL 본문은 그대로 실행했다.
- 탈퇴 권한·멱등성·프로필/관계/그룹/공개 기록 정리·그룹장 이전·빈 그룹 삭제·재가입·개인 백업/계정/세션 보존 및 프로필 없는 기록/관계 삽입 차단을 검증했다. 실제 여러 PostgreSQL 연결의 동시 부하 검사는 미실행이다.
- 관리자 신규 종목 생성 후 다른 일반 사용자와 게스트의 조회를 검증했다. 운영 두 계정/기기의 제보 증상은 미재현이다.
- tree-sitter Swift 파서로 변경한 앱 6개 파일 및 XCTest 2개 파일의 구문 검사 통과. diff 공백 검사·코드 검토 통과. 구문 검사는 Swift 컴파일 성공을 뜻하지 않는다.
- XCTest에 캐시 쓰기 실패 시 최신 목록 표시, 관리자 새 종목 갱신, 네트워크 오류 시 마지막 목록 보존, 탈퇴 후 개인 데이터 보존/공개 중지, 실패/서버 미적용 시 기존 프로필 유지 검사를 추가했다. Windows에 Swift/Xcode가 없어 XCTest 실행·전체 iOS 빌드·UI 렌더 검증은 미실행이다.

최신 교차 검토 (2026-10-09):

- Claude `b65301a`를 통합했다. `AppModel.swift`는 `81ea364`와 같고, 담당 실행 탭 파일 차이는 신규 `testFailedSetDoesNotStartRest` 한 개다. 기존 저장 실패 휴식 유지 단언과 함께 보존했다.
- 이전 CI `37935579499` 원본 로그: URLSession이 Swift 취소를 `NSError(domain: Swift.CancellationError, code: 1)`로 전달했다. 타입 검사에서 빠져 취소 테스트 한 개의 단언 두 개가 실패했고 `WorkoutFlowTests` 9개는 모두 통과했다.
- `9f218e7`에서 Swift/NSError 취소, NSURLError 취소, underlying 취소, 취소된 Task를 처리했다. 각 형식을 마지막 정상 목록에서 독립 검사하고 실제 네트워크 실패 안내도 유지했다. 관리자 확인은 전역 busy와 분리되어 있으며 이전 권한은 확정 결과까지 유지한다.
- 사용자 승인 범위의 검토 브랜치 push로 macOS CI 재실행. [Validate GymNote 37937581607](https://github.com/iasanullweb-maker/GymNote/actions/runs/37937581607) 전체 성공: swiftc 모델/계정/일상/기록/순위 검사, PostgreSQL 17 권한/탈퇴 검사, 계정 삭제 검사, iPad XCTest 74개 중 실패 0·기존 UX 캡처 5개 건너뜀. WorkoutFlowTests 10개(신규 testFailedSetDoesNotStartRest 포함), RecordCatalogTests 10개(취소 회귀 포함) 모두 통과했다. [Build IPA 37937581550](https://github.com/iasanullweb-maker/GymNote/actions/runs/37937581550) 앱·위젯 Release 빌드·IPA 생성도 성공했다. 원격 main push·릴리스 게시·운영 SQL 적용은 하지 않았다.
- 이전 `iPad-test-results` 산출물을 다운로드하여 원본 로그와 manifest, 834/417pt 실행 목록, 360pt 운동·휴식 카드 캡처를 검토했다. 해당 화면은 정상 렌더링됐지만 RootView 탭 막대가 포함되지 않고 카드 테스트에는 세트 수를 전달하지 않으므로 하단 겹침·세트 배너 통합 검증 근거로 사용하지 않는다.
- 편집 모드 없는 길게 끌기, 완료 경계에서 놓은 모습, iPhone SE 세로/가로·iPad·큰 글자·휴식 중 전체 하단 배치와 완료 애니메이션 실제 모습은 미실행이다. 운영 두 계정의 공통 종목 노출 제보 재현도 남아 있다.
- 다른 채팅의 `326d030`, `ce39de8` 기기 검증 문서를 보존했다. `05ae172` 이후 Codex 변경은 `d107b79` 등으로 커밋되어 있으며 Claude 보고서와 공유 API 변경을 함께 검토했다.
- 원본 main의 다른 대화 HANDOFF.md 편집 때문에 첫 통합을 멈췄다. 사용자가 해당 대화에서 커밋한 뒤 진행하도록 선택했고, `6a18b0c` 커밋과 추적 파일 미커밋 변경 없음을 확인했다. UX 잠금 아래 `5d62ecf`를 main에 병합한 앱 통합 커밋은 `50bad50`이다. 텔레그램 체크리스트·기존 미추적 `%SystemDrive%/` 폴더를 보존했고, 병합 앱 소스는 CI 대상 `9f218e7`와 동일함을 확인했다. 완료 기록 문서는 별도 경량 검토 후 같은 잠금으로 통합한다.

친구 탈퇴 운영 사용에는 `202610090003_social_withdraw.sql` 적용이 필요하다. 서버 배포와 실기기 확인은 코드 구현·로컬 통합 완료와 구분한다.

최신 배포 (2026-10-09 23:00 KST):

- 사용자 승인으로 main `0128f23`을 push했다. 앱 코드는 CI 통과 소스 `9f218e7`와 같고, 다른 대화의 미커밋 변경 없이 UX 잠금으로 점검표를 통합했다.
- [Build IPA 37940596587](https://github.com/iasanullweb-maker/GymNote/actions/runs/37940596587) 전체 성공. 0.1.91/build 91의 앱/위젯 Release 빌드, 스크립트 검사, build-91/latest 게시, AltStore 갱신을 완료했다.
- 실제 배포 IPA 2,006,818바이트, SHA-256 `53b15300384025a39cc66b0bcb908d00f4f84ded863b5326c8c316d88aafc803`. 앱/위젯 버전·서명 리소스·Supabase 설정 및 두 릴리스/AltStore 소스의 버전·크기·digest·고정 다운로드 주소 일치를 확인했다.
- 운영 SQL은 Supabase 로그인 세션 부재로 조회/적용하지 못했다. 002의 운영 적용 여부는 미확인이고 이번 003은 미적용이다. 적용 전 기존 FK/RPC·고아 행 확인, 필요한 마이그레이션 적용과 권한 확인이 남았다.
- [77개 실사용 점검표](../../RELEASE_DEVICE_CHECKLIST.md)를 추가했다. 기존 0.1.88 클라우드 첫 실행 미확인 현상은 원인 불명이며 0.1.91이 해결했다고 보고하지 않는다. 실제 기기 첫 실행·터치·배치·두 계정 검증은 별도로 남는다. 기기에서 성공하지 않은 항목은 체크하지 않는다.
