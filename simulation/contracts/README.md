# 공통 규격 검증과 통합 준비 검사

A가 소유하는 독립 검증 도구다. 기존 v1 JSON 스키마는 변경하지 않는다. B/C/D는 필요하면 validate.mjs를 가져다 쓸 수 있다. 네트워크·외부 패키지·모델 API가 필요하지 않다.

## 명령

~~~powershell
node simulation/contracts/test_validate.mjs
node simulation/contracts/audit.mjs
node simulation/contracts/audit.mjs --root C:/Users/Donghyun/Documents/2026_IASA/GymNote --require-panel
node simulation/contracts/audit.mjs --manifest simulation/runs/capture-run/manifest.json --require-captures
~~~

Node 24 이상 CLI가 필요하다. 이 세션에서는 독립 Node 실행기가 PATH에 없어 Codex Node REPL에서 모듈을 import해 exported 함수로 검사를 실행했다. 독립 CLI 설치·실행을 완료했다는 뜻은 아니다.

기본 audit는 B/C 입력이 없으면 awaiting-inputs를 반환하고 정상 종료한다. --require-panel은 사용자 최소 4개·시나리오 최소 5개·유효 manifest가 없으면 종료 코드 1, --require-captures는 같은 기기 변형의 고유 화면 10개 PNG가 검증되지 않으면 1이다. 잘못된 입력은 옵션과 무관하게 거부한다. 예시 파일을 실제 담당 산출물로 대신 집계하지 않는다.

## 검증 범위

- 네 JSON 계약에서 현재 사용하는 키워드의 타입·필수 필드·상수·enum·조건부 필드를 검사한다. 일반 JSON Schema 전체 구현은 아니며 미지원 스키마 키워드는 명시적으로 거부한다.
- capture ID·시작 화면·검사 ID·기기 변형 중복과 고유 화면 10개 세트를 검사한다.
- dry-run의 실행 완료/모델 호출/성공 주장, 근거 없는 pass/fail, screen-review의 app-state 판정을 거부한다.
- audit는 입력 JSON과 PNG 크기에 상한을 두고 상대 경로·심볼릭 링크의 디렉터리 탈출·PNG signature/IHDR·SHA-256을 검사한다. PNG 전체 디코딩·실제 앱 화면 내용·상태 저장·UI 조작은 검증하지 않는다.
- 임시 합성 입력으로 4×5×3=60 계획을 검증하되 모델 호출·실제 평가가 없음을 함께 확인한다.

## 모듈 API

~~~javascript
import { validateDocument, validatePanel, validateSession } from './simulation/contracts/validate.mjs';
validateDocument('persona', persona);
validatePanel({ personas, scenarios, manifest });
validateSession(session, scenario);
~~~

validateSession의 scenario는 평가자 전용이다. 사용자 입력에 checks를 넣지 않는다. 파일 존재·해시 검사와 JSON 계약 검사는 별개이며 validateDocument만으로 실제 캡처를 인증했다고 보고하지 않는다.
