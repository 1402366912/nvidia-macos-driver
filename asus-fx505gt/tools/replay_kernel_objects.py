#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Replay only the recorded four C++ object compilations from verified local roots.

No downloads/linking/install/loading/device access. Compiler shared-library setup
is supplied by the caller's existing environment. Outputs must be a new directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
BASE = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--roots', required=True, type=Path, help='JSON root-label to local absolute-path mapping; see BUILD_COHORT.md')
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    evidence = json.loads((BASE / 'validation/kernel-object-compile.json').read_text())
    roots = json.loads(a.roots.read_text())
    required = set(evidence['root_labels']) | {'compiler'}
    if set(roots) != required or not all(isinstance(x, str) and Path(x).is_absolute() for x in roots.values()):
        raise ValueError('Supply exactly the documented absolute local root paths')
    if a.output.exists() or a.output.is_symlink():
        raise ValueError('Output must be new; earlier failures are retained')
    roots['output'] = str(a.output.resolve())
    def expand(text):
        for name, value in roots.items():
            text = text.replace('${' + name + '}', value)
        if '${' in text:
            raise ValueError('Unresolved input placeholder')
        return text
    if digest(Path(roots['compiler'])) != evidence['compiler']['sha256']:
        raise ValueError('Different compiler binary; this exact replay requires the recorded compiler')
    for item in evidence['dependencies']:
        path = Path(expand(item['path']))
        if not path.is_file() or digest(path) != item['sha256']:
            raise ValueError('Changed/missing used dependency: ' + item['path'])
    out = Path(roots['output']); out.mkdir(parents=True)
    results = []
    for unit in evidence['translation_units']:
        command = [expand(s) for s in unit['command']]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        name = Path(expand(unit['unit'])).stem
        (out / (name + '.log')).write_bytes(result.stdout)
        record = {'unit': unit['unit'], 'exit': result.returncode, 'command': command}
        if result.returncode == 0:
            obj = Path(command[command.index('-o') + 1])
            data = obj.read_bytes()
            if data[:4] != b'\xcf\xfa\xed\xfe':
                raise ValueError('Expected little-endian 64-bit Mach-O object')
            record.update(object_sha256=digest(obj), object_bytes=len(data),
                          matches_recorded_object=digest(obj) == unit['object']['sha256'])
        results.append(record)
        (out / 'REPLAY.json').write_text(json.dumps(results, indent=2) + '\n')
        if result.returncode:
            raise RuntimeError(name + ' failed; compiler log retained')
    print('Four actual kernel TUs compiled to Mach-O objects. No native link/runtime/hardware claim.')

if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, RuntimeError) as error: sys.exit(str(error))
