# USB 연결 끊김 해결 방안 조사

2026-10-10. 사용자 최우선 요청에 따른 조사이며 제품·라이브러리·기기 설정 변경은 하지 않았다. 조사 코드 기준은 main `0a8f53f`, UX 총괄 `6ed00cf`다. 두 브랜치의 USB 어댑터는 동일하다.

## 기존 증거와 이번 확인

- 이전 45초 비브라우저 수신 검사에서 2,037개 프레임 메시지와 서버 AU 중단 재시작 1회가 기록됐다. PC 포커스 처리만으로 해결할 수 있다는 근거는 없다.
- 이전 연결 복구 때 `userspace dial plane is closed`가 관찰됐고 새 서버/터널에서 영상 수신이 복구됐다. 이는 새 터널 복구의 근거이며 최초 중단 원인을 특정하지 않는다.
- 이전 RCTL 활성화·비트레이트 제한·motion IDR 비활성화에서도 중단이 남았다. 현재 어댑터는 RCTL 기본 비활성화, `--no-motion-idr`다. 같은 옵션을 다시 켜고 해결됐다고 주장하지 않는다.
- 이번 조회 시 127.0.0.1:8766 리스너는 없었다. 실제 화면 수집·입력·실시간 연결 비교는 수행하지 않았다. 기기 연결 여부까지 확인한 것은 아니다.

기존 상세 기록: [Windows USB 검증](windows-usb-ipad-validation.md), [첫 파일럿](subagent-pilot.md).

## 우선순위 1: 끊어진 userspace 터널의 복구 누락

설치된 pymobiledevice3 11.26.0에서 `userspace_tunnel.py`의 dial은 터널이 닫혔을 때 errno 없는 `ConnectionError('userspace dial plane is closed')`를 발생시킨다. 그러나 `screen_stream.py`의 `_is_tunnel_dead_error`는 해당 오류를 인식하지 않는다. 기기 연결 없는 직접 호출에서 다음을 재현했다.

| 입력 | 실제 분류 |
|---|---|
| 닫힌 userspace의 ConnectionError | False |
| 위 오류를 cause로 가진 RuntimeError | False |
| ConnectionResetError 대조군 | True |
| 무관한 ValueError 대조군 | False |

watchdog는 True인 오류만 `_reconnect_signal`로 전달한다. 또한 `_ensure_fresh_stream`은 기존 스트림을 정리한 후 새 DisplayService에 연결하며, watchdog는 `_active_service is None`이면 검사하지 않는다. 재시작 중 연결 실패로 서비스가 없는 상태가 남으면 해당 watchdog만으로 재시도가 이어지지 않을 수 있다. 이는 코드상 복구 공백이며 이번 실기기 재현은 아니다.

제안: 정확한 closed-userspace 오류와 cause/context 경로를 인식하되 모든 ConnectionError를 무조건 같은 오류로 취급하지 않는다. **분류 수정만으로 끝내지 않는다.** 기존 reconnect loop는 tunneld에서 동일 기기를 다시 찾는 방식이다. 실제 CLI가 in-process userspace 터널을 사용한다면 이 터널의 소유 수명과 재생성 경로도 마련해야 한다. 기존 닫힌 RSD로 영상만 반복 재시작해서는 복구되지 않는다. fresh RSD 획득·서비스 재부착·브라우저 프레임 재개까지 검증한다.

## 우선순위 2: 브라우저와 서버의 복구 요청 조율

서버는 정상 AU가 5초 중단되면 재시작하고, 15초 간격·연속 실패 3회 상한을 둔다. 브라우저는 디코더 출력 `frameCount`가 멈추면 8초부터 PLI, 25초부터 `/restart`를 요청하며 30초마다 반복한다. 초기 디코더 오류에도 별도 `/restart`가 있다.

`/restart`는 202를 즉시 반환하고 별도 task에서 force restart한다. 스트림 lock은 실행을 직렬화하지만 요청을 하나로 합치지 않으며, HTTP restart task 자체에는 watchdog와 동일한 바깥쪽 10초 제한이 없다. 여러 탭이나 서버 watchdog와 겹치면 재시작이 대기열로 쌓일 가능성이 있다. 실제 중복 여부는 아직 측정하지 않았다.

