#!/usr/bin/env python3
"""Check Chinese translations and printf placeholders before packaging."""
import json
import re
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'Docky/Localizable.xcstrings').read_text())
format_token = re.compile(r'%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?(?:hh|ll|h|l|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]')

def tokens(value):
    return Counter(re.sub(r'^%\d+\$', '%', item) for item in format_token.findall(value))

errors = []
for key, entry in catalog['strings'].items():
    unit = entry.get('localizations', {}).get('zh-Hans', {}).get('stringUnit', {})
    if unit.get('state') != 'translated' or 'value' not in unit:
        errors.append(f'Missing Chinese translation: {key!r}')
    elif tokens(key) != tokens(unit['value']):
        errors.append(f'Placeholder mismatch: {key!r}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'OK: {len(catalog["strings"])} Simplified Chinese entries; all placeholders preserved.')
