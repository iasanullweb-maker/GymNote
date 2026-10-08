"""AltStore 소스(source.json) 만들기.

GitHub Actions에서 빌드가 끝난 뒤 실행됨.
사용법: python3 scripts/make_source.py <ipa 경로> <버전> <빌드 번호> <다운로드 URL> <출력 경로>
"""
import json
import os
import sys
from datetime import datetime, timezone

ipa, version, build, url, out = sys.argv[1:6]
repo = os.environ.get("GITHUB_REPOSITORY", "iasanullweb-maker/GymNote")
raw = f"https://raw.githubusercontent.com/{repo}/main"

source = {
    "name": "헬스노트",
    "subtitle": "개인용 헬스 보조 앱",
    "description": "헬스노트 개인 배포용 AltStore 소스",
    "iconURL": f"{raw}/docs/icon.png",
    "website": f"https://github.com/{repo}",
    "tintColor": "#F07A2E",
    "nsfw": False,
    "featuredApps": ["com.gymnote.app"],
    "apps": [
        {
            "name": "헬스노트",
            "bundleIdentifier": "com.gymnote.app",
            "developerName": "iasanullweb-maker",
            "subtitle": "루틴, 세트 체크 위젯, 휴식 타이머, 최고 기록",
            "localizedDescription": (
                "요일별 루틴과 세트 체크, 홈·잠금 화면 위젯, "
                "잠금 화면 휴식 타이머, 최고 기록과 그래프."
            ),
            "iconURL": f"{raw}/docs/icon.png",
            "tintColor": "#F07A2E",
            "category": "utilities",
            "versions": [
                {
                    "version": version,
                    "buildVersion": build,
                    "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "localizedDescription": f"빌드 #{build}",
                    "downloadURL": url,
                    "size": os.path.getsize(ipa),
                    "minOSVersion": "17.0",
                }
            ],
            "appPermissions": {
                "entitlements": ["com.apple.security.application-groups"],
                "privacy": {},
            },
        }
    ],
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(json.dumps(source, ensure_ascii=False, indent=2))
