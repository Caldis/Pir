#!/usr/bin/env python3
"""Validate native localization parity and literal lookup coverage."""
import collections
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
resources = root / 'Sources/Pir/Resources'
translations = {}
for locale in ['en', 'zh-Hans']:
    path = resources / f'{locale}.lproj/Localizable.strings'
    translations[locale] = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
    keys = [json.loads(key) for key in re.findall(r'^("(?:[^"\\]|\\.)*")\s*=', path.read_text(), re.MULTILINE)]
    duplicates = [key for key, count in collections.Counter(keys).items() if count > 1]
    assert not duplicates, f'{locale}: duplicate keys: {duplicates}'
    assert all(value.strip() for value in translations[locale].values()), f'{locale}: empty translation'
assert translations['en'].keys() == translations['zh-Hans'].keys(), 'English and Chinese keys differ'
# Lookup keys retain internal Pin terminology; only displayed values use window names.
assert translations['en']['Pins'] == 'Windows', 'English window tab must be Windows'
assert translations['zh-Hans']['Pins'] == '浮窗', 'Chinese window tab must be 浮窗'
for key, value in translations['en'].items():
    assert not re.search(r'\bpins\b|\b(?:a|the|each|close|show|hide|delete|text|file) pin\b', value, re.IGNORECASE), f'English: legacy window noun in {key}: {value}'
for key, value in translations['zh-Hans'].items():
    assert not any(term in value for term in ['贴屏', '贴图']), f'Chinese: legacy window noun in {key}: {value}'
for path in (root / 'Sources/Pir').rglob('*.swift'):
    for key in re.findall(r'L\(\s*("(?:[^"\\]|\\.)*")', path.read_text()):
        value = json.loads(key)
        assert value in translations['en'], f'{path.name}: missing translation: {value}'
print(f'Native English and Chinese: {len(translations["en"])} matching keys')

web = root / 'website/locales'
english = json.loads((web / 'en.json').read_text())
chinese = json.loads((web / 'zh.json').read_text())
assert english.keys() == chinese.keys(), 'Website locale keys differ'
html = (root / 'website/index.html').read_text()
for key in re.findall(r'data-i18n(?:-aria-label|-alt)?="([^"]+)"', html):
    assert key in english, f'Missing website translation: {key}'
print(f'Website English and Chinese: {len(english)} matching keys')
