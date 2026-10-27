"""Fail CI if the unsigned iPhone IPA is malformed or loses its identity."""

import argparse
import plistlib
import zipfile


def verify(path, expected_build_version=None):
    with zipfile.ZipFile(path) as archive:
        entries = archive.namelist()
        names = set(entries)
        assert len(entries) == len(names), "Duplicate ZIP entry names"
        root = "Payload/Gyma.app/"
        info = plistlib.loads(archive.read(root + "Info.plist"))
        nested = sorted({
            name[: name.index(".app/", len(root)) + 5]
            for name in names
            if name.startswith(root) and ".app/" in name[len(root):]
        })
        assert not nested, "Unexpected embedded apps: " + repr(nested)
        assert info["CFBundleIdentifier"] == "com.mato.gyma"
        assert "iPhoneOS" in info["CFBundleSupportedPlatforms"]
        if expected_build_version is not None:
            assert info["CFBundleVersion"] == str(expected_build_version), (
                f"Expected build version {expected_build_version}, found {info['CFBundleVersion']}"
            )
        assert root + info["CFBundleExecutable"] in names, "Missing executable"
        assert root + "PrivacyInfo.xcprivacy" in names, "Missing privacy manifest"
        assert root + "Assets.car" in names, "Missing compiled asset catalog (app icon)"
        print(f"Verified iPhone IPA: {path} ({info['CFBundleShortVersionString']} build {info['CFBundleVersion']})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", help="Path to the unsigned IPA")
    parser.add_argument("--expected-build-version", help="Required CFBundleVersion (for example, the CI run number)")
    args = parser.parse_args()
    verify(args.ipa, expected_build_version=args.expected_build_version)
