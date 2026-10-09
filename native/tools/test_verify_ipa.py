"""Packaging regressions using real ZIP files and binary property lists."""

import contextlib
import io
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

from verify_ipa import verify


class VerifyIPATests(unittest.TestCase):
    phone_root = "Payload/Gyma.app/"
    watch_root = phone_root + "Watch/GymaWatch.app/"

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "gyma.ipa"

    def make_ipa(self, watch_roots=None, watch_changes=None, phone_changes=None):
        phone = {
            "CFBundleIdentifier": "com.mato.gyma",
            "CFBundleExecutable": "Gyma",
            "CFBundleVersion": "42",
            "CFBundleShortVersionString": "0.4.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
        }
        phone.update(phone_changes or {})
        watch = {
            "CFBundleIdentifier": "com.mato.gyma.watchkitapp",
            "CFBundleExecutable": "GymaWatch",
            "CFBundleVersion": "42",
            "CFBundleShortVersionString": "0.4.0",
            "CFBundleSupportedPlatforms": ["WatchOS"],
            "WKCompanionAppBundleIdentifier": "com.mato.gyma",
            "WKApplication": True,
            "WKRunsIndependentlyOfCompanionApp": False,
        }
        watch.update(watch_changes or {})
        roots = [self.watch_root] if watch_roots is None else watch_roots
        with zipfile.ZipFile(self.path, "w") as archive:
            for root, info in [(self.phone_root, phone)] + [(root, watch) for root in roots]:
                archive.writestr(root + "Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
                archive.writestr(root + info["CFBundleExecutable"], b"executable fixture")
                archive.writestr(root + "PrivacyInfo.xcprivacy", plistlib.dumps({}))

    def check(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            verify(self.path, **kwargs)

    def test_canonical_watch_bundle_passes(self):
        self.make_ipa()
        self.check(expected_build_version="42")

    def test_workout_runtime_configuration_passes(self):
        self.make_ipa(watch_changes={
            "GymaRequiresWorkoutRuntime": True,
            "NSHealthUpdateUsageDescription": "Keep your workout available and signal rest completion.",
            "WKBackgroundModes": ["workout-processing", "audio"],
        })
        self.check()

    def test_workout_runtime_requires_health_usage_description(self):
        for usage in (None, "", "  \n", False):
            with self.subTest(usage=usage):
                properties = {
                    "GymaRequiresWorkoutRuntime": True,
                    "WKBackgroundModes": ["workout-processing", "audio"],
                }
                if usage is not None:
                    properties["NSHealthUpdateUsageDescription"] = usage
                self.make_ipa(watch_changes=properties)
                with self.assertRaisesRegex(AssertionError, "NSHealthUpdateUsageDescription"):
                    self.check()

    def test_workout_runtime_requires_each_background_mode(self):
        for modes, missing in ((["audio"], "workout-processing"), (["workout-processing"], "audio"),
                               (None, "workout-processing")):
            with self.subTest(modes=modes):
                properties = {
                    "GymaRequiresWorkoutRuntime": True,
                    "NSHealthUpdateUsageDescription": "Keep your workout available.",
                }
                if modes is not None:
                    properties["WKBackgroundModes"] = modes
                self.make_ipa(watch_changes=properties)
                with self.assertRaisesRegex(AssertionError, "WKBackgroundModes " + missing):
                    self.check()

    def test_workout_runtime_rejects_background_modes_as_string(self):
        self.make_ipa(watch_changes={
            "GymaRequiresWorkoutRuntime": True,
            "NSHealthUpdateUsageDescription": "Keep your workout available.",
            "WKBackgroundModes": "workout-processing,audio",
        })
        with self.assertRaisesRegex(AssertionError, "WKBackgroundModes must be an array"):
            self.check()

    def test_old_plugins_placement_is_rejected(self):
        self.make_ipa(watch_roots=[self.phone_root + "PlugIns/GymaWatch.app/"])
        with self.assertRaisesRegex(AssertionError, "Expected exactly one Watch app"):
            self.check()

    def test_arbitrary_nested_placement_is_rejected(self):
        self.make_ipa(watch_roots=[self.phone_root + "Resources/GymaWatch.app/"])
        with self.assertRaisesRegex(AssertionError, "Expected exactly one Watch app"):
            self.check()

    def test_missing_watch_is_rejected(self):
        self.make_ipa(watch_roots=[])
        with self.assertRaisesRegex(AssertionError, "Expected exactly one Watch app"):
            self.check()

    def test_duplicate_watch_bundle_is_rejected(self):
        self.make_ipa(watch_roots=[self.watch_root, self.phone_root + "PlugIns/GymaWatch.app/"])
        with self.assertRaisesRegex(AssertionError, "Expected exactly one Watch app"):
            self.check()

    def test_wrong_companion_identity_is_rejected(self):
        self.make_ipa(watch_changes={"WKCompanionAppBundleIdentifier": "com.example.other"})
        with self.assertRaises(AssertionError):
            self.check()

    def test_mismatched_phone_watch_build_is_rejected(self):
        self.make_ipa(watch_changes={"CFBundleVersion": "41"})
        with self.assertRaises(AssertionError):
            self.check()

    def test_wrong_ci_build_version_is_rejected(self):
        self.make_ipa()
        with self.assertRaisesRegex(AssertionError, "Expected build version 43"):
            self.check(expected_build_version="43")

    def test_command_line_accepts_expected_build_version(self):
        self.make_ipa()
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("verify_ipa.py")),
             str(self.path), "--expected-build-version", "42"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.watch_root, result.stdout)


if __name__ == "__main__":
    unittest.main()
