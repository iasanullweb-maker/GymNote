# 다른 대화 변경 통합 배포 — 2026-10-10

## 현재 상태

사용자가 다른 대화의 변경을 검토·통합하고 배포하도록 승인했다. GitHub 재인증을 마친 뒤 저장소 소유 계정을 지정해 업로드했고, 최종 후보의 전체 CI와 Release 빌드가 통과했다. 로컬 main 통합·원격 push·**0.1.99 공개 릴리스·AltStore 소스 갱신·IPA 대조까지 완료**했다. 기기 설치는 수행하지 않았다.

검증 커밋은 `fa4d54a3ea1f255326f2c81bedaeb975ba9c129d`, 실제 main 배포 커밋은 `9580a758dd4d4efd6df9b8fb2973459e494edab7`이다. 검증 대기 중 다른 대화가 추가한 인수인계 문서를 source에 병합했다. 두 SHA의 전체 diff가 `HANDOFF.md` 하나뿐임을 확인했으므로 앱·위젯·공유 코드·리소스·테스트·설정·서버·빌드 도구/CI 트리는 동일하다. 공통 잠금 아래 원본 main에 fast-forward 통합했고, 원격 main의 ancestry와 추적 파일의 깨끗한 상태를 재확인한 뒤 일반 push했다. 기존 미추적 `%SystemDrive%/` 폴더는 보존했다.

## 검토·병합 범위

- `codex/shared-exercise-catalog`: 운동 안내, 시작 루틴, 운동 요약, 종목 대체와 동시 진행 보존. `codex/planfit-workout-improvements`의 작업을 포함한다. 후보 병합 커밋 `728efa1`.
- `codex/login`: 기존 구현 이후의 빈 검증 표시 커밋까지 병합했다. 후보 병합 커밋 `4570ec6`.
- `origin/codex/multi-device-sync`: 다중 기기 동기화, 모바일 데이터 연결, 요일에 의존하던 테스트 수정까지 병합했다. 후보 병합 커밋 `f6ca53f`.
- 기존 로컬 main에 통합된 UI·계획·기록 변경과 파일럿 후속 UI 수정 `cc09fbe`를 보존했다. 다른 작업 브랜치와 워크트리의 추적 파일 상태를 확인했고, 이미 포함된 변경은 중복 구현하지 않았다.

제품·저장 로직과 UI를 별도 읽기 전용 subagent 두 개로 검토했다. 아래 수정 뒤 코드 검토에서 추가 차단 문제는 발견되지 않았다. 코드 검토는 컴파일·XCTest 통과를 대신하지 않는다.

## 배포 준비 중 수정

1. `506dbe1`: 종목 대체 화면을 연 뒤 위젯에서 새 운동을 시작한 경우, 오래된 화면의 대체 저장이 최신 진행을 덮어쓰지 않도록 차단했다. 이를 재현하는 회귀 테스트를 추가했다. 기존 병합 테스트의 기대값에는 실제 저장 형식에서 유지하는 빈 반복 배열을 포함시켜 전체 데이터 비교를 유지했다.
2. `09001e9`: 기존 `scripts/test_cloud_merge.swift`의 다중 기기 병합 회귀 검사를 Validate와 Build IPA 워크플로 모두에 추가했다.
3. `c1bb52e`: CI에서 확인한 `App/RoutineView.swift:228`의 SwiftUI Section 컴파일 오류를 수정했다. 제목 문자열과 footer를 함께 쓰던 호출을 명시적 content/header/footer 초기화로 변경했다.
4. `93d94cb`: 운동 목록 toolbar의 bare EditButton(View)과 ToolbarItem(ToolbarContent) 혼합으로 발생한 추가 컴파일 오류를 수정했다. EditButton을 ToolbarItem으로 감쌌으며 별도 UI 검토에서 확인했다.
5. `fa4d54a`: 저장 실패 복구 테스트가 SharedStore.activate로 새 generation을 만든 뒤 모델의 오래된 선택 정보를 사용하던 오류를 수정했다. 실제 제품 경로인 AppModel.switchAccount로 복귀하고 계정 ID·새 generation·재시도 및 영속화를 검사한다. 제품의 stale 선택 쓰기 차단은 유지했으며 별도 저장 로직 검토에서 확인했다.

## 검증 근거와 남은 단계

`git diff --check`와 변경 검토는 통과했다. Windows에는 Swift/Xcode 도구가 없어 로컬 빌드는 실행하지 않았다. 아래 macOS CI에서 전체 iPad XCTest와 앱·위젯 Release 빌드를 수행했다.

