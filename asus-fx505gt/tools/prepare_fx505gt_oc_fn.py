#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare definition-only OpenCore patches for the recorded FX505GT loaded table."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys


def prepare(data, evidence):
    if hashlib.sha256(data).hexdigest() != evidence['sha256']:
        raise ValueError('Input is not the recorded FX505GT loaded DSDT')
    if data[:4] != b'DSDT' or struct.unpack_from('<I', data, 4)[0] != len(data) or sum(data) % 256:
        raise ValueError('Invalid DSDT length/checksum')
    patches = []
    for m in evidence['methods']:
        old = data[m['start']:m['end_exclusive']]
        if hashlib.sha256(old).hexdigest() != m['method_sha256'] or data.count(old) != 1:
            raise ValueError('Changed/nonunique method: ' + m['name'])
        off = m['name_offset'] - m['start']
        if old[off:off+4] != m['name'].encode() or old[0] != 0x14:
            raise ValueError('Not the recorded MethodOp definition')
        new_name = 'X' + m['name'][1:]
        if new_name.encode() in data:
            raise ValueError('Existing renamed method: ' + new_name)
        new = old[:off] + new_name.encode() + old[off+4:]
        patches.append(dict(Base='', BaseSkip=0, Comment='FX505GT Fn ' + m['name'] + ' to ' + new_name,
                            Count=1, Enabled=True, Find=old, Limit=0, Mask=b'', OemTableId=data[16:24],
                            Replace=new, ReplaceMask=b'', Skip=0, TableLength=0, TableSignature=b'DSDT'))
    if len(patches) != 14:
        raise ValueError('Expected fourteen methods')
    return patches


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: prepare_fx505gt_oc_fn.py RECORDED_LOADED_DSDT.aml NEW_PATCHES.plist')
    root = Path(__file__).resolve().parent.parent
    evidence = json.loads((root/'field-20261017/DSDT-loaded-hotkeys.json').read_text())
    patches = prepare(Path(sys.argv[1]).read_bytes(), evidence)
    with Path(sys.argv[2]).open('xb') as out:
        out.write(plistlib.dumps(patches, sort_keys=False))
    print('Prepared 14 exact MethodOp definition patches; no DSDT replacement or installation.')


if __name__ == '__main__':
    main()
