# Unofficial iLoader 2.3.8 with Watch support

This is a custom Windows build for installing Gyma's paired iPhone and Apple Watch apps. It is not an official iLoader release and is not endorsed by the upstream authors. The official project is [nab138/iloader](https://github.com/nab138/iloader).

The build keeps version 2.3.8, labels the UI as an unofficial Watch build, and disables automatic updates. It keeps the existing application identifier so installed iLoader settings remain available. Enter Apple Account credentials only in the desktop application; GitHub Actions receives no Apple credentials and produces the Windows tool, not a device-signed IPA.

## Upstream fixes in 2.3.8

This port includes the [upstream 2.3.8 release](https://github.com/nab138/iloader/releases/tag/v2.3.8) and its matching isideload 0.4.6 backend. It retains the authentication/503 fixes and the corrected pairing-file names for StikDebug and SideStore. Upstream requires a new authentication with 2FA and migrates unsupported custom anisette servers to its supported server list. Trusted-device 2FA works; upstream still lists SMS 2FA as broken. Normal launches use this new upstream authentication path; optional diagnostics remain opt-in.

## Pinned sources

| Component | Source revision |
| --- | --- |
| iLoader 2.3.8 | `nab138/iloader@cc5b168ee5e39693e3e8f4a7e591ec5e0766b6d4` |
| isideload 0.4.6 | `nab138/isideload@8ca39b6203263e539408986e546c42e7c1cc3699` |
| Watch implementation reference | `Rzbck/isideload@f7b9f3da570edd6824c29680545e710846d07df5` |
| Windows transport reference | `Rzbck/iloader@70f37e9b4afc659ab44ec1944c034093f4cda416` |

Watch support is adapted from the [iLoader Watch companion project](https://github.com/Rzbck/iloader-watch-companion), retaining the newer generic Sideloader API and apple-codesign-quick signer. Both upstream code projects are MIT licensed; their license notices and iLoader's branding notice are included in the build artifact.

The backend revision is the source SHA recorded in the published isideload 0.4.6 crate's `.cargo_vcs_info.json`.

## What the patches do

- Discover embedded `Watch/*.app` bundles and their extensions.
- Rewrite the phone, Watch and extension identifiers and companion references together.
- Register the paired Watch and provision each bundle using its device platform.
- Sign the Watch with its own profile and entitlements before sealing the phone app.
- Install directly through the paired iPhone, preserving the selected USB connection and checking the forwarded Watch identity.
- Update an installed Watch app in place; remove only an explicitly identified installation placeholder.

Exactly one paired Watch is supported. Gyma 0.5.1 uses HealthKit workout runtime for wrist-down rest vibration and the system workout indicator. The installer enables HealthKit for Watch bundles that declare Health usage or Gyma's runtime marker, then verifies that the downloaded Watch profile grants the entitlement before signing. Tests cover bundle discovery, identifier relationships, persisted plists, HealthKit capability checks, and provisioning/platform selection. Physical installation and app launch must still be checked on the actual paired devices; passing a Windows build cannot establish that Apple accepted a particular account's profiles.

## Build locally on Windows

Future iLoader builds run locally on this PC. Rebuild the installer only when its patches change; ordinary Gyma app changes need a new IPA, not a new iLoader installer. GitHub Actions is a manually dispatched fallback, used only when explicitly requested.

From the Gyma repository in **64-bit PowerShell 7**, check readiness without starting a build:

```powershell
pwsh -NoProfile -File .\tools\iloader\build-local.ps1 -CheckPrerequisites
```

The helper requires Git, current Rust with the `x86_64-pc-windows-msvc` standard library, Bun, Visual Studio C++ x64/x86 tools, a Windows 10/11 SDK, Perl, and GNU make. It discovers and activates an existing Visual Studio installation through `vswhere`, and reuses the portable Perl and GNU make tools in `.local/device-tools/strawberry-perl/` when present. It does not install tools or SDKs. Missing prerequisites produce specific instructions. `-Preflight` is an alias for `-CheckPrerequisites`.

Existing portable tools can be supplied on `PATH`, or with `-ToolDirectories` when calling the script from PowerShell:

```powershell
.\tools\iloader\build-local.ps1 -CheckPrerequisites -ToolDirectories @(
    'C:\path\to\portable-perl\perl\bin',
    'C:\path\to\gnu-make\bin'
)
```

Once the check passes, build:

```powershell
pwsh -NoProfile -File .\tools\iloader\build-local.ps1
```

Pass the same `-ToolDirectories` paths to the build if needed. The helper checks out the pinned upstream revisions in fresh sibling directories, snapshots and applies the current patches, verifies that Cargo selects the custom backend and a single `idevice` version, runs the locked release backend tests, installs frozen Bun dependencies, and builds the x64 NSIS installer. Failed commands stop the build. No Apple credentials or device connection are needed for compilation.

By default, `.local/iloader/` holds reusable local state:

- `cache/cargo-target/` and `cache/bun/`: persistent build and download caches. Existing Cargo registry/git caches are also reused.
- `sources/<run>/`: fresh checkouts and the exact patch inputs for each run, retained on success and failure. Existing checkouts and local source edits are never overwritten or reset.
- `native/`: the separately compiled native anisette helper.
- `diagnostics/<session>/`: opt-in diagnostic session copies and traces.

Finished installers go to `build/iloader/<run>/`, with SHA-256 checksums, build provenance, exact patches, dependency lockfiles, and upstream license notices. Both roots are resolved relative to this script, so the defaults work from any working directory.

Use `-BuildRoot 'D:\build-cache\iloader-watch'` to choose another cache/source location. An explicitly supplied `-BuildRoot` keeps artifacts under `<BuildRoot>/artifacts/<run>/` for compatibility. Use `-ArtifactsRoot 'D:\installers\iloader'` to override the artifact location independently, with either the default or a custom build root. These options configure the local installer builder; the separate native-helper and diagnostics scripts retain their own path options and defaults.

Only one build can use a given build root at a time. The helper accounts for the explicit Cargo target directory when finding the installer and refuses to package an old cached installer. It does not automatically delete sources or caches. `-SelfTest` checks path resolution, custom-root compatibility, and dependency-validation logic without fetching sources or compiling. Existing local caches were preserved during the project reorganization; ordinary Gyma app changes do not require rebuilding them.

## Install

### Optional authentication diagnostics

The custom backend supports a local, opt-in diagnostic trace for investigating Apple login failures. Build with the normal local helper, then start a baseline session:

```powershell
pwsh -NoProfile -File .\tools\iloader\start-diagnostics.ps1
```

The launcher gracefully restarts this custom iLoader as a session copy, leaving the Cargo executable available for future builds. Enter credentials and 2FA only in iLoader. Each session is saved under `.local/iloader/diagnostics/`; `auth.jsonl` appears when a GrandSlam login request starts. It records request field types, allowlisted public client information, HTTP status, and numeric Apple errors. It excludes credential values, anisette values, account/device identifiers, tokens, and response bodies. TLS verification stays enabled. The separate ordinary iLoader logs are not covered by this diagnostic redaction.

Baseline preserves the existing login request. For a controlled comparison, `-Experiment cpd-booleans` changes only the four CPD flags from strings to plist booleans. `-Experiment authkit-user-agent` changes only the User-Agent to the AuthKit string used in SideStore's AltSign; its CPD flags retain baseline string types. These are separate investigation options, not verified fixes for `-80045`. Return to the default baseline to compare behavior. Sessions do not automatically submit credentials or retry login, and the launcher does not change saved anisette settings. Launching iLoader normally disables these opt-in diagnostics and experiments.

`-Experiment cpd-metadata` uses boolean CPD flags and adds the existing provider's local-user and routing information plus a fresh whole-second UTC timestamp, UTC timezone, and matching `en_US` locale. Other headers, the provisioned identity, and authentication behavior remain at baseline. It does not invent a serial number. This compares a more complete CPD structure in one attempt; a changed result needs further isolation before becoming a default fix.

The separate `build-native-anisette-helper.ps1` compiles an x86 helper against the existing Windows SDK, without running it. `-Experiment windows-native-anisette` uses that helper to obtain MID/OTP from installed Apple libraries through a private in-memory pipe. The profile retains baseline client headers, existing provisioned identity, and remote routing metadata, changing only MID/OTP. It still needs the existing remote server and state. It is a hybrid comparison, not a complete native Windows identity; failure cannot establish whether a coherent native client would work. The launcher copies the helper into its session directory and records its hash. Never run the helper directly in a terminal or redirect its authentication output to a file. The standalone helper has AGPL-3.0-only attribution in its source.

`-Experiment windows-native-identity` obtains the client description, device ID, local-user ID, MID and OTP from the installed Windows Apple libraries, with routing information `84215040`. It uses the native getter approach from [AltServer's February 2026 fix for -22410](https://github.com/rileytestut/AltServer-Windows/commit/e91915d11068e62cd17a9290776afeeb744b9c03), plus complete CPD metadata and boolean flags. This profile does not use the remote anisette service or its saved provisioning state. The helper verifies the supported `iCloud_main.dll` SHA-256 before resolving its private methods; an unsupported binary fails without falling back. This is still an experimental comparison, not a verified fix for current Apple authentication failures. Native identity values remain excluded from diagnostic traces.

With the 2.3.8 backend, both native experiments stop if Apple requests server resynchronization. The hybrid `windows-native-anisette` experiment also stops if saved provisioning needs replacement. Restart in baseline mode to use upstream recovery; neither native experiment silently falls back.

### Device installation

Use `iloader-2.3.8-watch-windows-x64.exe` from the printed local artifact directory. For an explicitly requested GitHub build, download `iloader-2.3.8-watch-windows-x64-<run number>` from **iLoader 2.3.8 Watch build**. Both outputs include checksums, provenance, patches, and license notices.

Install it and confirm the window says **Unofficial Watch build**. Connect the paired iPhone by USB, select its USB entry, keep the Watch unlocked nearby with Developer Mode enabled, and select Gyma's combined `gyma-swift-unsigned.ipa`.

Do not manually append an Apple team identifier to Gyma's source bundle identifiers. The signing tool derives the identifiers from the account used at installation time.
