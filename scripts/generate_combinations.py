#!/usr/bin/env python3
"""Generate the pinned 3beol 2noshift table without network access."""
import argparse
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
rules = json.loads((root / 'spec/sunarae.json').read_text())
pairs = sorted(rules['initial_replacements'] + rules['combinations'])
assert len(pairs) == 27 and len({key for key, _ in pairs}) == len(pairs)
text = (
    '/* Generated from spec/sunarae.json. LGPL-2.1-or-later.\n'
    f" * 3beol/libhangul {rules['revision']} */\n"
    'static const HangulCombinationItem sunarae_combinations[] = {\n'
    + ''.join(f'    {{ 0x{key:08x}, 0x{value:04x} }},\n' for key, value in pairs)
    + '};\n'
)
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
target = root / 'vendor/libhangul/sunarae-combinations.h'
if args.check:
    if target.read_text() != text:
        raise SystemExit('Sunarae combinations are out of date')
    print('27 Sunarae rules match the pinned source')
else:
    target.write_text(text)
