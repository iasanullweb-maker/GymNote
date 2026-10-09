# 공통 코드·실행 규격 마무리

2026-10-09. 현재 A 대화에서 사용자 요청으로 수행했다. 다른 대화에 새 작업 지시를 보내지 않았다. 단일 Python/SQLite 통합 구현을 먼저 main에서 가져와 중복 구현을 피했다.

- 변경: automation/contracts/tasks.py, TASKS.md, store.py, service.py, worker/runner.py, tests/test_contracts.py, README.md, HANDOFF.md, 이 보고서.
- 동작: 공통 입력·상태 검증, 동일 이벤트의 다른 입력 거부, 시도 ID 검증, 이전 시도 결과 보존, 재시작 작업 폴더 보존, 관리자 requestId 기반 중복 방지, 상세·이력 API.
- 검증: Python py_compile 및 unittest discover -s automation/tests -v의 25개 검사 통과. 기존 DB 이전·재전송·잘못된 입력·종료/이전 시도 갱신 거부·취소·회복·실제 HTTP·가짜 에이전트/격리 Git 검증 포함. git diff --check 통과.
- 범위: 실제 봇·유료 에이전트·운영 DB·원격 push·배포·전체 iOS 빌드·XCTest는 미실행. Claude 어댑터·질문 답변에 따른 기존 세션 재개·완료 자동 알림은 후속 항목이다.
- 통합: 완료 커밋을 공통 잠금 스크립트로 기존 main에 통합하고 최종 응답에 실제 결과를 적는다. 최신 커밋은 git log -1 -- docs/parallel-work/reports/common-runtime.md로 확인한다.
