"""Remove Telegram's notch badge from source, or package its built IPA for sideloading."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile


SOURCE_PATH = Path("submodules/Display/Source/WindowContent.swift")
ORIGINAL = 'self.badgeView.image = UIImage(bundleImageName: "Components/AppBadge")'
REPLACEMENT = 'self.badgeView.image = nil // Personal build: omit the notch watermark.'


def patch(root):
    path = root / SOURCE_PATH
    original = path.read_text(encoding="utf-8")
    if original.count(ORIGINAL) != 1:
        raise SystemExit("Expected exactly one notch-badge image assignment; refusing to guess.")
    updated = original.replace(ORIGINAL, REPLACEMENT)
    path.write_text(updated, encoding="utf-8")
    assert ORIGINAL not in updated and updated.count(REPLACEMENT) == 1
    print("Removed notch-badge image assignment: " + str(SOURCE_PATH))


def verify_unencrypted_arm64(data):
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected a 64-bit little-endian Mach-O executable")
    if struct.unpack_from("<I", data, 4)[0] != 0x0100000C:
        raise ValueError("Expected an arm64 iPhone executable")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O load command")
        if cmd in (0x21, 0x2C) and struct.unpack_from("<I", data, offset + 16)[0] != 0:
            raise ValueError("Encrypted App Store executable cannot be sideloaded")
        offset += size


def package(source, output, commit):
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt build archive")
        infos = [n for n in archive.namelist() if n.startswith("Payload/")
                 and n.count("/") == 2 and n.endswith(".app/Info.plist")]
        if len(infos) != 1:
            raise ValueError("Expected exactly one main application")
        info_path = infos[0]
        app = info_path.rsplit("/", 1)[0]
        info = plistlib.loads(archive.read(info_path))
        executable_path = app + "/" + info["CFBundleExecutable"]
        binary = archive.read(executable_path)
        verify_unencrypted_arm64(binary)
        info["CFBundleDisplayName"] = "SimHelp Chat"
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as packaged:
            for entry in archive.infolist():
                if "/_CodeSignature/" in entry.filename or entry.filename.endswith("embedded.mobileprovision"):
                    continue
                if entry.filename.startswith(app + "/Watch/"):
                    continue
                data = plistlib.dumps(info) if entry.filename == info_path else archive.read(entry)
                packaged.writestr(entry, data)
            packaged.writestr(app + "/NO-NOTCH-LOGO.txt",
                "Unofficial personal build from https://github.com/TelegramMessenger/Telegram-iOS\n"
                "Upstream commit: " + commit + "\n"
                "Change: omit Components/AppBadge from WindowContent.swift.\n"
                "The executable was compiled from source; no App Store executable was used.\n"
                "Requires personal signing before installation. Device behavior is unverified.\n")
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert archive.read(executable_path) == binary
        assert plistlib.loads(archive.read(info_path))["CFBundleDisplayName"] == "SimHelp Chat"
    report = {"upstream_commit": commit, "badge_removed_in_source": True,
              "arm64_unencrypted_executable": True, "requires_signing": True,
              "tested_on_device": False, "app_version": info.get("CFBundleShortVersionString"),
              "minimum_ios": info.get("MinimumOSVersion"),
              "ipa_sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    patch_args = commands.add_parser("patch")
    patch_args.add_argument("root", type=Path)
    pack_args = commands.add_parser("package")
    pack_args.add_argument("source", type=Path)
    pack_args.add_argument("output", type=Path)
    pack_args.add_argument("--commit", required=True)
    args = parser.parse_args()
    if args.command == "patch":
        patch(args.root)
    else:
        package(args.source, args.output, args.commit)
