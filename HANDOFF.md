# 헬스노트 (GymNote) 작업 인계

마지막 업데이트: 2026-10-08

## 현재 배포: 0.1.43 (통합 배포, 배포 보류 해제)
- 2026-10-08 17시대. AltStore 소스 버전 **0.1.43**, 릴리스 `build-43`·`latest` (GymNote.ipa 1,102,338바이트, sha256 a1da52d6…be9a, 두 릴리스 동일).
- 포함: 운동·일상 공간, 큰 운동/일상 전환 버튼, 로그인 선택 화면(이메일, Apple·Google은 준비 중)·오프라인 동기화, 일상 위젯과 운동 위젯 운동 이름·횟수 표시, 휴식 하나로 통일(세트 완료 시 설정 휴식 자동 시작), 휴식 −/+ 간격 설정.
- 배포 보류 해제: AGENTS.md의 보류 규칙 삭제. 이후 작업은 평소처럼 검증 후 main 통합·배포.
- 아이패드: AltStore → My Apps → 헬스노트 Update. 설치 후 로그인 화면, 전환 버튼, 일상 위젯 추가, 세트 완료 후 휴식 자동 시작, 기존 기록 유지를 확인할 것.

## 최신 로그인·오프라인 변경 (0.1.43에 배포)
- 로그인 첫 화면은 `App/LoginView.swift`의 Apple·Google·이메일 선택 화면으로 변경했다. 이메일 선택 후 로그인/회원가입, OTP 입력과 기록 가져오기 동의를 표시한다. Google·Apple은 실제 인증 서비스 연결 전이라 버튼을 비활성화하고 '준비 중'을 명시한다. 계정의 재인증·삭제·동기화 관리는 기존 화면을 유지한다. iPad에서는 최대 440pt로 입력 영역을 제한하고 작은 화면과 큰 글씨에서는 스크롤한다. Xcode Preview '로그인 선택'으로 확인할 수 있다.
- `codex/login`에서 운동·일상 공간과 기존 휴식 설정을 보존해 통합했다. 실행·계획·기록에 이어 네 번째 **설정** 탭을 사용하며 계정 관리는 설정 안에서 연다.
- 저장된 세션이 없는 Wi-Fi 첫 실행은 로그인 화면을 보여 준다. Wi-Fi가 없으면 기기의 게스트 기록으로 시작한다. 이미 로그인된 기기는 같은 계정의 캐시를 이어 쓰고 연결 복구 시 자동 동기화한다.
- 로그인 화면에서 기기 기록 가져오기에 동의하면 보호된 계정 사본에 먼저 추가한다. 연결 실패·앱 재실행 후에도 이어 쓸 수 있고, 서버 기록과 합쳐 버전을 비교해 저장한다. 원본 게스트 기록과 복구 사본을 유지하며 서로 다른 수정은 선택 없이 덮어쓰지 않는다. 일상 항목·완료 기록도 포함한다.
- 토큰은 비공유 Keychain에 유지하고 계정별 파일 및 서버 권한 검사를 유지한다. 모바일 데이터만 연결되면 동기화하지 않는다.
- 사용자 요청: Claude 작업이 끝난 뒤 한 번에 배포. 이번 변경은 로그인 브랜치의 배포 없는 CI만 실행하고 검증 후 로컬 main에 병합한다. main push·릴리스·AltStore 갱신은 보류한다. `Build IPA`는 `codex/login`에서 작업 전체를 건너뛴다.
- 실제 기기의 이메일 수신·로그인, Wi-Fi 해제/복구, 이전 설치 데이터 복원과 화면 조작은 0.1.43 설치 후 확인해야 한다.

## 한 줄 요약
아이패드용 개인 헬스 보조 네이티브 앱. Mac 없이 Windows + GitHub Actions로 빌드하고 AltStore(무료 Apple ID)로 설치한다. AltStore 소스 설치까지 성공했고, My Apps의 `7 DAYS` 표시를 확인했다. 이제 데이터 유지와 위젯·Live Activity 실제 동작을 확인한다.

