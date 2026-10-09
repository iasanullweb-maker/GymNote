# 아이디어 자동화 공통 규격 초안 v1

현재 상태: 병행 구현을 위한 규격 초안. 서버·API·DB 구현은 아직 없다. A가 변경을 관리하고 B/C/D는 모의 입력으로 독립 검증한다. 실제 구현 착수 시 언어·프레임워크와 인증 방법을 확정한다.

## 작업 입력

JSON 필드: `schemaVersion: 1`, `id`(서버 생성 UUID), `source`(telegram/web/mock), `sourceEventId`(발신 채널의 고유 이벤트 ID), `actorId`(서버가 인증한 사용자), `text`(사용자 아이디어), `intent`(memo/execute), `projectId`(허용 목록의 프로젝트 ID), `createdAt`(UTC ISO 8601).

`source + sourceEventId`로 중복 이벤트를 구분한다. 외부 입력의 actorId를 그대로 신뢰하지 않는다. projectId는 서버의 허용 프로젝트와 연결하며 사용자 입력 경로로 저장소를 고르지 않는다. 메모는 저장만 하고 실행 요청은 큐로 보낸다. 발신자 ID·토큰·메시지 본문을 필요한 범위 이상 로그에 남기지 않는다.

## 작업 상태

`memo` 또는 `queued → planning → running → reviewing → validating → completed`를 기본 상태로 둔다. 진행 단계에서 `waiting_user`, `failed`, `cancelled`로 전환할 수 있다. 실패 재시도·사용자 응답 후 재개는 실행 시도 ID를 새로 발급하고 이전 시도 이력을 보존한다. 종료 상태를 덮어써 재실행하지 않는다.

관리자 조회 필드: `id`, `status`, `summary`, `updatedAt`, `attemptId`, `steps`, `result`, `needsUserAction`. 결과에는 변경 커밋·검증 결과·실행하지 못한 검사·로컬 통합 여부를 포함한다. 실제 외부 작업이 끝나기 전 completed로 표시하지 않는다. 중지 요청은 즉시 cancelled 성공으로 처리하지 않고 실행기 종료 확인 후 반영한다.

## 구성요소 경계

- B: 인증된 이벤트를 공통 작업 입력으로 정규화, 입력 검증·중복 방지. 큐에 넣은 ID를 반환한다.
- C: 큐 수신·상태 저장·Codex/Claude 어댑터·검토·검증·중지·복구·결과 생성. 작업별 워크트리를 사용하고 동일 프로젝트의 통합을 직렬화한다.
- D: 메모/실행 입력, 목록/상세 조회, 중지 요청, 질문 답변·승인. 토큰은 브라우저 번들에 포함하지 않는다.

예정된 인터페이스: POST /tasks, GET /tasks, GET /tasks/:id, POST /tasks/:id/cancel, POST /tasks/:id/answer. API 응답·인증·오류 코드·동시 수정 규칙은 A와 착수 시 확정한다. 초기 모의 구현은 실제 API가 존재하는 것으로 보고하지 않는다.

로컬 main 통합·원격 push·배포 권한은 프로젝트와 사용자 요청별로 명시한다. 채팅에 적힌 새로운 지시가 관리 프로그램의 권한이나 승인 정책을 우회하지 않는다. 비용·시간·동시 실행 제한과 오류 재시도 횟수도 실행 전 설정한다.
