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
| `App/` | SwiftUI 앱: 운동 / 루틴 / 기록 탭, 앱 아이콘 |
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
- 기록 탭하면 수정, 종목별 "전체 기록 보기", 최고 기록 트로피 표시, 그래프
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
- AltStore 소스 설치 완료: 사용자가 My Apps의 **`7 DAYS` 표시를 확인**함 (2026-10-08).
- 데이터 유지, 위젯·잠금 화면 타이머 동작, 백그라운드 갱신 설정은 아직 확인 필요.
- 설치 중 겪었던 **"AltServer could not find this device"** 오류 참고:
  - 원인 후보: 두 기기 모두 VPN 켜짐(Bonjour 검색 불가), 와이파이의 기기 간 통신 차단, Windows 네트워크가 "공용", 방화벽.
  - 안내한 해결: **USB로 연결해서 설치**(가장 확실) 또는 VPN 끄기 + Windows 네트워크 개인으로 + 방화벽에서 AltServer/Bonjour 허용, 안 되면 휴대폰 핫스팟으로 테스트.
  - 설치 후 확인할 것: My Apps에 "7 DAYS"로 표시, AltStore Settings의 Background Refresh, 아이패드 설정 › AltStore › 백그라운드 앱 새로 고침.

## 다음 할 일 / 아이디어
1. 설치한 앱을 열어 기존 루틴·기록이 유지되는지 확인
2. 위젯·잠금 화면 타이머 실제 동작 확인, 실시간 현황 권한
3. 오늘 저녁 Mac: Xcode 설치 → `brew install xcodegen` → `xcodegen generate` → Team 선택 → 아이패드에서 실행 (미리보기·디버깅 목적. 무료 계정이면 7일 만료는 동일)
4. App Store 배포는 보호자 명의 Apple Developer Program(연 $99) 필요. 아이콘·스크린샷·개인정보 처리방침·설명문 준비. 기능을 더 다듬은 뒤 고려.

## 무료 서명 제약 (기억할 것)
- 7일마다 갱신 필요 (AltServer 켜진 노트북 + 같은 네트워크 또는 USB)
- 활성 앱 3개(AltStore 포함), 주당 앱 ID 10개(헬스노트는 앱+위젯 2개 사용)
- 만료돼도 데이터는 남고, 갱신하면 다시 열림
