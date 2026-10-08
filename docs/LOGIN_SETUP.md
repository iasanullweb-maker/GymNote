# GymNote 계정 연결

## 현재 구현

- 계정 탭: 이메일 인증번호 로그인/가입, 재발송, 세션 복원, 로그아웃, 재인증 후 계정 삭제.
- 계정 연결이 없어도 게스트 운동 기능은 유지된다. 가짜 로그인으로 우회하지 않는다.
- Supabase Auth의 REST API를 HTTPS로 호출하며, 비밀번호·인증번호 검증·JWT 발급은 Supabase가 맡는다.
- 토큰은 앱의 비공유 Keychain (`WhenUnlockedThisDeviceOnly`), 운동 기록은 계정별 App Group 파일에 저장한다.
- 게스트 원본은 로그인만으로 업로드되지 않는다. 사용자가 가져오기를 선택하면 백업 후 추가한다.
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

- **Confirm signup**과 **Magic Link** 두 이메일 템플릿에 인증번호 `{{ .Token }}`을 넣는다. 로그인 링크 대신 앱에 입력할 코드를 안내한다.
- OTP 유효기간은 5분, 재발송 간격은 60초 이상으로 설정한다.
- JWT 유효기간은 15분 정도로 설정하고 refresh token rotation을 유지한다.
- 발송·검증의 서버 요청 제한을 유지한다. 앱의 60초 제한은 사용 편의를 위한 것으로 서버 제한을 대체하지 않는다.
- 기본 테스트 메일 서비스에는 수신자/발송 제한이 있으므로 실제 사용에는 SMTP 발송 서비스를 연결한다. 발송 서비스의 키는 Supabase 설정에만 입력한다.
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
2. 로그인만 했을 때 게스트 기록이 업로드되지 않는지, 가져오기 후 중복이 없는지.
3. A → 로그아웃 → B에서 앱·위젯·타이머·알림에 A의 기록이 남지 않는지.
4. 오프라인 수정 후 복귀, 두 기기의 충돌, 동기화 중 위젯 체크.
5. AltStore 갱신/재서명 후 세션과 기록 접근. Apple 팀이 바뀌면 Keychain 접근이 달라져 재로그인이 필요할 수 있다.
6. 계정 삭제 전 재인증 필수 여부와 실제 서버 기록 삭제.

## 근거 문서

- [Supabase 이메일 OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Supabase Auth REST API](https://github.com/supabase/auth/blob/master/openapi.yaml)
- [서버 행 접근 정책](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase JWT 인증 방법과 timestamp](https://supabase.com/docs/guides/auth/jwt-fields)
- [Keychain 접근 제한](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
