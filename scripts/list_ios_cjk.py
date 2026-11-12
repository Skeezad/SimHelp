import re
from pathlib import Path
p = re.compile(r'"(?:\\.|[^"\\])*"')
c = re.compile(r'[\u3400-\u9fff]')
items=[]
for f in Path('iOS').rglob('*.swift'):
    for x in p.findall(f.read_text(encoding='utf8')):
        if c.search(x): items.append((str(f),x))
print(len(items))
for f,x in items[:160]: print((str(f)+' '+repr(x)).encode('ascii','backslashreplace').decode('ascii'))
