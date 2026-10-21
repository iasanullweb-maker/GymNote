---
name: 헬스노트 (GymNote)
description: 세트 사이 한 번의 탭으로 기록하고, 기록을 깨는 순간을 분명히 알려 주는 iPad·iPhone 운동 기록 앱
colors:
  workout-orange: "#FF9500"
  daily-teal: "#30B0C7"
  done-green: "#34C759"
  alert-red: "#FF3B30"
  grouped-background: "#F2F2F7"
  grouped-surface: "#FFFFFF"
  label: "#000000"
  secondary-label: "#3C3C4399"
typography:
  large-title:
    fontFamily: "SF Pro (system, Dynamic Type .largeTitle)"
    fontSize: "34pt"
    fontWeight: 700
  title:
    fontFamily: "SF Pro (system, Dynamic Type .title / .title2)"
    fontSize: "28pt / 22pt"
    fontWeight: 600
  headline:
    fontFamily: "SF Pro (system, Dynamic Type .headline)"
    fontSize: "17pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system, Dynamic Type .body)"
    fontSize: "17pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (system, Dynamic Type .footnote / .caption)"
    fontSize: "13pt / 12pt"
    fontWeight: 400
  numeric:
    fontFamily: "SF Pro monospacedDigit"
    fontSize: "follows its text style"
    fontFeature: "tnum"
rounded:
  control: "8pt"
  card: "12pt"
  panel: "16pt"
  switcher-item: "17pt"
  switcher: "22pt"
  hero: "24pt"
  status-card: "28pt"
spacing:
  xxs: "2pt"
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "24pt"
components:
  button-primary:
    backgroundColor: "{colors.workout-orange}"
    textColor: "{colors.label}"
    height: "56pt"
  button-start-bar:
    backgroundColor: "{colors.workout-orange}"
    height: "52pt"
  button-stepper:
    rounded: "{rounded.card}"
    width: "52pt"
    height: "56pt"
  status-card:
    rounded: "{rounded.status-card}"
    padding: "16pt"
  panel:
    backgroundColor: "{colors.grouped-surface}"
    rounded: "{rounded.panel}"
    padding: "16pt"
  workspace-switcher:
    rounded: "{rounded.switcher}"
  workspace-switcher-item-selected:
    rounded: "{rounded.switcher-item}"
---

# Design System: 헬스노트 (GymNote)

<!-- 이 파일은 /impeccable document(scan mode)로 2026-10-21 기존 SwiftUI 코드에서 추출했다. 색 값은 iOS 시스템 색의 라이트 모드 기준값이며, 코드에서는 항상 시스템 색 이름(.orange 등)을 쓴다. -->

## Overview

**Creative North Star: "기록을 깨는 코치"**

헬스노트는 옆에서 세트를 세어 주는 코치처럼 행동한다. 평소에는 iOS 기본 목록과 컨트롤 뒤로 조용히 물러나 있고, 사용자가 해야 할 바로 그 한 가지(다음 세트, 휴식, 완료)만 주황으로 크게 밝힌다. 기록을 깨거나 루틴을 끝낸 순간에는 숨기지 않고 확실하게 알려 준다. 동기 부여는 화려한 장식이 아니라 숫자와 정확한 피드백에서 나온다.

화면은 Apple의 HIG를 그대로 따른다. 탭 바, 내비게이션 스택, 그룹 목록, 시트, SF Symbols가 구조를 맡고, 브랜드는 tint 색, 숫자 타이포, 상태 카드, 짧은 완료 애니메이션으로만 드러난다. 아이패드는 세워 두고 멀리서 보고, 아이폰은 땀 난 손으로 누르기 때문에 운동 화면의 핵심 버튼은 시스템 기본보다 크게 만든다.

**Key Characteristics:**
- iOS 기본 컨트롤·그룹 목록 위주, 직접 만든 컨트롤은 운동 실행 화면에만
- 작업 공간별 단일 포인트 색: 운동 = 주황, 일상 = 청록
- 운동 중 핵심 버튼 52–56pt 높이
- 숫자(횟수·시간·기록)는 고정폭 숫자로 흔들리지 않게
- 성취 순간(세트 완료, 운동 저장, 최고 기록)에만 분명한 피드백

## Colors

