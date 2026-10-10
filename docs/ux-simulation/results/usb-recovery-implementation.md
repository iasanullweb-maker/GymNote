# USB 연결 복구 구현 — 2026-10-10

후속 실기기 확인: USB 연결 후 정지 화면 오인에 대한 보완과 Chrome 앱 전환/조작 확인을 수행했다. 아래의 ‘기기 0대·미검증’ 설명은 최초 구현 시점의 이력이며, 현재 확인 범위와 남은 한계는 [정지 화면 실기기 검증](usb-idle-recovery-validation.md)을 따른다.

사용자가 연결 끊김 해결 방안 구현을 요청했다. [조사 결과](usb-disconnection-investigation.md)의 닫힌 userspace 터널 복구 누락, 복구 요청 중복, 서비스 없음 상태의 watchdog 공백을 보완했다. 기존 UX 총괄 워크트리에서 USB 어댑터와 해당 검사·문서만 수정했다. 제품 Swift·설치 라이브러리·기기 설정은 변경하지 않았다.

## 변경

- 새 `simulation/usb/viewer_recovery.py`: 오류 체인의 정확한 closed-userspace 감지와 상류 단절 분류, 스트림 시작 작업 공유·12초 제한·15초 cooldown, 서비스 없음 재시도와 연속 실패 3회 상한.
- `scripts/ux_simulation_usb_viewer.py`: 동일 USB 기기로 고정한 supervisor/worker 실행. 단절은 기존 서버의 정리 경로를 거친 뒤 worker exit 75로 전달하고 새 프로세스가 CLI 터널을 다시 만든다. 5분 안에 3회만 교체한다. 서버의 전체 task 정리에 coordinator가 취소되지 않도록 원래 CLI task에서 serve를 유지했다.
- 브라우저는 스트림 종료·읽기 실패·초기 연결 실패 때 중복 없이 5/15/30초 재접속한다. 최대 3회, 정상 출력 300개 이상·페이지 실행 60초 이상이면 한도 회복. 전면 복귀·좌표 보정·개인정보 차단은 유지한다.
- 내용 없는 진단: 서버 worker PID/세대·RTP·AU·gap/reorder/corrupt·HTTP 메시지·queue·복구 상태와 브라우저 수신/디코딩/그리기를 분리한다. `/gymnote/health`와 콘솔 카운터를 제공하며 화면 파일은 만들지 않는다.

실행·검사·실기기 비교 절차는 [USB README](../../../simulation/usb/README.md)에 있다. 종료는 Ctrl+C, 내부 worker 인수로도 loopback/오디오 차단을 바꿀 수 없다. 새 런타임 설치나 별도 tunneld 서비스 구성은 하지 않았다.

## 검증

Windows의 Python 3.12.10 / pymobiledevice3 11.26.0 및 기존 Codex 번들 Node 24.21.0으로 변경된 작업 파일을 검사했다. 아래 검사는 모두 통과했다.

- Python recovery 검사 13개: 동시 복구 요청 1회 실행, 호출자 취소와 작업 분리, exact/cause/context·cycle 오류 분류, 닫힌 터널에서 기존 worker 정리, 기존 errno 단절의 worker 교체, 제한 시간 취소, non-force 경로 cooldown, 서비스 없음 재시도, 실패 상한, supervisor 교체 상한·시간창·Ctrl+C, 개인정보 없는 snapshot.
- adapter 검사: 기존 개인정보 GET/POST 8개 차단·오디오 생성 차단·변경된 상류 거부 및 health 응답의 합성 secret 제외.
- Node: 전체 패치 JS 문법, 기존 lifecycle와 좌표 회귀, 실제 패치 소스에서 읽은 브라우저 재접속 중복 방지·재접속 간 한도·잘못된 저장 한도·종료 경로 연결.
- 기기 없는 실행기 시작: exit 1과 USB 기기 연결 안내를 확인했다. 무한 재시도나 새 서버 시작은 없었다. 문서 로컬 링크와 `git diff --check` 통과.

실기기 USB 조회는 연결 기기 0대였다. 따라서 최초 끊김 원인, 실제 스트림 재개, 안정성·장시간 사용성은 **미검증**이다. 기기 없이 하는 검사 통과를 실기기 해결로 표현하지 않는다. 다음은 USB 연결·잠금 해제·GymNote 전면 후 단일 뷰어의 전면 유지/PC 앱 전환 카운터 비교와 10분 반복이다. 강제 기기 분리·화면 수집·기록 변경은 수행하지 않았다.

전체 iOS 빌드·XCTest는 제품 코드 변경이 없어 미실행이다. 로컬 커밋·공통 잠금 아래 main 통합을 수행하며 최종 해시는 완료 응답에서 제공한다. 원격 push·배포는 수행하지 않는다.