## 환경
- 기기: 아이패드(iPad Pro, iPadOS 26 계열), Windows 노트북. Mac은 평소엔 못 쓰고 2026-10-08 저녁에 사용 가능.
- GitHub: `iasanullweb-maker/GymNote` (공개). Claude GitHub 앱 설치됨 → Claude가 직접 push 가능.
- 로컬 작업 폴더: `C:\Users\Donghyun\Documents\2026_IASA\GymNote` (Git 저장소, main 브랜치, GitHub과 동기화)
  - 최신 `GymNote.ipa`도 이 폴더에 받아둠 (.gitignore로 커밋 제외)
- Windows: iTunes(Apple 사이트 버전), iCloud(Apple 직접 링크 버전), AltServer 설치 완료.
- 아이패드: AltStore 설치 완료, 개발자 모드 켬.

## 앱 구성
| 폴더 | 내용 |
|---|---|
| `App/` | SwiftUI 앱: 운동 / 계획 / 기록 탭, 앱 아이콘 |
| `Widget/` | 홈·잠금 화면 위젯(세트 체크 버튼), 잠금 화면 휴식 타이머(Live Activity) |
| `Shared/` | 데이터 모델, App Group 공유 저장소, App Intents |
| `project.yml` | XcodeGen 설정 (Xcode 프로젝트 자동 생성) |
| `.github/workflows/build.yml` | 빌드 → ad-hoc 서명(엔타이틀먼트 포함) → .ipa → 릴리스 → AltStore 소스 갱신 |
| `scripts/make_source.py` | AltStore `source.json` 생성 |

### 기능 (현재)
- 날짜별 루틴 편집: 캘린더에서 날짜 선택, 선택한 주 일정 표시, 날짜/기존 요일 루틴 복사 (자동 주간 반복 없음)
- 운동 목록에 기본 세트·횟수·휴식을 저장해 날짜별 루틴에 가져오기 (복사 후 수정은 원본과 독립)
- 운동 탭: 최고 기록 영역 제거, 휴식 버튼이 같은 자리에서 휴식 중/카운트다운으로 전환
- 운동·기록 종목 추가는 입력창을 먼저 열고 저장할 때 생성 (취소하면 빈 항목 없음)
- 기존 데이터는 현재 주의 날짜 일정으로 한 번 이관, 요일 루틴은 복사용으로 보존, 기존 기록·진행 ID 유지
- 세트 체크, 세트 완료 시 휴식 타이머 자동 시작
- 위젯: 운동 줄 탭 = 세트 +1 (다 차면 0으로), 최고 기록 위 3개 종목, 휴식 버튼
- 휴식 끝 알림: 기본 무음(배너만), 루틴 탭 설정에서 소리 켜기
- 최고 기록: 종목 직접 추가/편집/삭제/순서 변경 (숫자형: 단위·낮을수록 좋음 옵션 / 라운드+횟수형), 위 3개가 위젯 표시
- 기록 첫 화면은 종목별 최고 기록·달성 날짜·그래프·전체 기록 보기를 표시. 개별 날짜별 기록 목록은 전체 기록 화면에서만 표시하며, 거기서 수정·삭제와 최고 기록 트로피 확인 가능
- 데이터: App Group 컨테이너의 `gymnote-data.json` (예전 형식도 읽게 디코딩 호환 처리)

## 배포 방식
- push(main) → Actions 빌드(약 2~4분) → 버전 `0.1.<run_number>`
- 릴리스: `build-N`(고정 주소, 최근 3개 유지) + `latest`
- AltStore 소스: `https://raw.githubusercontent.com/iasanullweb-maker/GymNote/altstore/source.json` (`altstore` 브랜치, Actions가 자동 갱신)

## 해결한 문제 (다시 겪지 않게)
- **AltStore 파일 선택 시 "file doesn't exist"**: 파일 앱 선택이 실패 → 노트북 AltServer **Shift+클릭 › Sideload .ipa**로 우회 (단, 이렇게 깔면 AltStore My Apps에 안 떠서 자동 갱신 불가) → AltStore 소스 방식으로 전환.
- **"name is invalid"**: Apple 앱 ID 이름에 한글 불가 → Info.plist 표시 이름을 `GymNote`로, 홈 화면 이름은 `ko.lproj/InfoPlist.strings`로 "헬스노트".
- **App Group**: AltStore가 그룹 ID 뒤에 팀 ID를 붙임 → `SharedStore`가 `ALTAppGroups`/프로비저닝 프로파일에서 실제 ID를 찾음. 실제 기기에서 `group.com.gymnote.app.56FM7SC53Q`로 "연결됨" 확인.
- GitHub GraphQL은 이 환경에서 막힘 → `gh api` REST 사용.

