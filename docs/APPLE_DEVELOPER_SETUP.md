# 유료 Apple Developer 계정 전환 준비 (TestFlight)

작성: 2026-10-21. 유료 Apple Developer Program 계정이 생겼을 때 하는 순서다. **가입·결제·배포 방식 전환은 사용자가 직접 결정한다.** 이 문서와 아래 도구는 미리 준비해 둔 것이며, 계정이 없는 지금은 아무것도 실행되지 않는다. 현재 할 일 체크는 [TODOLIST_HANDOFF](../TODOLIST_HANDOFF.md)의 같은 날짜 항목에서 관리한다.

미리 준비한 것:

| 파일 | 용도 |
| --- | --- |
| `scripts/apple_signing_setup.ps1` | Windows에서 개인키·CSR 생성 → 인증서(.cer)를 .p12로 변환 → GitHub 시크릿용 base64 파일 생성 |
| `.github/workflows/testflight.yml` | **수동 실행 전용.** 같은 커밋의 전체 검사(check.yml) 성공 후 정식 서명 빌드 → TestFlight 업로드. 기존 Build IPA·AltStore 게시는 바꾸지 않는다. |

비밀 파일(개인키·.p12·.p8·프로파일)은 모두 `.validation-tools/apple-signing/`(Git 미추적)에만 둔다. 저장소·채팅·문서에 붙여 넣지 않는다.

## 0. 가입 전 확인

- 가입 명의: Apple Developer Program은 법적 성인 명의로 가입한다. 해당하지 않으면 보호자 명의로 가입하고 사용자를 팀 멤버(Admin/App Manager)로 초대받는다. 가입한 Apple ID를 HANDOFF의 계정별 용도 표에 적는다(비밀번호는 적지 않음).
- 비용: 연 99 USD(가입 시 현지 가격 재확인). 결제 후 승인까지 1~2일 걸릴 수 있다.
- 기존 AltStore 앱은 **삭제하지 않는다.** AltStore 판은 번들 ID 뒤에 무료 팀 ID가 붙은 별도 앱이라 TestFlight 판과 동시에 설치된다. 두 앱의 기기 내 저장소(App Group)는 서로 다르므로, 넘어가기 전에 AltStore 판에서 로그인해 기록이 서버에 동기화됐는지 확인한다.

## 1. 계정 활성화 확인

1. developer.apple.com → Account에서 멤버십 상태 Active 확인.
2. Membership details의 **Team ID**(10자리)를 복사 → GitHub 저장소 Settings → Secrets and variables → Actions → **Variables**에 `APPLE_TEAM_ID`로 저장.

## 2. 번들 ID·App Group 등록 (Certificates, Identifiers & Profiles)

현재 코드 기준 값(`project.yml`, `Shared/SharedStore.swift`):

| 대상 | 값 |
| --- | --- |
| 앱 | `com.gymnote.app` |
| 위젯 | `com.gymnote.app.widget` |
| App Group | `group.com.gymnote.app` |

1. Identifiers → App Groups → `group.com.gymnote.app` 등록.
2. Identifiers → App IDs → `com.gymnote.app` 등록, Capabilities에서 **App Groups** 켜고 위 그룹 연결. (Sign in with Apple은 8번에서 켠다.)
3. 같은 방법으로 `com.gymnote.app.widget` 등록, App Groups 켜고 같은 그룹 연결.
4. **이름이 이미 사용 중이라 등록이 안 되면 멈추고 코드 작업으로 넘긴다.** 번들 ID는 전 세계에서 하나만 쓸 수 있다. 바꿀 때 함께 수정해야 하는 곳: `project.yml`의 번들 ID 3개(앱·위젯·테스트)와 App Group 2곳, `Shared/SharedStore.swift`의 `baseGroupID`, 로그인 복귀 주소 `com.gymnote.app://auth-callback`(코드와 Supabase Redirect URLs), AltStore `scripts/make_source.py`의 번들 ID. 바꾸면 전체 iOS 검사·계정 검사가 필요하다.

## 3. 배포 인증서 (Windows에서 가능, Mac 불필요)

```powershell
# 저장소 폴더에서
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\apple_signing_setup.ps1 -Mode Csr -Email "가입한 이메일" -Name "영문 이름"
```

