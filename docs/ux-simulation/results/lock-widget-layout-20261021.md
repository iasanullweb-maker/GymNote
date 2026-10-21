# 잠금 화면 운동 위젯 배치 수정

2026-10-21, 기준 main `6747efd1ead72622ef6d1e9c68b161b70c86587e`.
작업 브랜치 `codex/lock-widget-layout-20261021`, 기존 작업 브랜치/통합 대상 main.

## 관찰과 원인 범위

사용자 첨부에는 제목·운동 목록과 최고 기록 사이에 큰 빈 공간이 있다.
이 화면의 문구와 기록 표시는 accessoryRectangular가 아니라 systemSmall 구성과 일치한다.
`Widget/GymWidget.swift`의 small은 제목/운동 목록 뒤 세로 Spacer, 기록 이름/값 사이 가로 Spacer를 사용했다.
컨테이너의 여유 공간이 커질수록 콘텐츠가 벌어지는 구조다. Windows에서 해당 기기/OS의 실제 WidgetKit 제안 크기는 재현하지 못했다.

## 변경

- 작은 위젯 내부의 두 Spacer를 제거하고 콘텐츠 묶음을 topLeading에 정렬했다.
- 기록 이름과 값을 한 줄에 모으고 기존 recordValue의 세트/하루 설명을 재사용한다. 접근성 설명도 유지한다.
- 시스템 위젯 영역 크기, 저장/최고 기록 계산, 다른 위젯 family, Live Activity는 변경하지 않는다.

## 검증

- Windows, 수정된 GymWidget.swift: tree-sitter 0.26.0 + tree-sitter-swift 0.7.4 구문 검사 오류 0.
- diff 검토 및 `git diff --check` 통과. 기존 줄 수 제한·축소 비율·접근성 설명과 상단 정렬 확인.
- 전체 iOS/XCTest·앱/위젯 Release·실제 렌더 미실행: Swift/Xcode 없음. 작은 UI 검사 유예 규칙 적용. 웹 모사나 이전 CI를 검증 근거로 사용하지 않았다.
- 회귀 확인: 기록 0/1/3개, 긴 운동 이름/계획 제목, 휴식일, 큰 글자, iPad 세로/가로 잠금 화면 및 홈 화면. 실제 화면에서 제목/기록 사이 유동 간격이 없고 잘림 없이 보이는지 확인할 것.

## 인계

본인 변경만 커밋 후 기준 main을 다시 확인하고 공통 잠금 아래 fast-forward 통합한다.
원격 push·배포 없음. 기술 검증/사용자 확인은 TODOLIST_HANDOFF의 미완료 항목으로 남긴다.
