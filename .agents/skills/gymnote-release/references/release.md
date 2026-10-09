# 현재 배포 경로 확인

명령은 저장소 루트에서 현재 remote와 도구에 맞춰 사용한다. 접근 권한이 없으면 기존 문서만으로 실제 배포 완료를 주장하지 않는다. 현재 워크플로가 아래 내용과 다르면 실제 설정을 우선하고 차이를 보고한다.

## 워크플로 의미

- check.yml: pull_request 및 codex 브랜치 push의 iPad XCTest·계정 삭제·격리 DB 검사. 현재 workflow_dispatch는 없다.
- build.yml: main 및 codex 브랜치 push와 workflow_dispatch의 모델 검사·macOS Release 앱/위젯 빌드·IPA artifact. 브랜치 예외와 버전 생성 규칙도 확인한다.
- main 실행만 build-N/latest 릴리스와 altstore 브랜치 source.json을 갱신한다. 현재 버전은 0.1.<run_number>이며 run 번호 확인 전에 버전을 단정하지 않는다. latest 교체와 오래된 build-N 정리도 이 워크플로에서 수행한다.
- 두 워크플로는 독립적이다. main push가 check.yml 성공을 기다리거나 새 XCTest를 실행한다고 가정하지 않는다. 전체 검증이 없으면 승인 범위 안의 codex 브랜치/PR로 검증한 후 대상 트리와 배포 트리를 대조한다.
- IPA는 인증서 없이 빌드하고 App Group entitlements를 포함한 ad-hoc 서명으로 포장한다. AltStore가 설치 시 재서명한다. App Store/TestFlight 배포 절차로 보고하지 않는다.

## 대상과 원격

git remote -v, fetch 후 원격 브랜치와 로컬 로그·diff를 확인한다. fetch는 원격 쓰기가 아니지만 push는 외부 변경이다. 다른 작업의 로컬 통합·원격 커밋을 덮어쓰지 않는다. main에 미승인 변경이 있으면 선택한 배포 트리를 별도 브랜치에서 구성할 수 있으나 원격 main의 기존 변경을 되돌리는 결과라면 임의로 진행하지 않는다.

GitHub CLI가 있으면 run list/view/watch, release view/download를 사용하고 커넥터가 있으면 동등한 기능을 사용한다. 옵션은 설치된 도움말로 확인한다. 최신 run 목록 대신 기록한 대상 run ID를 따른다.

## 완료 대조

1. 대상 run head SHA와 branch, 검사·빌드·Publish releases·Update AltStore source 성공을 확인한다. 취소/건너뜀은 성공이 아니다.
2. build-N의 target commit/tag와 IPA, latest의 대상·파일 일치를 확인한다. latest가 다른 작업의 더 새 배포면 구분하고 승인 없이 되돌리지 않는다.
3. IPA는 Git 제외 전용 출력 폴더에서 확인한다. Info.plist의 앱/위젯 버전·빌드, 바이트 수·SHA-256을 기록한다. 토큰·비공개 계정 값을 출력하지 않는다.
4. remote altstore의 source.json에서 bundle ID, 버전/빌드, 고정 build-N downloadURL, size가 실제 IPA와 일치하는지 확인한다. 설치 안내는 README를 따른다.
5. 릴리스 공개, 소스 갱신, 사용자 AltStore 설치, 실기기 검사를 각각 보고한다. 일부만 성공했으면 완료라고 묶지 않는다.

## 실패와 복구

검증 실패는 원인과 수정 필요 범위를 보고하고, 수정이 승인된 범위일 때 고친 뒤 새 SHA를 재검증한다. 준비 상태 확인만 요청받았으면 제품·테스트를 임의 수정하지 않는다. 빌드·게시 실패는 실패 단계와 공개 상태 확인 후 승인된 동일 범위에서 재시도한다. 제품 변경·배포 범위 변화가 필요하면 해당 부분만 조율한다. 이전 정상 커밋·IPA 근거를 보존하고 Git 기록을 강제로 되감지 않는다. 재서명·설치·데이터 보존은 실기기 확인 전 복구 완료로 보고하지 않는다.
