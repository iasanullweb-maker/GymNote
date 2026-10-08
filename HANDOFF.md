# 헬스노트 (GymNote) 작업 인계

마지막 업데이트: 2026-10-08

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
- 워크트리 작업 완료 시 별도 병합 요청 없이 변경 검토와 필요한 검증을 마치고 원래 작업 브랜치에 통합한다.
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
