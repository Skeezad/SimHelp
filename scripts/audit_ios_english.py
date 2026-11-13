from pathlib import Path
import re, json
ROOT=Path(__file__).resolve().parents[1]
CJK=re.compile('[\u3400-\u9fff\u3040-\u30ff]')

def spans(s):
    out=[]
    def code(i, nested=False):
        depth=1
        while i<len(s):
            if s.startswith('//',i):
                j=s.find('\n',i); i=len(s) if j<0 else j+1
            elif s.startswith('/*',i):
                d=1;i+=2
                while i<len(s) and d:
                    if s.startswith('/*',i): d+=1;i+=2
                    elif s.startswith('*/',i): d-=1;i+=2
                    else:i+=1
            elif s[i]=='"': i=string(i)
            elif nested and s[i]=='(':depth+=1;i+=1
            elif nested and s[i]==')':
                depth-=1;i+=1
                if depth==0:return i
            else:i+=1
        return i
    def string(i):
        delim='"""' if s.startswith('"""',i) else '"'
        i+=len(delim);start=i
        while i<len(s):
            if s.startswith(delim,i):
                if i>start:out.append((start,i,len(delim)==3))
                return i+len(delim)
            if s.startswith('\\(',i):
                if i>start:out.append((start,i,len(delim)==3))
                i=code(i+2,True);start=i
            elif s[i]=='\\': i+=2
            else:i+=1
        raise ValueError('Unclosed Swift string')
    code(0)
    return out


errors=[]
for p in (ROOT/'apps/ios').rglob('*.swift'):
 if 'Tests' in str(p): continue
 s=p.read_text(encoding='utf8')
 for a,b,_ in spans(s):
  if CJK.search(s[a:b]): errors.append(str(p.relative_to(ROOT))+': '+ascii(s[a:b][:100]))
if errors: raise SystemExit('\n'.join(errors))
import plistlib
for p in (ROOT/'apps/ios').rglob('Info.plist'):
 info=plistlib.loads(p.read_bytes())
 for key,value in info.items():
  if key.endswith('UsageDescription') and CJK.search(str(value)):raise SystemExit(str(p)+': '+key)
print('PASS: Swift string structure, English text, and permission explanations')
