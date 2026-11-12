import json, re
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[1] / "iOS"
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
LIT = re.compile(r'"(?:\\.|[^"\\])*"')
VAR = re.compile(r"\\\([^)]*\)|\\[nt]")
CACHE_FILE = Path(__file__).with_name("ios_dynamic_translation_cache.json")
try: cache = json.loads(CACHE_FILE.read_text(encoding="utf8"))
except Exception: cache = {}

def prepare(token):
    raw = token[1:-1]
    if not CJK.search(raw) or '"""' in raw or 'http://' in raw or 'https://' in raw:
        return None
    vars = []
    def repl(m):
        vars.append(m.group(0)); return f" __VAR{len(vars)-1}__ "
    text = VAR.sub(repl, raw)
    if '"' in text or len(text) > 500: return None
    return text, vars

def translate(token):
    prepared = prepare(token)
    if not prepared: return token, token
    if token in cache: return token, cache[token]
    text, vars = prepared
    try:
        data = requests.get("https://translate.googleapis.com/translate_a/single",
            params={"client":"gtx", "sl":"auto", "tl":"en", "dt":"t", "q":text}, timeout=15).json()
        out = "".join(p[0] for p in data[0] if p and p[0])
        for i, value in enumerate(vars): out = out.replace(f"__VAR{i}__", value)
        if CJK.search(out): return token, token
        result='"'+out+'"'; cache[token]=result; return token,result
    except Exception: return token, token

files=[p for p in ROOT.rglob("*.swift") if p.name != "AppUpdateView.swift"]
tokens=set()
for p in files: tokens.update(x for x in LIT.findall(p.read_text(encoding="utf8")) if prepare(x))
pending=[x for x in tokens if x not in cache]
with ThreadPoolExecutor(max_workers=8) as pool:
    for f in as_completed([pool.submit(translate,x) for x in pending]):
        k,v=f.result()
        if k != v: cache[k]=v
CACHE_FILE.write_text(json.dumps(cache,ensure_ascii=False,indent=2),encoding="utf8")
changed=0
for p in files:
    s=p.read_text(encoding="utf8")
    n=LIT.sub(lambda m: cache.get(m.group(0),m.group(0)),s)
    if n!=s: p.write_text(n,encoding="utf8"); changed+=1
print(f"translated {len(cache)} literals in {changed} files")
