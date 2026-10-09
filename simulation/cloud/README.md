# 실제 iPad 클라우드 실험

## 현재 상태

1단계 실제 iPad → AirServer → Computer Use 자동 관찰 확인 완료. CLI와 AirServer를 같은 활성 Windows 가상 데스크톱에 두고 수신 창을 전면 표시해야 한다. 실제 설정 → 계획 → 설정 복귀와 휴식 90초/간격 15초 유지 확인.

2단계는 BrowserStack 체험 계정 가입 대기. 실제 클라우드 설치·실행·가상 사용자 반복 실험은 미검증.

## 업로드 파일

루트 GymNote.ipa는 0.1.15였으므로 사용하지 않는다. 원본 저장소의 .validation-tools/cloud-ipad/GymNote-0.1.88.ipa에 공개 build-88 IPA를 준비했다. SHA-256: 523464a94cf2bab9de4fb98394102a58ac30617af06f43597896d0ad0a0f6dc2. 공식 asset digest 일치, 대상 앱 커밋 fcf4d97cf15283f1f2c1845450dee014392cf346.

읽기 전용 검사: python simulation/cloud/ipa_preflight.py .validation-tools/cloud-ipad/GymNote-0.1.88.ipa
회귀 검사: python -m unittest discover -s simulation/cloud

IPA 사전 검사는 메타데이터·해시만 확인하며 네트워크 업로드·압축 해제·앱 실행을 하지 않는다. iPhoneOS/iPad 지원 선언은 설치 성공 증거가 아니다. 프로비저닝 프로필이 없어 재서명 호환성, App Group/위젯/알림 동작을 별도로 확인한다.

## 첫 클라우드 세션

1. 사용자가 [App Live](https://app-live.browserstack.com/) 체험 계정에 가입·로그인한다. 결제 단계는 진행하지 않고 조건을 확인한다.
2. Uploaded Apps → Upload에서 위 IPA를 선택한다. [공식 업로드 절차](https://www.browserstack.com/docs/app-live/app-source/upload-apps).
3. 실제 목록에서 iPad / iPadOS 17 이상을 선택하고 정확한 모델·OS를 기록한다.
4. 설치·첫 화면·탭 이동을 검증하고 오류가 있으면 메시지와 중단 상태를 기록한다.
5. 개인 GymNote 계정 대신 새 게스트/합성 데이터 상태를 사용한다. 공개 IPA에는 자동 fixture 진입점이 없어 초기 상태 구성은 별도 구현해야 한다.
6. 종료 시 기기 세션을 종료한다. 서비스 데이터 정리 여부는 확인 없이 단정하지 않는다.

[공식 체험 안내](https://www.browserstack.com/support/faq/plans-pricing/plans/what-do-i-get-with-a-free-trial)는 App Live 총 30분·기기당 1분, App Automate 100분으로 안내한다(2026-10-09 조회). 실제 계정 표시 한도를 우선 확인한다. App Live는 최초 설치·브라우저 조작 확인용이고 반복 자동 실험은 App Automate 연결이 필요하다.

## 반복 실험 완료 조건

- 실제 앱 버전·해시·기기·OS·세션 근거
- 사용자별 초기 데이터, 실행 사이 초기화 확인
- persona/현재 화면/목표만 사용자 역할에 제공; 평가 checks 분리
- 실제 조작과 전후 화면 및 실패/중단 기록; 실제 모델 사용량
- 앱 상태/알림/개인정보 검사는 실제 근거 없으면 not-evaluated
- 기존 계약 검증 통과, 동일 과제 반복; 업로드 성공만으로 전체 완료 보고 금지
