# 웹 가상 환경 후속 작업 — 2026-10-09

A/B/C/D의 기반 산출물은 모두 로컬 main 통합됨을 Git ancestry와 깨끗한 워크트리로 확인했다. 사용자는 Mac/Xcode를 사용할 수 없으므로 실제 iOS 캡처·빌드 대신 Windows에서 열 수 있는 별도 웹 행동 프로토타입을 구현했다.

## 구현과 연결

- simulation/web/core.mjs: demo-v1 시각, 세션별 메모리 사본, 10개 화면, 운동·계획 복귀·일지 추가·편집 취소·합성 친구 공개 해제 상태 전환.
- preview.html/ui.js: 가상 사용자 선택·목표·직접 조작, 종료 후 기획자 검토·근거·메모·JSON 내보내기.
- build.mjs: C JSON과 B manifest를 A 검증기로 확인하고 오프라인 단일 HTML 생성. D의 buildDryRunSession과 A validateSession을 사용해 iOS 미실행 결과도 별도 보관.
- 웹 판정은 webFormat:1의 prototypeResult이며 nativeResult는 항상 not-evaluated. 관찰/사람 확인은 웹에서도 미평가. 모델 호출은 0.

## 검증 결과

- Node 내장 REPL에서 상태 모델 검사 18개 통과. 잘못된 횟수·빈 입력·중복 요청·단계 제한·세션 격리·거짓 성공을 검사했다.
- 실제 UI 소스를 최소 DOM 모형에서 실행하여 5개 흐름과 내보내기 이벤트 1개 통과. 입력 change가 DOM 버튼을 교체해 저장 클릭을 잃는 문제를 수정했다. 이것은 실제 브라우저 검사와 구분한다.
- 4×5×3=60세션의 고정 스크립트 재생, 웹 app-state 실패 0. 모든 native 세션은 not-run/not-evaluated이며 사람이 평가한 사용성 성공률로 표현하지 않는다.
- 공유 검사 41개는 앞선 A 통합에서 통과. 이번 작업은 기존 v1 스키마를 변경하지 않는다.
- 실제 브라우저 검사 미완료: Browser Use가 request-header policy 로딩 오류를 반복했고, Computer Use는 현재 URL을 충분히 확인하지 못해 조작을 중단했다. 렌더·접근성·브라우저 다운로드 완료는 검증하지 않았다.
- Swift 컴파일·XCTest·전체 iOS 빌드·live 모델·원격 push/CI/배포/운영 DB 작업은 미실행. Node CLI가 PC PATH에 설치됐다고 보고하지 않는다.

## 사용과 후속 경계

README의 preview 명령으로 만든 simulation/runs/<새 ID>/index.html을 직접 연다. Node가 없어도 생성된 HTML은 열 수 있다. 결과는 ignored runs 경로에 남고 기존 출력은 덮어쓰지 않는다.

현재 가상 사용자 역할은 사람이 직접 수행하고 batch는 고정 스크립트다. live 모델이 목표에 따라 행동하거나 기획 개선안을 자동 생성하는 어댑터는 아직 없다. 웹에서 얻은 개선안의 제품 적용과 실제 iOS 검증도 별도 작업이다. 운영 인증·데이터를 이 환경에 연결하지 않는다.
