"""Create the personal, local-only IPA from the unsigned upstream artifact.

This is a defensive binary pass for the Windows handoff: it invalidates the
vendor update/feedback hosts and removes visible vendor branding. A real Swift
rebuild on macOS is still preferred; the script never claims to change protocol
identifiers used for the local Android bridge.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / ".tools/airsim-ios.ipa"
OUTPUT = ROOT / "dist/SimHelp-iPhone-personal-local.ipa"

def replace_padded(data: bytes, old: bytes, new: bytes) -> tuple[bytes, int]:
    if len(new) > len(old):
        raise ValueError((old, new))
    replacement = new + b"\0" * (len(old) - len(new))
    return data.replace(old, replacement), data.count(old)

def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    replacements = {
        # Invalid local-only destinations: URL construction/host validation fails.
        b"https://airsim-push.remotepilot.site/v1/feedback": b"about:blank",
        b"https://api.github.com/repos/kai-wu-cortex/AirSIM/releases?per_page=100": b"about:blank",
        b"https://github.com/kai-wu-cortex/AirSIM": b"about:blank",
        b"https://airsim-push.remotepilot.site": b"about:blank",
        b"https://push.remotepilot.site": b"about:blank",
        b"api.github.com": b"invalid.com",
        b"remotepilot.site": b"invalid.invalid",
        b"kai-wu-cortex": b"TheSkeezad",
        # UI/product strings only; protocol markers are uppercase AIRSIM and remain intact.
        b"AirSIM": b"SimHel",
    }
    counts = {k.decode("ascii", "ignore"): 0 for k in replacements}
    with zipfile.ZipFile(INPUT) as source, zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as target:
        app_info = next(n for n in source.namelist() if n.endswith(".app/Info.plist") and n.count("/") == 2)
        app_root = app_info.rsplit("/", 1)[0]
        for item in source.infolist():
            if "/_CodeSignature/" in item.filename or item.filename.endswith("embedded.mobileprovision"):
                continue
            data = source.read(item)
            if item.filename.endswith(".plist"):
                try:
                    info = plistlib.loads(data)
                    def clean(value):
                        if isinstance(value, str):
                            for old, new in (("https://airsim-push.remotepilot.site", "about:blank"),
                                              ("https://api.github.com", "about:blank"),
                                              ("https://github.com/kai-wu-cortex/AirSIM", "about:blank"),
                                              ("airsim-push.remotepilot.site", "")):
                                value = value.replace(old, new)
                            return value
                        if isinstance(value, dict): return {clean(k): clean(v) for k, v in value.items()}
                        if isinstance(value, list): return [clean(v) for v in value]
                        return value
                    info = clean(info)
                    if item.filename == app_info:
                        info["CFBundleDisplayName"] = "SimHelp"
                        info["CFBundleName"] = "SimHelp"
                        info["CFBundleDevelopmentRegion"] = "en"
                        info["SimHelpAuthor"] = "TheSkeezad"
                    data = plistlib.dumps(info, fmt=plistlib.FMT_XML)
                except Exception:
                    pass
            if item.filename != app_info and not item.filename.endswith(".plist"):
                for old, new in replacements.items():
                    data, count = replace_padded(data, old, new)
                    counts[old.decode("ascii", "ignore")] += count
            target.writestr(item, data)
        target.writestr(app_root + "/SimHelpLicenses/PROVENANCE.txt",
                        "SimHelp personal local-only handoff.\n"
                        "The iOS executable was not rebuilt on Windows; this pass invalidates vendor update/feedback URLs and changes metadata/branding.\n"
                        "For a fully rebuilt release, build the modified Swift source on macOS with Xcode.\n"
                        "Author: TheSkeezad\n")
        for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"):
            target.write(ROOT / "upstream-airsim" / name, app_root + "/SimHelpLicenses/" + name)
    with zipfile.ZipFile(OUTPUT) as check:
        info = plistlib.loads(check.read(app_info))
        assert info["CFBundleDisplayName"] == "SimHelp"
        blob = b"".join(check.read(n) for n in check.namelist() if n.startswith(app_root + "/"))
        forbidden = [x for x in (b"airsim-push.remotepilot.site", b"api.github.com", b"kai-wu-cortex") if x in blob]
        if forbidden:
            raise RuntimeError("forbidden external strings remain: " + repr(forbidden))
    report = {
        "input": str(INPUT), "output": str(OUTPUT),
        "input_sha256": hashlib.sha256(INPUT.read_bytes()).hexdigest(),
        "output_sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "replacement_counts": counts,
        "network_policy": "external vendor update and feedback destinations invalidated; local pairing only",
        "swift_rebuilt": False,
        "author": "TheSkeezad",
    }
    (OUTPUT.parent / "SimHelp-iPhone-personal-local.audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
