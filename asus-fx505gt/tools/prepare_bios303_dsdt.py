#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Offline exact-fixture transformation. Never writes firmware or boot configuration."""
import hashlib
import json
from pathlib import Path
import struct
import sys

def transform(data, manifest):
    if hashlib.sha256(data).hexdigest() != manifest['file_sha256']:
        raise ValueError('DSDT differs from the exact public BIOS303 fixture; refusing any mutation')
    if len(data) != manifest['length'] or data[:36].hex() != manifest['header_hex']:
        raise ValueError('ACPI header/OEM/revision/length differs')
    if data[:4] != b'DSDT' or struct.unpack_from('<I', data, 4)[0] != len(data) or sum(data) % 256:
        raise ValueError('Invalid ACPI signature, length or checksum')
    for name in manifest["required_absent_names"]:
        if name.encode("ascii") in data:
            raise ValueError("Adapter/renamed symbol already exists: " + name)
    for method in manifest["keyboard_light_methods"]:
        body=data[method["start"]:method["end_exclusive"]]
        if hashlib.sha256(body).hexdigest()!=method["method_sha256"]:
            raise ValueError("Keyboard-light firmware method source changed")
    out = bytearray(data)
    offsets = set()
    for method in manifest['methods']:
        start, end, offset = method['method_start'], method['method_end'], method['definition_name_offset']
        old, new = method['method'].encode('ascii'), method['renamed_method'].encode('ascii')
        if len(old) != 4 or len(new) != 4 or offset in offsets or data[offset:offset+4] != old:
            raise ValueError('Invalid/nonunique method definition target')
        if new in data:
            raise ValueError('Renamed symbol already exists; refusing namespace collision')
        body = data[start:end]
        if hashlib.sha256(body).hexdigest() != method['method_sha256']:
            raise ValueError('Method source bytes changed')
        # NameSeg immediately precedes MethodFlags. Re-parse AML package
        # length instead of trusting an arbitrary occurrence of the name.
        if body[0] != 0x14:
            raise ValueError('Not an AML MethodOp')
        follow = body[1] >> 6
        pkg = body[1] & (0x0f if follow else 0x3f)
        for i in range(follow): pkg |= body[2+i] << (4+8*i)
        if start+1+pkg != end or start+2+follow != offset or data[offset+4] != 0:
            raise ValueError('Method package/arguments/flags do not match source')
        # Definition is exact; other references are intentionally left intact
        # so callers enter the new Darwin wrapper, or original body elsewhere.
        offsets.add(offset)
        out[offset:offset+4] = new
    if len(offsets) != 14:
        raise ValueError('Expected exactly the 14 documented hotkey definitions')
    out[9] = 0
    out[9] = (-sum(out)) & 0xff
    assert len(out) == len(data) and sum(out) % 256 == 0
    return bytes(out)

def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: prepare_bios303_dsdt.py EXACT_SOURCE_DSDT.aml NEW_OUTPUT.aml')
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root/'acpi/BIOS303-provenance.json').read_text())
    source, target = map(Path, sys.argv[1:])
    result = transform(source.read_bytes(), manifest)
    # Atomic exclusive creation: never overwrite any original/source/result.
    with target.open('xb') as stream:
        stream.write(result)
    print('Created OFFLINE renamed DSDT fixture:', target)
    print('SHA256:', hashlib.sha256(result).hexdigest())
    print('Requires matching SSDT source compiled separately. Nothing installed or applied to a machine.')

if __name__ == '__main__':
    main()
