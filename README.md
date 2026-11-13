# SimHelp

A personal phone bridge maintained by **TheSkeezad**. Keep the physical SIM in an Android phone and use the paired iPhone for calls and SMS.

This repository is private. Its visibility does not change the source license or required notices.

## What is included

- **iPhone app:** Keypad, Recents, Messages, Contacts, and Settings; English interface and permission explanations.
- **Android app:** setup, permissions, pairing, call and SMS handling, and the Shizuku audio bridge.
- **Local connectivity:** pairing and direct connections over a shared network, with optional Bluetooth support.
- **Optional services:** relay and gateway sources for advanced deployments. They require separate configuration.

Call audio depends on the Android device and its firmware. Galaxy A12 / Android 12 two-way audio has not been verified in a real call. A connected service or successful build does not establish audio compatibility.

## Repository layout

```text
apps/
  android/
    standalone/       Android application manifest and entry-point build scripts
    phone-control/    Android UI, phone/SMS integration, and connection services
    audio-bridge/     Android call-audio bridge
  ios/
    SimHelp/          iPhone application
    SimHelp.xcodeproj Xcode project and shared scheme
    Shared/           Shared models and presentation helpers
    SimHelpLiveActivityExtension/
    SimHelpWatchApp/   Optional Watch target; omitted from the sideloaded IPA
services/
  relay/              Optional relay worker and self-hosted deployment sources
  gateway/            Gateway agent, installer, and packaging tools
scripts/              Build and source-validation utilities
docs/                 Setup guides and technical reference
  archive/            Earlier implementation notes; not the current setup guide
.github/workflows/    GitHub Actions builds
LICENSE               Source license
NOTICE                Required source attribution
THIRD_PARTY_NOTICES.md Dependency licenses and notices
```

Compiled apps, private signing keys, dependency downloads, and local logs are excluded from Git. Local tools belong in `.local/`, build intermediates in `build/`, and installable files in `dist/`.

## Start here

1. Read [Setup](docs/guide/setup.md) for Android and iPhone installation and pairing.
2. Read [Building](docs/guide/building.md) to generate an APK or unsigned IPA.
3. Read [Architecture](docs/guide/architecture.md) for the components, connection modes, and compatibility details.

Use the current setup guide instead of archived release instructions. Historical documents describe additional configurations that may not apply to this personal build.

## Quick build

### Android on Windows

Install Python 3.11+, a JDK capable of compiling Java 17, and Android SDK platform/build tools. Android Studio's bundled JDK and the SDK under `%LOCALAPPDATA%\Android\Sdk` are used by default.

```powershell
python scripts/check_android_text.py
python scripts/build_android.py
```

Output: `dist/SimHelp-Android.apk`. Keep the same signing key when building updates for an installed copy. See [Building](docs/guide/building.md) for environment variables and signing details.

### iPhone without a local Mac

Open **Actions → Build SimHelp iOS IPA → Run workflow**. After a successful run, download the **SimHelp-iPhone-unsigned** artifact, extract the IPA, and sign/install it with Sideloadly or a compatible sideloading tool.

The workflow uses a macOS runner. The unsigned IPA cannot be installed directly without signing. Apple ID provisioning and device support depend on the signing tool and account.

## Verification

```powershell
python scripts/check_android_text.py
python scripts/audit_ios_english.py
```

The Android check rejects accidental `Text Text` placeholders. The iOS check checks Swift string structure and rejects untranslated Chinese/Japanese text in source literals and permission explanations. These checks supplement compilation; they do not replace testing on real phones.

## Naming and compatibility

App names, project files, source folders, and the main documentation use SimHelp. Some internal authentication labels, discovery identifiers, and stored preference keys retain their existing values for compatibility. Changing those values independently can prevent already paired devices from communicating.

## License and attribution

Personal adaptations are maintained by **TheSkeezad**. The source is governed by [PolyForm Noncommercial 1.0.0](LICENSE). Required attribution remains in [NOTICE](NOTICE), and dependency notices remain in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Repository privacy and application branding do not replace those terms.
