# 세부 튜토리얼 배포 인계 — 사용자 요청으로 작업 종료

> 2026-10-22 재개 확인: 정식 #141 attempt 2는 이후 게시까지 성공했다. [최종 IPA·AltStore 대조 결과](release-141-20261022.md)를 따른다. 아래는 2026-10-21 중단 당시의 기록이다.

정리 시각: 2026-10-21T23:29:28+09:00

## 사용자 지시와 현재 상태

- 사용자 “배포 진행해” 승인으로 배포 준비와 main push를 수행했다. 이후 “여기까지 하고 정리해둬” 지시를 받아 추가 변경·push·재시도·배포 검증을 멈춘다.
- 정리 시점 배포는 **완료하지 않았다**. 기존 정식 latest는 `950417f`(0.1.137)다. 최종 IPA·build/latest 태그·AltStore 버전/빌드·URL·크기·해시 대조는 아직 하지 못했다.
- GitHub 실행은 취소하지 않고 유지했다. 정식 #141은 앞으로 실행기가 배정되면 자동 게시까지 진행할 수 있다. Intel #142는 검증 브랜치 실행으로 게시하지 않는다. 새 자동화/모니터는 만들지 않았다.

## 승인된 배포 범위와 커밋

- 이번 요청: 세부 튜토리얼 7종·계획 이름 직접 편집 제거·계정별 완료 이력 동기화.
- 별도 위젯 배치 수정 `6e9e826`은 이번 배포에서 제외했다. 로컬 main과 원래 작업 브랜치에는 그대로 보존했다. 원본 main을 통째로 push하면 이 위젯 수정까지 포함되므로 그러지 않는다.
- 원격 기존 main `950417f`에서 배포용 워크트리 `C:/Users/Donghyun/Documents/ChatGPT/gymnote in web 2/detail-tutorial-release`를 만들었다. `fdf08f5` → `068a3bd`, `6c95bae` → `4e5b52e`로 제품 변경 두 커밋만 cherry-pick했다.
- 배포 대상 `4e5b52e41a18ec1e5128e191718c0c44b347ce98`: App·Shared·Tests·scripts·CI·project Git 트리 ID는 검토 소스 `6c95bae`와 같고 Widget은 기존 정식 `950417f`와 같다. 근거 `.validation-tools/release-detail/component-trees.json`.
- [사전 검증 #140 / 39612081523](https://github.com/iasanullweb-maker/GymNote/actions/runs/39612081523): 같은 `4e5b52e`의 iOS·DB·계정 삭제·tooling·앱/위젯 Release·게이트 모두 성공. XCTest 186개(182 통과·기존 4개 건너뜀·실패 0). 실제 세부 안내 15장 검토 근거는 기존 [결과](detail-tutorial-account-20261021.md) 참조. 해당 앱/공유/검사 트리는 동일하다.

## 정식 #141: 원격 main에 반영했으나 게시 대기

- 공통 `.validation-tools/ux-integration.lock` 아래 원격 main 기준·소스 SHA·양쪽 추적 파일·진행 중 Git 작업·scope·ancestry를 확인해 `4e5b52e`를 일반 fast-forward push했다. 원격 main 현재 `4e5b52e`.
- [정식 Build IPA #141 / 39613144658](https://github.com/iasanullweb-maker/GymNote/actions/runs/39613144658), source `4e5b52e`, 예정 버전 0.1.141.
- 1차 실행은 GitHub가 hosted runner를 여러 차례 배정하지 못해 build와 checks/ios가 cancelled, 전체 failure. 주석: `The job was not acquired by Runner of type hosted even after multiple attempts`; macOS arm64 capacity 안내. DB·계정 삭제·tooling 성공, gate/publish skipped. 부분 게시 없음·기존 latest 유지 확인 후 같은 run/SHA의 failed jobs 재실행을 한 번 요청했다.
- 정리 시점 attempt 2: **queued**. build·checks/ios queued, DB·계정 삭제·tooling success. 추가 재실행은 하지 않았다.

## Intel 대체 검증 #142: 실행 중, main 미반영

- 재실행도 배정 대기가 이어져 공식 [GitHub 실행기 문서](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)의 표준 `macos-15-intel`로 대체 검증을 준비했다. 변경은 `.github/workflows/build.yml` build와 check.yml ios의 runs-on 두 줄뿐이다. 앱·모델·테스트·배포 게이트는 유지한다.
- 브랜치 `codex/detail-tutorial-intel-release-20261021`, 커밋 `a45389de6ce0b7ff04d0ea85c2e4e6bff0c975e5`. 위 배포용 워크트리는 현재 이 브랜치에 있다. 원래 `codex/detail-tutorial-release-20261021` 브랜치도 `4e5b52e`로 보존돼 있다.
- [검증 Build IPA #142 / 39616093717](https://github.com/iasanullweb-maker/GymNote/actions/runs/39616093717): 정리 시점 **in_progress**. Intel build·checks/ios 진행 중, DB·계정 삭제·tooling 성공. 전체 통과/Release 완료는 아직 확인하지 않았다.
- `a45389d`는 검증 브랜치에만 push했으며 원격/로컬 main과 원래 작업 브랜치에 병합하지 않았다. 사용자 중단 요청으로 검증 결과를 더 기다리거나 main에 반영하지 않는다.

## 재개 순서

1. 새 실행을 만들기 전에 #141 attempt 2와 #142의 현재 상태, 원격 main, latest와 AltStore 소스를 먼저 조회한다. 상태는 이 문서 작성 뒤 바뀔 수 있다.
2. #141이 게시까지 성공했다면 같은 run/source를 고정하여 실제 IPA·앱/위젯 0.1.141·build-141/latest SHA·고정 URL·크기·SHA-256·AltStore를 대조한다. 이 경우 #142를 배포할 필요가 있는지 별도로 판단하고 중복 배포하지 않는다.
3. #141이 여전히 배정 대기/실패이고 #142가 전체 검사·앱/위젯 Release·게이트 성공했다면, 실행 중인 #141의 게시 여부부터 확인·정리한다. 원격 main이 여전히 `4e5b52e`인지 확인하고, 검증된 `a45389d`만 일반 fast-forward push하여 새 정식 run의 게이트/게시를 확인한다. 새 버전 번호는 실제 run으로 확인한다. 원래 main 전체를 push하지 않는다.
4. #142 실패 시 로그를 확인해 source/검사/실행 환경의 문제를 구분한다. 검사·보안을 우회하거나 실패한 검증을 통과로 처리하지 않는다. 재개 전에는 추가 행동하지 않는다.
5. 실제 게시 성공 뒤 `plan_editor_github.py release-audit <run> <정확한 SHA> <Git 제외 출력 폴더>`로 고정 태그·latest·IPA·AltStore를 대조하고 이 문서·HANDOFF·TODOLIST를 갱신한다. 실기기 설치/두 계정·두 기기/VoiceOver 확인은 사용자 확인 대기다.

## 로컬 정리와 도구

- 원래 작업 폴더 `tutorial-focus`, 브랜치 `codex/tutorial-focus-20261021`: `59c29ca`에서 원격 main의 배포 이력 `4e5b52e`를 병합했다. 로컬 위젯 변경을 보존했으며 제품·검사·CI 트리는 기존 검증 `6c95bae`와 동일하다. 이번 정리 문서만 커밋하고 기존 main에 잠금 아래 로컬 통합한다. 문서 push로 새 배포를 시작하지 않는다.
- 원본 `C:/Users/Donghyun/Documents/2026_IASA/GymNote`의 기존 미추적 `%SystemDrive%/`는 그대로 보존한다. Intel CI 대체 변경은 아직 통합하지 않는다.
- GitHub API 도구: 원본 `.validation-tools/plan_editor_github.py`(runs/jobs/artifacts/joblog/release-audit). 인증은 기존 Git credential을 내부적으로 읽으며 토큰을 출력하지 않는다.
- 로컬 근거: 원래 작업 폴더 `.validation-tools/release-detail/`의 preflight-ios.log, component-trees.json, attempt-1-runner-failure.json, pause-snapshot.json. guarded push 스크립트도 같은 폴더에 있으나 재개 시 최신 SHA/상태를 다시 확인해야 한다.
