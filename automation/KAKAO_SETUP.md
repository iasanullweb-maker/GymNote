# 카카오톡 작업함 연결

2026-10-12: 사용자가 텔레그램 계정 대신 카카오톡 채널 챗봇을 선택했다. 같은 날 PC가 꺼져 있어도 메시지를 잃지 않도록 **클라우드 우편함(중계) 방식**을 기본으로 바꿨다. 아래 코드·검사는 구현 범위이며 채널 생성·Supabase 함수 배포·실제 연결은 사용자 설정이다.

흐름: 카카오톡 채널 → 챗봇 폴백 블록 → Supabase Edge Function `kakao-skill`(항상 켜짐) → Supabase 우편함 테이블 → (PC가 켜지면) PC 서비스가 가져가 기존 SQLite 작업 큐에 넣음 → Codex 구현·검토·검증·로컬 통합 → PC가 상태 요약을 Supabase에 올림 → 카카오톡 `상태`가 PC 꺼짐과 상관없이 응답.

- PC가 꺼져 있어도 메모·실행 요청은 접수되어 우편함에 남는다(사용자별 대기 100건까지). PC가 켜지면 받은 순서대로 처리한다.
- 실제 코드 작업(Codex)은 여전히 PC가 켜져 있고 서비스가 실행 중일 때만 진행된다.
- 공개 터널(cloudflared)·고정 주소 관리가 필요 없다. PC에서는 외부로 나가는 HTTPS 요청만 한다.
- 우편함의 원문은 PC가 가져가 확인(ack)하는 즉시 지운다. 처리 기록은 30일, 상태 요약은 90일 뒤 정리된다. 상태 요약에는 아이디어 본문·코드·로그가 없다.
- 앱 사용자(anon/authenticated)는 우편함·상태 테이블과 함수에 접근할 수 없다. 함수만 서버 키(service_role)로 접근한다.

## 1. 채널과 챗봇 만들기