## 지금 진행 중
- AltStore 소스 설치와 업데이트 완료: 사용자가 My Apps의 `7 DAYS`와 버전 **0.1.6**을 확인함 (2026-10-08). 현재 앱 실행 시 개발자 신뢰 재승인이 필요.
- 데이터 유지, 위젯·잠금 화면 타이머 동작, 백그라운드 갱신 설정은 아직 확인 필요.
- 설치 중 겪었던 **"AltServer could not find this device"** 오류 참고:
  - 원인 후보: 두 기기 모두 VPN 켜짐(Bonjour 검색 불가), 와이파이의 기기 간 통신 차단, Windows 네트워크가 "공용", 방화벽.
  - 안내한 해결: **USB로 연결해서 설치**(가장 확실) 또는 VPN 끄기 + Windows 네트워크 개인으로 + 방화벽에서 AltServer/Bonjour 허용, 안 되면 휴대폰 핫스팟으로 테스트.
  - 설치 후 확인할 것: My Apps에 "7 DAYS"로 표시, AltStore Settings의 Background Refresh, 아이패드 설정 › AltStore › 백그라운드 앱 새로 고침.

## 다음 할 일 / 아이디어
1. 설정 → 일반 → VPN 및 기기 관리에서 본인 Apple ID의 개발자 앱을 신뢰한 뒤, 앱을 열어 기존 루틴·기록이 유지되는지 확인
2. 위젯·잠금 화면 타이머 실제 동작 확인, 실시간 현황 권한
3. 오늘 저녁 Mac: Xcode 설치 → `brew install xcodegen` → `xcodegen generate` → Team 선택 → 아이패드에서 실행 (미리보기·디버깅 목적. 무료 계정이면 7일 만료는 동일)
4. App Store 배포는 보호자 명의 Apple Developer Program(연 $99) 필요. 아이콘·스크린샷·개인정보 처리방침·설명문 준비. 기능을 더 다듬은 뒤 고려.

## 무료 서명 제약 (기억할 것)
- 7일마다 갱신 필요 (AltServer 켜진 노트북 + 같은 네트워크 또는 USB)
- 활성 앱 3개(AltStore 포함), 주당 앱 ID 10개(헬스노트는 앱+위젯 2개 사용)
- 만료돼도 데이터는 남고, 갱신하면 다시 열림

