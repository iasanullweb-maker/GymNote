# GymNote — 새 계정 Codex CLI 인수인계

작성일: 2026-10-09 (한국 시간). 기존 Codex 앱과 새 ChatGPT 계정(Pro 100 plan, 사용자 설명)을 병행하기 위한 자료다. 요금제·계정 권한은 실제 로그인 화면에서 확인한다. 아래 설치·로그인·작업 폴더 생성 명령은 안내이며 이 문서 작성 중 실행하지 않았다.

## 1. 작업 경로와 GitHub

| 용도 | 경로 / 링크 |
|---|---|
| 기존 작업 폴더·통합 대상 | `C:\Users\Donghyun\Documents\2026_IASA\GymNote` — `main` |
| 이 문서를 만든 워크트리 | `C:\Users\Donghyun\.codex\worktrees\5367\GymNote` |
| 새 CLI 작업 폴더 권장 위치 | `C:\Users\Donghyun\Documents\2026_IASA\GymNote-cli` — 아직 생성하지 않음 |
| 기존 Codex 사용자 상태 | `C:\Users\Donghyun\.codex` |
| 새 CLI 사용자 상태 권장 위치 | `C:\Users\Donghyun\.codex-cli-pro100` — 아직 생성하지 않음 |
| GitHub 저장소 | https://github.com/iasanullweb-maker/gymnote |
| Git remote (`origin`) | `https://github.com/iasanullweb-maker/gymnote.git` |
| Actions | https://github.com/iasanullweb-maker/gymnote/actions |
| 검증 워크플로 | https://github.com/iasanullweb-maker/gymnote/actions/workflows/check.yml |
| IPA 빌드 워크플로 | https://github.com/iasanullweb-maker/gymnote/actions/workflows/build.yml |
| 최신 릴리스 | https://github.com/iasanullweb-maker/gymnote/releases/tag/latest |
| IPA 다운로드 | https://github.com/iasanullweb-maker/gymnote/releases/download/latest/GymNote.ipa |
| AltStore 소스 (README의 기존 주소) | https://raw.githubusercontent.com/iasanullweb-maker/GymNote/altstore/source.json |
| Supabase 프로젝트 | https://supabase.com/dashboard/project/wthfekhyrsbslnkyvtax |

GitHub·Supabase 링크는 저장소 설정과 문서에서 확인했다. 원격 접속 권한, 최신 배포 버전, 원격과 로컬의 일치 여부는 이번 작업에서 확인하지 않았다. 새 ChatGPT 계정 로그인과 GitHub 저장소 접근 인증은 별개다.

## 2. 먼저 읽을 자료

새 CLI의 작업 폴더에서 다음 순서로 읽는다. 이 문서와 아래 자료는 Git에 포함되므로 워크트리에서도 읽을 수 있다.

1. `AGENTS.md`: 상시 작업 규칙. 완료 후 검토·검증하고 시작 당시 기존 작업 브랜치에 로컬 통합한다.
2. `docs/CODEX_CLI_HANDOFF.md`: 경로, 계정 분리, 병행 작업 방법.
3. `HANDOFF.md`: 누적 기능 변경, 검증 결과, 미배포·미검증 사항. 오래된 제목보다 날짜와 최신 추가 기록을 확인한다.
4. `README.md`, `project.yml`: 프로젝트 개요와 빌드 원본.
5. `.github/workflows/check.yml`, `.github/workflows/build.yml`: 실제 검사·빌드·배포 조건.
6. `docs/LOGIN_SETUP.md`, `docs/RECORD_CATALOG_SETUP.md`, `docs/SOCIAL_SETUP.md`: 서버 연동과 마이그레이션.

`docs/MACBOOK_SETUP_PROMPT.md`는 Mac 환경 이전용 별도 요청이다. 거기에 적힌 과거 push·배포 승인 범위를 이번 CLI 작업에 자동 적용하지 않는다.

## 3. CLI 설치와 새 계정 인증

이 세션에서 `codex.exe`는 `C:\Users\Donghyun\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe`에 있었고, `codex --version`은 `codex-cli 0.161.0`이었다. 일반 PowerShell의 PATH에서도 사용 가능한지는 아래 명령으로 확인한다. 이 세션에는 앱 번들 Node가 있었지만 `npm`은 PATH에서 발견되지 않았다.

```powershell
Get-Command codex -ErrorAction SilentlyContinue
codex --version
```

