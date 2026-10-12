# 카카오톡 작업함 연결

2026-10-12: 사용자가 텔레그램 계정 대신 카카오톡 채널 챗봇 + 스킬 서버를 선택했다. 아래 코드와 로컬 검사는 구현 범위이며 채널 생성·공개 HTTPS 연결·운영 배포는 별도 설정이다.

흐름: 카카오톡 채널 → 챗봇 폴백/명령 블록 → 공개 HTTPS → PC의 스킬 전용 포트 8766 → 기존 SQLite 작업 큐 → Codex 구현·검토·검증·로컬 통합. 관리자 화면은 PC의 8765에만 유지한다. PC·서비스·HTTPS 연결이 켜져 있어야 한다.

## 1. 채널과 챗봇 만들기

1. [카카오톡 채널 관리자센터](https://center-pf.kakao.com/)에서 개인 작업함용 채널을 만든다. 예: GymNote 작업함.
2. [챗봇 관리자센터](https://chatbot.kakao.com/)에서 카카오톡 챗봇을 만든다. 계정에 이용 신청/승인 화면이 나오면 해당 절차를 먼저 진행한다.
3. 봇 설정의 카카오톡 채널 연결에서 만든 채널을 연결한다. 개발채널과 운영채널을 구분한다.
4. 봇 설정/관리 URL에서 봇 ID를 확인한다. 실제 스킬 payload의 `bot.id`와 일치해야 한다. 채널 검색용 ID와 봇 ID는 다르다.

## 2. 로컬 설정과 비밀 헤더 준비

`automation/config.example.json`을 Git 밖 `%LOCALAPPDATA%/GymNoteAutomation/config.json`에 복사한다. 기존 파일이 있다면 덮어쓰지 말고 필요한 항목만 추가한다. `projects.gymnote.path`는 원본 저장소, `branch`는 기존 main이다. Codex 실행 파일 경로도 실제 PC와 대조한다.

첫 연결은 다음 설정으로 시작한다.

```json
{
  "telegramEnabled": false,
  "kakaoEnabled": true,
  "kakaoPort": 8766,
  "kakaoBotIds": ["만든-봇-ID"],
  "kakaoUserKeys": [],
  "kakaoDiscoveryEnabled": true,
  "executionEnabled": false,
  "maxTasksPerSession": 1
}
```

위 JSON은 기존 설정에 추가/수정할 항목만 보여 준다. `projects`, `defaultProject`, `port`, `codexExecutable`은 예시의 기존 항목을 유지한다. bot/user ID는 문자열이며 Kakao 로그인 사용자 번호와 다르다. 발견 모드에서는 허용된 봇의 `내정보`만 미등록 사용자에게 답한다. 다른 메시지는 저장·실행되지 않는다.

같은 PowerShell 창에 서로 다른 관리자·스킬 비밀값을 준비한다. Windows PowerShell 5.1에서도 실행 가능한 예:

```powershell
function New-GymNoteSecret {
    $taskBytes = New-Object byte[] 32
    $taskGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $taskGenerator.GetBytes($taskBytes) }
    finally { $taskGenerator.Dispose() }
    return [BitConverter]::ToString($taskBytes).Replace('-', '').ToLowerInvariant()
}
$env:GYMNOTE_AUTOMATION_ADMIN_TOKEN = New-GymNoteSecret
$env:KAKAO_SKILL_TOKEN = New-GymNoteSecret
```

스킬 토큰은 영문/숫자/`_`/`-`로 32~128자여야 한다. 카카오 관리자센터의 비밀 헤더 설정에 복사할 때만 본인 로컬 창에서 `$env:KAKAO_SKILL_TOKEN`을 확인한다. 토큰을 이 채팅·Git·URL·로그에 넣지 않는다. 개인 비밀번호 관리자에 보관한 기존 값을 숨김 입력으로 다시 쓰려면:

```powershell
$taskSkillSecret = Read-Host 'Kakao skill token' -AsSecureString
$env:KAKAO_SKILL_TOKEN = ([PSCredential]::new('skill', $taskSkillSecret)).GetNetworkCredential().Password
```

새 PowerShell 창은 환경변수를 이어받지 않는다. 새 스킬 토큰을 생성하면 관리자센터의 운영·테스트 헤더값도 함께 바꿔야 한다.

## 3. 사전 점검과 서비스 시작

저장소 루트에서 실행한다. PATH에 Python이 없다면 확인된 `C:/Users/Donghyun/AppData/Local/Python/pythoncore-3.14-64/python.exe`를 쓴다.

```powershell
python -m automation.check --config "$env:LOCALAPPDATA/GymNoteAutomation/config.json"
python -m automation.service --config "$env:LOCALAPPDATA/GymNoteAutomation/config.json"
```

사전 점검은 비밀값을 출력하거나 외부 API/모델을 호출하지 않는다. `ok=true`는 실제 카카오 연결·Codex 인증 성공을 뜻하지 않는다. 관리자 포트 8765와 스킬 포트 8766은 별도이며 모두 localhost에 바인딩된다.

## 4. 공개 HTTPS와 스킬 등록

카카오 서버는 PC의 localhost에 접근할 수 없다. HTTPS 역방향 프록시나 터널이 `127.0.0.1:8766`으로 연결되어야 한다. **8765 관리자 화면은 공개하지 않는다.** 공개 연결은 `/kakao/skill`의 POST만 허용하고, `x-api-key`를 유지해야 한다. Origin 헤더가 붙는 브라우저 직접 호출은 거부된다.

초기 연결 시험에는 설치된 cloudflared의 Quick Tunnel을 사용할 수 있다. 다음 명령은 실제 외부 터널을 시작하므로 운영 연결 단계에서만 실행한다. 이 구현 작업에서는 설치·실행하지 않았다.

```powershell
cloudflared tunnel --url http://127.0.0.1:8766
```

출력된 HTTPS 주소 끝에 `/kakao/skill`을 붙인다. Quick Tunnel은 테스트용이며 재시작 시 주소가 바뀔 수 있다. 상시 운영은 고정 HTTPS 주소와 연결/요청 제한을 갖춘 프록시 또는 named tunnel을 준비한다. 스킬 수신기는 최대 16개 요청 스레드, 요청 전체 3.5초·유휴 2초 제한, 본문 32KB 제한, DB 대기 0.5초를 적용한다. 외부 프록시에서도 본문 크기·전체 수신 시간·연결 수·요청 빈도를 제한하고, 요청 본문과 인증 헤더의 로깅을 끈다.

챗봇 관리자센터:

1. 스킬을 만들고 URL·테스트 URL에 `https://공개주소/kakao/skill`을 등록한다.
2. **헤더값 입력 / 테스트 헤더값 입력**에 `x-api-key`와 로컬 `KAKAO_SKILL_TOKEN` 값을 각각 설정한다. 두 환경 모두 설정한다.
3. 폴백 블록에 이 스킬을 연결하고 응답은 **스킬데이터 사용**으로 설정한다. 도움말/웰컴/별도 명령 블록과 매칭되는 입력에는 그 블록에도 같은 스킬을 연결한다. 자유 발화가 다른 블록에 잡히면 폴백으로 전달되지 않는다.
4. 일반 스킬 응답을 사용한다. AI 콜백 옵션은 켜지 않는다.
5. 테스트 후 운영 채널에 배포한다. 관리자센터 테스트 사용자 식별자는 실제 개인 채팅 사용자와 다를 수 있다.

## 5. 본인 등록과 메모 확인

실제 연결한 채널 채팅에서 `내정보`를 보낸다. 응답의 `bot.id`·`botUserKey`를 PC 로컬 설정에 등록한다. 실제 사용자 `botUserKey`는 봇별로 다르다.

서비스를 Ctrl+C로 종료한 뒤 `kakaoUserKeys`에 본인 키를 넣고 `kakaoDiscoveryEnabled=false`로 바꾼다. 사전 점검·서비스 시작을 다시 수행한다. 사용자 ID를 이 대화나 Git에 복사하지 않는다.

`메모 운동 기록 화면 개선 아이디어`를 보내 저장 응답과 작업 ID를 확인한다. PC 관리자 화면에서도 같은 메모를 확인한다. 실행은 아직 꺼져 있으므로 `실행` 요청은 큐에 등록되지 않는다.

## 6. 작은 자동 작업 확인

서비스를 멈춘 뒤 Codex 인증을 확인하고 `executionEnabled=true`, `maxTasksPerSession=1`로 다시 시작한다. 사용자의 실행 요청을 통해 계정 사용량을 소비한다. 첫 요청 예:

```text
실행 smoke-1 docs/automation-smoke-test.md에 카카오톡 연결 확인 문장만 추가해 줘. 앱 코드는 수정하지 마.
```

접수 응답의 **상태 확인** 버튼 또는 `상태 작업ID`로 구현·검토·검증·로컬 통합 결과를 조회한다. 실제 결과를 확인하기 전 완료 체크를 바꾸지 않는다. `중지 작업ID`는 활성 작업에 중지만 요청하며 실행기 종료 전에는 중지 완료로 표시하지 않는다. 재시도는 실패/사용자 확인 필요/중지된 실행 작업에만 가능하고 새 워크트리를 사용한다. 보존된 워크트리를 먼저 검토한다.

## 지원 명령과 중복 정책

| 입력 | 동작 |
|---|---|
| 일반 메시지 / `메모 내용` / `/memo 내용` | 메모 저장, 자동 실행 없음 |
| `실행 요청키 내용` / `/run 요청키 내용` | 자동 작업 요청 |
| `상태` / `/status` | 본인의 최근 5개 작업 상태 |
| `상태 작업ID` / `/status 작업ID` | 본인 작업의 결과 요약 |
| `중지 작업ID` / `/cancel 작업ID` | 중지 요청 |
| `재시도 요청키 작업ID` / `/retry 요청키 작업ID` | 실행 작업 재시도 |
| `도움말` / `/help` | 명령 안내 |
| `내정보` / `/whoami` | 발견 모드에서 호출자 식별자 확인 |

요청키는 영문·숫자·`_`·`-` 1~64자다. 같은 봇·사용자의 같은 실행 키는 영구적으로 같은 작업을 가리키며 다른 내용을 붙이면 거부한다. 새 작업에는 새 키를 사용한다. 재시도 키는 작업별로 같은 재시도 명령의 재전송을 막는다. 카카오 스킬의 공개 스키마에 안정적인 요청 ID가 없어 실행에는 명시적 키를 요구한다.

메모는 같은 봇·사용자·내용을 60초 내 다시 받으면 기존 메모를 반환한다. SQLite 트랜잭션으로 동시 수신과 서비스 재시작 뒤에도 유지한다. 60초 이후에는 새 메모로 저장된다. 이 제한은 고의로 반복한 같은 메모도 합칠 수 있고 오래 지연된 메모 재전송은 새 메모가 될 수 있다. exactly-once를 보장하지 않는다.

## 결과 알림의 범위

첫 구현은 접수 답변 + 상태 조회다. 조회에는 작업 ID·상태·로컬 통합 여부·커밋·검사/미실행 개수만 포함하고 아이디어 본문·코드·로그·모델 상세 요약은 포함하지 않는다. 자세한 검토 사유는 로컬 관리자에서 확인한다. 원격 push·앱 배포·운영 DB 변경은 실행 승인 범위에 포함되지 않는다.

일반 스킬 제한은 5초이고 AI 콜백 URL은 1분·1회이므로 수분짜리 Codex 작업의 완료 push로 사용할 수 없다. Event API 완료 알림은 비즈 인증 채널/앱·월렛·유료 메시지 조건이 있어 이번에 구현·활성화하지 않았다. 따라서 기다리기만 하면 완료 메시지가 자동 도착한다고 안내하지 않는다. 기존 텔레그램 알림은 보존하며 카카오 작업을 텔레그램으로 보내지 않는다.

## 검증과 공식 근거

```powershell
python -m unittest discover -s automation/tests -v
```

합성 Kakao/Telegram 입력·격리 SQLite/Git·로컬 HTTP·가짜 에이전트 검사다. 실제 채널 배포·공개 HTTPS·외부 수신·Codex 계정 실행 검증을 대체하지 않는다.

- [카카오 스킬 서버·URL·비밀 헤더](https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/make_skill)
- [카카오 요청/응답 JSON](https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/answer_json_format)
- [블록·폴백](https://kakaobusiness.gitbook.io/main/tool/chatbot/main_notions/block)
- [AI 콜백 제약](https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/ai_chatbot_callback_guide)
- [Event API 조건](https://kakaobusiness.gitbook.io/main/tool/chatbot/main_notions/event-api)
- [Cloudflare Quick Tunnel 공식 안내](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)