시스템 색만 쓰는 절제된 팔레트이며, 색은 "어느 작업 공간인가"와 "상태가 무엇인가"를 알려 주는 데만 쓴다.

### Primary
- **Workout Orange** (`.orange`, workout-orange): 앱 전체 tint와 운동 작업 공간의 색. 시작 바, 세트 완료 버튼, 휴식 중 상태 카드 아이콘, 진행 강조. 주황 배경 위 글씨는 검정(`.black`)으로 대비를 확보한다.

### Secondary
- **Daily Teal** (`.teal`, daily-teal): 일상(할 일·습관) 작업 공간 전용. 일상 진행 막대, 완료 체크, 캘린더의 일상 개수 표시. 운동 화면에는 쓰지 않는다.

### Tertiary
- **Done Green** (`.green`, done-green): "끝났다"는 상태 전용. 휴식이 끝나 다음 세트를 할 때의 상태 카드 테두리·아이콘.
- **Alert Red** (`.red`, alert-red): 저장 실패, 삭제 같은 파괴적 동작, 오류 문구만.

### Neutral
- **Grouped Background** (`Color(.systemGroupedBackground)`): 화면 바탕.
- **Grouped Surface** (`Color(.secondarySystemGroupedBackground)`): 로그인·친구 화면의 패널 바탕.
- **Label / Secondary Label** (`.primary` / `.secondary`): 본문과 보조 정보. 보조 정보(`.secondary`)가 가장 많이 쓰이는 전경색이다.
- **Materials** (`.regularMaterial`, `.thinMaterial`): 떠 있는 상태 카드와 하단 바.

### Named Rules
**The One Workspace, One Color Rule.** 한 화면에는 그 작업 공간의 포인트 색 하나만 쓴다. 운동 화면에 청록, 일상 화면에 주황을 섞지 않는다.

**The Semantic Only Rule.** 색은 시스템 색 이름으로만 지정한다. hex 직접 지정은 다크 모드·고대비에서 깨지므로 쓰지 않는다.

**The Spotlight Rule.** 주황 채움(배경)은 화면에서 지금 누를 단 하나의 동작에만 쓴다. 나머지는 테두리(`.bordered`)나 글자색으로 낮춘다.

## Typography

**Display Font:** SF Pro (시스템 폰트)
**Body Font:** SF Pro (시스템 폰트)
**Label/Mono Font:** SF Pro의 `monospacedDigit()` 변형

**Character:** 모든 글자는 시스템 텍스트 스타일을 따르고, 숫자만 고정폭으로 바꿔 타이머와 횟수가 바뀔 때 레이아웃이 흔들리지 않게 한다.

### Hierarchy
- **Large Title** (bold, 34pt): 최상위 화면 제목.
- **Title / Title2 / Title3** (semibold–bold, 28/22/20pt): 운동 이름, 상태 카드의 큰 숫자, 섹션 대표 값.
- **Headline** (semibold, 17pt): 목록 행 제목, 카드 제목. compact 레이아웃에서 title을 대신한다.
- **Body / Callout / Subheadline** (regular, 17/16/15pt): 설명, 입력값.
- **Footnote / Caption / Caption2** (regular, 13/12/11pt): 보조 정보, 세트 상세, 진단. 앱에서 가장 많이 쓰는 크기대이며 11pt 아래로 내려가지 않는다.

### Named Rules
**The Dynamic Type Rule.** 새 코드는 `.font(.headline)`처럼 텍스트 스타일만 쓴다. `.system(size:)` 고정 크기는 기존 코드에 일부 남아 있지만(달력 셀 등) 새로 추가하지 않는다.

**The Steady Numbers Rule.** 바뀌는 숫자(타이머, 횟수, 기록)에는 `.monospacedDigit()`를 붙인다.

## Layout

- 탭 바(실행·계획·기록·친구·설정) + 각 탭의 `NavigationStack`이 기본 구조다. 운동/일상 전환은 상단의 큰 두 칸 전환 버튼이 맡는다.
- 아이패드와 아이폰은 한 앱이 폭으로 적응한다. 폭 600pt 미만이면 `gymnoteCompactLayout`이 켜지고, 큰 제목을 headline으로 줄이고 여백을 좁힌다(예: 패딩 16pt → 10pt).
- 간격은 4pt 배수 리듬(2·4·8·12·16·24pt)을 쓰고, 행 안 요소 간격은 대부분 8–12pt, 카드 안쪽 여백은 16pt다.
- 설정·기록처럼 정보가 많은 화면은 그룹 목록(`List`/`Form`)을 쓴다.