## 2026-10-08 수정본 빌드 결과 / 작업 분리
- 별도 워크트리: `C:\Users\Donghyun\.codex\worktrees\calendar-routines\GymNote`
- 이 채팅의 작업 브랜치: `codex/calendar-routines`. 코드 편집은 워크트리에서 수행. 기존 작업 폴더는 다른 채팅이 사용하므로 통합 전에 브랜치와 미커밋 변경을 확인할 것.
- 기능 수정 커밋: `25161b2` (main에 반영, GitHub Actions #6 성공).
- 배포 버전: `0.1.6`, 릴리스 `build-6`, AltStore 소스 갱신 완료.
- 새 IPA는 위 워크트리의 `GymNote.ipa`에 다운로드 (커밋 제외).
- 검증: Swift 모델 검증(구형 데이터 이전, 완료 세트·기록 유지, 자동 주간 반복 없음, 날짜별 진행 분리, 운동 목록 독립, JSON 재로드) 통과. 앱/위젯 iOS Release 컴파일과 패키징 성공.
- 실제 아이패드 화면, 캘린더 설정, 입력창과 휴식 표시 동작은 업데이트 후 확인 필요.
- 현재 GitHub 인증은 `iasanullweb-maker` 계정으로 완료. 명령 실행 시 `git -c credential.username=iasanullweb-maker ...` 사용.

## 워크트리 통합 원칙 (사용자 요청)
- 워크트리 작업 완료 시 사용자가 다시 말하지 않아도 **"워크트리 변경을 검토하고 기존 작업 브랜치에 합쳐줘."**를 실행한다. 변경 검토와 필요한 검증을 마치고 원래 작업 브랜치에 로컬 병합한다. 상시 작업 규칙은 저장소 루트의 `AGENTS.md`에도 기록했다.
- 다른 채팅의 변경은 보존하고 강제 push나 reset으로 덮어쓰지 않는다. 충돌은 의미를 확인해 해결하고, 사용자 판단이 필요한 경우에만 질문한다.
- 최종 답변에 통합 여부와 검증·빌드 결과를 명시한다.

## 2026-10-08 AltStore 갱신 멈춤 / 개발자 신뢰
- 증상: My Apps에서 헬스노트가 보이지 않음. Sources의 FREE → Approve 후 진행도가 멈춤. Refresh 실패 알림이 있었지만 상세 오류 문구는 확보하지 못했고, 재시도에서는 몇 분 동안 갱신이 끝나지 않음.
- 확인한 사실: Windows에서 Apple iPad USB 인식 정상, AltServer 응답 정상, Apple Mobile Device Service와 Bonjour Service 실행 중. 설치된 AltServer는 1.8.0. iTunes는 처음에 꺼져 있어 실행했지만, iTunes 미실행이 원인이라고 확정하지 않음.
- AltServer 자동 재시작 시 Windows가 프로세스 종료 권한을 거부함. 사용자에게 AltStore 완전 종료 → AltServer 트레이 Exit 후 재실행 → USB 연결·잠금 해제 유지 → AltStore 자체만 먼저 갱신 순서를 안내.
- 결과: 사용자가 AltStore 자체 갱신 성공을 확인. 이후 Sources → 헬스노트 → FREE → Approve로 설치 완료하고 **0.1.6** 표시를 확인함.
- 원인 판단: AltStore/AltServer 연결 또는 진행 중 요청의 일시적 정체 가능성. 상세 오류가 없어 AltServer만의 문제로 확정할 수 없음. 같은 배포 파일로 성공했으므로 IPA 배포 파일 문제 가능성은 낮음.
- 재발 시: 앱 삭제나 Shift+AltServer 직접 설치부터 하지 말고 위 갱신 복구 순서로 먼저 시도. 멈추면 iTunes의 아이패드 인식과 상세 오류 문구를 확인.
- 후속 증상: 헬스노트 실행 시 '신뢰하지 않는 개발자' 표시. **설정 → 일반 → VPN 및 기기 관리 → 본인 Apple ID의 개발자 앱 → 신뢰** 안내. 화면에 재시작 안내가 나오면 따를 것.
- 개발자 신뢰는 iPadOS의 실행 승인 상태이며, 이 메시지 자체는 앱 설정·기록 초기화의 증거가 아님. 신뢰가 다시 필요한 정확한 이유(서명 인증서 등)는 확인하지 못함. 앱 데이터 유지 여부도 실행 후 확인 필요.
- 참고: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows / https://faq.altstore.io/altstore-classic/troubleshooting-guide

## 2026-10-08 기록 첫 화면 정리 (최신 빌드 0.1.8)
- 사용자의 최종 요청: 최고 기록·달성 날짜·그래프·전체 기록 보기 유지. 첫 화면에 누적되는 날짜별 개별 기록 목록만 제거.
- 전체 기록 화면에서 기존 기록 열람·수정·삭제와 최고 기록 트로피 표시 유지. 저장 데이터 변경 없음.
- 최종 기능 커밋: `d7cee1a`, main 통합 완료. GitHub Actions #8에서 모델 검증, 앱/위젯 Release 빌드, IPA 패키징, AltStore 소스 갱신 성공.
- 배포 버전 `0.1.8`, 릴리스 `build-8`. 워크트리의 `GymNote.ipa`를 최신 파일로 교체하고 릴리스 SHA256 일치 확인.
- 아이패드에서 AltStore My Apps → 헬스노트 Update로 설치 후 화면 확인 필요.

## 계획 캘린더 / 운동 일지 연동
- 루틴 탭 이름을 계획으로 변경. 월간 날짜 칸 높이를 키우고 날짜 아래에 그날의 여러 운동 이름을 작은 글씨로 표시. 월 이동·오늘 선택·선택한 주 목록 유지.
- 운동 시작 → 세트 체크 → 모든 세트 완료 시 자동으로 운동 일지 저장. 일부 세트만 완료한 경우 운동 마치기로 저장 가능. 세트 완료 전에는 시작 취소 가능.
- 기록 탭에서 최고 기록 / 운동 일지를 선택. 최고 기록 그래프와 종목 기능 유지. 일지에는 날짜·운동 이름·완료 세트·계획의 세트당 횟수/시간·운동 시간을 저장.
- 시작 당시 계획을 복사해 일지로 보존하므로 이후 계획 수정과 독립. 진행 중 세션은 저장 파일에 포함돼 앱 재실행 후 복원. 완료 세트 0인 일지와 중복 종료 저장 방지.
- Codable 새 필드(activeWorkout, workouts)는 구형 파일에서 nil/빈 배열로 디코딩. 기존 기록 보존.
- 검증 브랜치(codex/**)는 모델 검사와 iOS 앱·위젯 빌드 및 IPA artifact까지만 수행. 릴리스·AltStore 소스 갱신은 main에서만 수행. 검증 후 main에 통합한다.

## 계획·운동 일지 최종 검증 / 배포 0.1.10
- 기능 커밋 `ac47425`. 전용 브랜치 Actions #9에서 Swift 모델 검증, 앱·위젯 iOS Release 컴파일과 IPA 생성 통과 후 main에 통합.
- main Actions #10 성공, 버전 **0.1.10** / 릴리스 `build-10` 배포 및 AltStore 소스 갱신 완료.
- 워크트리의 `GymNote.ipa`를 0.1.10으로 교체, 공개 릴리스 SHA256 일치 확인.
- 추가 검증: 2024/2026 모든 달의 주 정렬·일수·중복 없는 날짜, 구형 파일에서 세션/일지 필드 생략 디코딩, 진행 중 중복 시작 방지, 0세트 저장 방지, 체크 취소, 세션 JSON 복원, 계획이 변경돼도 시작 당시 운동과 횟수 보존, 마지막 세트 자동 저장, 최고 기록 유지, 중복 종료 방지, 일부 세트 종료·일지 재로드.
- 실제 아이패드에서 큰 달력·여러 운동 이름 표시, 운동 시작→완료→기록의 운동 일지 흐름 확인 필요.
- 일지의 횟수/시간은 시작 당시 계획의 세트당 기준을 자동 복사한 값이며 실제 수행 횟수를 센서는 측정하지 않음. 현재 운동 화면은 하루 일지 저장 후 저장됨 상태로 표시.

## 캘린더 날짜 표기·글씨 / 미리보기
- 계획 캘린더와 선택한 주 목록의 날짜는 '1일' 대신 숫자 '1'처럼 표시.
- 월 제목 title, 요일 16pt, 날짜 22pt, 운동 이름·휴식 14pt로 확대. 날짜 칸 최소 높이 132pt.
- `App/PlanCalendarView.swift`에 샘플 데이터를 사용하는 Xcode `#Preview("계획 캘린더")` 추가. 월 이동·날짜 선택을 실제 SwiftUI 미리보기에서 확인 가능.
- 실제 iOS/iPadOS 시뮬레이터와 SwiftUI 미리보기는 Mac의 Xcode에서 확인. Windows 브라우저 시안은 배치 확인용이며 네이티브 실행 검증과 다름. GitHub macOS 실행 환경의 시뮬레이터 캡처도 대안이지만 현재 자동 캡처는 미구현.
## 기록 화면 종목별 + 버튼 / 배포 0.1.15
- 각 종목(푸쉬업·풀업·신디 등) 머리글 오른쪽의 **+ 기록** 버튼으로 그 종목 기록을 바로 추가. 이때 입력창의 종목 선택 칸은 숨김.
- 오른쪽 위 '종목 편집'·'+' 버튼 제거. 종목 추가·편집·순서 변경은 목록 맨 아래 **종목 추가 · 편집 · 순서**로 이동.
- 작업 방식: 워크트리 `claude/record-quick-add`에서 수정 → 브랜치 검증 빌드(Build IPA, 모델 검증 포함) 성공 → 변경 검토 → main에 fast-forward 통합.
- main Actions #15 성공, 버전 **0.1.15** 배포 및 AltStore 소스 갱신. 실제 아이패드 화면 확인 필요.

## 작업 원칙 (사용자 요청, 매번 적용)
- 작업은 별도 워크트리/브랜치에서 하고, 끝나면 변경 검토와 검증 빌드 후 원래 작업 브랜치(main)에 통합한다. 따로 말하지 않아도 이렇게 진행.

## 캘린더 글씨 최종 검증 / 배포 0.1.18
- 날짜 숫자 표기와 확대된 캘린더 글씨, Xcode 캘린더 미리보기 반영. 미리보기는 별도 샘플 초기화로 실제 계정 저장소를 열거나 샘플 데이터로 덮어쓰지 않는다.
- 다른 채팅의 계정 기능 및 기록 종목별 + 버튼 변경을 보존해 통합. HANDOFF 충돌은 양쪽 기록을 모두 유지하여 해결.
- 통합 커밋 `578eb7f`. 브랜치 Build IPA #17 및 Validate GymNote #7 성공: 모델/계정 검사, iPad 시뮬레이터 보안 회귀 테스트, DB 권한·동시 백업, 계정 삭제 권한 검사, 앱/위젯 Release 빌드 통과.
- 기존 main에 fast-forward 통합 후 main Actions #18 성공. **0.1.18** / `build-18` 릴리스와 AltStore 소스 게시 확인.
- 워크트리의 `GymNote.ipa`를 0.1.18로 교체하고 공개 릴리스 SHA256 일치 확인.
- 로컬 Windows에서는 Xcode 시뮬레이터/Canvas 실행 불가. Mac에서는 `App/PlanCalendarView.swift`의 '계획 캘린더' Preview로 설치 없이 월 이동·날짜 선택을 확인할 수 있다. 실제 화면 시각 검토는 아직 하지 않았으며 GitHub 시뮬레이터 테스트 성공과 구분할 것.
## 앱 점검 수정 5건 / 배포 0.1.20
- 브랜치 `claude/app-fixes`(워크트리)에서 수정 → 브랜치 검증 빌드(모델 회귀 검사 포함) 성공 → 검토 → main fast-forward 통합 → main Actions #20 성공, **0.1.20** 배포·AltStore 소스 갱신.
1. 기록 파일 보호 등급 `completeUntilFirstUserAuthentication`으로 변경 + 기존 json 파일 변환(`relaxProtection`, activate 시). 잠금 상태에서도 위젯 표시. 토큰은 키체인 유지. LOGIN_SETUP.md 문구 갱신.
2. 위젯 세트 체크(`completeSetFromWidget`): 진행 중 운동이 없고 오늘 저장한 일지도 없으면 운동 자동 시작 → 일지에 남음. 이미 저장한 날은 기존처럼 체크만.
3. 날짜가 지난 진행 중 운동(`closeStaleWorkout`): 앱 reload·운동 시작·위젯 체크 때 정리. 완료 세트 있으면 일지 저장(endedAt 없음 → 운동 시간 미표시), 0세트면 버림.
4. 하루 여러 운동: 저장 후 운동 탭에 '새 운동 시작'. 새 운동은 그날 계획 운동의 완료 세트를 0으로 초기화하고 시작, 이전 일지는 보존.
5. 계획 탭 '이 주 계획을 다음 주에도 반복' (1/2/4/8주). 오늘 이후 날짜만 덮어씀, 복사본은 새 운동 ID.
- 실제 아이패드 확인 필요: 잠금 화면 위젯 표시, 위젯 첫 체크 후 운동 탭 '운동 중' 표시, 주간 반복.

## 설정 탭 / 운동 탭 휴식 −/+ (배포 0.1.25)
- 계정 탭 → **설정 탭**(`App/SettingsView.swift`): 기본 휴식(15초 단위, 15~600초), 휴식 끝 알림 소리, 계정(기존 `AccountView`를 시트로 열기, 코드 변경 없음), 진단.
- 운동 탭 휴식 타이머 행 오른쪽에 −/+ (`AppModel.adjustDefaultRest`, 범위는 `SettingsView.restRange/restStep` 공용).
- 계획 탭의 설정·진단 섹션 제거(설정 탭으로 이동).
- 브랜치 `claude/settings-tab` 검증 빌드 성공 → main fast-forward → main Actions #25 성공, 0.1.25 배포.
- **codex/calendar-routines 통합 시 주의**: `App/GymNoteApp.swift` RootView에서 충돌 (main은 4번째 탭이 `SettingsView`, 그 브랜치는 탭을 없애고 사람 아이콘으로 `AccountView` 시트). 그 구조를 쓸 경우 아이콘을 설정(gearshape)으로 바꾸고 시트에 `SettingsView()`를 띄우면 휴식 설정·계정·진단이 모두 유지됨. `RoutineView`는 자동 병합됨.

## 운동·일상 공간 통합
- 상단 운동/일상 선택, 공통 실행·계획·기록 탭. 마지막 분야 기억, 계획의 선택 날짜 공유. 일상에서도 진행 중 운동으로 돌아갈 수 있음. 공부 기능은 제외.
- 오른쪽 위 설정 버튼에서 SettingsView 열기. Claude의 0.1.20 및 0.1.25 수정(위젯/지난 운동 정리/여러 운동/주 반복/휴식 −/+)과 다른 Codex의 SMTP 안내 모두 보존.
- 일상: 날짜 지정 또는 미정 할 일, 매일·지정 요일·N일 간격 습관, 날짜별 건너뛰기/복원, 완료/취소. 추가 버튼은 빈 항목 저장 없이 편집창부터 열고 저장 시 추가.
- 일상 실행에 오늘 일정·지난 미완료·날짜 미정 표시. 지난 일정은 원래 날짜에 체크하거나 편집에서 이동. 계획에서 선택한 날짜/주 일정과 운동·일상 전체 캘린더 제공.
- 완료 기록은 제목·메모·종류·계획 날짜·실제 완료 시각을 복사해 보존. 항목 수정/삭제와 독립. 주간 할 일/습관 완료 수, 현재 반복 일정 기준 오늘까지 습관 달성률과 날짜별 완료 내역/취소 제공.
- AppData 새 dailyItems/dailyCompletions는 구형 저장 파일에서 빈 배열로 읽음. 계정 파일·백업·게스트 가져오기에 포함. 변경은 ID별 적용하여 동시 운동/위젯 변경 보존.
- 일상 실행/계획 Xcode Preview 추가. AppModel 미리보기는 편집까지 메모리에서만 수행하여 실제 저장소 접근 방지.
- 기능 검증 커밋 `e0a93c8`: 브랜치 Build IPA #26 및 Validate GymNote #11 성공. 기존 운동/계정 회귀 검사, 새 일상 반복·예외·완료 스냅샷·구형 파일·계정 가져오기·동시 운동 변경 검사, 실제 계정 파일 격리/미리보기 저장 방지 테스트, 앱/위젯 Release와 iPad 시뮬레이터 테스트 통과.
- 네이티브 화면 시각 검토와 실제 아이패드 조작은 아직 확인하지 않음. 공부와 일상 알림 기능은 이번 범위에 없음.
## 운동·일상 최종 배포 0.1.28
- main 통합 커밋 `585ed57`. main Actions #28 성공, **0.1.28** / `build-28` 배포 및 AltStore 소스 게시 확인.
- 검증된 기능 코드에 인계 문서만 추가한 상태로 통합. 다른 채팅의 최신 main 변경(0.1.25 설정·휴식 −/+)과 로컬 main SMTP 문서를 모두 포함.
- 워크트리 `GymNote.ipa`를 새 파일로 교체하고 GitHub 릴리스 SHA256 일치 확인.
- 실제 아이패드에서 운동↔일상 전환, +에서 할 일/습관 추가, 완료→기록, 날짜 이동과 습관 건너뛰기/복원, 설정의 휴식 −/+를 확인할 것.
## 휴식 −/+ 간격 설정 / 버튼 크기 (배포 0.1.33)
- 사용자 의도: 운동 탭 휴식 −/+를 누를 때 바뀌는 **간격**을 설정에서 조절. `AppData.restStep`(기본 15초) 추가, 설정 탭 '−/+ 버튼 간격' 5~120초·5초 단위. 기본 휴식도 5초 단위, 최소 5초(`SettingsView.restRange` 5...600).
- `applyingEdits`에 restStep 병합 추가, 예전 파일은 15초로 읽음. 모델·계정 회귀 검사 추가.
- −/+ 아이콘 크기 고정(22pt, semibold)으로 두 버튼 크기 통일.
- 작업 중 main이 0.1.28(일상 작업 통합)로 앞서 나가 `origin/main`을 브랜치에 병합. `Models.swift` CodingKeys 충돌은 restStep + dailyItems/dailyCompletions 모두 유지로 해결. 병합본 검증 빌드 성공 → main fast-forward → Actions #33 성공, **0.1.33** 배포.
## 휴식 하나로 통일 / 세트 완료 시 자동 휴식
- 사용자 요청: 운동마다 휴식을 다르게 둘 필요가 없음. 세트 완료를 누르면 설정한 휴식이 자동으로 시작.
- `AppModel.completeSet`: 운동별 `restSeconds` 대신 `data.defaultRest`로 `startDefaultRest()`. 0초 운동도 이제 휴식이 켜짐. 마지막 세트로 운동이 일지에 저장되면 휴식 안 켬(기존과 동일).
- 계획·운동 목록 편집창의 '세트 사이 휴식' 항목 제거, 목록·운동 탭 부제에서 휴식 표시 제거. 설정 탭 이름을 '세트 사이 휴식'으로, 설명에 모든 운동 공통 자동 시작 명시.
- `Exercise.restSeconds`는 예전 파일·계정 동기화·다른 브랜치 호환을 위해 필드만 유지(없으면 0으로 디코딩, 기본값 0). 모델 회귀 검사 추가.
- 위젯 세트 체크는 지금도 휴식을 켜지 않음(앱 운동 탭만 자동). 필요하면 `CompleteSetIntent`를 LiveActivityIntent로 바꿔 확장 가능.
- 브랜치 `claude/unified-rest` Build IPA #40 성공(모델 검증·Release 빌드·IPA) → main fast-forward.
- **codex/calendar-routines 통합 시 주의**: 그 브랜치가 `ExerciseDraftForm`/`completeSet`을 바꿨다면 운동별 휴식 Stepper가 다시 들어오지 않게 확인.


## 운동·일상 전환 버튼 확대 (0.1.43에 배포)
- 기존 360pt 폭 제한의 작은 segmented Picker 대신 화면 너비를 나눠 쓰는 큰 버튼 두 개 배치. 최소 높이 60pt, 아이콘과 title3 글씨를 가운데 정렬.
- 운동은 주황색, 일상은 청록색. 선택한 버튼의 배경·테두리·체크 표시로 현재 분야 구분. VoiceOver 선택 상태, 동작 줄이기 설정 지원. 마지막 분야 기억과 선택한 탭/날짜 유지.
- `App/WorkspaceSwitcher.swift`의 '분야 전환' Xcode Preview에서 별도 저장소 없이 전환 가능. 실제 화면 시각 검토는 아직 하지 않음.
- 검증 커밋 `6d78a23`: 브랜치 Build IPA #39와 Validate GymNote #18 성공. 모델/계정/일상 검사, 앱·위젯 Release 빌드, iPad 시뮬레이터 회귀 검사 통과. 최신 로컬 로그인·일상 위젯과 원격 0.1.33 휴식 간격 수정 보존.
- 기존 main에 로컬 통합. AGENTS.md 배포 보류에 따라 main push·릴리스 게시·AltStore 소스 갱신은 하지 않음. 이후 통합 배포에 포함할 것.

## 최종 통합 / 배포 0.1.43
- 원격 main `ecf68ef`(Claude: 휴식 하나로 통일)과 노트북 로컬 main `6ba793a`(Codex: 로그인·오프라인, 전환 버튼, 일상 위젯; 원격 `codex/calendar-routines`와 동일, 미커밋 변경 없음)를 병합. 병합 커밋 `f762cbd`.
- 충돌은 HANDOFF.md 끝부분뿐이었고 양쪽 기록을 모두 유지. 코드 파일은 자동 병합(SettingsView는 Codex '저장 상태' 섹션 + Claude '세트 사이 휴식' 문구 둘 다 유지).
- 코드 검토: `completeSet`→`startDefaultRest()`, 계획 편집창 운동별 휴식 없음, 새 위젯·로그인 코드에 `restSeconds` 사용 없음, `WorkspaceSwitcher`(최소 높이 60pt)·`LoginView`·`DailyWidget`(WidgetBundle 등록)·운동/일상 탭 분기 포함 확인.
- 검증: `codex/final-integration`에서 Build IPA #42(모델 검증·앱/위젯 Release 빌드·IPA, 릴리스 단계 건너뜀)와 Validate GymNote #19(ios 시뮬레이터 회귀, database 권한, account-deletion) 모두 성공.
- main fast-forward 후 main Actions #43 한 번만 실행, 성공 → 0.1.43 릴리스·AltStore 소스 게시 확인.
- `build.yml`의 `codex/login` 빌드 건너뛰기 조건은 배포와 무관하므로 유지.
