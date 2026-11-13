"""Fail the Android build when replacement placeholders enter app text."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'apps/android/phone-control'
LITERALS = re.compile(r'"(?:\\.|[^"\\])*"')
PLACEHOLDER = re.compile(r'\bText(?:[\s\u200c]+Text)+\b')
def check(value, path):
    if value.strip() == 'Text' or PLACEHOLDER.search(value):
        raise SystemExit(f'Untranslated placeholder in {path}: {value!r}')
for path in (APP / 'src').rglob('*.java'):
    for match in LITERALS.finditer(path.read_text(encoding='utf8')):
        check(match[0][1:-1], path)
for path in (APP / 'res').rglob('*.xml'):
    for node in ET.parse(path).iter():
        if node.text: check(node.text, path)
print('PASS: Android text contains no Text placeholders')