제안: server 측에서 진행 중 재시작을 공유하고 모든 경로에 같은 제한 시간·cooldown·실패 보고를 적용한다. 브라우저는 수신/디코더/그리기 지표를 분리한 뒤 디코더 복구를 우선하고, 서버가 복구 중이면 추가 전체 재시작을 보류한다. offline 표시나 timeout만 늘리는 변경은 해결로 인정하지 않는다.

## 우선순위 3: 최초 패킷 중단 지점 분리

화면·음성·클립보드를 저장하지 않는 카운터로 동일 시간축에서 다음을 측정한다.

| 관측 | 다음 조사 |
|---|---|
| RTP 패킷 증가도 중단 | 인코더/기기 잠금/USB·userspace 터널/수신 task 종료를 구분 |
| RTP는 증가, 정상 AU는 중단 | sequence gap·reorder·corrupt AU·재조립 처리 |
| 정상 AU는 증가, HTTP 전달은 중단 | 구독자 queue overflow·needs_key·writer drain 지연 |
| HTTP는 증가, 디코더 출력은 중단 | WebCodecs 오류·decode queue·키프레임 대기 |
| 디코더 출력은 증가, 그리기만 중단 | requestAnimationFrame·포커스·canvas 처리 |

기존 임시 카운터는 5초 단위이고 스트림 재시작 시 RTP 누적치가 리셋된다. 새 측정은 스트림 세대와 restart 원인/진행 여부도 기록해야 리셋을 패킷 손실로 오해하지 않는다. 오류 분류와 카운터만 남기고 HID 요청 body·기기 식별자·원본 영상은 남기지 않는다.

비교 순서: 뷰어 1개로 전면 유지 → 동일 상태의 PC 앱 전환 10초/30초 → 비브라우저 수신기만 연결. 조건별 최소 3분 탐색 후 유력 수정으로 10분 반복한다. 정적 화면과 안전한 앱 내부 탭 전환을 구분한다. 최초 원인 측정 전 RCTL·비트레이트·USB 포트 등 여러 변수를 동시에 바꾸지 않는다. 물리적 케이블/포트와 TCP/QUIC 비교는 패킷 계층 중단 근거가 있을 때 진행한다.

## 상류 조사

- [공식 v11.26.0 릴리스](https://github.com/doronz88/pymobiledevice3/releases/tag/v11.26.0): 조회된 최신 릴리스는 설치 버전과 같다. 이 릴리스의 변경 설명에서 화면 중단 해결은 확인하지 못했다. 무조건 업그레이드를 우선하지 않는다.
- [공식 screen_stream 소스](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/core_device/screen_stream.py): 조회된 오류 분류 부분에도 동일한 closed-userspace 처리 누락이 있다. master 페이지는 변경 가능한 자료이며 설치 파일의 근거는 아래 해시다.
- [이슈 #1759](https://github.com/doronz88/pymobiledevice3/issues/1759): 작성자가 클라이언트 프레이밍 오류로 철회했다. 현재 문제의 상류 결함 근거로 사용하지 않는다.
- [대체 미러링 discussion #1668](https://github.com/doronz88/pymobiledevice3/discussions/1668): 작성자는 Windows용 Valeria와 저속 접근성 fallback을 제시하지만 원격 입력은 제공하지 않는다. 마지막 대체 관찰 후보이며 설치·호환성·안정성은 미검증이다.

## 검증과 다음 작업

이번 Windows Python 3.12.10 환경에서 `simulation/usb/test_viewer_adapter.py` 통과: 개인정보 경로 8개 차단·오디오 생성 차단·상류 변경 거부. 위 오류 분류 호출은 현재 누락 재현이며 수정 통과 검사가 아니다.

설치 소스 SHA-256:

- screen_stream.py: `22b8da0201918af06e642b7859873d17ef2976338b2d4fe43c7e8a596b6ea6f6`
- userspace_tunnel.py: `6d2908f23e4d1cc7829ea57509bdbb6f4a15aa5055066a240a913e0fd8eb4eca`

다음 구현 후보는 카운터 진단 추가, closed-userspace 복구/터널 수명 처리, 재시작 요청 병합이다. 실제 서버가 없는 이번 조사에서는 어느 후보도 실기기 해결로 판정하지 않는다. 제품 코드·설치 라이브러리·운영 설정 변경, 전체 iOS 빌드·XCTest·JS 회귀 재실행·push·배포는 미실행이다. 문서만 변경하므로 문서 검토와 공백 검사를 수행하고 UX 총괄 브랜치에서 커밋·로컬 통합한다.
