# 운동 시작 차단·미등록 운동 정리 — 2026-10-12

## 요청과 현재 상태

사용자가 0.1.104에서 운동 시작 불가를 제보하고 수정·검증·배포·업데이트 후 휴리봇 작업을 재개하도록 요청했다. USB 화면에서 미등록 종목 안내를 직접 확인했다. 계획의 종목 하나라도 활성 관리자 종목 이름과 일치하지 않으면 전체 시작이 막히는 코드가 원인이다. 후속 사용자 지시로 새 미등록 생성 금지와 과거 일지·최고기록까지 포함한 기존 미등록·비활성 운동 삭제를 확정했다.

작업 폴더 `.worktrees/start-workout-fix`, 브랜치 `codex/start-workout-fix-20261012`, 시작 main `25993f8`. 기존 버전 표시와 신디 세트 전환도 이번 통합 트리의 검증 대상이다. 기존 미추적 `%SystemDrive%/`는 보존한다.

## 동작과 데이터 경계

- 현재 서버 조회 성공 후 프로세스 내 정리 정책을 활성화한다. 내장 기본값·캐시·조회 실패/취소로는 삭제하지 않으며 정상 빈 서버 목록은 전체 미등록으로 처리한다.
- 주간/날짜 계획, 목록, 진행 세션, 과거 일지, 보존 성취, 기록 정의·기록·보존 최고, 세트별 횟수/무게/측정값/완료 참조를 정리한다. 활성 종목의 호환되는 기존 기록 ID는 보존한다. 빈 날짜 키는 유지해 주간 계획 fallback을 막는다.
- 계정별 읽기·저장·서버 채택·병합·게스트 가져오기에서 재유입을 정리한다. 원격/로컬/기준 데이터를 같은 기준으로 비교하고 서버 원본과 다르면 dirty로 삭제를 동기화한다. 서버 SQL 변경은 없다.
- 등록된 운동과 일상·설정을 보존한다. 실제 삭제 전 보호된 로컬 복구 사본을 유지하고 쓰기 실패 시 원본을 덮어쓰지 않는다. 복구 사본은 사용자 화면에 표시하거나 자동으로 복원하지 않는다.
- 빈 종목의 운동 만들기를 제거하고 등록된 종목 선택만 허용한다. 저장·대체 후보·실행 직전에도 등록 여부를 검사한다.

## 검토·검증

독립 `start_audit`가 원인과 데이터 경계를 검토하고 XCTest 11개를 작성했다. `creation_guard`가 생성 UI를 보완하고 기존 회귀 fixture 영향을 검토했다. 주 에이전트가 통합 검토와 실패/성공 서버 조회·신규 생성 차단 XCTest 3개를 추가했다. 기존 저장 실패/위젯 경쟁 검사는 등록된 종목으로 조건을 바꿔 새 가드가 검사 목적을 가리지 않게 했다.

Windows Python 3.12/tree-sitter-swift로 변경 Swift 11개 구문 오류 0, git diff --check 통과. 실제 기기 화면은 Git 제외 `simulation/runs/start-workout-20261012/before.png`에 보관한다. 화면은 원인 증거이며 저장/동기화 검사 결과가 아니다.

