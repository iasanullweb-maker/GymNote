# Windows USB 화면 뷰어

실제 iPad 관찰용 로컬 어댑터다. 제품 Swift 코드나 가상 사용자 실행기는 아니다. Mac/Xcode는 필요하지 않으며, 기존 `.validation-tools/ipad-usb/python312`의 pymobiledevice3 **11.26.0** 환경을 사용한다. 다른 버전·예상과 다른 상류 소스에서는 시작을 거부한다. 설치 라이브러리는 수정하지 않는다.

저장소 루트에서 실행한다.

```powershell
.\.validation-tools\ipad-usb\python312\python.exe scripts/ux_simulation_usb_viewer.py
```

- iPad를 USB 연결하고 직접 잠금 해제한 뒤 GymNote를 연다. 신뢰·개발자 모드 승인은 사용자가 직접 처리한다.
- 노트북 Chrome에서 `http://127.0.0.1:8766/`를 연다. 기존 서버가 같은 포트를 사용하면 본인 서버만 종료한 뒤 실행한다.
- 바인딩은 `127.0.0.1:8766`으로 고정한다. CLI 인수는 받지 않는다. 클립보드 HTTP 경로와 오디오 접근을 차단하고 기기 오디오 스트림도 생성하지 않는다.
- 첫 실행·어댑터 변경 후 페이지를 한 번 새로고침한다. 종료는 서버 실행 터미널의 Ctrl+C. 실행기는 선택한 USB 기기를 새 worker에서도 유지하며, 닫힌 터널은 기존 서버 정리 후 새 프로세스에서 다시 만든다. 재시도 상한에 도달했거나 기기가 다시 연결되지 않으면 USB 연결·잠금 해제 후 수동으로 다시 실행한다.
- 화면에는 보이는 내용이 포함된다. GymNote 테스트 데이터만 표시하고 개인 앱·인증 화면이 보이면 자동 관찰과 입력을 멈춘다. 다른 PC 프로세스의 로컬 접근까지 막는 인증 서버는 아니다.

## PC 앱 전환 처리

뷰어가 숨겨져 있거나 포커스를 잃으면 **프런트엔드의** 오프라인 자동 복구를 보류한다. 복귀하면 카운터를 초기화하고 5초 복구 시간을 준다. 닫힌 디코더는 재생성하고 키프레임을 한 번 요청한다. HTTP 스트림이 끝났거나 읽기가 실패했다면 페이지를 다시 연결한다. 실제 전면 영상 장애의 기존 복구는 유지한다.

기기→PC 패킷 중단에 대한 상류 서버 watchdog은 유지한다. 이 어댑터가 USB·OS·인코더 장애까지 해결했다고 판단하지 않는다. PC에서 다른 앱을 10초/30초 열었다가 돌아오는 실제 검증과 장기간 안정성 확인은 별도로 수행한다.

## 2026-10-10: 터널 복구·재시작 조율·카운터

`viewer_recovery.py`는 설치 파일을 수정하지 않고 실행 중 클래스에 적용된다.

- 정확한 `userspace dial plane is closed` 오류와 cause/context, 상류의 기존 터널 단절 분류를 사용한다. 영상만 반복 재시작하지 않고 worker를 종료한 뒤 동일 기기로 새 터널을 만든다. 시작 시 USB 기기가 정확히 1대여야 하며, 여러 기기는 기존 `PYMOBILEDEVICE3_UDID`로 지정한다. 기기 식별자는 보고서나 로그에 추가하지 않는다.
- 모든 스트림 시작 경로는 진행 중 작업을 공유한다. 12초 제한·15초 cooldown을 적용하고 서비스가 없는 상태에서 실패가 연속 3회면 자동 재시작을 멈춘다. 기존 watchdog가 서비스 없음으로 중단하는 경로는 별도 카운터 monitor가 구독자가 있을 때만 재시도한다.
- worker 교체는 5분 안에 최대 3회, 대기 2/5/10초다. 기기 없음·무관한 시작 오류·Ctrl+C는 자동 worker 재시작 대상이 아니다.
- 브라우저의 스트림 종료·읽기 오류·초기 연결 실패는 5/15/30초 간격으로 최대 3회 재접속한다. 중복 종료 이벤트는 하나로 합친다. 디코더 출력 300개 이상과 페이지 실행 60초 이상이 함께 충족되면 한도를 회복한다.
- `/gymnote/health`와 콘솔 `USB_COUNTERS`는 worker PID·스트림 세대·RTP 수신·정상 AU·gap/reorder/corrupt·HTTP 전달·구독자 대기·복구 상태만 제공한다. 페이지 아래 진단에는 브라우저 수신 bytes/messages·디코더 출력·실제 그리기도 분리해 표시한다. 영상·음성·클립보드·HID 요청 내용은 진단에 저장하지 않는다.

카운터를 읽을 때 worker PID 또는 generation이 달라지면 RTP 누적치의 감소를 패킷 손실로 해석하지 않는다. HTTP 전달은 모든 구독자의 합계이며, 디코더 출력은 실제 canvas 그리기와 별개다. 이 변경은 복구 경로 개선이며 최초 패킷 중단 원인이나 실기기 안정화가 입증됐다는 뜻은 아니다.

기기 연결 전 검사는 다음으로 실행한다. Python은 원본 폴더의 번들 런타임을 사용할 수 있다.

