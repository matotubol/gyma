"""Fail CI if an unsigned native IPA loses its paired Watch app or identity."""

import plistlib
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        phone_root = "Payload/Gyma.app/"
        phone = plistlib.loads(archive.read(phone_root + "Info.plist"))
        watch_roots = [
            name.removesuffix("Info.plist")
            for name in names
            if name.startswith(phone_root)
            and name.endswith(".app/Info.plist")
            and name != phone_root + "Info.plist"
        ]
        assert len(watch_roots) == 1, "Expected exactly one embedded Watch app"
        watch_root = watch_roots[0]
        watch = plistlib.loads(archive.read(watch_root + "Info.plist"))
        assert phone["CFBundleIdentifier"] == "com.mato.gyma"
        assert watch["CFBundleIdentifier"] == "com.mato.gyma.watchkitapp"
        assert watch["WKCompanionAppBundleIdentifier"] == phone["CFBundleIdentifier"]
        assert watch["WKApplication"] is True
        assert watch["WKRunsIndependentlyOfCompanionApp"] is False
        assert phone["CFBundleVersion"] == watch["CFBundleVersion"]
        assert phone["CFBundleShortVersionString"] == watch["CFBundleShortVersionString"]
        assert "iPhoneOS" in phone["CFBundleSupportedPlatforms"]
        assert "WatchOS" in watch["CFBundleSupportedPlatforms"]
        for root, info in [(phone_root, phone), (watch_root, watch)]:
            assert root + info["CFBundleExecutable"] in names, f"Missing executable in {root}"
            assert root + "PrivacyInfo.xcprivacy" in names, f"Missing privacy manifest in {root}"
        print(f"Verified native iPhone + Watch IPA: {path}")
        print(f"Companion: {watch_root} -> {phone['CFBundleIdentifier']}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_ipa.py <unsigned.ipa>")
    verify(sys.argv[1])
