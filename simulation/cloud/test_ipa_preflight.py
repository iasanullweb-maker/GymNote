import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from ipa_preflight import inspect_ipa

class PreflightTests(unittest.TestCase):
    def test_metadata_and_rejections(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "test.ipa"
            baseline = {"CFBundleExecutable": "GymNote", "CFBundleIdentifier": "com.gymnote.app", "CFBundleShortVersionString": "0.1.88", "UIDeviceFamily": [1,2], "CFBundleSupportedPlatforms": ["iPhoneOS"]}
            cases = [(baseline, None), (dict(baseline, CFBundleSupportedPlatforms=["iPhoneSimulator"]), "device build"), (dict(baseline, UIDeviceFamily=[1]), "iPad support"), (dict(baseline, CFBundleExecutable="Missing"), "missing")]
            for info, error in cases:
                with self.subTest(error=error):
                    with zipfile.ZipFile(path, "w") as archive:
                        archive.writestr("Payload/GymNote.app/Info.plist", plistlib.dumps(info))
                        archive.writestr("Payload/GymNote.app/GymNote", b"synthetic-placeholder")
                    if error:
                        with self.assertRaisesRegex(ValueError, error):
                            inspect_ipa(path)
                    else:
                        report=inspect_ipa(path)
                        self.assertEqual(report["cloudInstallation"], "not-tested")
                        self.assertEqual(len(report["sha256"]),64)
                        self.assertEqual(report["version"],"0.1.88")
            with zipfile.ZipFile(path,"a") as archive:
                archive.writestr("Payload/Other.app/Info.plist", b"other")
            with self.assertRaisesRegex(ValueError,"exactly one"):
                inspect_ipa(path)

if __name__ == "__main__":
    unittest.main()
