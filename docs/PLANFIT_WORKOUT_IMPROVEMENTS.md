# 플랜핏 조사 후 운동 흐름 개선

2026-10-10. 적용 스킬: gymnote-task, gymnote-verify, gymnote-ux-check, gymnote-data-change, gymnote-handoff. HANDOFF의 최신 상태와 AGENTS, 병행 작업 배정 및 로컬 통합 절차를 확인했다. 이전 자동화 A/B/C/D 배정을 이번 앱 작업의 역할로 사용하지 않았다.

## 워크트리 및 기준

- 시작 폴더: `C:/Users/Donghyun/Documents/ChatGPT/gymnote in web 2/GymNote`, 브랜치 `codex/shared-exercise-catalog`, 시작 커밋 `f82bff6`.
- 시작 당시 다른 작업의 미커밋 파일 10개를 보존했다. 해당 작업이 원본에서 `a658708`로 커밋된 뒤 작업 워크트리에 병합해 호환성을 검토했다.
- Codex 앱의 create_worktree 호출은 `fatal: invalid reference: codex/shared-exercise-catalog`로 실패했다. 앱 도구의 복구 성공으로 보고하지 않는다.
- 확인 결과 대화 cwd인 상위 `gymnote in web 2`에도 별도의 빈 Git 저장소가 있고(`master`, HEAD 없음), 실제 GymNote는 그 아래 별도 저장소다. 앱 호출의 브랜치 참조 실패는 이 상위 폴더를 저장소로 인식한 상황과 일치한다. 이번에는 앱 프로젝트 설정을 임의 변경하지 않고 실제 GymNote 루트를 명시해 Git 워크트리를 사용했다.
- HANDOFF의 Git 방식은 정상: `git -C GymNote worktree add -b codex/planfit-workout-improvements .worktrees/planfit-workout-improvements HEAD`로 실제 생성했다. 경로는 위 시작 폴더 아래 `.worktrees/planfit-workout-improvements`, 새 브랜치는 `codex/planfit-workout-improvements`다. git worktree 목록과 브랜치로 확인한다.
- 검토·커밋 후 기존 `codex/shared-exercise-catalog`로 공통 UX 통합 잠금 아래 로컬 병합한다. 최종 통합 여부와 커밋은 완료 응답의 상태 확인 결과를 따른다. 별도 main 통합·원격 push·배포·운영 DB 변경은 하지 않는다.

## 구현한 순서와 사용법

1. **지난 기록:** 실행 탭 운동마다 가장 최근 저장 일지의 세트별 실제 횟수·무게를 표시한다. 복사한 루틴의 UUID가 달라도 기존 운동 이름 정규화 기준으로 조회한다. 같은 이름이 중복된 일지는 복사 대상으로 선택하지 않는다. 진행 중 세션·미래 일지는 제외하며, 미기록 횟수를 계획 횟수로 채워 넣지 않는다. 운동을 시작한 뒤 **지난 N세트 횟수로 채우기**를 누르면 현재 입력 횟수만 바뀌고, 사용자가 세트 완료를 눌러야 저장된다. 무게는 참고용이며 자동 입력하지 않는다. 시간 운동에는 횟수 채우기를 표시하지 않는다.
2. **종료 요약:** 실행 탭의 최근 운동 결과와 운동 일지 상세에서 완료 세트·기록된 실제 횟수·운동 시간·최근 7일 운동 일수·기존 기록 대비 신기록을 표시한다. 계획 횟수는 실적에 합산하지 않는다. 이전 운동 대비 횟수는 모든 세트가 완료되고 실제 횟수가 모두 있으며 종목·세트 수·세트별 무게가 같은 경우에만 비교한다. 부분 완료·구성 변경·무게 변경·미기록이면 성장 수치를 만들지 않는다. 지난 운동 직접 입력의 미기록 경과 시간은 그대로 유지한다.
3. **기본 루틴:** 빈 실행 화면 또는 계획 → 날짜 설정 → **기본 루틴 선택해서 추가**에서 맨몸/덤벨/헬스장, 운동 경험, 15/30/45분을 고르고 미리보기 후 추가한다. 기존 날짜 계획 뒤에 새 UUID로 추가하며 원래 운동과 일지는 보존한다. 해당 날짜의 운동을 진행 중이면 추가를 막는다. 시간은 구성 선택 기준이며 실제 소요 시간을 보장하지 않는다. 고정 기본 루틴이며 AI 개인화·자동 중량 추천은 아니다.
4. **운동 안내·대체:** 실행 탭 각 운동의 **운동 안내·대체**에서 부위·필요 기구·핵심 동작·흔한 실수·외부 자세 자료를 확인한다. 15개 안내 종목과 명시적 별칭을 제공한다. 대체 이유와 기구로 후보를 좁히거나 전체 안내 종목에서 직접 선택한다. 새로운 횟수/시간을 확인하고 적용한다. 이미 완료한 세트는 원래 운동 ID/이름/실제 횟수/무게로 남고 남은 세트만 새 UUID 운동으로 나뉜다. 진행 중 교체는 세션에만 반영되고 저장 일지·원래 날짜 계획을 소급 수정하지 않는다. 안내가 없는 개인 종목에는 미준비 안내를 표시한다.

## 저장 및 동시 변경

