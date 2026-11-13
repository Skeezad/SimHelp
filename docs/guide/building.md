# Building SimHelp

## Android on Windows

Requirements: Python 3.11+, `curl.exe`, a Java toolchain that supports Java 17, and Android SDK platform/build tools. The builder verifies dependency checksums before compilation.

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_SDK_ROOT = "$env:LOCALAPPDATA\Android\Sdk"
python scripts/build_android.py
```

The builder compiles `apps/android/phone-control/src` and `apps/android/audio-bridge/src`, and uses `apps/android/standalone/AndroidManifest.xml`. It also includes source and dependency license notices in the APK.

Output: `dist/SimHelp-Android.apk`.

Local downloads: `.local/dependencies/`. Build intermediates: `build/android/`.

### Signing

The default personal signing key is `.local/keys/simhelp-personal.keystore`. If it does not exist, the builder creates it using the local personal-build configuration. It is ignored by Git.

To use an existing compatible personal key:

```powershell
$env:SIMHELP_KEYSTORE = "C:\private\simhelp-personal.keystore"
python scripts/build_android.py
```

The personal builder uses the configured personal-key password convention in the script. For other signing credentials, use the release-signing options in the component shell builder. Preserve your key securely: an update must use the same application ID and certificate as the installed app. Never upload signing keys or passwords to the repository.

### Android component shell builder

```sh
sh apps/android/standalone/build.sh
```

This builder has its own SDK/JDK defaults and signing options. Read its configuration before using it outside the Windows workflow.

## iPhone using GitHub Actions

The `Build SimHelp iOS IPA` workflow checks English text, builds the `SimHelp` scheme from `apps/ios/SimHelp.xcodeproj`, packages the phone app, removes the optional Watch companion, and uploads the unsigned IPA artifact.

No local Mac is needed to run this workflow. Sideloading still requires signing the downloaded IPA.

## iPhone on macOS

Open `apps/ios/SimHelp.xcodeproj`, select the `SimHelp` scheme, and configure your own signing team for device installation. Command-line unsigned builds can follow the settings in `.github/workflows/simhelp-ios-unsigned.yml`.

## Source checks

```sh
python scripts/check_android_text.py
python scripts/audit_ios_english.py
```

Additional component tests remain alongside their sources. Some historical tests assert earlier wording or deployment assumptions; treat the current app build and device behavior as separate validation steps.
