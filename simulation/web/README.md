# Windows 웹 가상 환경

Mac/Xcode 없이 실행하는 **행동 프로토타입**이다. 제품 Swift View·파일 저장소·네트워크와 연결되지 않는다. 화면 10개의 의미와 C의 사용자 4개·시나리오 5개를 재사용하되, 실제 앱의 화면 충실도나 사용성 성공을 증명하지 않는다.

## 실행

저장소 루트에서 Node 24 이상을 사용한다. 의존성 설치·서버·API 키는 필요 없다.

```powershell
node simulation/web/build.mjs preview web-preview-001
node simulation/web/tests.mjs
node simulation/web/test-ui.mjs
node simulation/web/build.mjs batch web-batch-001
```

생성된 `simulation/runs/web-preview-001/index.html`을 Chrome/Edge에서 직접 연다. 이미 있는 출력 폴더는 덮어쓰지 않으므로 다시 생성할 때 새 이름을 지정한다. Node가 없는 PC에서는 이미 생성된 HTML을 열어 사용할 수 있다. 실행 파일·결과는 Git에서 무시되며 재생성 가능하다.

## 역할과 흐름

1. **사용자 역할**: 사용자·시나리오를 선택하고 새 세션을 시작한다. 목표를 읽고 화면을 직접 조작한다. 10개 화면은 운동/계획/기록/일지/친구 분야로 연결된다. 실제 횟수와 계획 값은 분리되고, 편집은 저장 전까지 draft에만 남는다.
2. **기획자 역할**: 종료 후 상태 검사와 조작 근거를 검토하고 관찰·개선안·재검증 방법을 적는다. JSON 내보내기로 상태 전후, 이벤트, 메모, 입력/소스 해시를 보관한다. 자동 생성된 사용자 의견이나 개선안은 없다.
3. **재생 검사**: batch는 공개된 고정 스크립트로 4×5×3=60세션을 재생한다. 사용자 특성에 따라 행동을 추론하는 AI가 아니다. 동일 반복은 안정성 검사이며 행동 다양성·사용성 성공률로 해석하지 않는다.

`userPacket()`은 persona·userGoal·현재 표시 상태만 전달한다. checks·미래 화면·저장소·스크립트는 포함하지 않는다. 브라우저 소스 자체에는 평가 코드가 있으므로 이 화면은 비밀 평가 서버가 아니다. 후속 모델 어댑터는 이 packet만 허용하고 평가자 자료와 분리해야 한다. 현재 packet은 화면 이미지가 아닌 표시 데이터이며 live 모델 호출/자동화 어댑터는 미구현이다.

## 재현성과 결과

- 기준 날짜/시각은 demo-v1, 2026-10-12 09:00 서울. 타이머는 버튼으로 가상 시간을 이동하며 시스템 시계는 사용하지 않는다.
- 세션마다 새 메모리 사본. 합성 친구 요청은 미수락, 공개 해제는 공개 행 제거와 개인 백업 보존으로 재현한다. 운영 계정·DB·알림·localStorage는 사용하지 않는다. 페이지 새로고침 전 JSON을 내보내야 한다.
- 결과는 별도 `webFormat:1`, `environment:web-prototype`이며 `prototypeResult`와 `nativeResult`를 분리한다. 기존 네이티브 session v1의 mode를 임의 확장하지 않는다.
- observation-only/manual은 항상 not-evaluated. 웹 app-state만 이벤트·before/after로 판정한다. iOS 결과는 항상 not-evaluated이고 모델 요청은 0이다.
- batch의 `native-not-run.json`은 D의 `buildDryRunSession()`으로 만들고 A의 검증기로 검사한 미실행 세션이다. B의 pending manifest를 captured로 변경하지 않는다.
- CSP는 외부 네트워크를 차단하고 데이터 문자열은 DOM textContent로 표시한다. 입력은 합성 데이터만 사용한다.

## 제품 검증과 연결 경계

이 프로토타입은 RootView·SwiftUI 접근성·실제 친구 권한·저장 실패·탭 상태의 구현을 재현하지 않는다. 웹에서 찾은 개선안은 별도 제품 변경과 검증이 필요하다. Mac/Xcode를 사용할 수 없으므로 실제 iOS 캡처·Swift 컴파일·전체 iOS 빌드는 보류 상태다. 원격 CI·배포·유료 모델 호출은 이 도구를 만든 것만으로 실행되지 않는다.