## Elevation & Depth

기본은 평평한 그룹 목록이다. 깊이는 운동 중 "지금 상태"를 알려 주는 떠 있는 상태 카드에만 쓴다: 시스템 머티리얼 배경 + 옅은 그림자 + 상태 색 테두리.

### Shadow Vocabulary
- **Status Float** (`.shadow(color: .black.opacity(0.12), radius: 10, y: 4)`): 운동 중·휴식 상태 카드 전용.

### Named Rules
**The Flat By Default Rule.** 목록·패널·버튼에는 그림자를 넣지 않는다. 그림자는 화면 위에 떠서 상태를 알리는 카드에만 쓴다.

## Shapes

모서리는 모두 둥글고, 큰 요소일수록 반경이 커진다. 큰 카드는 `style: .continuous`(애플식 연속 곡률)를 쓴다.

- 작은 컨트롤 8pt → 세트 버튼·카드 12pt → 패널 16pt → 전환 버튼 항목 17pt / 전체 22pt → 로그인·친구 히어로 24pt → 상태 카드 28pt.
- 패널 테두리는 `.primary.opacity(0.08–0.1)` 1pt 선으로 아주 옅게.

## Components

### Buttons
- **Shape:** 시스템 버튼 스타일 기본 모양. 직접 만든 큰 버튼은 12pt 반경.
- **Primary:** `.borderedProminent` + 주황 tint. 실행 화면의 세트 완료 버튼은 주황 배경·검정 글씨·높이 56pt, 긴 글씨는 줄바꿈.
- **Secondary:** `.bordered`. 목록 안 보조 동작은 `.borderless`.
- **Disabled:** 할 수 없는 동작은 숨기지 않고 회색으로 비활성(시작·불러오기 버튼).

### Cards / Containers
- **Corner Style:** 패널 16pt, 상태 카드 28pt continuous.
- **Background:** 패널은 Grouped Surface, 상태 카드는 `.regularMaterial`.
- **Shadow Strategy:** 상태 카드만 Status Float.
- **Border:** 상태 카드는 상태 색 40% 투명도 1pt, 패널은 primary 8–10%.
- **Internal Padding:** 16pt (compact 10pt).

### Inputs / Fields
- **Style:** 시스템 `TextField`, `Stepper`, `Picker`, `DatePicker`를 그대로 쓴다.
- **Error:** 필드 아래 빨간 문구 "저장하지 못했어요. 입력 내용은 남아 있으니 다시 시도해 주세요." 형식. 입력은 지우지 않는다.

### Navigation
- **Style:** 시스템 `TabView` 탭 바와 SF Symbols(`checkmark.circle`, `calendar`, `chart.bar`, `person.2`, `gearshape`). 편집 중 이탈은 `EditingNavigationGuard`가 막는다.

### Workout Controls (signature)
- **시작 바:** 높이 52pt, 운동 시작 후 같은 자리에서 "운동 중" 표시로 바뀐다.
- **세트 횟수 −/+:** 굵은 아이콘 24pt, 독립 테두리 버튼 52×56pt. 가운데 완료 버튼과 붙지 않게 분리.
- **순서 바꾸기:** 시스템 `List.onMove`. 완료한 운동은 아래로 모이고, 완료 취소 시 원래 자리로 돌아간다.

### Short Swipe Delete (signature)
- 목록 행을 왼쪽으로 짧게 밀어 삭제한다(`App/ShortSwipeAction.swift`). 시스템 `swipeActions`는 넓은 iPad 행에서 끝까지 밀어야 해서, 사용자 요청으로 화면 폭과 무관한 고정 거리(36pt 열기 · 120pt 바로 실행)를 쓰는 예외 컴포넌트다.
- 행 글자는 제자리에 두고, 오른쪽에서 둥근 빨간 버튼(12pt continuous, 위아래 6pt·오른쪽 8pt 여백)이 밀린 거리만큼 자라며 덮는다. 버튼 왼쪽 16pt는 행 배경색으로 부드럽게 사라진다. 버튼이 좁으면 휴지통 아이콘만 보인다.
- 행 여백(위아래 11pt, 좌우 20pt)은 이 컴포넌트가 직접 그린다. 편집 모드에서는 왼쪽 빨간 빼기 버튼으로 바뀐다.