```powershell
.\.validation-tools\ipad-usb\python312\python.exe simulation/usb/test_viewer_recovery.py
.\.validation-tools\ipad-usb\python312\python.exe simulation/usb/test_viewer_adapter.py
```

`test_viewer_reconnect.mjs`는 `runTests(<전체 패치 JS 경로>)`로 브라우저 재접속 중복·재시도 한도를 검사한다. 전체 패치 JS는 설치된 `VIEWER_JS_TEMPLATE`에 `install_patches`를 적용해 Git 제외 경로에 내보내고 Node `--check`도 실행한다. 기존 lifecycle·coordinates 검사와 함께 실행한다.

실기기 검증은 iPad USB 연결·잠금 해제·GymNote 전면 상태에서 시작한다. 처음에는 뷰어 하나만 열고 전면 유지 3분, PC 앱 전환 10초/30초, 복귀 후 3분의 카운터를 비교한다. 전송이 안정적인 후보로 10분 반복하고 실제 탭 이동 반영도 확인한다. 강제 USB 분리나 앱 데이터 변경 없이 자연 중단의 복구부터 확인한다. 실제 기기 미연결 시 해당 검증을 완료로 처리하지 않는다.

## 검사

```powershell
.\.validation-tools\ipad-usb\python312\python.exe simulation/usb/test_viewer_adapter.py
node --input-type=module -e "import('./simulation/usb/test_viewer_lifecycle.mjs').then(m => console.log(m.runTests()))"
node --input-type=module -e "import('./simulation/usb/test_viewer_coordinates.mjs').then(m => console.log(m.runTests()))"
```

Python 검사는 기기 연결 없이 GET/POST 개인정보 경로 8개, 오디오 생성 차단, 변경된 상류 거부를 확인한다. Node 검사는 PC 앱 전환·숨긴 탭·복귀 유예·중복 이벤트·반복 복귀를 확인한다. 패치된 전체 JS 문법 검사와 실제 서버 경로 확인도 통합 시 수행한다. 현재 로컬 PATH에는 Node가 없어 연결된 Node 실행기로 JS 검사를 수행했다.

## 클릭·스크롤 좌표 조사

사용자는 PC 입력이 전달되지만 위치가 어긋난다고 보고했다. 현재 입력 실패만으로 HID 권한 문제라고 단정하지 않는다.

- [agent-device 실제 iPad 보고 #1511](https://github.com/callstack/agent-device/issues/1511): 가로 UI의 접근성 위치는 회전하지만 터치는 세로 좌표로 주입된 사례. 세로에서는 같은 조작이 작동했다. 현재 pymobiledevice3와는 다른 입력 경로다.
- [sim-use 스크롤 보고 #66](https://github.com/lycorp-jp/sim-use/issues/66): 가로 모드에서 스크롤·좌표 제스처의 축이 화면과 90도 달랐던 사례. 현재 기기의 동일 원인을 입증하는 자료는 아니다.
- [상류 HID 설명](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/cli-recipes.md): 좌표는 화면 전체의 0~65535 정규화 값이다. 현재 뷰어는 canvas의 CSS 크기와 내부 크기를 환산하고 `visualRotation`을 역회전한다. 따라서 무조건 브라우저 배율을 곱하거나 상수 오프셋을 더하지 않는다.

검증 순서는 세로에서 기록을 변경하지 않는 탭 클릭 → 가로 양방향에서 같은 탭 → 화면 배율 변경 후 같은 탭 → 목록 스크롤 방향 비교다. 브라우저 배율 100%는 첫 비교 조건일 뿐 원인 해결로 보지 않는다. PC 포인터·영상의 위치·실제 선택된 탭을 함께 기록한다. 일정한 평행 이동이면 여백/좌표 원점, 배율에 따라 오차가 커지면 CSS/픽셀 환산, 90도 또는 축 반전이면 기기 기준 좌표 변환을 조사한다. 세로/가로의 비대칭 지점을 확인한 뒤 정규화 좌표의 회전·축 반전 보정을 적용한다.

## 터치 좌표 보정

처음 모서리 설명으로 90°를 추정했지만 실제 클릭 위치와 좌우 드래그가 맞지 않았다. 사용자가 270° 선택 후 **보이는 그대로 입력됨**을 확인했다. 정규화 영상 좌표 `(x,y)`를 세로 HID 좌표 `(1-y,x)`로 변환한다. 클릭·드래그·스와이프 버튼에 동일하게 적용한다. 기존 영상 회전 역변환 이후에 보정하므로 CSS 배율이나 픽셀 비율을 별도로 곱하지 않는다.

페이지 위의 **터치 좌표** 기본값은 `자동 (확인된 가로 방향 270°)`다. 원본 영상이 세로이면 보정하지 않는다. 반대로 가로를 돌렸다면 `반대 가로 90°`, 거꾸로 세로면 `뒤집힌 세로 180°`, 이미 입력이 맞는 환경이면 `보정 없음 / 세로`를 선택한다. 자동은 영상 종횡비와 이번에 확인한 방향을 사용하며 기기의 양쪽 가로 방향을 감지하지 않는다. 새로고침하면 기본값으로 돌아간다.

좌표 검사는 모서리·중심·드래그 축·CSS 배율·세로/반대 가로·영상 회전·경계 제한을 확인한다. 적용 후 실제 GymNote의 기록을 바꾸지 않는 탭 클릭과 목록 드래그로 검증한다. 전체 iOS 빌드와 가상 사용자 실험은 수행하지 않았다.
