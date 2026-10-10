# GymNote 계정 연결

## 현재 구현

- 첫 실행 로그인 화면과 설정 탭: 이메일 인증번호 로그인/가입, **Google 로그인**, 재발송, 세션 복원, 로그아웃, 재인증 후 계정 삭제.
- Google·Apple은 Supabase의 OAuth 로그인 + PKCE를 시스템 인증 브라우저(`ASWebAuthenticationSession`, 저장된 쿠키 없는 ephemeral 세션)로 연다. Google Client Secret과 Apple 서명 키는 Supabase 설정에만 있고 앱·저장소에는 없다. 버튼은 Supabase가 해당 방식을 켰다고 알려 줄 때만 활성화된다(`/auth/v1/settings`). Apple은 유료 Apple Developer Program이 필요해 현재 비활성이다(아래 7번).
- 계정 연결이 없어도 게스트 운동 기능은 유지된다. 가짜 로그인으로 우회하지 않는다.
- Supabase Auth의 REST API를 HTTPS로 호출하며, 비밀번호·인증번호 검증·JWT 발급은 Supabase가 맡는다.
- 토큰은 앱의 비공유 Keychain (`WhenUnlockedThisDeviceOnly`), 운동 기록은 계정별 App Group 파일에 저장한다.
- 로그인 화면의 "기기에 있던 기록을 계정에 이어서 저장"에 동의하면 게스트 원본을 백업하고 계정별 기기 사본으로 이어 쓴다. 첫 서버 읽기 전 연결이 끊겨도 이 사본으로 계속 운동한다. 새 계정 사본의 첫 동기화는 서버 기록을 읽고 양쪽 사본을 보관한 뒤 기기 기록을 추가하여 버전을 비교해 업로드한다. 동의하지 않았다면 설정에서 가져오기를 선택할 수 있다. 첫 동기화 동의는 프로젝트·사용자 UUID에 묶으며 연결 실패 시 재시도한다.
- 인터넷 연결(Wi-Fi·모바일 데이터·유선)이 없는 첫 실행은 로그인 화면을 생략하고 게스트 기기 기록으로 시작한다. 이미 로그인한 기기는 Keychain 세션과 같은 계정의 캐시를 복원하여 기록을 이어 쓴다. 오프라인으로 바뀌었다고 계정을 게스트로 전환하거나 다른 계정 기록을 합치지 않는다.
- 연결이 돌아오면 로그인된 계정의 변경을 자동 동기화한다. 2026-10-10부터 아이폰 사용을 위해 모바일 데이터도 온라인으로 본다(이전에는 Wi-Fi·유선만). 앱이 화면에 있는 동안 30초마다 서버 버전 번호만 확인하고, 바뀌었을 때만 전체 기록을 받는다. 연결 가능한 경로가 있어도 서버에 도달하지 못하면 기기 기록을 보존하며 다음 연결/앱 활성화/수동 동기화 때 재시도한다.
- 계정 기록은 수정 후/앱을 다시 열 때 동기화한다. 서버 버전 충돌은 사용자가 선택하기 전까지 중단한다.
- 운동 기록 파일은 '재부팅 후 첫 잠금 해제부터 접근 가능' 등급으로 저장해 잠금 화면 위젯이 읽을 수 있다. 토큰은 키체인에만 두고 위젯과 공유하지 않는다.

## 1. Supabase 프로젝트 만들기

Supabase에서 프로젝트를 만들고, 프로젝트 URL (`https://프로젝트ID.supabase.co`)과 `sb_publishable_...` 공개용 키를 확인한다. 이 앱은 hosted Supabase의 publishable key만 받는다.

관리자용 `service_role`, `sb_secret_...`, SMTP 비밀번호는 앱·GitHub 코드·채팅에 넣지 않는다.

## 2. 데이터베이스 정책 적용

Supabase SQL Editor에서 `supabase/migrations/202610080001_accounts.sql`을 한 번 실행한다.

이 정책은 본인 계정의 활성 세션만 조회/업로드할 수 있게 한다. 앱이 사용자 ID를 전달하지 않고 서버가 JWT의 `auth.uid()`로 소유자를 결정한다. 직접 INSERT/UPDATE/DELETE는 금지하고 업로드 RPC가 버전을 비교한다. 정책을 `using (true)`로 완화하면 안 된다.

