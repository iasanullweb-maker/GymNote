# AltStore 갱신 문제 빠른 해결

헬스노트는 무료 Apple ID로 AltStore에서 서명하므로 **7일마다 Refresh**가 필요하다. Refresh는 노트북 AltServer가 Apple 서버에 접속해 새 서명을 받아 iPad에 넣는 과정이다. 그래서 다음 셋 중 하나라도 막히면 실패한다.

1. **iPad ↔ 노트북 연결:** 같은 Wi-Fi(학교망은 기기 간 통신이 막히는 경우가 많음) 또는 USB
2. **노트북 프로그램:** AltServer, iTunes·iCloud(Apple 홈페이지판), Apple Mobile Device Service, Bonjour
3. **노트북 → Apple 서버 접속:** 학교망에서는 막힐 수 있음 → VPN 또는 휴대폰 핫스팟

**기존 AltStore·헬스노트 앱은 삭제하지 않는다.** 삭제하면 기기에만 있던 기록을 잃을 수 있다.

## 1분 해결 순서

1. 노트북에서 **`AltStore 진단.cmd`**(저장소 맨 위)를 더블클릭하고, iPad에 뜬 오류 문구를 붙여 넣는다. 화면의 "원인 후보와 해결 순서"를 위에서부터 따른다.
2. 결과가 애매하면 Claude/Codex에게 "AltStore 진단 봐줘"라고 한다. 보고서는 `.validation-tools/altstore-doctor/latest.txt`에 저장된다(Git 추적 안 함).
3. 학교에서는 기본으로 **노트북 VPN 켜기 + iPad USB 연결 + 잠금 해제 → AltStore → My Apps → Refresh All**로 한다.

## 오류 문구별 원인과 해결

| iPad에 보이는 증상·문구 | 원인 | 해결 |
|---|---|---|
| `Could not find AltServer` | iPad가 노트북을 못 찾음(학교 Wi-Fi 기기 간 차단, AltServer 꺼짐) | USB 연결·잠금 해제·신뢰 → AltServer 실행 확인 → Refresh All. 처음 한 번 iTunes에서 "Wi-Fi를 통해 이 iPad와 동기화" 켜기 |
| `The operation timed out`, `12002`, `The request timed out` | 노트북 → Apple/AltStore 서버 접속이 막힘(학교망) | 노트북 VPN 또는 핫스팟 → USB 연결 → Refresh All. (2026-10-19 사례) |
| iTunes에 iPad가 안 보임 | USB 인식 실패 | 잠금 해제 후 재연결·"신뢰" → 다른 포트/데이터 케이블 → iTunes 종료 후 Apple Mobile Device Service 다시 시작 → 그래도 안 되면 iPad 설정 → 일반 → 전송 또는 재설정 → 재설정 → **위치 및 개인정보 보호 재설정**(데이터 유지) 후 재연결. 장치 관리자에 느낌표가 있으면 Apple Mobile Device USB Driver 제거 후 재연결 (2026-10-21 사례) |
| `HTTP 503`, `Service Unavailable` (502·504 포함) | 서버가 요청 거절: 학교망 필터/프록시 또는 Apple·AltStore 서버 일시 장애 | 노트북·iPad VPN 또는 핫스팟 → Refresh All. 계속되면 [Apple 개발자 시스템 상태](https://developer.apple.com/system-status/)의 Certificates, Identifiers & Profiles·Account 확인 후 대기. 만료 전이면 앱은 계속 사용 가능 (2026-10-21 사례: 학교 Wi-Fi·VPN 끔에서 발생, 노트북·iPad VPN + USB로 해결) |
| `Incorrect Apple ID or password`, `session expired`, `-22411`, `-36607` | Apple ID 로그인 만료 | AltStore → Settings 로그아웃 → 같은 Apple ID로 로그인(2단계 인증 코드 입력) |
| `anisette`, `-45054` | iCloud 인증 정보 생성 실패 | iCloud(웹 설치판) 실행·로그인 → AltServer 재시작 |
| `Maximum App ID limit`, `10 App IDs` | 무료 계정 주간 App ID 한도(7일 10개) | 번들 ID 변경·새 앱 설치 금지. 7일 기다림. 헬스노트는 앱+위젯 2개를 쓴다 |
| `maximum number of apps`, 활성 앱 3개 | 무료 계정 활성 앱 3개(AltStore 포함) | My Apps에서 안 쓰는 앱 Deactivate |
| AltStore 자체가 안 열림 / 만료 표시 | 서명 만료 | 노트북 AltServer 트레이 → Install AltStore → 해당 iPad, **같은 Apple ID로 덮어 설치(삭제 금지)** → Refresh All |
| 새 버전이 안 보이거나 UPDATE 다운로드 실패 | iPad → GitHub 접속 막힘, 소스 캐시 | iPad VPN/핫스팟 → Browse 화면 당겨서 새로고침 → UPDATE. 앱 문제인지는 `source.json`의 버전·크기와 릴리스 IPA를 대조 |
| Microsoft Store판 iTunes/iCloud 설치 | AltServer 비호환 | Store판 제거 → Apple 홈페이지판 설치 |

## 예방 장치

- **앱 안 만료 표시(0.1.116 이후 배포분):** 설정 → 진단에 `앱 서명 만료: 날짜 · 남은 시간`이 보이고, 48시간 이내면 설정 맨 위에 "AltStore 갱신 필요" 안내와 "AltStore 열기" 버튼이 나온다. 만료 **48·24·3시간 전**에 알림이 온다(일상 알림 설정과 무관, 알림 권한 필요). Refresh하면 새 만료일로 알림이 다시 맞춰진다.
- **갱신은 여유 있게:** 알림이 오면 집 Wi-Fi(AltServer와 같은 네트워크)에서 노트북을 켠 채로 두거나, 학교에서는 VPN+USB로 바로 Refresh한다. 만료 직전까지 미루지 않는다.
- **진단 먼저, 삭제는 마지막:** 단순 시간 초과로 Apple ID 변경·앱 삭제·프로그램 전체 재설치를 먼저 하지 않는다.

## 참고

- [AltServer 공식 안내](https://faq.altstore.io/altstore-classic/altserver), [문제 해결 가이드](https://faq.altstore.io/altstore-classic/troubleshooting-guide)
- 사례 기록: [HANDOFF](../HANDOFF.md)의 2026-10-19 12002 시간 초과, 2026-10-21 USB 미인식 기록
