#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Optional CPU-only tests against the exact separately downloaded public fixture."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('offline', root/'tools/prepare_bios303_dsdt.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if len(sys.argv) != 2:
    raise SystemExit('Usage: bios303_transform_test.py EXACT_PUBLIC_DSDT.aml (no hardware access)')
data = Path(sys.argv[1]).read_bytes()
manifest = json.loads((root/'acpi/BIOS303-provenance.json').read_text())
result = module.transform(data, manifest)
changed = {i for i,(a,b) in enumerate(zip(data,result)) if a != b}
expected = {9} | {m['definition_name_offset'] for m in manifest['methods']}
assert changed == expected and len(changed) == 15
assert len(result) == len(data) and sum(result) % 256 == 0
assert hashlib.sha256(result).hexdigest() == 'b4ad65b115b6c4d5683a6ff4f23d12771fb0d4910fdb49272b4db5f029df2539'
assert hashlib.sha256(data).hexdigest() == manifest['file_sha256']
for changed_input in (data[:-1], b'XXXX'+data[4:], result, data[:50]+bytes([data[50]^1])+data[51:]):
    try:
        module.transform(changed_input, manifest)
    except ValueError:
        pass
    else:
        raise AssertionError('Mismatched/truncated/already-patched input accepted')
print('PASS: exact public BIOS303 fixture; 14 definition-name bytes + checksum only; input retained; all mismatches rejected')