`scripts/auth_test_schema.sql`은 테스트용 가짜 Auth 테이블이다. **실제 Supabase 프로젝트에 실행하지 않는다.**

## 3. 이메일 인증 설정

Authentication의 Email provider를 켜고 이메일 확인을 유지한다. 사용할 로그인 방식은 6자리 이메일 OTP다.

- **먼저 Custom SMTP를 연결한다.** [Supabase의 2026-06-03 변경](https://supabase.com/changelog?tags=platform)에 따라 이후 생성된 Free 프로젝트는 기본 SMTP 사용 중 이메일 템플릿을 수정할 수 없다. Source 버튼이 비활성화돼 있으면 이 제한부터 확인한다.
- SMTP 메일 발송 서비스에서 제공하는 host, port, username, password와 검증된 발신 주소를 Supabase의 SMTP 설정에 입력한다. 비밀번호와 발송 서비스 키는 Supabase 설정에만 보관하며 앱·GitHub 코드·채팅에 넣지 않는다. [SMTP 설정 안내](https://supabase.com/docs/guides/auth/auth-smtp)
- **Confirm signup**과 **Magic Link** 두 이메일 템플릿에 인증번호 `{{ .Token }}`을 넣는다. 로그인 링크 대신 앱에 입력할 코드를 안내한다.
- OTP 유효기간은 5분, 재발송 간격은 60초 이상으로 설정한다.
- JWT 유효기간은 15분 정도로 설정하고 refresh token rotation을 유지한다.
- 발송·검증의 서버 요청 제한을 유지한다. 앱의 60초 제한은 사용 편의를 위한 것으로 서버 제한을 대체하지 않는다.
- 기본 테스트 메일 서비스는 프로젝트 팀원의 이메일로만 보낼 수 있으며 발송량도 제한된다. 공개용 API 키만으로는 SMTP 설정을 변경할 수 없다.
- 현재 UI는 CAPTCHA 챌린지를 지원하지 않는다. 공개 배포 전에 발송 남용 방어를 검토하고 CAPTCHA를 켜려면 챌린지 처리도 먼저 연결한다.

## 4. 계정 삭제 함수 배포

Supabase CLI로 프로젝트를 연결한 뒤:

```sh
supabase functions deploy delete-account --project-ref 프로젝트ID
```

`supabase/config.toml`은 게이트웨이 JWT 검증 대신 함수 안에서 `auth.getUser()`로 JWT를 검증하도록 설정한다. 함수의 `getUser`, 활성 세션 확인, 최근 5분 OTP 확인을 제거하면 안 된다. 갱신된 토큰의 `iat`만으로 재인증을 판단하지 않는다.

호스팅 환경의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`가 필요하다. 기본 Supabase 함수 환경이 제공하는 값이며, 관리자 키는 이 서버 환경에서만 사용한다. 함수는 요청 본문의 사용자 ID를 받지 않는다. Auth 계정 삭제 시 운동 기록도 외래 키로 함께 삭제된다.

## 5. 앱 빌드 설정 연결

GitHub 저장소의 Settings → Secrets and variables → Actions → **Variables**에 다음 공개 설정을 넣는다.

| 이름 | 값 |
|---|---|
| `GYMNOTE_SUPABASE_URL` | 프로젝트 HTTPS URL |
| `GYMNOTE_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_...` 공개용 키 |

기존 IPA 빌드 워크플로가 이 값을 Xcode 빌드 설정에 전달한다. 값이 없으면 로그인 기능만 비활성화된다. 공개용 키는 IPA에서도 추출할 수 있는 값이며, 데이터 보호는 서버 권한 정책이 담당한다.

Mac에서 직접 빌드할 때는 Xcode의 해당 User-Defined Build Settings에 동일한 값을 지정한다. URL과 키만 설정하고 App Group에 Keychain 공유 권한을 추가하지 않는다.

## 6. Google 로그인 설정

메뉴 이름은 콘솔 개편에 따라 조금 다를 수 있다. 프로젝트 URL은 `https://wthfekhyrsbslnkyvtax.supabase.co`.

### Google Cloud Console (console.cloud.google.com)

1. **프로젝트 선택**: 상단 프로젝트 선택 → 새 프로젝트(예: `GymNote`) → 만들기.
2. **Google Auth Platform → 브랜딩(Branding)**: 시작하기 → 앱 이름 `헬스노트`, 사용자 지원 이메일, 개발자 연락처 이메일 입력. 로고는 넣지 않아도 된다(넣으면 브랜드 확인 절차가 생길 수 있음).
3. **대상(Audience)**: 사용자 유형 **외부(External)**. 게시 상태가 **테스트**이면 **테스트 사용자**에 로그인할 Google 계정을 추가한다(최대 100명). 기본 범위(openid·이메일·프로필)만 쓰므로 민감 범위 검증 대상은 아니며, 친구들도 쓰게 하려면 **앱 게시(프로덕션)** 로 바꾼다.
4. **데이터 액세스(Data Access)**: 범위 추가 → `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`만 선택. 다른 범위는 추가하지 않는다.
5. **클라이언트(Clients) → 클라이언트 만들기**
   - 애플리케이션 유형: **웹 애플리케이션** (토큰 교환은 Supabase 서버가 하므로 iOS 유형이 아님)
   - 이름: `GymNote Supabase`
   - 승인된 JavaScript 원본: 비워 둔다
   - 승인된 리디렉션 URI: `https://wthfekhyrsbslnkyvtax.supabase.co/auth/v1/callback`
   - 만들기 → **클라이언트 ID**와 **클라이언트 보안 비밀번호(Client Secret)** 를 확인한다. Secret은 Supabase 입력란에만 붙여 넣고 앱·GitHub·채팅에 쓰지 않는다.

### Supabase 대시보드

1. **Authentication → Sign In / Providers → Google**: Enable 켜기, **Client IDs**에 웹 클라이언트 ID, **Client Secret**에 보안 비밀번호 입력. *Skip nonce checks*는 끈 채로 둔다. 화면의 Callback URL이 위 리디렉션 URI와 같은지 확인 → Save.
2. **Authentication → URL Configuration → Redirect URLs → Add URL**: `com.gymnote.app://auth-callback`을 **정확히** 추가한다. 이 주소가 없으면 로그인 후 앱으로 돌아오지 못하고 인증 창에 남는다(취소하면 앱은 그대로 유지). Site URL은 바꾸지 않는다.
3. **Email provider의 Confirm email은 켜 둔다.** 자동 계정 연결의 안전 조건이다(8번).
4. **Allow manual linking**은 꺼 둔다(앱에 수동 연결 기능 없음).
5. 아이패드에서 Wi-Fi 연결 후 앱을 열면 Google 버튼이 활성화된다. 설정이 아직이면 '준비 중'으로 남는다.

### 앱 복귀 주소와 보안

- 검증된 https 복귀(유니버설 링크, `ASWebAuthenticationSession`의 https 콜백)는 **Associated Domains** 권한이 필요하고, Apple 공식 표에서 이 권한은 무료 계정(Apple Developer)에 제공되지 않는다. 그래서 무료 서명(AltStore)에서는 사용자 지정 스킴 `com.gymnote.app://auth-callback`을 쓴다.
- 이 스킴은 Info.plist에 등록하지 않는다. Apple 문서: *"ASWebAuthenticationSession ensures that only the calling app's session receives the authentication callback, even when more than one app registers the same callback URL scheme."*
- 보호 장치: 시도마다 새 PKCE 검증값(S256, 메모리에만 보관) → Supabase가 허용 목록의 정확한 주소로만 복귀 → 앱이 스킴·호스트·경로를 정확히 비교 → 코드 교환 시 같은 검증값을 증명해야 세션 발급(코드 5분, 1회용).
- 취소·거부(`access_denied`)·잘못된 복귀·교환 실패는 기기 기록을 건드리지 않고 메시지만 표시한다. 인증 중 앱이 종료되면 검증값이 사라져 다음 실행에서 처음부터 다시 로그인한다(반쪽 상태 없음).
- 앱은 Google 토큰을 받지 않는다. 결과는 기존과 같은 Supabase 세션(Keychain 보관)이다.
- 정식 출시 후 유료 계정이 생기면 Associated Domains + https 복귀로 바꾸는 것을 검토한다.

## 7. Apple 로그인 조건

- Apple 공식 표(Supported capabilities, iOS)에서 **Sign in with Apple은 Apple Developer Program(ADP)에만 제공**되고, 무료 Apple 계정과 Enterprise에는 없다. 지금 AltStore가 쓰는 무료 Apple ID로는 네이티브 Apple 로그인 권한을 서명할 수 없다.
- 웹 방식(이 앱이 이미 구현한 Supabase OAuth 경로)도 Apple의 **Services ID**, 도메인·복귀 URL 등록, **Sign in with Apple 키(.p8)** 가 필요하며 이는 개발자 계정의 인증서·식별자 화면에서 만든다.
- 비용: Apple Developer Program **연 99 USD**(현지 통화 가능). HANDOFF대로 보호자 명의 가입이 필요할 수 있다.
- 가입 후 웹 방식으로 켜는 절차: Identifiers에서 Services ID 생성 → Sign in with Apple 구성(도메인 `wthfekhyrsbslnkyvtax.supabase.co`, 복귀 URL `https://wthfekhyrsbslnkyvtax.supabase.co/auth/v1/callback`) → Keys에서 Sign in with Apple 키 생성(.p8은 한 번만 다운로드) → Supabase Apple provider에 Services ID와 키로 만든 Secret 입력. Apple의 웹 Secret은 최대 6개월마다 다시 만들어야 한다. 키 파일은 Git·앱에 넣지 않는다.
- Supabase에서 Apple을 켜면 앱의 Apple 버튼이 코드 수정 없이 활성화된다. App Store 배포 시에는 네이티브 Sign in with Apple(권한 + ID 토큰 + nonce)로 전환과 App Review Guideline 4.8 검토가 필요하다.
- Apple의 **이메일 가리기**를 쓰면 `@privaterelay.appleid.com` 주소가 오므로 기존 이메일 계정과 연결되지 않고 새 계정이 된다(8번).

## 8. 계정 연결·중복 계정 정책

- 모든 기록은 서버가 검증한 **사용자 UUID**별 파일·서버 행에 저장한다. 앱은 이메일 문자열을 비교해 기록을 합치지 않는다.
- Supabase는 서버에서 **확인된 이메일이 같은 경우에만** 새 Google/Apple 신원을 기존 사용자에 자동 연결한다(같은 UUID). 이메일 OTP로 확인한 주소와 Google이 확인한 주소가 같으면 같은 계정이 되는 것이며, 두 신원 모두 그 이메일의 소유를 증명한 경우다. 앱이 서로 다른 UUID의 기록을 합치는 일은 없다.
- Supabase 코드는 이메일 자동 확인(autoconfirm)이 켜져 있으면 확인되지 않은 주소도 확인된 것으로 취급하므로 **Confirm email을 반드시 켜 둔다**.
- 다른 주소의 Google 계정, Apple 이메일 가리기는 별도 계정이 된다. 설정 → 계정에 로그인 이메일과 **로그인 방법**(이메일/Google/Apple)이 표시되므로 사용자가 구분할 수 있다. 두 계정의 기록을 합치는 기능은 없다. 나중에 필요하면 Supabase 수동 연결(베타)을 최근 재인증 후에만 허용하는 방식으로 설계한다.
- 소셜 로그인도 기기(게스트) 기록은 로그인 화면의 '이 기기의 기록도 이어서 저장'에 동의했을 때만 가져온다. 기본값은 꺼짐.

## 9. 재인증과 계정 삭제

- 서버(`delete-account`)는 기존 검사(`getUser` 토큰 검증, `sub` 일치, 활성 세션 `gymnote_session_valid`, 요청 본문의 사용자 ID 무시)를 유지하고, 이 세션의 AMR에 **5분 이내의 `otp` 또는 `oauth` 로그인**이 있을 때만 삭제한다. `token_refresh`, 갱신된 `iat`, 오래된 로그인은 인정하지 않는다.
- 앱은 계정에 연결된 방법만 본인 확인에 제시한다(이메일 계정은 인증번호, Google 계정은 Google). Google/Apple 본인 확인은 저장된 로그인이 없는 새 인증 창으로 열려 실제로 다시 로그인해야 한다.
- 다른 계정으로 인증하면 거부하고 그때 생긴 세션을 서버에서 종료한다. 같은 계정으로 확인되면 대체된 이전 세션도 종료를 시도한다.
- **이 변경은 함수 재배포가 필요하다**: `supabase functions deploy delete-account --project-ref wthfekhyrsbslnkyvtax`. 재배포 전에는 Google 계정 삭제가 서버에서 403으로 거부된다(안전한 방향).

## 기록과 복구

- 기존 `gymnote-data.json`은 게스트 저장 형식으로 이관된다. 이관 전 `guest-before-accounts.json` 사본을 만든다.
- 각 계정은 `account-사용자UUID.json`으로 분리된다. 이메일은 파일 이름으로 사용하지 않는다.
- 충돌 시 서버 기록을 선택하면 기존 로컬 사본, 로컬 기록을 선택하면 기존 서버 사본을 `backup-사용자UUID-임의UUID.json`에 보관한다. 복구 UI는 아직 없으며 사본을 추출해서 복원하는 개발자 작업이 필요하다.
- 로그아웃은 계정의 로컬 사본을 숨기되 미동기화 기록을 지우지 않는다. 같은 계정으로 다시 인증하면 접근할 수 있다. 서버 로그아웃이 실패하면 앱이 그 사실을 표시한다.
- 계정 삭제는 서버와 현재 기기의 계정 사본·복구 사본을 삭제한다. 다른 기기의 오프라인 사본과 원래 게스트 기록까지 원격으로 지우지는 않는다.
- 서버 운영자는 운동 기록을 읽을 수 있다. HTTPS와 iOS 파일 보호를 사용하지만 종단간 암호화는 구현하지 않았다.
- 자동 백그라운드 동기화는 없고, 앱 실행 중 수정/재활성화/네트워크 복구 시 동기화한다. 위젯 변경은 앱이 다시 활성화되면 업로드한다.
- 파일을 읽거나 저장하지 못하면 원본을 덮어쓰지 않는다. 저장 오류 알림을 확인한다.

## 검증

`.github/workflows/check.yml`은 별도 브랜치/PR에서 모델 검사, iPad 시뮬레이터 XCTest, PostgreSQL 권한 검사를 실행한다. IPA 배포는 하지 않는다.

테스트 범위: 게스트 이관, 계정 격리, 과거 위젯 버튼 거부, 업로드 중 변경 보존, 손상 파일 보존, Keychain 저장/삭제, 인증 오류, 익명/다른 계정/로그아웃 세션 차단, 동기화 버전 충돌, 계정 삭제 cascade.

출시 전 실제 프로젝트와 iPad에서 확인할 것:

1. 신규 가입과 기존 이메일 로그인, 코드 오입력·만료·재사용·재발송 제한.
2. 로그인 시 가져오기 미동의 상태에서는 게스트 기록이 업로드되지 않는지, 동의 후 자동 가져오기와 재시도에 중복이 없는지.
3. A → 로그아웃 → B에서 앱·위젯·타이머·알림에 A의 기록이 남지 않는지.
4. 오프라인 수정 후 복귀, 두 기기의 충돌, 동기화 중 위젯 체크.
5. AltStore 갱신/재서명 후 세션과 기록 접근. Apple 팀이 바뀌면 Keychain 접근이 달라져 재로그인이 필요할 수 있다.
6. 계정 삭제 전 재인증 필수 여부와 실제 서버 기록 삭제.
7. Google: 첫 로그인(테스트 사용자), 취소·동의 거부, Redirect URLs 누락 시 동작, 이메일 계정과 같은 Gmail로 로그인 시 같은 계정·기록, 다른 Google 계정은 별도 계정, Google 계정 삭제 전 재인증.

## 근거 문서

- [Supabase 이메일 OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Supabase Google 로그인](https://supabase.com/docs/guides/auth/social-login/auth-google) · [PKCE 흐름](https://supabase.com/docs/guides/auth/sessions/pkce-flow) · [계정 연결](https://supabase.com/docs/guides/auth/auth-identity-linking)
- [Apple 지원 기능 표 (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/) · [멤버십 비교](https://developer.apple.com/support/compare-memberships/)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Google OAuth 정책(내장 웹뷰 금지)](https://developers.google.com/identity/protocols/oauth2/policies) · [게시 상태](https://support.google.com/cloud/answer/15549945)
- [Supabase Auth REST API](https://github.com/supabase/auth/blob/master/openapi.yaml)
- [서버 행 접근 정책](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase JWT 인증 방법과 timestamp](https://supabase.com/docs/guides/auth/jwt-fields)
- [Keychain 접근 제한](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