- 첫 SHA `6d63fbf`의 Validate run `38198081182`는 새 테스트의 긴 배열 표현식 타입 검사 시간 초과로 컴파일 실패했다. 제품 검사·DB·권한은 통과했고 당시 Build run `38198081186`은 후속 push로 취소됐다. 테스트 표현식을 타입이 명확한 여러 배열 추가로 나눴으며 검사를 삭제하거나 약화하지 않았다.
- 최종 검증/배포 코드 `45ae068408e4b2697530ac31ce8f8c705f64ac82`의 [Validate run 38198234097](https://github.com/iasanullweb-maker/GymNote/actions/runs/38198234097) 성공. 실제 로그를 대조해 XCTest 144개 중 140개 통과·기존 UX 캡처 4개 건너뜀·실패 0을 확인했다. 신규 14개와 기존 신디 검사 모두 통과했다. Swift 모델·계정·클라우드 병합·일상·기록·친구 순위, 계정 삭제 권한 및 격리 DB 검사도 통과했다.
- 같은 SHA의 [검증용 Build run 38198234081](https://github.com/iasanullweb-maker/GymNote/actions/runs/38198234081)에서 앱·위젯 전체 Release 빌드 성공.
- 공통 통합 잠금 아래 기존 main에 fast-forward로 로컬 통합하고 전체 트리 동일성을 대조했다. 사용자 배포 승인 범위로 정확히 같은 SHA를 원격 main에 push했다.
- [정식 Build run 38198762377](https://github.com/iasanullweb-maker/GymNote/actions/runs/38198762377), **0.1.107/build 107 배포 완료**. 앱·위젯 Release 빌드, 릴리스 게시, AltStore 소스 갱신 모두 성공했다. 검증 SHA와 배포 SHA가 동일하다. 운영 SQL 변경/적용은 없다.

## 배포 대조와 다음 단계

- [build-107](https://github.com/iasanullweb-maker/GymNote/releases/tag/build-107)·[latest](https://github.com/iasanullweb-maker/GymNote/releases/tag/latest)의 태그 대상은 `45ae068408e4b2697530ac31ce8f8c705f64ac82`로 동일하다. 두 자산의 API digest·크기가 같으며 고정 IPA를 직접 내려받아 2,171,197바이트, SHA-256 `8b4b4b91dd811ee71a57fae8dff446bcf8c993b2917a830d5bcd185be20eae47`를 대조했다.
- IPA 내부 `com.gymnote.app`·`com.gymnote.app.widget` 모두 0.1.107/build 107이다. 두 Mach-O 실행 파일의 LC_CODE_SIGNATURE SuperBlob에서 XML entitlements를 읽어 서명 App Group `group.com.gymnote.app`을 확인했다. 실제 설치 재서명은 AltStore가 수행한다.
- 원격 altstore SHA `da662ae1ef036d7fa3bca742884411930fb22418`의 source.json bundle ID·버전·빌드·크기·고정 build-107 다운로드 URL이 IPA와 일치한다.
- 사용자에게 AltStore 소스 새로고침→업데이트→설정 하단 `0.1.107 (107)` 확인→실행 화면 열기를 안내했다. 현재 **업데이트·실기기 운동 시작·삭제 결과는 사용자 확인 대기**이며 자동 검사로 완료 처리하지 않았다. 확인 후 휴리봇 작업을 재개한다. 기존 사용자 확인 대기도 보존했다.
- 사용자는 USB 연결·같은 Wi-Fi에서 Sources 새로고침의 긴 로딩을 보고했고, 이어 107 버전의 UPDATE가 표시됐다고 확인했다. 이는 최신 소스 정보를 받은 범위의 확인이며 설치 성공은 아니다. PC 읽기 전용 점검에서는 USB 1대·AltServer 1.8.0 응답·Apple Mobile Device/Bonjour 실행·PC VPN 어댑터 연결 끊김을 확인했다. AltServer/iTunes 재시작이나 네트워크 설정 변경은 하지 않았다.
- 정리 권한은 프로세스 내에만 두므로 앱 재시작 뒤 성공한 서버 조회 전에는 삭제를 유예한다. 다른 기기의 구버전 데이터가 먼저 내려오면 조회 성공까지 잠시 보일 수 있고 이후 읽기·저장 경계에서 제거된다. 오프라인·조회 실패 상태를 임의 삭제로 해결하지 않는다.
- 배포 결과 문서는 `[skip ci]` 커밋으로 공통 잠금 아래 로컬 main에 후속 통합해 추가 앱 버전을 만들지 않는다.
