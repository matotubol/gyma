# Unofficial iLoader 2.3.6 with Watch support

This is a custom Windows build for installing Gyma's paired iPhone and Apple Watch apps. It is not an official iLoader release and is not endorsed by the upstream authors. The official project is [nab138/iloader](https://github.com/nab138/iloader).

The build keeps version 2.3.6, labels the UI as an unofficial Watch build, and disables automatic updates. It keeps the existing application identifier so installed iLoader settings remain available. Enter Apple Account credentials only in the desktop application; GitHub Actions receives no Apple credentials and produces the Windows tool, not a device-signed IPA.

## Pinned sources

| Component | Source revision |
| --- | --- |
| iLoader 2.3.6 | `nab138/iloader@dc396af059fd46982062cd8fc90252d7e27085e9` |
| isideload 0.4.3 | `nab138/isideload@c23db688c7f6079413bf82dad4e4f19e5ddf4ce7` |
| Watch implementation reference | `Rzbck/isideload@f7b9f3da570edd6824c29680545e710846d07df5` |
| Windows transport reference | `Rzbck/iloader@70f37e9b4afc659ab44ec1944c034093f4cda416` |

Watch support is adapted from the [iLoader Watch companion project](https://github.com/Rzbck/iloader-watch-companion), retaining the newer generic Sideloader API and apple-codesign-quick signer. Both upstream code projects are MIT licensed; their license notices and iLoader's branding notice are included in the build artifact.

## What the patches do

- Discover embedded `Watch/*.app` bundles and their extensions.
- Rewrite the phone, Watch and extension identifiers and companion references together.
- Register the paired Watch and provision each bundle using its device platform.
- Sign the Watch with its own profile and entitlements before sealing the phone app.
- Install directly through the paired iPhone, preserving the selected USB connection and checking the forwarded Watch identity.
- Update an installed Watch app in place; remove only an explicitly identified installation placeholder.

Exactly one paired Watch is supported. Gyma does not request HealthKit entitlements. Tests cover bundle discovery, identifier relationships, persisted plists, and provisioning/platform selection. Physical installation and app launch must still be checked on the actual paired devices; passing a Windows build cannot establish that Apple accepted a particular account's profiles.

## Build and install

Push changes to these patches on `swift` to run **iLoader 2.3.6 Watch build**, or dispatch `.github/workflows/iloader-watch.yml`. The workflow checks out the pinned sources into sibling directories, applies both patches, tests the backend, verifies the dependency resolution, and builds the NSIS installer with locked Rust and frontend dependencies.

Download `iloader-2.3.6-watch-windows-x64-<run number>`. The artifact includes the installer, SHA-256 hashes, patches, source provenance and license notices. Install it and confirm the window says **Unofficial Watch build**. Connect the paired iPhone by USB, select its USB entry, keep the Watch unlocked nearby with Developer Mode enabled, and select Gyma's combined `gyma-swift-unsigned.ipa`.

Do not manually append an Apple team identifier to Gyma's source bundle identifiers. The signing tool derives the identifiers from the account used at installation time.
