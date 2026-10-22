#!/usr/bin/env python3
"""Check paired .strings tables, printf arguments, and literal Swift lookups."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ENTRY = re.compile(r'\s*(?:/\*.*?\*/\s*|//[^\n]*\n\s*)*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;', re.S)
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hljztL])?([@diuoxXfFeEgGaAcCsSp%])')


def read_table(path):
    source = path.read_text(encoding='utf-8')
    result = {}
    offset = 0
    while source[offset:].strip():
        match = ENTRY.match(source, offset)
        if not match:
            raise ValueError(f'{path}: invalid .strings syntax at offset {offset}')
        key, value = (json.loads(item) for item in match.groups())
        if key in result:
            raise ValueError(f'{path}: duplicate key: {key}')
        if not value.strip():
            raise ValueError(f'{path}: empty value: {key}')
        result[key] = value
        offset = match.end()
    return result


def arguments(value):
    sequence = 0
    result = Counter()
    for match in FORMAT.finditer(value):
        position, length, kind = match.groups()
        if kind == '%':
            continue
        sequence += 1
        result[(int(position) if position else sequence, (length or '') + kind)] += 1
    return result


def check(resources, sources):
    zh, en = [read_table(resources / language / 'Localizable.strings') for language in ('zh-Hans.lproj', 'en.lproj')]
    if zh.keys() != en.keys():
        raise ValueError(f'key mismatch: missing English {sorted(zh.keys() - en.keys())}; missing Chinese {sorted(en.keys() - zh.keys())}')
    for key in zh:
        if arguments(zh[key]) != arguments(en[key]):
            raise ValueError(f'format argument mismatch: {key}')
    for path in sources.rglob('*.swift'):
        source = path.read_text(encoding='utf-8')
        keys = re.findall(r'\bL\("([^"\\]+)"\)', source)
        keys += re.findall(r"return error\('([^']+)'\)", source)
        for key in keys:
            if key not in zh:
                raise ValueError(f'{path}: missing lookup: {key}')
    print(f'Localization OK: {len(zh)} keys per language; no duplicates, empty values, missing lookups, or format mismatches.')


if __name__ == '__main__':
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=root / 'Resources')
    parser.add_argument('--sources', type=Path, default=root / 'Sources')
    options = parser.parse_args()
    try:
        check(options.resources, options.sources)
    except (OSError, ValueError) as error:
        print(f'Localization check failed: {error}', file=sys.stderr)
        sys.exit(1)