### Status Card (signature)
- 탭 공통으로 떠 있는 운동 중 / 휴식 중 / 휴식 끝 카드. 머티리얼 + 28pt continuous + Status Float. 휴식 중은 주황, 휴식 끝은 초록. 타이머는 `Text(timerInterval:)` 고정폭 숫자.

### Workspace Switcher (signature)
- 운동(주황)·일상(청록) 두 칸. 바탕 `secondary 8%` 22pt, 선택 칸은 해당 색 12% 채움 + 17pt.

## Do's and Don'ts

### Do:
- **Do** iOS 기본 컨트롤(`Toggle`, `Stepper`, `Picker`, 스와이프 동작, 컨텍스트 메뉴, 시트)을 먼저 쓴다.
- **Do** 운동 중 누르는 버튼은 52pt 이상, 그 밖의 모든 터치 영역은 44×44pt 이상으로 만든다.
- **Do** 세트 완료·운동 저장·최고 기록 갱신 순간에는 짧고 분명한 피드백(아이콘 전환, 상태 문구, 0.2–0.3초 애니메이션)을 준다. 저장이 실제로 끝난 뒤에만 "저장됨"을 보여 준다.
- **Do** 아이패드(834pt)와 아이폰(compact, 600pt 미만) 폭에서 모두 확인한다.
- **Do** 동작을 줄이기 설정(Reduce Motion)에서는 이동 애니메이션 대신 페이드로 바꾼다.

### Don't:
- **Don't** hex 색이나 커스텀 그라데이션을 쓰지 않는다. 시스템 색과 머티리얼만 쓴다.
- **Don't** 한 화면에 운동 주황과 일상 청록을 함께 쓰지 않는다.
- **Don't** 탭 바·뒤로 가기 제스처·시스템 컨트롤을 직접 다시 만들지 않는다. (예외: 위의 Short Swipe Delete)
- **Don't** `.system(size:)` 고정 글자 크기를 새로 추가하지 않는다.
- **Don't** 목록·패널·버튼에 그림자를 넣지 않는다.
- **Don't** 자주 누르는 동작(세트 체크, −/+)에 긴 애니메이션을 넣지 않는다. 하루 수십 번 누르는 동작은 즉각 반응이 우선이다.

### 날짜 계획 편집 (2026-10-21)

- ‘계획한 운동’은 현재 내용을 보여 주고, ‘운동 추가’에 종목 선택·기본 루틴을 모은다. 추가는 기존 운동 뒤에 붙이며, 전체 교체는 별도의 ‘계획 교체’ 구역으로 분리한다.
- 휴식/빈 계획과 같은 날짜는 비활성으로 표시하고 이유를 행 안에 항상 적는다. 교체는 원본/대상 날짜·제목·운동 목록/개수를 확인하는 시트를 거친다. 원본 계획과 이미 저장한 일지는 변경하지 않는다.
- 이름은 별도 시트에서 저장/취소한다. 실패하면 입력을 남긴다. 새 휴식일의 첫 운동 추가는 그 운동 이름을 기본 이름으로 쓰고, 빈 이름은 운동 이름 요약을 보여 준다. 사용자가 저장한 기존 제목은 마이그레이션하거나 자동 덮어쓰지 않는다.
- 운동 행에는 ›를 표시하고 ‘순서 편집 / 완료’로 순서 조작을 구분한다. 삭제 성공 후 ‘삭제 되돌리기’를 제공하며 자동으로 사라지지 않는다. 같은 날짜의 후속 변경이 있으면 오래된 복원을 막는다.
- 지난 날짜 계획은 수정할 수 있지만 저장된 운동 기록은 바뀌지 않는다고 알린다. 진행 중인 날짜의 계획 변경은 운동이 끝날 때까지 비활성이다.
- 횟수는 숫자 키보드 직접 입력과 시스템 Stepper를 함께 제공한다. 1~9999 정수만 저장하고 잘못된 입력은 필드 가까이에 설명한다. 세트별 횟수에도 같은 규칙을 적용하며 신디 고정 구성은 유지한다.
