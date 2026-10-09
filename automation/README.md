# 텔레그램 아이디어 작업함

2026-10-09: 기존 A/B/C/D 계획을 한 대화의 통합 구현으로 전환했다. Python 3.12 표준 라이브러리만 사용한다. 별도 패키지 설치·클라우드 서버 없이 PC에서 실행한다.

## 사용 흐름

- 봇에게 일반 메시지 또는 `/memo 내용` → 아이디어를 SQLite에 저장한다.
- `/run 개선할 내용` → 영구 큐에 등록한다. 실행기가 활성화되어 있으면 순서대로 작업한다.
- `/status 작업ID`, `/cancel 작업ID`, `/retry 작업ID` → 본인이 등록한 작업만 조회·중지·재시도한다.
- 관리자 화면 → 아이디어 기록·실행 요청·목록·결과·중지·재시도. 토큰은 메모리에만 보관한다.

실행은 새 Git 워크트리 생성 → Codex 구현·검사·커밋 → 별도 읽기 전용 Codex 검토 → 변경 상태 재확인 → 로컬 fast-forward 통합이다. main이 진행했거나 추적 파일 미커밋 변경·진행 중 Git 작업·공통 잠금이 있으면 `waiting_user`로 멈추고 작업을 보존한다. 성공 완료는 실제 통합이 끝난 뒤만 표시한다. 원격 push·배포·운영 DB 변경은 실행 프롬프트의 승인 범위에서 제외한다. 프롬프트 제한은 운영체제 권한 경계가 아니며 Codex의 workspace-write 샌드박스와 승인 정책을 함께 사용한다.

## 로컬 시작

1. `automation/config.example.json`을 **Git 밖의 로컬 폴더**에 복사한다. `projects.gymnote.path`는 기존 main 작업 폴더다. `codexExecutable`은 설치된 CLI의 절대 경로다.
2. 같은 PowerShell 창에서 관리자 토큰과 (연결 시) 봇 토큰을 환경 변수로 설정한다. 토큰을 저장소·메시지·실행 인자에 넣지 않는다.
3. 저장소 루트에서 다음처럼 실행한다. `python`이 PATH에 없다면 설치된 Python 실행 파일의 절대 경로를 사용한다.

```powershell
$env:GYMNOTE_AUTOMATION_ADMIN_TOKEN = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
# 봇 토큰을 숨긴 입력으로 받는다. 이 창의 자식 프로세스에만 적용된다.
$taskBotSecret = Read-Host 'Telegram bot token' -AsSecureString
$taskCredential = [PSCredential]::new('bot', $taskBotSecret)
$env:TELEGRAM_BOT_TOKEN = $taskCredential.GetNetworkCredential().Password
python -m automation.service --config C:/path/to/local-config.json
```

관리자 토큰을 확인할 때는 본인 로컬 창에서만 `$env:GYMNOTE_AUTOMATION_ADMIN_TOKEN`을 확인해 관리자 화면에 붙여 넣는다. 서비스는 `http://127.0.0.1:8765`에만 열리며 인증 없는 API 요청·다른 Origin·다른 Host를 거부한다. API와 관리자 화면은 외부에 공개하지 않는다.

## 실행 전 사전 점검

설정 파일을 만든 뒤 다음 명령은 실제 봇·에이전트를 실행하지 않고 Python 버전, Git 통합 브랜치, 켜진 기능의 허용 목록·필수 환경 변수·CLI 파일 경로만 확인한다. 토큰 값을 출력하지 않는다.

~~~powershell
python -m automation.check --config C:/path/to/local-config.json
~~~

ok=true는 실제 봇 토큰 유효성·Codex 로그인·사용량·발송 성공을 의미하지 않는다. webhook/다른 polling 수신기, 포트와 런타임 쓰기 권한도 실제 연결 시 확인해야 한다. 현재 PC에서 확인된 Python 경로는 C:/Users/Donghyun/AppData/Local/Python/pythoncore-3.14-64/python.exe (3.14)이며 PATH의 python/py를 사용할 수 없으면 이 절대 경로를 사용한다.

## 실제 텔레그램 연결

BotFather에서 생성한 봇 토큰, 허용 발신자의 숫자 user ID, 허용 채팅의 숫자 chat ID가 필요하다. `allowedUserIds`와 `allowedChatIds`에 각각 입력하고 `telegramEnabled: true`로 바꾼다. **두 허용 목록이 모두 일치해야** 기록·실행·조회·중지가 가능하다. 그룹에서 일반 아이디어 메시지까지 받으려면 BotFather의 그룹 privacy 설정을 확인한다. 초기 연결은 봇과의 개인 대화가 간단하다.

이 서비스는 getUpdates long polling을 사용한다. 같은 봇을 다른 CLI/서비스에서 polling하면 충돌한다. 기존 작업에서 같은 봇을 사용 중인지 확인하고 한 수신기만 켠다. 기존 webhook을 임의 삭제하지 않으며 webhook이 설정된 봇은 먼저 해당 연결 소유자와 조율한다.

