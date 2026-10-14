"""Fail CI if an unsigned native IPA loses its paired Watch app or identity."""

import argparse
import plistlib
import zipfile


def verify(path, expected_build_version=None):
    with zipfile.ZipFile(path) as archive:
        entries = archive.namelist()
        names = set(entries)
        assert len(entries) == len(names), "Duplicate ZIP entry names"
        phone_root = "Payload/Gyma.app/"
        watch_root = phone_root + "Watch/GymaWatch.app/"
        phone = plistlib.loads(archive.read(phone_root + "Info.plist"))
        embedded_app_roots = set()
        for name in names:
            if not name.startswith(phone_root):
                continue
            parts = name.removeprefix(phone_root).split("/")
            for index, part in enumerate(parts[:-1]):
                if part.endswith(".app"):
                    embedded_app_roots.add(phone_root + "/".join(parts[: index + 1]) + "/")
        assert embedded_app_roots == {watch_root}, (
            "Expected exactly one Watch app at " + watch_root
            + "; found " + repr(sorted(embedded_app_roots))
        )
        watch = plistlib.loads(archive.read(watch_root + "Info.plist"))
        assert phone["CFBundleIdentifier"] == "com.mato.gyma"
        assert watch["CFBundleIdentifier"] == "com.mato.gyma.watchkitapp"
        assert watch["WKCompanionAppBundleIdentifier"] == phone["CFBundleIdentifier"]
        assert watch["WKApplication"] is True
        assert watch["WKRunsIndependentlyOfCompanionApp"] is False
        if watch.get("GymaRequiresWorkoutRuntime") is True:
            usage = watch.get("NSHealthUpdateUsageDescription")
            assert isinstance(usage, str) and usage.strip(), (
                "Watch workout runtime requires a nonempty NSHealthUpdateUsageDescription"
            )
            modes = watch.get("WKBackgroundModes", [])
            assert isinstance(modes, list), "Watch WKBackgroundModes must be an array"
            for mode in ("workout-processing", "audio"):
                assert mode in modes, f"Watch workout runtime requires WKBackgroundModes {mode}"
        assert phone["CFBundleVersion"] == watch["CFBundleVersion"]
        if expected_build_version is not None:
            assert phone["CFBundleVersion"] == str(expected_build_version), (
                f"Expected build version {expected_build_version}, found {phone['CFBundleVersion']}"
            )
        assert phone["CFBundleShortVersionString"] == watch["CFBundleShortVersionString"]
        assert "iPhoneOS" in phone["CFBundleSupportedPlatforms"]
        assert "WatchOS" in watch["CFBundleSupportedPlatforms"]
        for root, info in [(phone_root, phone), (watch_root, watch)]:
            assert root + info["CFBundleExecutable"] in names, f"Missing executable in {root}"
            assert root + "PrivacyInfo.xcprivacy" in names, f"Missing privacy manifest in {root}"
        print(f"Verified native iPhone + Watch IPA: {path}")
        print(f"Companion: {watch_root} -> {phone['CFBundleIdentifier']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", help="Path to the unsigned native IPA")
    parser.add_argument("--expected-build-version", help="Required CFBundleVersion (for example, the CI run number)")
    args = parser.parse_args()
    verify(args.ipa, expected_build_version=args.expected_build_version)