CLI가 없거나 별도로 설치하려면 [공식 CLI 설치 안내](https://learn.chatgpt.com/docs/codex/cli)를 따른다. npm 설치 경로를 선택하면 Node.js와 npm을 준비한 뒤 실행한다.

```powershell
npm install -g @openai/codex@latest
codex --version
```

기존 앱과 같은 인증 상태를 공유하지 않도록 **새 CLI 전용 PowerShell 창**에서 사용자 상태 경로를 지정한다. `CODEX_HOME`은 사용자 설정·기록·캐시 위치를 정하는 공식 환경 변수다. 아래 설정은 해당 창과 자식 프로세스에만 적용되며 시스템 전역 환경 변수로 저장하지 않는다. ([상태 경로 공식 문서](https://learn.chatgpt.com/docs/config-file/config-advanced))

```powershell
# 새 CLI를 쓸 때마다 이 전용 창에서 먼저 실행
$env:CODEX_HOME = 'C:\Users\Donghyun\.codex-cli-pro100'
New-Item -ItemType Directory -Path $env:CODEX_HOME -Force | Out-Null

# 최초 1회: 브라우저에서 새 계정임을 확인하고 로그인
codex -c 'cli_auth_credentials_store="file"' login
codex -c 'cli_auth_credentials_store="file"' login status
```

브라우저가 기존 계정을 자동 선택하면 새 계정으로 바꾼 뒤 인증한다. `login status`는 인증 방식 확인용이며 새 계정 선택 자체는 브라우저에서 확인한다. 이후 실행도 아래처럼 동일한 저장 방식을 지정한다. `file` 방식은 전용 `CODEX_HOME/auth.json`에 인증 정보를 저장하므로 다른 저장소 방식의 공유를 피할 수 있다. 이 파일은 비밀이며 Git·채팅·인수인계 자료에 복사하지 않는다. ([인증 공식 문서](https://learn.chatgpt.com/docs/auth))

Pro 구독을 이용하려면 **Sign in with ChatGPT**를 사용한다. API key 로그인은 별도 API 사용량 과금 방식이다. 기존 앱에서 로그아웃하거나 기존 `.codex`를 복사할 필요는 없다. ([인증과 과금 방식](https://learn.chatgpt.com/docs/auth))

### Git 커밋 작성자 설정 (커밋 실패 시)

새 CLI에서 `Author identity unknown`이 나오면 Git 작성자 이름과 이메일이 설정되지 않은 상태다. ChatGPT 로그인과 Git 작성자 설정은 별개이며, 작성자 설정은 GitHub 인증·push 권한을 부여하지 않는다.

먼저 현재 저장소의 설정과 기존 커밋을 확인한다.

```powershell
git config --get user.name
git config --get user.email
git log -5 --format='%h %an <%ae>'
```

이 저장소에서 기존 Codex 커밋에 사용한 정보는 `Codex <codex@users.noreply.github.com>`이다. 사용자 개인 이름·이메일을 임의로 만들지 말고, 유효한 기존 설정이 있다면 그대로 사용한다. 작성자 설정이 없으면 아래처럼 **이번 커밋에만** 기존 Codex 정보를 적용할 수 있다. 메시지는 실제 변경 내용으로 바꾸고, 이번 작업 파일만 선택해 stage한 뒤 실행한다.

```powershell
git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit -m "작업 내용에 맞는 커밋 메시지"
```

이 저장소의 이후 커밋에도 계속 사용할 때는 저장소 폴더에서 다음 명령으로 로컬 설정을 저장한다. 연결된 워크트리들이 이 저장소 설정을 공유할 수 있으므로 다른 작업에도 적용됨을 고려한다. 전역 설정은 변경하지 않는다.

```powershell
git config --local user.name "Codex"
git config --local user.email "codex@users.noreply.github.com"
```

새 CLI에 전달할 문구:

```text
Git 작성자 설정이 없으면 저장소의 기존 Codex 작성자
Codex <codex@users.noreply.github.com>을 git -c user.name=Codex
-c user.email=codex@users.noreply.github.com 방식으로 이번 커밋에만 적용해줘.
전역 설정은 바꾸지 말고 이번 작업 파일만 커밋한 다음,
다른 작업 변경을 보존하면서 검증과 기존 브랜치 로컬 통합을 이어가줘.
```

## 4. 병행 작업은 별도 워크트리에서

새 계정도 같은 파일을 수정하면 충돌할 수 있으므로 작업 폴더와 브랜치를 분리한다. 원격만 clone하면 아직 push하지 않은 로컬 변경이 빠질 수 있어, 같은 PC에서는 기존 **로컬 main**에서 워크트리를 만드는 방법을 권장한다.

먼저 다음 읽기 명령으로 현황을 확인한다.

```powershell
Set-Location 'C:\Users\Donghyun\Documents\2026_IASA\GymNote'
git status --short
git branch --show-current
git worktree list
git log -5 --oneline
```

기존 폴더가 `main`이고 미커밋 변경이 없으며, 아래 브랜치·폴더가 아직 없을 때 **한 번만** 실행한다. 미커밋 변경이 있으면 보존하고 해당 작업과 통합 시점을 조율한다. 커밋되지 않은 변경은 새 워크트리에 따라오지 않는다.

```powershell
git worktree add -b codex/cli-pro100 ../GymNote-cli main
Set-Location 'C:\Users\Donghyun\Documents\2026_IASA\GymNote-cli'
codex -c 'cli_auth_credentials_store="file"'
```

CLI를 다시 시작할 때는 3절의 `CODEX_HOME` 설정과 위 `Set-Location`을 먼저 실행한다. 워크트리 생성이 끝나면 이미 있는 폴더를 재사용한다. 기존 채팅 기록·플러그인 연결이 전용 상태 폴더에 준비됐다고 가정하지 말고 필요한 도구와 권한을 확인한다.

작성 시작 시 기존 main과 문서 워크트리의 기준 커밋은 `4497785`였고 둘 다 깨끗했다. 이것은 스냅샷이며 이 커밋으로 되돌리라는 의미가 아니다. 여러 기존 워크트리가 있으므로 작업 시작마다 `git worktree list`를 다시 확인한다. 예: `codex/login`, `codex/calendar-routines`, `codex/common-record-catalog`, `codex/manual-workout-entry`, `codex/widget-daily-summary`, `codex/workout-status-live-activity`. 브랜치 이름만 보고 진행 중·미통합 여부를 단정하지 않는다.

각 계정에 다른 기능·파일 범위를 맡기고 작업 내용과 검증 결과를 문서로 남긴다. 특히 `App/AppModel.swift`, `Shared/Models.swift`, `project.yml`, 워크플로, `HANDOFF.md`를 동시에 변경할 때는 실제 diff를 비교한다. main 통합과 배포는 한 작업씩 순차 실행한다.

## 5. 프로젝트 구조와 현재 주의할 사항

GymNote는 SwiftUI 기반 iPhone/iPad 운동·일상 앱이다. Swift 5, 최소 iOS 17.0, XcodeGen을 사용한다. Windows에서 편집하고 GitHub Actions의 macOS 환경에서 iOS를 빌드할 수 있다.

| 경로 | 역할 |
|---|---|
| `App/` | 운동·계획·기록·설정 UI, 계정 동기화, 친구 기능 |
| `Shared/` | 데이터 모델·저장·운동 기록·공통 종목·순위·App Intents |
| `Widget/` | 홈/잠금 화면 위젯, Live Activity |
| `Resources/` | 앱·위젯 리소스 |
| `Tests/`, `scripts/test_*` | XCTest, Swift 모델 검사, Node 계정 삭제 검사, SQL 권한 검사 |
| `supabase/migrations/` | 계정·공통 종목·친구/그룹 SQL |
| `supabase/functions/` | 서버 함수 |
| `project.yml` | Xcode 프로젝트 생성 원본. 생성된 프로젝트만 고치지 않는다. |

`HANDOFF.md`에 따르면 친구·그룹 경쟁은 로컬 main에 통합됐지만 실제 서버 SQL 적용과 배포는 남아 있다. 공통 종목 서버 설정은 문서 마지막의 적용 완료 기록을 확인한다. 편집 중 화면 이동 차단, 탭 복귀 등 UI 변경에는 전체 iOS 검증 대기 기록이 있으므로 모든 현재 변경을 검증 완료로 취급하지 않는다. 이 상태는 문서 기반이며 실제 서버·Actions 현황은 실행 시 재확인한다.

계정 기록은 사용자 UUID로 분리하며 토큰은 Keychain에 보관한다. 로그인·동기화·저장·DB 정책을 수정할 때는 계정 격리, 오프라인 변경 보존, 버전 충돌, 권한 검사를 바로 실행한다. Supabase 관리자 키·SMTP 비밀번호·OAuth Secret은 앱과 저장소에 넣지 않는다. `scripts/auth_test_schema.sql`은 테스트 DB 전용이며 운영 Supabase에서 실행하지 않는다.

## 6. 검증·로컬 통합·배포

- 문서 작업: 내용·경로·링크 정의와 `git diff --check` 검토.
- 작은 UI 변경: 코드 검토·가벼운 검사 후 로컬 통합. 전체 iOS 빌드·XCTest 미실행 여부를 완료 응답에 명시한다.
- 로그인·보안·저장 변경: 관련 모델·XCTest·DB·계정 삭제 검사를 바로 실행한다. 실행 명령은 최신 `check.yml`을 따른다.
- 전체 iOS 검증: Mac/Xcode 또는 GitHub Actions가 필요하다. Windows의 문법 확인만으로 iOS 빌드 성공을 보고하지 않는다.
- `Validate GymNote`: PR 또는 `codex/**` push에서 검사. IPA 릴리스는 하지 않는다.
- `Build IPA`: `main`, `codex/**` push 또는 수동 실행. `codex/login`은 현재 job 예외가 있다. 작업 브랜치는 IPA artifact를 만들고, **main은 릴리스 게시와 AltStore 소스 갱신까지 수행한다**. 단순 동기화 목적으로 main을 push하지 않는다.

완료 시 상시 규칙대로 변경을 검토하고 필요한 검증 후, 시작 당시 기존 작업 브랜치(이 문서의 기본은 main)에 로컬 병합한다. 통합 직전 기존 폴더의 브랜치와 미커밋 변경을 다시 확인하고, 타 작업 변경을 reset·강제 push·임의 stash로 덮어쓰지 않는다. 충돌은 의미를 확인해 해결한다. 원격 push·운영 SQL 적용·배포는 해당 요청의 승인 범위를 확인한다.

## 7. 새 CLI에 붙여 넣을 첫 메시지

```text
GymNote 작업을 기존 Codex 앱과 병행할 새 CLI 세션이야.
기존 작업 폴더는 C:\Users\Donghyun\Documents\2026_IASA\GymNote이고,
새 CLI 작업 폴더는 C:\Users\Donghyun\Documents\2026_IASA\GymNote-cli야.
저장소는 https://github.com/iasanullweb-maker/gymnote.git 이야.

먼저 실제 cwd, 브랜치, git status, git worktree list를 확인하고
AGENTS.md, docs/CODEX_CLI_HANDOFF.md, HANDOFF.md, README.md,
project.yml과 최신 워크플로를 읽어줘.
새 CLI 폴더가 없다면 기존 폴더 상태와 중복 이름을 확인하고,
다른 작업 변경을 보존하면서 로컬 main에서 별도 codex/ 브랜치와 워크트리를 만들어줘.
계정 인증 정보나 다른 세션의 토큰을 읽어서 옮기지 마.
Git 작성자 설정이 없으면 이 자료의 'Git 커밋 작성자 설정' 절대로
기존 Codex 작성자 정보를 이번 커밋에만 적용하고 전역 설정은 바꾸지 마.

상시 규칙에 따라 작업 완료 후 코드 검토·필요한 검증을 거쳐
시작 당시 기존 작업 브랜치에 로컬 통합해줘.
통합 직전 기존 폴더 상태를 다시 확인하고 다른 채팅의 변경을 보존해줘.
이번 인수인계는 원격 push·배포·운영 DB 변경 승인을 포함하지 않아.
완료 보고에는 변경 요약, 검증 결과, 전체 iOS 빌드 미실행 여부,
로컬 통합 여부, 원격 push·배포 여부를 적어줘.

지금은 자료를 읽고 작업 가능한 상태와 미검증 사항을 정리해줘.
구체적인 기능 작업은 내가 다음 메시지로 지정할게.
```

## 8. 이 자료 작성 시 확인한 범위

로컬 Git remote·워크트리·기준 브랜치·기존 폴더 상태, 프로젝트 문서와 워크플로, 설치된 CLI 버전/로그인 도움말을 확인했다. 새 계정 인증·CLI 설치·새 실행 폴더 생성·원격 push·배포는 실행하지 않았다. 문서 변경이라 전체 iOS 빌드·테스트는 실행하지 않는다.
