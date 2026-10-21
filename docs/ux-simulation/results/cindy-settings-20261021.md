# 신디 전용 운동 설정 (2026-10-21)

- 요청: 신디에만 목표 세트 수와 1세트 구성을 분리한다. 반복 횟수 설명을 중복하지 않고 다른 운동 설정은 유지한다.
- 기준 main `5599bdc`, 제품 소스 `4a3e905`. 담당 `App/RoutineView.swift`의 ExerciseDraftForm만 변경.
- 신디 이름은 기존 AppData.exerciseKey로 정규화해 판별한다(현재 Exercise는 종목 ID 없이 이름으로 카탈로그와 연결). 다른 rounds 종목으로 확대하지 않는다.
- 신디 화면 제목은 ‘신디 설정’, 조절값은 ‘목표 세트 수’ + N세트(기존 Stepper 1...20), 별도 시스템 Form Section ‘1세트 구성’에는 풀업 5회·푸쉬업 10회·에어 스쿼트 15회를 표시한다. ‘한 세트’ 텍스트 입력은 표시하지 않는다. 일반 운동 폼은 기존 코드를 else로 옮긴 것뿐이다.
- 기존 exercise.detail·계획·일지·ID와 저장 콜백을 보존한다. 기존 20분 AMRAP 등 사용자 조건도 저장값은 보존하되 신디 설정에서 표시·편집하지 않는다. 공유 폼을 쓰는 날짜 계획의 추가·수정과 내 운동 목록의 신디에 적용된다.
- 검증: 제품 diff 수동 검토(일반 분기·저장/취소·1...20 범위 유지), git diff --check 통과. 번들 Python + 기존 .validation-tools/swift-parser의 tree_sitter_swift로 RoutineView.swift 전체 파싱 오류 0. 모델/서버/동기화 변경 없음.
- 미실행: Windows에 Swift/Xcode 없음. SwiftUI 타입 검사·XCTest·앱/위젯 Release 전체 빌드·시뮬레이터 캡처·실기기·큰 Dynamic Type·VoiceOver는 미실행. 구문 검사로 컴파일/가독성 검증을 대체하지 않는다. 다음 묶음 통합 검증 또는 배포 전에 전체 검사·Release와 iPhone/iPad 캡처 확인 필요.
- 본인 변경만 커밋하고 기존 main에 공통 잠금·상태 재확인·fast-forward 조건으로 로컬 통합한다. 최종 커밋·통합 여부는 완료 응답에서 확인한다. push·Actions·배포·운영 변경 없음.
