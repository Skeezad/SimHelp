import json
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[1] / "iOS"
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
ARABIC = re.compile(r"[\u0600-\u06ff]")
LITERAL = re.compile(r'"(?:\\.|[^"\\])*"')
CACHE_FILE = Path(__file__).with_name("ios_translation_cache.json")
try:
    cache = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
except Exception:
    cache = {}
cache = {k: v for k, v in cache.items() if k != v and not re.search(r"[\u3400-\u9fff]", v)}

def should_translate(token):
    raw = token[1:-1]
    # Only replace simple literals. Interpolated/nested Swift strings must
    # keep their original syntax and are translated manually later.
    return bool(CJK.search(raw) or ARABIC.search(raw)) and "\\(" not in raw and '"' not in raw and not any(x in raw for x in ("http://", "https://"))

def translate(token):
    if token in cache or not should_translate(token):
        return token
    raw = token[1:-1]
    try:
        data = requests.get("https://translate.googleapis.com/translate_a/single",
            params={"client":"gtx", "sl":"auto", "tl":"en", "dt":"t", "q":raw}, timeout=15).json()
        out = "".join(p[0] for p in data[0] if p and p[0])
        # Restore Swift interpolation and escaped line breaks if translation omitted them.
        for marker in re.findall(r"\\\([^)]*\\\)|\\[nt]", raw):
            if marker not in out:
                out += " " + marker
        cache[token] = '"' + out.replace('\\', '\\\\').replace('"', '\\"') + '"'
    except Exception:
        cache[token] = token
    return token

files = [p for p in ROOT.rglob("*.swift") if p.name not in {"AppUpdateView.swift", "SimHelpSetupView.swift"}]
tokens = set()
for path in files:
    tokens.update(t for t in LITERAL.findall(path.read_text(encoding="utf-8")) if should_translate(t))
pending = [t for t in tokens if t not in cache]
with ThreadPoolExecutor(max_workers=16) as pool:
    for future in as_completed([pool.submit(translate, t) for t in pending]):
        future.result()
CACHE_FILE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
changed = 0
for path in files:
    text = path.read_text(encoding="utf-8")
    new = LITERAL.sub(lambda m: cache.get(m.group(0), m.group(0)) if should_translate(m.group(0)) else m.group(0), text)
    if new != text:
        path.write_text(new, encoding="utf-8")
        changed += 1
print(f"translated literals: {len(cache)}, files changed: {changed}")
