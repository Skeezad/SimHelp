"""Windows build of the SimHelp Android fork. Keeps upstream checksums and toolchain.

Requires Python 3.11+, JDK 17 and Android SDK platform/build-tools 35.
Uses workspace-local tools when JAVA_HOME/ANDROID_SDK_ROOT are unset.
"""
from pathlib import Path
import concurrent.futures
import hashlib
import json
import os
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT
TOOLS = ROOT / ".local"
OUT = ROOT / "build/android"
DIST = ROOT / "dist"
DEPS = TOOLS / "dependencies"


def run(*args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)


def download(url, path, sha256):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != sha256:
        run("curl.exe", "--ssl-revoke-best-effort", "-sS", "-L", "--fail", "--retry", "3",
            "--connect-timeout", "20", "--max-time", "300", "-o", path, url)
    if hashlib.sha256(path.read_bytes()).hexdigest() != sha256:
        raise RuntimeError(f"Checksum mismatch: {path.name}")
    return path


def main():
    import sys
    run(sys.executable, ROOT / "scripts/check_android_text.py")
    jdk = Path(os.environ.get("JAVA_HOME", Path("C:/Program Files/Android/Android Studio/jbr")))
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT", Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk"))
    # Prefer the newest installed SDK pair; Android Studio installs newer
    # platform/build-tools revisions than the original 35.0.0 baseline.
    bt_candidates = sorted((sdk / "build-tools").glob("*/aapt2.exe"))
    platform_candidates = sorted((sdk / "platforms").glob("*/android.jar"))
    bt = bt_candidates[-1].parent if bt_candidates else sdk / "build-tools/35.0.0"
    android = platform_candidates[-1] if platform_candidates else sdk / "platforms/android-35/android.jar"
    for required in (jdk / "bin/javac.exe", android, bt / "aapt2.exe"):
        if not required.exists():
            raise SystemExit(f"Missing tool: {required}. See README.fa.md.")
    for directory in (OUT / "classes", OUT / "dex", DIST, DEPS):
        directory.mkdir(parents=True, exist_ok=True)
    artifacts = {
        "api": "4def9bde498ef8626614c2fc5db9af4749c86f16f6c33e3f5658d35e70bab59b",
        "aidl": "33fe7191cdd69fcb66d649264f3b0c47acb2f3d6343afc05b98dbbff6f221963",
        "shared": "4659642c9339be0a26e9c65bb8648f7ad6d8f4a465f557993ccbc78802381635",
        "provider": "b0f18cd9812464ec171c53cac93a819fe411718a3965c311f01eb4de265381b3",
    }
    def aar(item):
        name, checksum = item
        file = download(f"https://repo.maven.apache.org/maven2/dev/rikka/shizuku/{name}/13.1.5/{name}-13.1.5.aar",
                        DEPS / f"shizuku-{name}.aar", checksum)
        jar = DEPS / f"shizuku-{name}.jar"
        with zipfile.ZipFile(file) as archive:
            jar.write_bytes(archive.read("classes.jar"))
        return jar
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jars = list(pool.map(aar, artifacts.items()))
    jars.append(download("https://redirector.gvt1.com/edgedl/android/maven2/androidx/annotation/annotation/1.3.0/annotation-1.3.0.jar",
                         DEPS / "annotation.jar", "97dc45afefe3a1e421da42b8b6e9f90491477c45fc6178203e3a5e8a05ee8553"))
    jars.append(download("https://repo.maven.apache.org/maven2/org/bouncycastle/bcprov-jdk15to18/1.84/bcprov-jdk15to18-1.84.jar",
                         DEPS / "bcprov.jar", "a30777eebbd44aa1713c14ee04547de1df63ef3e383e910ed210e1d0f2c2ef92"))
    java_dirs = [SRC / "apps/android/phone-control/src", SRC / "apps/android/audio-bridge/src"]
    sources = sorted(p for directory in java_dirs for p in directory.rglob("*.java"))
    # javac/d8 response files avoid Windows command-line length limits.
    quote = lambda p: '"' + str(p).replace("\\", "/") + '"'
    source_list = OUT / "sources.txt"
    source_list.write_text("\n".join(quote(p) for p in sources), encoding="utf-8")
    run(jdk / "bin/javac.exe", "-encoding", "UTF-8", "-source", "17", "-target", "17",
        "-classpath", os.pathsep.join(str(x) for x in [android, *jars]),
        "-d", OUT / "classes", "@" + str(source_list))
    dex_args = OUT / "dex-inputs.txt"
    # D8 on Windows treats response-file quotes as literal path characters;
    # this workspace has no spaces in these paths, so emit raw forward-slash paths.
    dex_args.write_text("\n".join(str(p).replace("\\", "/") for p in [*sorted((OUT / "classes").rglob("*.class")), *jars]), encoding="utf-8")
    run(jdk / "bin/java.exe", "-Xmx2g", "-cp", bt / "lib/d8.jar", "com.android.tools.r8.D8",
        "--lib", android, "--min-api", "29", "--output", OUT / "dex", "@" + str(dex_args))
    resources = OUT / "resources.zip"
    run(bt / "aapt2.exe", "compile", "--dir", SRC / "apps/android/phone-control/res", "-o", resources)
    manifest = OUT / "AndroidManifest.xml"
    manifest.write_text((SRC / "apps/android/standalone/AndroidManifest.xml").read_text(encoding="utf-8")
                        .replace('android:debuggable="true"', 'android:debuggable="false"'), encoding="utf-8")
    unsigned = OUT / "unsigned.apk"
    run(bt / "aapt2.exe", "link", "-o", unsigned, "-I", android, "--manifest", manifest, resources)
    with zipfile.ZipFile(unsigned, "a", zipfile.ZIP_DEFLATED) as archive:
        for dex in (OUT / "dex").glob("classes*.dex"):
            archive.write(dex, dex.name)
        for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"):
            archive.write(SRC / name, "assets/licenses/" + name)
    aligned = OUT / "aligned.apk"
    run(bt / "zipalign.exe", "-f", "4", unsigned, aligned)
    # A separate fork key prevents this APK replacing an upstream installation.
    key = Path(os.environ.get("SIMHELP_KEYSTORE", str(TOOLS / "keys/simhelp-personal.keystore")))
    key.parent.mkdir(parents=True, exist_ok=True)
    if not key.exists():
        run(jdk / "bin/keytool.exe", "-genkeypair", "-keystore", key, "-storepass", "android",
            "-keypass", "android", "-alias", "simhelp", "-dname", "CN=SimHelp Personal",
            "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650")
    apk = DIST / "SimHelp-Android.apk"
    signer = [jdk / "bin/java.exe", "-jar", bt / "lib/apksigner.jar"]
    run(*signer, "sign", "--ks", key, "--ks-pass", "pass:android", "--key-pass", "pass:android",
        "--out", apk, aligned)
    run(*signer, "verify", "--verbose", apk)
    run(bt / "aapt2.exe", "dump", "badging", apk)
    print(f"Built {apk}")


if __name__ == "__main__":
    main()
