"""Check all translated keys and printf argument parity without launching the app."""
from pathlib import Path
import json
import re
import subprocess
root = Path(__file__).resolve().parents[1]
catalogs = []
for lang in ('ko', 'en'):
    path = root / 'Resources' / f'{lang}.lproj' / 'Localizable.strings'
    subprocess.run(['plutil', '-lint', str(path)], check=True)
    data = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)])
    catalogs.append(json.loads(data))
ko, en = catalogs
assert ko.keys() == en.keys(), 'Language key mismatch'
for key in ko:
    assert re.findall(r'%(?:\.\d+)?[@dfsu]', ko[key]) == re.findall(r'%(?:\.\d+)?[@dfsu]', en[key]), key
for file in (root / 'Sources').glob('*.swift'):
    for key in re.findall(r'L10n\.(?:text|format)\("([^"\n]+)"', file.read_text()):
        assert key in en, f'Missing localization: {file.name}: {key}'
print(f'{len(en)} bilingual localization entries verified')
