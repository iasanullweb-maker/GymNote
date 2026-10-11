# 2026-10-11 후속 수정 배포

사용자가 ‘배포 진행해’로 0.1.99 후속 수정의 공개 배포를 승인했다. 수정 범위는 [후속 수정 결과](ux-cleanup-20261011.md)를 따른다. 운영 SQL 변경은 없다.

## 배포 준비

- 시작 main·작업 브랜치: `375165d8eb5d5e9a0f26865f6f22904e38c81ad9`. 원격 main을 fetch했으며 승인 범위 밖의 새로운 앱 변경은 없다. 기존 미추적 파일은 보존한다.
- 검증 코드: `d6897f286f1a928170111badccbec6b05acd2957`. 배포 준비까지 변경은 문서뿐이며 `git diff d6897f2 HEAD`로 실제 파일 내용을 대조했다. 앱·위젯·공유 코드·테스트·리소스·설정·서버·빌드 도구와 CI는 동일하다.
- [Validate](https://github.com/iasanullweb-maker/GymNote/actions/runs/38114590885): XCTest 124개 통과, 캡처 5개 건너뜀, 실패 0. Swift·계정 권한·격리 DB 검사 성공.
- [검증용 Build IPA](https://github.com/iasanullweb-maker/GymNote/actions/runs/38114590838): 앱·위젯 전체 Release 빌드 성공.
- 배포 준비 문서를 별도 커밋하고 통합 잠금 아래 main에 합친 뒤 승인된 main을 push한다. 실제 버전은 배포 run 번호가 확정된 후 기록한다.

## 결과

- **0.1.104/build 104 배포 완료.** SHA `8bb10dcad2a218aff6916cfed06ab9a6deb9fb1f`의 [Build IPA run 38116534197](https://github.com/iasanullweb-maker/GymNote/actions/runs/38116534197)이 성공했다. 전체 앱·위젯 Release 빌드, IPA 포장, 릴리스 게시, AltStore 갱신이 모두 success다.
- [build-104](https://github.com/iasanullweb-maker/GymNote/releases/tag/build-104)와 [latest](https://github.com/iasanullweb-maker/GymNote/releases/tag/latest)의 태그 대상은 배포 SHA와 같다. 두 IPA는 2,148,359바이트, SHA-256 `a1a18f940c41af2388ad61233e70d7c34fce1dda3b81efc17259613a4e02768c`로 일치한다. 고정 릴리스 IPA를 직접 내려받아 동일 해시를 확인했다.
- IPA 내부 앱 `com.gymnote.app`과 위젯 `com.gymnote.app.widget` 모두 버전 0.1.104/build 104다. 두 실행 파일의 ad-hoc 서명에 App Group `group.com.gymnote.app`이 포함됨을 확인했다. 설치 서명은 AltStore가 수행한다.
- 원격 altstore 커밋 `467144db3b33bc216a86f171e7c06834986f933f`의 source.json은 bundle ID·버전·빌드·크기·고정 build-104 다운로드 URL이 IPA와 일치한다.
- 운영 SQL 변경·적용은 없다. 기기 설치·실사용과 iPhone 시뮬레이터 검증은 미실행이다. 사용자 확인 8개와 기존 확인 대기는 [할 일 문서](../../../TODOLIST_HANDOFF.md)에 미완료로 유지한다. AltStore 소스를 새로고침하고 0.1.104로 업데이트한 뒤 기존 기록 보존부터 확인한다.
- 배포 후 문서는 `[skip ci]` 커밋으로 추가 앱 버전을 만들지 않는다. 문서도 검토·커밋 후 통합 잠금 아래 로컬 main에 통합한다.
