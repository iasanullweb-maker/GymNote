# 아이디어 자동화 실행 규격 v1

2026-10-09. 실제 구현은 Python 3.12 이상 표준 라이브러리 + SQLite다. 공통 검증은 automation/contracts/tasks.py, 저장은 automation/store.py, 로컬 API는 automation/service.py를 사용한다. 이전 초안의 /tasks, /answer, schemaVersion 등은 구현 API가 아니다. 아래 실제 규격으로 연결한다.

## 실행

저장소 루트에서 python -m automation.service --config <Git 밖 로컬 설정 JSON>으로 시작한다. 설정 예시는 automation/config.example.json이며 토큰·런타임 파일은 Git에 넣지 않는다. GYMNOTE_AUTOMATION_ADMIN_TOKEN은 24자 이상 무작위 값으로 환경에 주입한다. 상세 시작 절차는 automation/README.md를 따른다.

서버는 http://127.0.0.1:8765 (설정 port 변경 가능)에 바인딩한다. API는 Authorization: Bearer <관리자 토큰>과 정확한 Host, 동일 Origin을 검사한다. / 관리자 HTML에는 토큰이 없다. executionEnabled와 telegramEnabled는 기본 false다. 활성화 전에도 메모·실행 요청을 저장·조회할 수 있지만 큐 작업은 실행되지 않는다. 이미 켜진 서비스의 코드를 갱신하려면 저장된 작업을 보존하고 서비스를 재시작한다.

## HTTP 인터페이스

| 메서드·경로 | 입력·응답 |
|---|---|
| POST /api/tasks | JSON text, intent(memo/execute, 기본 memo), project(서버 허용 ID, 생략 시 defaultProject), 선택 requestId. 성공 201에 작업 객체 |
| GET /api/tasks | tasks(최신 최대 200개), projects, defaultProject, executionEnabled, executionPaused |
| GET /api/tasks/:id | task와 history(발생 순서의 상태·시도·결과 목록) |
| POST /api/tasks/:id/cancel | JSON {}. 실행 중이면 중지 요청 표시만 하고 실제 종료 후 cancelled |
| POST /api/tasks/:id/retry | JSON {}. failed/waiting_user/cancelled만 재등록. 새 실행 시도는 claim 때 생성 |

오류는 {"error":"..."}. 인증 실패 401, Host/Origin 실패 403, 입력·상태·동일 requestId의 다른 입력 400, 없는 경로·상세 작업 404. POST 본문은 1~32768바이트 JSON 객체. text는 원문 길이 1~8000자, 공백만/널 문자 거부. project는 허용 목록의 ID이며 파일 경로 입력은 받지 않는다. actor는 서버가 admin으로 정하고 외부 actor 필드는 사용하지 않는다.

requestId는 앞뒤 공백·제어문자 없는 1~200자 문자열. 전달하면 source=web + requestId로 영속 중복 방지한다. 동일 키·동일 입력은 기존 작업을 반환하며 다른 사용자·프로젝트·내용·실행 의도로 재사용하면 거부한다. 생략하면 서버 UUID를 생성하므로 별도 POST는 별도 작업이다. 응답을 못 받은 클라이언트가 안전하게 재전송하려면 requestId를 유지한다. 텔레그램은 update_id와 source=telegram이 이 역할을 한다.

## 저장·상태·시도

작업 객체: id, source(telegram/web/mock), event, actor, project, text, intent, status, created, updated, attempt, result, cancel. created/updated는 UTC ISO 8601이다. result는 summary, checks, notRun, commit, worktree, integrated 등을 담는다. cancel은 0/1 중지 요청이며 실행 종료 성공 표시가 아니다.

상태는 memo 또는 queued → planning → running → reviewing → validating → completed. 진행 중 실패/판단 필요는 waiting_user 또는 failed, 종료 확인 후 cancelled. memo/queued/waiting_user는 실행 프로세스가 없어 즉시 cancelled 가능하다. completed는 종료 상태로 다시 변경할 수 없다. 재시도만 failed/waiting_user/cancelled → queued를 허용한다. 메모는 실행기로 claim되지 않는다.