- 새로운 저장 필드나 서버 마이그레이션 없이 기존 DayPlan/WorkoutSession/실제 횟수·무게 형식을 사용한다. 안내와 기본 루틴 카탈로그는 앱에 포함하며 사용자 데이터와 별도로 관리한다.
- 기본 루틴 및 대체는 원본의 `AppModel.saveEdit` 저장 결과와 실제 새 운동 ID를 모두 확인한 뒤 화면을 닫는다. 실패 시 입력 화면을 유지한다. 계정 generation을 확인해 다른 계정으로 적용하지 않는다.
- 대체 화면에서 예상 세션 ID·완료 세트 수·원래 운동 내용을 확인한다. 저장 잠금 안에서도 최신 세션/날짜 계획과 기준 사본을 비교한다. 위젯·다른 기기에서 상태가 바뀐 구조 교체는 거부하여 추가 완료 횟수가 잘리는 것을 막고, 최신 기기 상태를 다시 읽는다. 일반 세트 완료·순서 이동·루틴 추가에는 기존 병합 방식이 적용된다.

## 검사 결과와 한계

- 이번 변경 Swift 12개 파일의 tree-sitter-swift 구문 검사 오류 0. git diff --check 통과. 저장 형식·호출자·앱/위젯 소스 포함·저장 실패·동시 세트 완료 경로를 코드 검토했다.
- 안내 이름 15개 고유성과 기본 루틴 종목 12개 모두의 안내 연결을 정적 검사했다. 기능 실행 테스트와 구분한다.
- 전체 App/Shared/Tests 49개 파일 검사에서 기존 `App/DailyViews.swift`의 여러 trailing closure 줄바꿈 `footer:` 위치가 파서 오류로 표시됐다. `a658708` 원본에서도 동일하다. 이번 파일은 수정하지 않았으며 Swift 컴파일 오류로 판정하지 않는다.
- `Tests/WorkoutInsightsTests.swift`에 XCTest 14개 추가: 실제 값/미기록/복사 UUID/중복 이름/미래 제외, 비교 조건/부분 완료/시간 미기록/운동일수, 기본 루틴 27조합/새 ID/직렬화/기존 계획 보존, 완료 후 대체/자동 종료/병합/재시작, 오래된 화면 거부, 후보 조건/별칭, 실제 저장·실패 복원·위젯 동시 완료·다른 기기 계획 충돌.
- **이 Windows 환경에는 Swift/Xcode가 없고 WSL도 설치되어 있지 않다. XCTest·기존 Swift 회귀 스크립트·전체 iOS 빌드·실기기 화면/위젯/두 기기 동작은 미실행이다. 구문 검사와 코드 검토를 이 검사들의 성공으로 보고하지 않는다.** 테스트 파일은 project.yml의 Tests 디렉터리 대상에 자동 포함된다.
- 웹 모사는 이 새 SwiftUI 흐름을 구현하지 않으므로 검증 근거로 사용하지 않았다. 이전 CI 성공을 이번 코드의 검증 근거로 사용하지 않는다.

## 다음 검증

- Mac/승인된 CI에서 GymNote XCTest 및 전체 앱·위젯 빌드. 특히 새 14개 테스트와 기존 WorkoutFlowTests·AccountStoreTests·수동 일지/모델/계정 회귀를 실행한다.
- iPhone/iPad 작은 화면·큰 글자에서 지난 기록·요약·미리보기·선택 화면의 스크롤과 저장/취소를 확인한다.
- 1세트 완료 후 대체 → 남은 세트 완료 → 일지에서 두 운동의 실제 값 확인 → 재실행하여 보존 확인.
- 대체 화면을 연 상태에서 위젯으로 다음 세트 완료 → 대체 저장 거부 → 최신 완료 기록 유지. 같은 계정 두 기기에서도 계획/세션 충돌을 확인한다.
- 저장 실패 재시도, 계정 전환, 새 운동 시작, 자정 이후 진행 중 운동, 이전 일지 수정 후 요약 재계산을 확인한다.

## 안내 자료

카피나 이미지를 복제하지 않고 짧은 한국어 안내를 작성했다. 외부 자료 링크는 인터넷 연결이 필요하다.

- [Mayo Clinic 운동 영상 모음](https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/strength-training/art-20046031)
- [Mayo Clinic 스쿼트](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/squat/vid-20084663)
- [Mayo Clinic 덤벨 운동](https://www.mayoclinichealthsystem.org/hometown-health/speaking-of-health/pump-you-up-exercise-with-dumbbells-video)
- [ACE 글루트 브리지](https://www.acefitness.org/resources/everyone/exercise-library/49/glute-bridge/)
- [ACE 루마니안 데드리프트](https://www.acefitness.org/continuing-education/certified/may-2025/8865/the-ace-do-it-better-series-the-romanian-deadlift/)
- [ACE 랫 풀다운](https://www.acefitness.org/resources/everyone/exercise-library/158/seated-lat-pulldown/)
- [NASM 운동 자료](https://www.nasm.org/workout-exercise-guidance)
- [NASM 레그 프레스](https://www.nasm.org/resource-center/exercise-library/leg-press)
- [NASM 체스트 프레스](https://www.nasm.org/resource-center/exercise-library/chest-press-machine)