1. [카카오톡 채널 관리자센터](https://center-pf.kakao.com/)에서 개인 작업함용 채널을 만든다. 예: GymNote 작업함.
2. [챗봇 관리자센터](https://chatbot.kakao.com/)에서 카카오톡 챗봇을 만든다. 계정에 이용 신청/승인 화면이 나오면 해당 절차를 먼저 진행한다.
3. 봇 설정의 카카오톡 채널 연결에서 만든 채널을 연결한다. 개발채널과 운영채널을 구분한다.
4. 봇 설정/관리 URL에서 봇 ID를 확인한다. 실제 스킬 payload의 `bot.id`와 일치해야 한다. 채널 검색용 ID와 봇 ID는 다르다.

## 2. 비밀값 두 개 만들기 (PowerShell)

서로 다른 두 값이 필요하다. `KAKAO_SKILL_TOKEN`은 카카오 → 함수 인증, `AUTOMATION_RELAY_TOKEN`은 PC → 함수 인증이다. PC 관리자 화면 토큰도 함께 만든다.

```powershell
function New-GymNoteSecret {
    $taskBytes = New-Object byte[] 32
    $taskGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $taskGenerator.GetBytes($taskBytes) }
    finally { $taskGenerator.Dispose() }
    return [BitConverter]::ToString($taskBytes).Replace('-', '').ToLowerInvariant()
}
$env:KAKAO_SKILL_TOKEN = New-GymNoteSecret
$env:AUTOMATION_RELAY_TOKEN = New-GymNoteSecret
$env:GYMNOTE_AUTOMATION_ADMIN_TOKEN = New-GymNoteSecret
```

값은 32~128자 영문/숫자/`_`/`-`여야 한다. Supabase·카카오 관리자센터에 붙여 넣을 때만 본인 창에서 `$env:KAKAO_SKILL_TOKEN` 등을 확인한다. 이 채팅·Git·URL·로그에 넣지 않는다.

새 PowerShell 창은 환경변수를 이어받지 않는다. PC를 켤 때마다 다시 넣기 번거로우면 본인 Windows 계정 환경변수로 저장할 수 있다(같은 PC 계정에서 읽을 수 있는 평문 저장이다).

```powershell
[Environment]::SetEnvironmentVariable('AUTOMATION_RELAY_TOKEN', $env:AUTOMATION_RELAY_TOKEN, 'User')
[Environment]::SetEnvironmentVariable('GYMNOTE_AUTOMATION_ADMIN_TOKEN', $env:GYMNOTE_AUTOMATION_ADMIN_TOKEN, 'User')
```

`KAKAO_SKILL_TOKEN`은 Supabase와 카카오에만 있으면 되고 PC에는 저장할 필요가 없다.

## 3. Supabase 준비 (대시보드)

GymNote 운영 프로젝트(`wthfekhyrsbslnkyvtax`)에서 진행한다. 운영 DB 변경이므로 아래 SQL 외 다른 문장을 실행하지 않는다.

1. **SQL Editor**에 저장소의 `supabase/migrations/202610120001_kakao_relay.sql` 전체를 붙여 넣고 실행한다. 확인:
   ```sql
   select count(*) as waiting from public.automation_kakao_inbox;                                    -- 0
   select has_table_privilege('anon', 'public.automation_kakao_inbox', 'select') as anon_can_read;     -- false
   select has_function_privilege('authenticated', 'public.automation_kakao_receive(text,text,text)', 'execute') as app_can_store; -- false
   ```
2. **Edge Functions → Deploy a new function → Via Editor**에서 이름을 `kakao-skill`로 정하고 저장소의 `supabase/functions/kakao-skill/index.ts` 전체를 붙여 넣어 배포한다. 배포 후 함수 설정에서 **JWT 검증 강제(Enforce JWT Verification)를 끈다**. `delete-account`와 같은 설정이다(카카오는 Supabase 로그인 토큰을 보낼 수 없고, 함수가 비밀 헤더를 직접 검사한다). CLI를 쓰면 `supabase functions deploy kakao-skill --project-ref wthfekhyrsbslnkyvtax --no-verify-jwt`.
3. **Edge Functions → Secrets**(`functions/secrets`)에 추가한다. 변경은 재배포 없이 바로 적용된다.

   | Key | Value |
   |---|---|
   | `KAKAO_SKILL_TOKEN` | 2단계의 스킬 토큰 |
   | `AUTOMATION_RELAY_TOKEN` | 2단계의 중계 토큰 |
   | `KAKAO_BOT_IDS` | 1단계의 봇 ID (여러 개면 쉼표로 구분) |
   | `KAKAO_USER_KEYS` | 처음에는 `none` (5단계에서 본인 키로 교체) |
   | `KAKAO_DISCOVERY` | `true` (5단계 후 `false`) |

   `SUPABASE_URL`·`SUPABASE_SERVICE_ROLE_KEY`는 Supabase가 자동으로 넣는다.

함수 주소: `https://wthfekhyrsbslnkyvtax.supabase.co/functions/v1/kakao-skill`

## 4. 챗봇에 스킬 연결

챗봇 관리자센터:

1. 스킬을 만들고 URL·테스트 URL 모두에 위 함수 주소를 등록한다.
2. **헤더값 입력 / 테스트 헤더값 입력**에 `x-api-key`와 `KAKAO_SKILL_TOKEN` 값을 각각 설정한다.
3. 폴백 블록에 이 스킬을 연결하고 응답은 **스킬데이터 사용**으로 설정한다. 도움말/웰컴/별도 명령 블록과 매칭되는 입력에는 그 블록에도 같은 스킬을 연결한다. 자유 발화가 다른 블록에 잡히면 폴백으로 전달되지 않는다.
4. 일반 스킬 응답을 사용한다. AI 콜백 옵션은 켜지 않는다.
5. 테스트 후 운영 채널에 배포한다. 관리자센터 테스트 사용자 식별자는 실제 개인 채팅 사용자와 다를 수 있다.

## 5. 본인 등록

실제 연결한 채널 채팅에서 `내정보`를 보낸다. 응답의 `botUserKey`를 Supabase Secrets의 `KAKAO_USER_KEYS`에 넣고 `KAKAO_DISCOVERY`를 `false`로 바꾼다. 같은 봇 ID·사용자 키를 PC 로컬 설정에도 넣는다(6단계). 사용자 키를 이 대화나 Git에 복사하지 않는다.

이 시점부터 PC가 꺼져 있어도 `메모 …`를 보내면 "메모를 받았습니다"가 오고, `상태`에 "PC 처리 대기 1건"이 보여야 한다.

## 6. PC 설정과 서비스 시작

`automation/config.example.json`을 Git 밖 `%LOCALAPPDATA%/GymNoteAutomation/config.json`에 복사한다. 기존 파일이 있다면 덮어쓰지 말고 필요한 항목만 바꾼다. `projects.gymnote.path`는 원본 저장소, `branch`는 기존 main이다. Codex 실행 파일 경로도 실제 PC와 대조한다.

```json
{
  "kakaoEnabled": false,
  "kakaoRelayEnabled": true,
  "kakaoRelayUrl": "https://wthfekhyrsbslnkyvtax.supabase.co/functions/v1/kakao-skill",
  "kakaoRelayPollSeconds": 5,
  "kakaoBotIds": ["만든-봇-ID"],
  "kakaoUserKeys": ["본인-botUserKey"],
  "executionEnabled": false,
  "maxTasksPerSession": 1
}
```

위 JSON은 바꿀 항목만 보여 준다. `kakaoEnabled`는 PC에서 직접 스킬을 받는 예전 방식이며 중계 방식에서는 끈다. 저장소 루트에서 실행한다. PATH에 Python이 없다면 확인된 `C:/Users/Donghyun/AppData/Local/Python/pythoncore-3.14-64/python.exe`를 쓴다.

```powershell
python -m automation.check --config "$env:LOCALAPPDATA/GymNoteAutomation/config.json"
python -m automation.service --config "$env:LOCALAPPDATA/GymNoteAutomation/config.json"
```

사전 점검은 비밀값을 출력하거나 외부 API/모델을 호출하지 않는다. `ok=true`는 실제 Supabase·카카오 연결이나 Codex 인증 성공을 뜻하지 않는다. 서비스는 5초마다 우편함을 확인한다. 연결이 실패해도 우편함 항목은 지워지지 않고 다음 확인에서 다시 처리된다(실패가 이어지면 최대 5분 간격으로 재시도).

5단계에서 PC가 꺼진 동안 보낸 메모가 서비스 시작 몇 초 뒤 `상태`에 작업 ID와 "메모 저장"으로 바뀌고, PC 관리자 화면(`http://127.0.0.1:8765`)에도 보이면 연결 성공이다.

## 7. 작은 자동 작업 확인

서비스를 멈춘 뒤 `codex login status`로 인증을 확인하고 `executionEnabled=true`, `maxTasksPerSession=1`로 다시 시작한다. 사용자의 실행 요청을 통해 계정 사용량을 소비한다. 첫 요청 예:

```text
실행 smoke-1 docs/automation-smoke-test.md에 카카오톡 연결 확인 문장만 추가해 줘. 앱 코드는 수정하지 마.
```

`상태` 또는 `상태 작업ID`로 구현·검토·검증·로컬 통합 결과를 조회한다. 상태 요약 끝의 "PC 기준 시각"은 PC가 마지막으로 올린 시각이다. 실제 결과를 확인하기 전 완료 체크를 바꾸지 않는다. `중지 작업ID`는 활성 작업에 중지만 요청하며 실행기 종료 전에는 중지 완료로 표시하지 않는다. 재시도는 실패/사용자 확인 필요/중지된 실행 작업에만 가능하고 새 워크트리를 사용한다. PC에서 실행이 꺼져 있을 때 보낸 `실행`은 작업으로 만들지 않고 `상태`의 "처리 결과"에 안내를 남긴다.

## 부록: PC 직접 수신 방식 (이전 구현, 보존)

`kakaoEnabled=true`이면 PC가 `127.0.0.1:8766`에서 스킬을 직접 받는다. 이 경우 카카오가 PC에 닿을 공개 HTTPS(예: `cloudflared tunnel --url http://127.0.0.1:8766`)가 필요하고 PC가 꺼져 있으면 메시지가 사라진다. 8765 관리자 화면은 절대 공개하지 않는다. 스킬 수신기는 최대 16개 요청 스레드, 요청 전체 3.5초·유휴 2초, 본문 32KB, DB 대기 0.5초 제한을 적용한다. 같은 봇에 두 방식을 동시에 연결하지 않는다.

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

중계 방식에서 메모는 우편함 항목 ID로 한 번만 저장된다. PC 쪽 확인이 늦어 같은 항목을 다시 가져와도 메모·실행이 중복되지 않는다. 우편함은 카카오가 같은 요청을 다시 보낸 경우를 구분하지 못하므로 그런 경우 메모가 두 번 저장될 수 있다(실행은 요청키로 막힌다).

PC 직접 수신 방식에서 메모는 같은 봇·사용자·내용을 60초 내 다시 받으면 기존 메모를 반환한다. SQLite 트랜잭션으로 동시 수신과 서비스 재시작 뒤에도 유지한다. 60초 이후에는 새 메모로 저장된다. 이 제한은 고의로 반복한 같은 메모도 합칠 수 있고 오래 지연된 메모 재전송은 새 메모가 될 수 있다. exactly-once를 보장하지 않는다.

## 결과 알림의 범위

접수 답변 + 상태 조회다. 중계 방식의 상태는 PC가 올린 요약과 우편함 대기·처리 결과를 함께 보여 준다. 조회에는 작업 ID·상태·로컬 통합 여부·커밋·검사/미실행 개수만 포함하고 아이디어 본문·코드·로그·모델 상세 요약은 포함하지 않는다. 자세한 검토 사유는 로컬 관리자에서 확인한다. 원격 push·앱 배포·운영 DB 변경은 실행 승인 범위에 포함되지 않는다.

일반 스킬 제한은 5초이고 AI 콜백 URL은 1분·1회이므로 수분짜리 Codex 작업의 완료 push로 사용할 수 없다. Event API 완료 알림은 비즈 인증 채널/앱·월렛·유료 메시지 조건이 있어 이번에 구현·활성화하지 않았다. 따라서 기다리기만 하면 완료 메시지가 자동 도착한다고 안내하지 않는다. 기존 텔레그램 알림은 보존하며 카카오 작업을 텔레그램으로 보내지 않는다.

## 검증과 공식 근거

```powershell
python -m unittest discover -s automation/tests -v      # PC 쪽(중계 포함), Python 3.12+
node scripts/test_kakao_skill.mjs                      # kakao-skill 함수, Node 22.13+
```

우편함 SQL은 CI `database` job의 `scripts/test_kakao_relay.sql`이 Supabase 기본 권한을 흉내 낸 격리 PostgreSQL에서 검사한다. 모두 합성 입력·격리 DB/Git·가짜 에이전트 검사이며 실제 채널 배포·Supabase 배포·외부 수신·Codex 계정 실행 검증을 대체하지 않는다.

- [카카오 스킬 서버·URL·비밀 헤더](https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/make_skill)
- [카카오 요청/응답 JSON](https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/answer_json_format)
- [블록·폴백](https://kakaobusiness.gitbook.io/main/tool/chatbot/main_notions/block)
- [AI 콜백 제약](https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/ai_chatbot_callback_guide)
- [Event API 조건](https://kakaobusiness.gitbook.io/main/tool/chatbot/main_notions/event-api)
- [Supabase Edge Function 시크릿](https://supabase.com/docs/guides/functions/secrets)
- [Supabase 대시보드에서 함수 배포](https://supabase.com/docs/guides/functions/quickstart-dashboard)
- [Cloudflare Quick Tunnel 공식 안내](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) (직접 수신 방식만)
