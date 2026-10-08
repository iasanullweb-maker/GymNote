# 헬스노트 (GymNote)

아이패드용 헬스 보조 앱. Mac 없이 GitHub Actions로 빌드하고 AltStore로 설치한다.

## 기능

- **운동**: 날짜별 루틴, 세트 체크, 세트 완료 시 같은 자리에서 휴식 타이머 표시
- **계획**: 캘린더에서 날짜별 설정, 선택한 주의 운동 표시, 다른 날짜 루틴 복사
- **운동 목록**: 운동 종류와 기본 세트·횟수·휴식을 저장하고 루틴에 가져오기
- **위젯**: 홈 화면(소·중·대·특대)에서 운동을 탭해서 세트 체크, 최고 기록, 휴식 버튼 / 잠금 화면 위젯
- **휴식 타이머**: 잠금 화면에 카운트다운(Live Activity), 끝나면 알림
- **최고 기록**: 푸쉬업, 풀업, 신디(라운드 + 추가 횟수), 기록 그래프
- **운동 일지**: 운동 시작 후 완료 세트·세트당 횟수/시간을 자동 저장, 기록 탭에서 확인
- **단축어/Siri**: "헬스노트 휴식 시작"
- **계정**: 이메일 인증번호 로그인, 계정별 기록 보관·동기화, 기존 기기 기록 가져오기, 계정 삭제 (Supabase 연결 필요)

로그인 연결과 보안 설정: [설정 가이드](docs/LOGIN_SETUP.md). 연결 전에도 게스트 운동 기능은 그대로 사용할 수 있다.

## 폴더 구조

```
App/       앱 화면 (운동 / 계획 / 기록)
Widget/    홈·잠금 화면 위젯, 잠금 화면 휴식 타이머
Shared/    앱과 위젯이 같이 쓰는 코드 (데이터, 저장, 인텐트)
project.yml                 XcodeGen 설정 (Xcode 프로젝트를 자동 생성)
.github/workflows/build.yml GitHub Actions 빌드 → GymNote.ipa
```

## 빌드

1. 이 폴더를 GitHub 저장소(**공개** 저장소면 macOS 빌드 무료)에 올린다.
2. `main` 브랜치에 push하면 Actions 탭에서 빌드가 돈다 (10분 안팎).
3. 성공하면 Releases의 **latest**에 `GymNote.ipa`가 올라간다.

실패하면 Actions 로그에서 `error:`가 있는 줄을 복사해서 Claude에게 보여주면 된다.

## 설치 (AltStore 소스, 추천)

1. AltStore → **Sources** → **+** → 아래 주소 추가
   `https://raw.githubusercontent.com/iasanullweb-maker/GymNote/altstore/source.json`
2. **Browse**(또는 소스 화면)에서 헬스노트 **설치**
3. 새 버전은 AltStore **My Apps**에 업데이트로 뜸
4. 7일 갱신: 노트북 AltServer를 켜두고 같은 Wi-Fi면 AltStore가 백그라운드에서 갱신

## 설치 (노트북에서 직접)

AltServer 트레이 아이콘을 **Shift + 클릭** → **Sideload .ipa…** → `GymNote.ipa`
(이 방법은 AltStore My Apps에 안 떠서 자동 갱신이 안 됨)

## 처음 실행 후

- 알림 권한 **허용** (휴식 끝 알림)
- **계획** 탭 → 아래 **진단**이 "연결됨"인지 확인 (위젯이 앱 데이터를 읽을 수 있는지)
- 홈 화면 편집 → 위젯 → 헬스노트 → **중간** 이상 크기 추가 (운동을 탭해서 세트 체크)
- 잠금 화면 편집 → 위젯 → 헬스노트 (직사각형 추천)
- 잠금 화면 타이머가 안 뜨면: 설정 › 헬스노트 › **실시간 현황** 켜기

## 위젯 체크 규칙

- 운동 한 줄을 탭할 때마다 세트 +1
- 다 채운 상태에서 한 번 더 탭하면 0으로 돌아감 (실수했을 때 되돌리기)

## 주의

- 무료 Apple ID 서명은 7일마다 만료 → AltStore에서 **Refresh All** (AltServer 켜진 노트북 필요)
- 만료돼도 데이터는 남아 있고, 갱신하면 다시 열린다

## 나중에 Xcode를 쓸 수 있게 되면

```
brew install xcodegen
xcodegen generate
open GymNote.xcodeproj
```
Signing & Capabilities에서 팀을 고르고, App Group(`group.com.gymnote.app`)을 앱과 위젯 둘 다에 켜면 된다.
