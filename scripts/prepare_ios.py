"""Repackage the matching upstream unsigned sideload client; does NOT compile Swift.

Preserves the app executable and its internal protocol. Signing is done by the
user's sideloader. Does not create APNs credentials or promise background push.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / ".tools/airsim-ios.ipa"
OUTPUT = ROOT / "dist/SimHelp-iPhone-unsigned.ipa"


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(INPUT) as source:
        plists = [p for p in source.namelist() if p.startswith("Payload/")
                  and p.count("/") == 2 and p.endswith(".app/Info.plist")]
        if len(plists) != 1:
            raise ValueError("Expected exactly one top-level iOS app")
        info_path = plists[0]
        app_path = info_path.rsplit("/", 1)[0]
        info = plistlib.loads(source.read(info_path))
        executable = f"{app_path}/{info['CFBundleExecutable']}"
        original_hash = hashlib.sha256(source.read(executable)).hexdigest()
        info["CFBundleDisplayName"] = "SimHelp"
        info["CFBundleName"] = "SimHelp"
        # Bundle ID/entitlements remain aligned for the sideloader to rewrite.
        info["NSMicrophoneUsageDescription"] = "برای مکالمه از طریق سیم‌کارت گوشی اندروید شما."
        info["NSLocalNetworkUsageDescription"] = "برای اتصال امن آیفون به گوشی اندروید روی وای‌فای یا هات‌اسپات."
        info["NSBluetoothAlwaysUsageDescription"] = "برای اتصال محلی به گوشی اندروید شما."
        info["NSContactsUsageDescription"] = "برای نمایش نام مخاطبان در تماس‌ها و پیامک‌ها."
        with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as out:
            for entry in source.infolist():
                if "/_CodeSignature/" in entry.filename or entry.filename.endswith("embedded.mobileprovision"):
                    continue
                data = plistlib.dumps(info) if entry.filename == info_path else source.read(entry)
                out.writestr(entry, data)
            for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"):
                out.write(ROOT / "upstream-airsim" / name, app_path + "/SimHelpLicenses/" + name)
            out.writestr(app_path + "/SimHelpLicenses/PROVENANCE.txt",
                         "SimHelp personal adaptation of AirSIM. iOS executable from upstream v0.9.8.21 build 162.\n"
                         "Metadata repackaging only; Swift was not rebuilt on Windows.\n"
                         "https://github.com/kai-wu-cortex/AirSIM\n")
    with zipfile.ZipFile(OUTPUT) as check:
        assert hashlib.sha256(check.read(executable)).hexdigest() == original_hash
        assert plistlib.loads(check.read(info_path))["CFBundleDisplayName"] == "SimHelp"
        assert not any("/_CodeSignature/" in p for p in check.namelist())
        minimum = info.get("MinimumOSVersion", "unknown")
    result = {"source_release": "v0.9.8.21", "ios_build": "162", "minimum_ios": minimum,
              "swift_rebuilt": False, "executable_sha256": original_hash,
              "input_sha256": hashlib.sha256(INPUT.read_bytes()).hexdigest(),
              "output_sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest()}
    (OUTPUT.parent / "ios-provenance.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {OUTPUT}; minimum iOS {minimum}; executable unchanged")


if __name__ == "__main__":
    main()
