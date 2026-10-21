# 세부 화면 튜토리얼·계정별 완료 이력 (2026-10-21)

## 구현 결과

- 작업 폴더 `C:/Users/Donghyun/Documents/ChatGPT/gymnote in web 2/tutorial-focus`, 브랜치 `codex/tutorial-focus-20261021`. 최초 제품·검사 `fdf08f5`, 최종 제품·검사 소스 `6c95bae14102a499e8094c62aed0f93282c3d4b5`.
- 운동 계획 설정(길게 누르기 시트와 날짜 상세 링크 공통), 운동 선택, 일반 운동 목표 설정, 신디 목표 설정, 계획 교체, 기본 루틴, 일상 추가·편집의 세부 안내 7종을 추가했다. 각 화면 최초 방문 때 안내하고 최종 단계에서 완료를 저장한다. 진행 중 날짜/다른 계정의 계획 편집기는 자동 안내하지 않는다.
- 계획 이름 버튼·편집 시트·전용 뷰·해당 캡처 참조를 제거했다. 기존 저장 제목은 보존한다.
- `AppData.completedCoachmarks`를 계정별 저장·기존 클라우드 JSON 백업으로 동기화한다. JSON의 기존 소유권·CAS 경로를 사용하며 서버 스키마/권한 변경은 없다. 동시 완료·위젯 저장·알려진 구버전 필드 누락에 대해 완료 이력을 합집합으로 병합한다.
- 계정 UUID 일치와 서버 확인/반영 완료 후에 자동 표시를 판단한다. 게스트 자동 안내는 없으며 게스트 기록 가져오기로 이력을 옮기지 않는다. 설정의 다시 보기는 앱 세션의 별도 완료 목록을 초기화하며 계정 이력을 지우지 않는다. 재실행하면 진행을 처음부터 표시하고 계정 전환 시 다시 보기 상태를 해제한다.

## 전체 검사와 화면 검토

- 사용자 승인 후 작업 브랜치에 push하여 [최종 Build IPA 39602412657](https://github.com/iasanullweb-maker/GymNote/actions/runs/39602412657)을 실행했다. SHA `6c95bae`의 checks/ios·database·account-deletion·tooling, 앱/위젯 Release 빌드, release-gate 모두 성공. 검증 브랜치이므로 publish는 skipped다.
- XCTest 186개: 182 통과·기존 캡처 4개 건너뜀·실패 0. TabCoachmarkTests 10개와 testDetailTutorialScreens 통과. Swift 모델·계정·클라우드 병합·일상·일지·기록 등 CI 회귀도 통과했다.
- 계정 이력 JSON 재읽기·새 계정 분리·원격 확인 전/게스트 자동 표시 차단·다시 보기·계정 전환·오래된 selection 쓰기 차단·구버전 서버본 채택 시 이력 보존 검사를 추가했다. 클라우드 스크립트에는 동시 완료 합집합·구버전 누락·게스트 가져오기 제외·왕복 인코딩·위젯 저장 보존 검사를 추가했다.
- 최종 네이티브 세부 안내 캡처 15장(7종 × iPad/iPhone 14장 + 큰 글자/다크 계획 안내 1장)을 직접 검토했다. 실제 제목/조작 행 강조, 카드·다음/시작하기 버튼 가시성, 주황/청록, 큰 글자 배치를 확인했다. 일반 계획 편집 다크 캡처도 확인하여 이름 편집 제거와 목록 행·구역 정렬이 유지됨을 확인했다.
- 첫 [Build IPA 39569375363](https://github.com/iasanullweb-maker/GymNote/actions/runs/39569375363), 소스 `6979441`도 전체 검사는 성공했지만 캡처에서 Section 전체 강조가 목록 정렬을 바꾼 점을 발견했다. `6c95bae`에서 측정을 실제 제목/Picker 행으로 옮겨 목록 구조를 복구하고 전체 검사·캡처를 다시 확인했다. 테스트 삭제/완화 없이 동일 검사로 통과했다.
- 최종 근거: iPad-test-results artifact `12347986366`, manifest의 UXSimulationCaptureTests/testDetailTutorialScreens. 로컬 `.validation-tools/detail-tutorial-ci/final/`, `ios-final.log`. 1차 캡처와 로그는 같은 폴더의 captures/, ios.log에 별도 보존한다.
- 최종 CI의 지연은 macOS 실행기 용량 제약 안내가 있었으며, 실제 XCTest는 119초에 실패 없이 완료했다. 브라우저 주석의 Node 20 action 강제 Node 24 전환 경고는 이번 제품 변경과 별개다.

## 통합과 남은 확인

- 최초 로컬 main 기준 `6e9e826`을 반영했고 이후 main의 배포 기록 `fcae617`을 `e99ad6c`에서 보존해 병합했다. 후자의 차이는 인계/배포 문서뿐이다. 최종 제품·검사·CI 입력은 검증 SHA `6c95bae`와 동일하게 유지하고 문서만 커밋한다.
- 로컬 main 대상 `fcae617`: 원본 `.validation-tools/ux-integration.lock`을 CreateNew로 획득하고 양쪽 추적 파일/진행 중 Git 작업·소스/대상 SHA·공백·ancestry·검증 이후 문서 외 변경 부재를 확인한 뒤 fast-forward 통합한다. 원본의 기존 미추적 `%SystemDrive%/`는 보존한다. 최종 source/main HEAD와 ancestry를 재확인한다.
- 작업 브랜치의 검증 소스만 push했다. 이 작업의 main push·배포·운영 DB 변경·외부 메시지 전송은 하지 않는다. 과거 0.1.137 배포는 이전 튜토리얼 작업의 이력이며 이번 계정/세부 안내 변경 배포가 아니다.
- 이전 기기 전역 완료 목록은 계정 소유자를 확인할 수 없어 임의로 옮기지 않는다. 서버 이력이 없는 기존 계정도 한 번 안내할 수 있다. 이후 새 버전 기기들에서 완료 이력을 동기화하면 새 기기에서 완료 안내가 반복되지 않는다.
- 구버전 앱만 사용하여 서버 JSON의 새 필드를 누락시킨 뒤 완전히 새 기기에 로그인하면 과거 이력을 복원할 근거가 없을 수 있다. 새 버전 기기의 로컬/동기화 기준 이력은 합집합으로 복구한다. 같은 새 버전의 두 기기로 실제 계정 흐름을 확인해야 한다.
- 사용자 실기기·VoiceOver·실제 로그인 두 계정/두 기기·오프라인 복구·실제 길게 누르기와 배포 후 사용자 확인은 대기다. 캡처는 iPad Pro 11-inch(M4) 시뮬레이터의 크기별 UIWindow/격리 합성 모델이며 독립 물리 iPhone/iPad 조작의 근거가 아니다.