| 대상 | Validate | Build IPA | 결과 |
|---|---|---|---|
| `506dbe1` | [#61](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044213001) | [#94](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044213003) | Section 컴파일 오류로 실패. Validate의 계정 삭제·DB 작업은 성공 |
| `09001e9` | [#62](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044383690) | [#95](https://github.com/iasanullweb-maker/GymNote/actions/runs/38044383703) | 같은 Section 컴파일 오류로 실패 |
| `248a8fa` | [#63](https://github.com/iasanullweb-maker/GymNote/actions/runs/38050645793) | [#96](https://github.com/iasanullweb-maker/GymNote/actions/runs/38050645813) | toolbar builder 혼합 컴파일 오류로 실패 |
| `93d94cb` | [#64](https://github.com/iasanullweb-maker/GymNote/actions/runs/38050898487) | [#97](https://github.com/iasanullweb-maker/GymNote/actions/runs/38050898495) | Release 성공. 저장 재시도 테스트의 두 단언 실패 |
| `fa4d54a` | [#65](https://github.com/iasanullweb-maker/GymNote/actions/runs/38051709671) | [#98](https://github.com/iasanullweb-maker/GymNote/actions/runs/38051709664) | 모든 작업 성공. XCTest 97개 중 92 통과·5 건너뜀·실패 0. 모델·계정·다중 기기 병합·DB·계정 삭제 검사와 Release 앱/위젯 빌드 성공 |
| `9580a75` main | 제품/검사 트리는 위 검증 SHA와 동일 | [#99](https://github.com/iasanullweb-maker/GymNote/actions/runs/38052075300) | Release 빌드·IPA 생성·Publish releases·Update AltStore source 모두 성공 |

공개 check annotations와 공식 Git 인증 도우미로 내려받은 Actions 로그로 오류와 최종 검사 결과를 확인했다. 최초 인증 실패 뒤 추가 인증 헤더·환경 토큰 탐색은 자동 승인 검토가 거부해 실행하지 않았다. 사용자의 공식 Git Credential Manager 로그인 후 등록된 두 계정 중 저장소 소유 계정을 지정하자 일반 Git 인증이 성공했다. 인증 정보와 원본 로그는 Git에 포함하지 않았다.

위 XCTest의 건너뜀 5개는 친구·친구 순위·기록 달력·운동 시작 전·휴식 화면의 인증 상태/고정 날짜/고정 시각 fixture 미지원 조건이다. 해당 화면의 실제 사용자 조작이나 운영 서버 동작을 검증한 것으로 보고하지 않는다.

## 배포 결과 대조

- [고정 릴리스 build-99](https://github.com/iasanullweb-maker/GymNote/releases/tag/build-99)와 [latest](https://github.com/iasanullweb-maker/GymNote/releases/tag/latest)의 target 및 실제 Git tag가 모두 배포 SHA `9580a758dd4d4efd6df9b8fb2973459e494edab7`과 일치한다.
- 공개 IPA를 내려받아 앱 `com.gymnote.app`과 위젯 `com.gymnote.app.widget`의 Info.plist가 모두 버전 `0.1.99`, 빌드 `99`임을 확인했다. 두 Mach-O의 서명 entitlement에 App Group `group.com.gymnote.app`이 포함돼 있다.
- IPA 크기: **2,227,390 bytes**. SHA-256: `6261237901d2c3490449710178f18e30036ab940406ac446a2c2e05ea60c0e04`. build-99/latest 자산의 크기·digest와 실제 파일이 일치한다.
- [AltStore source](https://raw.githubusercontent.com/iasanullweb-maker/GymNote/altstore/source.json)의 bundle ID, 버전 `0.1.99`, buildVersion `99`, size가 실제 IPA와 일치하고, downloadURL은 `https://github.com/iasanullweb-maker/GymNote/releases/download/build-99/GymNote.ipa`로 고정돼 있다.
- 배포 뒤 이 결과와 파일럿 인덱스만 문서 커밋·로컬 통합한다. 앱 코드 변경이나 새 배포를 시작하지 않는다. 문서 최종 커밋은 완료 응답에 남긴다.

후보와 기존 원격 main 사이에 Supabase 마이그레이션 변경은 없다. 운영 SQL을 별도 적용하지 않았으며, 기존 운영 서버 미확인 항목이 앱 빌드 성공으로 해소됐다고 보고하지 않는다. 현재 설치된 iPad 앱의 SHA는 미확인이고, 이번 수정 화면의 실제 기기 재검증은 배포·설치 후 수행해야 한다.