1. 생성된 `.validation-tools\apple-signing\gymnote_distribution.csr`을 Certificates → + → **Apple Distribution**에 업로드.
2. 받은 `distribution.cer`를 같은 폴더에 저장하고:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\apple_signing_setup.ps1 -Mode P12 -CerPath .validation-tools\apple-signing\distribution.cer
```

3. 입력한 .p12 비밀번호는 GitHub 시크릿 `APPLE_CERT_PASSWORD`로만 저장한다. `gymnote_distribution.key`를 잃어버리면 인증서를 새로 만들어야 하므로 백업한다(공유 금지).

## 4. 프로파일 (App Store 배포용)

Profiles → + → **App Store Connect**(Distribution) → 앱 ID 선택 → 3번 인증서 선택. 앱(`com.gymnote.app`)과 위젯(`com.gymnote.app.widget`) 각각 만들고 `.validation-tools\apple-signing\`에 아래 이름으로 저장한다.

- `GymNote_AppStore.mobileprovision`
- `GymNoteWidget_AppStore.mobileprovision`

TestFlight 배포에는 기기 UDID 등록이 필요 없다. (Xcode/Ad Hoc 직접 설치를 쓸 때만 Devices에 iPad·iPhone UDID 등록)

## 5. App Store Connect 앱 레코드와 API 키

1. appstoreconnect.apple.com → 앱 → + → 새 앱: 플랫폼 iOS, 이름 `헬스노트`(사용 중이면 다른 이름), 기본 언어 한국어, 번들 ID `com.gymnote.app`, SKU 예: `gymnote`.
2. 사용자 및 액세스 → 통합 → App Store Connect API → 팀 키 생성(역할 **App Manager**). **Issuer ID**, **Key ID**를 적고 `AuthKey_<KeyID>.p8`을 `.validation-tools\apple-signing\`에 저장한다. p8은 한 번만 내려받을 수 있다.

## 6. GitHub 시크릿 등록

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\apple_signing_setup.ps1 -Mode Secrets -AscKeyId <KeyID> -AscIssuerId <IssuerID>
```

`.validation-tools\apple-signing\secrets\`에 시크릿별 파일이 생긴다. 저장소 Settings → Secrets and variables → Actions → **Secrets**에 같은 이름으로 각 파일 내용을 붙여 넣는다(GitHub CLI가 있으면 `-Upload`로 바로 등록).

| 이름 | 종류 | 내용 |
| --- | --- | --- |
| `APPLE_TEAM_ID` | Variable | 1번 Team ID |
| `APPLE_CERT_P12_BASE64` | Secret | .p12 base64 |
| `APPLE_CERT_PASSWORD` | Secret | .p12 비밀번호 |
| `APPLE_APP_PROFILE_BASE64` | Secret | 앱 프로파일 base64 |
| `APPLE_WIDGET_PROFILE_BASE64` | Secret | 위젯 프로파일 base64 |
| `ASC_KEY_ID` | Secret | API Key ID |
| `ASC_ISSUER_ID` | Secret | Issuer ID |
| `ASC_KEY_P8_BASE64` | Secret | p8 base64 |

## 7. 첫 TestFlight 업로드

1. `testflight.yml`은 main에 있어야 Actions 화면에 수동 실행 버튼이 생긴다. main push는 AltStore 공개 배포를 시작하므로 **사용자 배포 승인 범위 안에서** 다른 변경과 함께 올린다.
2. Actions → **TestFlight** → Run workflow(main). 같은 커밋의 전체 검사가 성공해야 서명·업로드 단계가 실행된다.
3. 시크릿이 빠졌거나 프로파일의 번들 ID·팀이 맞지 않으면 서명 전에 이유를 출력하고 멈춘다.
4. 업로드 후 App Store Connect → TestFlight에서 처리 완료(수 분~수십 분) → 수출 규정(암호화) 질문 응답 → 내부 테스터 그룹에 본인 Apple ID 추가.
5. iPad·iPhone에 TestFlight 앱 설치 → 초대 수락 → 헬스노트 설치. 빌드는 90일간 유지되고 7일 재서명이 필요 없다.

버전: TestFlight 빌드는 `0.2.<TestFlight 실행 번호>`로 올라간다(입력으로 앞자리 변경 가능). AltStore 판 `0.1.N`과 구분된다.

## 8. 계정이 생기면 쓸 수 있게 되는 기능 (각각 별도 작업)

- **Sign in with Apple**: 앱 ID에 Sign in with Apple capability 추가 → 프로파일 재생성 → Services ID·키 생성 → Supabase Apple provider 켜기. 코드 경로는 이미 있고 서버가 켜면 버튼이 활성화된다(HANDOFF ‘Google·Apple 로그인’). 엔타이틀먼트 추가는 코드·검사 작업이다.
- **잠금화면 휴식 타이머(Live Activity)**: 이미 구현(`Shared/RestActivity.swift`, `NSSupportsLiveActivities`). 정식 서명 빌드에서 실기기 동작을 다시 확인한다. 원격 푸시로 갱신하려면 Push Notifications capability가 추가로 필요하다(현재 미사용).
- **AltStore 의존 정리**: TestFlight 판이 안정되면 서명 만료 경고(`SigningExpiry`)·AltStore 게시를 유지할지 결정한다. 사용자 결정 전에는 기존 경로를 그대로 둔다.
- **App Store 정식 출시**: 개인정보 처리방침·스크린샷·심사 자료가 필요하다. 장기 검토 항목.

## 막혔을 때

- `security import` 실패(MAC verification failed): .p12를 이 스크립트로 다시 만든다(macOS 호환 암호화 방식 사용).
- `No profile for team ... matching ...`: 프로파일이 Distribution용인지, 앱/위젯 번들 ID와 Team ID가 맞는지 확인.
- `Invalid Provisioning Profile ... missing application-groups`: 앱 ID에서 App Groups를 켠 뒤 프로파일을 **다시 만들어** 시크릿을 교체.
- 업로드 `ENTITY_ERROR` / 빌드 번호 중복: 같은 번호가 이미 있으면 워크플로를 다시 실행해 새 번호로 올린다.
