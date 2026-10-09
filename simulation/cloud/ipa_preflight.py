"""Read-only IPA metadata check before real iPad cloud installation."""
import argparse
import hashlib
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path


def inspect_ipa(path):
    path = Path(path)
    if not path.is_file():
        raise ValueError("IPA file not found")
    if path.stat().st_size > 1_000_000_000:
        raise ValueError("IPA exceeds conservative 1 GB upload limit")
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        roots = [n for n in names if re.fullmatch(r"Payload/[^/]+[.]app/Info[.]plist", n)]
        if len(roots) != 1:
            raise ValueError("Expected exactly one main application Info.plist")
        info_entry = archive.getinfo(roots[0])
        if info_entry.file_size > 1_000_000:
            raise ValueError("Unexpectedly large Info.plist")
        info = plistlib.loads(archive.read(info_entry))
        prefix = roots[0][:-len("Info.plist")]
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable or "/" in executable or "\\" in executable:
            raise ValueError("Invalid application executable name")
        if prefix + executable not in names:
            raise ValueError("Main application executable is missing")
        families = info.get("UIDeviceFamily", [])
        platforms = info.get("CFBundleSupportedPlatforms", [])
        warnings = ["Metadata checks do not prove BrowserStack installation or execution.",
                    "Re-signing can change App Group, widget, notification, or keychain behavior."]
        if "iPhoneOS" not in platforms:
            raise ValueError("Expected an iPhoneOS device build; simulator builds are not accepted")
        if 2 not in families:
            raise ValueError("App does not declare iPad support")
        provisioned = prefix + "embedded.mobileprovision" in names
        if not provisioned:
            warnings.append("No embedded provisioning profile; cloud re-signing must be verified.")
        report = {"formatVersion": 1, "bundleId": info.get("CFBundleIdentifier"),
                  "version": info.get("CFBundleShortVersionString"),
                  "build": info.get("CFBundleVersion"),
                  "minimumOS": info.get("MinimumOSVersion"),
                  "deviceFamilies": families, "supportedPlatforms": platforms,
                  "hasProvisioningProfile": provisioned,
                  "extensions": sorted(n for n in names if n.startswith(prefix + "PlugIns/") and n.endswith(".appex/Info.plist")),
                  "bytes": path.stat().st_size, "sha256": None,
                  "cloudInstallation": "not-tested", "warnings": warnings}
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    report["sha256"] = digest.hexdigest()
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(inspect_ipa(args.ipa), ensure_ascii=False, indent=2))
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