SQLite BEGIN IMMEDIATE 트랜잭션으로 등록·중복 처리·claim·상태 변경을 직렬화한다. source+event는 고유 키다. claim은 새 attempt UUID를 만들고 현재 결과를 비운다. 이력에는 이전 시도의 결과가 남는다. 실행기의 state(..., attempt=<claim ID>)는 오래된 시도에서 온 쓰기를 거부한다. 이전 버전 DB에는 intent와 history.result 열을 데이터 삭제 없이 추가한다. 기존 cancelled 작업은 원래 메모/실행을 알 수 없어 intent=null을 유지하며 추정하지 않는다. 이전에 기록하지 않았던 과거 이력은 복원하거나 꾸며내지 않는다.

재시작은 진행 중 작업을 waiting_user로 바꾸고 기존 worktree/base/결과를 보존한다. 자동 재실행하지 않는다. 재시도는 새 작업 폴더와 시도 ID를 사용한다. 작업당 시간 제한·서비스 세션당 작업 수 제한은 설정한다. 금액 예산을 강제하는 기능은 아직 없다.

## 구성요소 연결과 범위

- 메시지 수신은 발신자·채팅 허용 목록 검사 후 Store.create로 입력한다. 일반 메시지는 memo, /run은 execute다.
- 실행기는 Store.claim으로 한 작업을 받아 상태와 시도 ID를 갱신한다. 구현·별도 검토·검증 후 승인된 프로젝트에서만 로컬 통합한다.
- 관리자 화면은 위 API를 호출하며 requestId를 사용한 재전송과 상세 이력을 이용할 수 있다. 조회 응답을 받은 것만으로 실행 성공을 표시하지 않는다.

현재 실행 어댑터는 Codex만 구현됐다. Claude 어댑터·/answer로 기존 세션 재개는 미구현이다. 신규 텔레그램 execute 요청의 종료/판단 필요 상태 알림은 영속 큐에서 원래 채팅으로 발송한다. 공통 코드 테스트는 합성 텔레그램·가짜 에이전트·실제 SQLite/localhost HTTP·격리 Git 저장소를 사용한다. 실제 봇 연결이나 유료 모델 실행 성공을 의미하지 않는다. 운영 토큰이나 실사용 DB 없이 검증한다. 원격 push·배포·운영 SQL은 사용자 요청별 승인 범위를 따른다.

## 텔레그램 상태 알림

telegram_targets는 새 텔레그램 요청의 원래 chat ID를 저장한다. tasks의 completed/failed/waiting_user/cancelled 이력과 telegram_notifications 큐를 같은 트랜잭션으로 기록한다. 실행 중 cancel 요청만으로 중지 알림을 보내지 않고 실행기가 cancelled를 확정해야 한다. 메모·관리자/구형 작업은 자동 알림 대상이 아니다. 재시도별 attempt와 알림 ID를 보존하며 과거 상태 알림을 현재 시도의 결과로 덮어쓰지 않는다.

알림 payload는 integrated boolean·40자리 소문자 hex commit·checks/notRun 개수만 보존한다. 모델 요약/로그/아이디어/토큰을 알림에 넣지 않는다. 배달 직전에 현재 사용자·채팅 허용 목록을 검사한다. 권한 제거는 suppressed로 보존, 성공 응답은 sent, 실패는 pending과 지수 backoff(10초~300초)를 유지한다. polling 스레드가 한 번에 최대 10개를 처리하며 대기 중인 getUpdates 때문에 발송이 지연될 수 있다. 서비스 단일 인스턴스 잠금을 그대로 사용한다.

Telegram sendMessage와 SQLite를 하나의 외부 트랜잭션으로 묶을 수 없으므로 응답 유실/발송 직후 재시작에는 중복 가능성이 있다. 알림 ID로 식별하며 exactly-once를 주장하지 않는다. telegramNotificationsEnabled=false는 큐를 삭제하지 않고 발송만 멈춘다. 다시 켜면 권한을 재검사한 뒤 남은 알림을 처리한다.

python -m automation.check --config <local-config.json>은 네트워크/에이전트 실행/비밀값 출력 없는 사전 점검이다. 실제 봇 인증·모델 로그인·서비스 운영 검증과 구분한다.