Codex CLI가 해당 계정으로 로그인되어 있어야 실제 에이전트가 실행된다. `executionEnabled: true`로 켜며 `autoIntegrate: true`인 프로젝트만 로컬 통합한다. 기본 예시는 두 외부 기능을 꺼둔 상태라 토큰 없이 로컬 관리자 기능부터 확인할 수 있다. 실제 실행은 사용 중인 계정의 한도를 소비하며 기본 한도는 **한 번에 1개, 서비스 실행당 최대 10작업, 구현/검토 호출 각각 900초**다. 금액 한도를 보장하는 기능은 없다. 작업 수 한도 도달 후 대기열은 보존되며 서비스 재시작 후 계속한다.

PC가 켜져 있고 서비스가 실행 중이어야 수신·자동 실행된다. 자동 시작 등록은 포함하지 않았다. Ctrl+C는 실행 프로세스 트리를 중지한 뒤 서비스를 닫는다. 비정상 재시작 시 진행 중 작업은 자동 재실행하지 않고 `waiting_user`로 복구한다. 이전 워크트리를 검토한 뒤 명시적으로 재시도한다. 재시도는 새 시도 ID·새 워크트리를 만들며 기존 결과를 삭제하지 않는다.

## 저장·결과·검증

공통 입력·상태·API 실행 규격은 [contracts/TASKS.md](contracts/TASKS.md)에 확정했다. 관리자 클라이언트는 POST /api/tasks에 선택 `requestId`를 유지해 네트워크 재전송 시 중복 등록을 막을 수 있다. GET /api/tasks/:id는 작업과 시도별 상태·결과 이력을 반환한다. 현재 화면은 목록 API를 그대로 사용하며 새 상세 API는 연결용으로 제공한다.

기존 SQLite는 데이터 삭제 없이 intent와 history.result 열을 추가한다. 재시도 시 새 실행 결과와 이전 시도의 이력을 분리하고, 재시작 복구는 작업 폴더 정보를 유지한다. 실행기의 시도 ID가 달라졌거나 작업이 종료된 뒤 도착한 상태 변경은 거부한다.

기본 로컬 데이터: `%LOCALAPPDATA%/GymNoteAutomation/ideas.sqlite3`, `attempts/`, `worktrees/`. `runtimeDir`로 변경 가능하다. 개인 아이디어와 에이전트 로그가 들어 있으므로 Git에 넣지 않는다. SQLite는 암호화하지 않는다. 시도 로그에는 아이디어나 코드가 들어갈 수 있지만 텔레그램으로 자동 전송하지 않는다. 봇·관리자 토큰 환경 변수는 Codex 자식 프로세스에 전달하지 않는다.

`source + event` 고유 키와 SQLite 트랜잭션으로 중복 큐 등록·동시 claim을 막는다. 수신 처리를 저장한 뒤 offset을 영구 저장하고 접수 답장을 보낸다. 답장 발송이 실패해도 저장된 작업은 남지만 답장은 자동 재전송하지 않는다. 새 텔레그램 실행 요청은 완료·실패·사용자 확인 필요·실제 중지 상태를 원래 요청 채팅으로 알린다. `telegramNotificationsEnabled`(기본 true)로 알림만 끌 수 있다. 상태 변경과 알림 큐를 같은 SQLite 트랜잭션에 저장하며 전송 실패는 10초부터 최대 5분 간격으로 재시도한다. 서비스 재시작 뒤에도 미전송 알림이 남는다. 알림을 보내기 직전에 현재 발신자·채팅 허용 목록을 다시 검사하고 권한이 제거된 알림은 suppressed로 보존한다. 과거 작업과 관리자 화면 요청에는 알림 대상을 임의로 추가하지 않는다.

알림에는 작업 ID·상태·로컬 통합 여부·유효한 커밋·검사/미실행 개수만 포함한다. 아이디어 본문·코드·로그·모델의 상세 오류/요약은 보내지 않는다. 네트워크 응답 유실이나 발송 직후 프로세스 종료 시 동일 알림이 중복 도착할 수 있으며 `알림 #번호`로 식별한다. 정확히 한 번 발송을 보장하지 않는다. `/status`와 관리자 화면도 계속 사용할 수 있다. 질문 답변에 따른 기존 Codex 세션 재개·Claude 어댑터는 아직 미구현이다.

```powershell
python -m unittest discover -s automation/tests -v
```

테스트는 가짜 텔레그램 입력/가짜 에이전트와 실제 SQLite·격리 Git 저장소·로컬 HTTP API를 사용한다. 실제 Telegram API 접속과 유료 Codex 실행 성공을 대신하지 않는다. 전체 iOS 빌드·XCTest는 Windows에서 실행하지 않았다.

공식 참고: [Telegram Bot API](https://core.telegram.org/bots/api#getupdates), [Codex 비대화형 실행](https://learn.chatgpt.com/docs/non-interactive-mode). 실행 인자·JSON 출력 스키마는 설치된 CLI `exec --help`와 함께 확인했다.
