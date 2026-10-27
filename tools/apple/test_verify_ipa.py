"""Packaging regressions using real ZIP files and binary property lists."""

import contextlib
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from verify_ipa import verify


class VerifyIPATests(unittest.TestCase):
    root = "Payload/Gyma.app/"

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "gyma.ipa"

    def make_ipa(self, changes=None, extra=(), skip=()):
        info = {
            "CFBundleIdentifier": "com.mato.gyma",
            "CFBundleExecutable": "Gyma",
            "CFBundleVersion": "42",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
        }
        info.update(changes or {})
        files = {
            "Info.plist": plistlib.dumps(info, fmt=plistlib.FMT_BINARY),
            "Gyma": b"executable fixture",
            "PrivacyInfo.xcprivacy": plistlib.dumps({}),
            "Assets.car": b"assets fixture",
        }
        with zipfile.ZipFile(self.path, "w") as archive:
            for name, data in files.items():
                if name not in skip:
                    archive.writestr(self.root + name, data)
            for name in extra:
                archive.writestr(self.root + name, b"x")

    def check(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            verify(self.path, **kwargs)

    def test_canonical_ipa_passes(self):
        self.make_ipa()
        self.check(expected_build_version="42")

    def test_rejects_wrong_build_version(self):
        self.make_ipa()
        with self.assertRaisesRegex(AssertionError, "Expected build version"):
            self.check(expected_build_version="43")

    def test_rejects_wrong_bundle_identifier(self):
        self.make_ipa({"CFBundleIdentifier": "com.example.other"})
        with self.assertRaises(AssertionError):
            self.check()

    def test_rejects_embedded_apps(self):
        self.make_ipa(extra=["Watch/GymaWatch.app/Info.plist"])
        with self.assertRaisesRegex(AssertionError, "Unexpected embedded apps"):
            self.check()

    def test_requires_executable_privacy_manifest_and_assets(self):
        for name, message in [("Gyma", "executable"), ("PrivacyInfo.xcprivacy", "privacy"), ("Assets.car", "asset")]:
            with self.subTest(name=name):
                self.make_ipa(skip={name})
                with self.assertRaisesRegex(AssertionError, message):
                    self.check()


if __name__ == "__main__":
    unittest.main()
