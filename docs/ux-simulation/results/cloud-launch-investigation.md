# 클라우드 앱 실행 추가 조사 (2026-10-09)

## 결론

GymNote 0.1.88 설치 성공 뒤 첫 화면을 확인하지 못하는 현상을 iPad Pro 11 (2024)와 iPad Air 6에서 관찰했다. 두 기기의 실제 OS는 17.5다. 앱 충돌, 실행 요청 실패, 재서명 문제 중 어느 원인인지는 아직 확정하지 못했다. 이번 조사에서 앱 코드를 임의 수정하지 않았다.

## IPA 실행 파일 검사

검사 대상은 공개 build-88 IPA이며 SHA-256은 첫 세션 문서와 README의 값과 같다. 원본 앱 커밋은 fcf4d97cf15283f1f2c1845450dee014392cf346이다. Windows에서 ZIP·plist·Mach-O·CodeDirectory를 읽기 전용으로 조사했다.

| 항목 | 본체 / 위젯 결과 | 의미와 한계 |
|---|---|---|
| 실행 파일 | Mach-O 64-bit, arm64, 실행 권한 0755 | 시뮬레이터 빌드나 실행 파일 누락은 발견하지 못함 |
| 플랫폼 / 최소 OS | iOS device(2) / 17.0 | 실제 17.5가 최소 버전 조건을 충족함 |
| 빌드 SDK | 26.2 | 최소 OS와 다름. 17.5에서 모든 심볼의 존재·동작까지 검증한 것은 아님 |
| 라이브러리 | 시스템 framework 및 /usr/lib 참조 | 누락된 자체 framework 또는 @rpath 라이브러리 참조는 발견하지 못함 |
| 암호화 | cryptid = 0 | 암호화된 App Store 실행 파일이 아님 |
| 코드 페이지 SHA-256 | 본체 1,684개, 위젯 279개 모두 일치 | 원본 CodeDirectory와 실행 코드 비교. 전체 서명·리소스·재서명 IPA 검증은 아님 |
| 서명 / 권한 | ad-hoc, App Group group.com.gymnote.app | embedded.mobileprovision 없음. 클라우드 재서명 결과는 별도 확인 필요 |

로컬 조사 스크립트는 .validation-tools/cloud-ipad/inspect_binary.py에 보관하며 제품용 검증 도구로 배포하지 않는다.

## 시작 코드 검토

- SharedStore는 App Group 컨테이너가 없으면 Application Support로 대체한다. AppModel은 초기 저장 오류를 잡아 storageError에 기록한다. App Group 옵션 OFF만으로 실행 실패를 단정할 수 없다.
- 앱 시작의 계정 bootstrap은 오류 처리와 initialized 완료 경로가 있다. 알림 등록·권한 요청·Live Activity 호출도 검토했으며 확인한 경로에 명시적 fatalError, precondition, try!는 발견하지 못했다. 시스템 내부 예외까지 제외하는 검사는 아니다.
- IPA 커밋과 현재 시작 코드·SharedStore·프로젝트·빌드 설정을 비교했다. 해당 범위의 차이는 AccountModel의 공통 종목 캐시 저장 오류 처리뿐이다. 앱 시작 관련 설명은 build-88에도 적용된다.

## 재현 시도와 수집 한계

1. 사용자가 재설치·실행을 승인했다. 기존 Pro 11 재접속은 구매 안내와 함께 막혔다.
2. 기기 변경 승인을 받고 Air 6에 같은 IPA를 설치했다. 실제 제목은 v17.5, 설치 성공 알림 뒤 관찰한 앱 화면은 홈 화면에 머물렀다. 이 세션에서는 별도의 GymNote 아이콘 탭이나 재시작 성공을 확인하지 않았다.
3. BrowserStack iOS Settings의 App Crash Logs → Fetch logs를 요청했다. 버튼의 로딩 반응을 확인했지만 ZIP/.ips 다운로드는 확인하지 못했다. 콘솔의 crash_mover: Could not checkin with lockdown은 수집 프로세스의 오류이며 GymNote 충돌 원인으로 해석하지 않는다.
4. 전체 기기 로그·Debug 수준 전환과 Download logs를 시도했으나 마지막 확인 상태는 com.gymnote.app / Error였다. 새 로그 파일도 확인되지 않았다. 전체 로그 확보를 완료로 처리하지 않는다.
5. 2분 체험 시간이 끝나 세션이 자동 종료되고 대시보드에 종료 안내가 표시됐다. 결제·설정 변경·새 업로드·외부 문의는 수행하지 않았다.

Computer Use에서 브라우저 전면 복원 뒤에도 창이 다른 창에 가려지고, 클릭 후 스냅샷·접근성 상태가 뒤늦게 갱신되는 현상이 반복됐다. 앱과 자동 조작 문제를 구분할 추가 증거가 필요하다.

## 다음 조사 순서

1. 재설치 전에 로그 필터·다운로드 조작이 실제 반영되는지 검증한다. 자동 조작이 불안정하면 사용자의 직접 실행과 로그 다운로드를 비교한다.
2. 실행 직전 All Device Logs와 가장 상세한 로그 수준을 선택하고 앱을 재시작한다. 시작 시각·번들 ID·PID·종료 이유를 확보한다. 재설치가 필요한 새 기기는 승인과 체험 가능 여부를 확인한다.
3. .ips가 있으면 exception/termination namespace·reason·faulting thread·binary UUID를 분석한다. 파일이 없다는 사실만으로 충돌이 없었다고 단정하지 않는다.
4. 로그가 서명·권한 문제를 가리킬 때 App Group/위젯 재서명 조건을 검토한다. dyld 심볼 문제가 나오면 SDK·OS 호환성을, 앱 스택이 나오면 해당 초기화 코드를 수정한다. 원인 근거 없이 위젯 삭제나 저장·로그인 로직 변경부터 하지 않는다.

[BrowserStack 충돌 로그 다운로드](https://www.browserstack.com/docs/app-live/session-debugging/iOS-crash-logs) · [기기 로그와 필터](https://www.browserstack.com/docs/app-live/session-debugging/app-device-logs)

## 검증·통합 범위

실행 파일 읽기 검사와 문서 검토를 수행했다. 앱 실행 성공은 미확인이다. 앱 코드 변경·전체 iOS 빌드·XCTest·원격 push·배포는 수행하지 않았다. 원본 로그와 개인정보는 Git에 포함하지 않는다.
