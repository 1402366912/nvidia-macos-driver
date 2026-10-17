#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Packaging contract fixtures only; no native compile, install or execution."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import plistlib
import struct
import tempfile

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('packager', BASE / 'tools/package_userland.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory(prefix='fx-package-contract-') as temp:
    root = Path(temp) / 'build'; root.mkdir()
    out = Path(temp) / 'package'
    receipt = {'state': 'source-prepared'}
    (root / 'BUILD_RECEIPT.json').write_text(json.dumps(receipt))
    try:
        m.package(root, out)
    except ValueError:
        assert not out.exists()
    else:
        raise AssertionError('Accepted source-only build')
    # Synthetic headers only: exercise packaging logic, never call these apps built.
    header = struct.pack('<IiiIIIII', 0xfeedfacf, 0x1000007, 3, 2, 0, 0, 0, 0)
    names = set(m.HELPERS)
    for app, (bundle, binary) in m.APPS.items():
        name = app + '/Contents/Info.plist'
        path = root / name; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleExecutable': binary}))
        names.add(name); names.add(app + '/Contents/MacOS/' + binary)
    for name in names:
        if name.endswith('.plist'): continue
        path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(header)
    identity = root / 'userland/FXBuildIdentity.h'
    identity.write_text('#define FX_EXPECTED_HELPER_SHA256 "' + m.digest(root / 'userland/fxprofile') + '"\n#define FX_EXPECTED_RADIO_SHA256 "' + m.digest(root / 'userland/FX505GT Control.app/Contents/Helpers/fxradio') + '"\n')
    names.add('userland/FXBuildIdentity.h')
    receipt = {'state': 'built-not-installed-or-executed', 'native_tools': {'fixture': True},
               'steps': [{'label': label, 'exit': 0} for label in ('kext', 'userland', 'platform', 'acpi')],
               'outputs': {n: {'sha256': m.digest(root / n), 'bytes': (root / n).stat().st_size} for n in names}}
    (root / 'BUILD_RECEIPT.json').write_text(json.dumps(receipt))
    with contextlib.redirect_stdout(io.StringIO()):
        m.package(root, out)
    assert (out / 'Applications/华硕控制.app/Contents/MacOS/AsusControl').is_file()
    assert (out / 'PrivilegedHelperTools/ASUSPlatform/AsusAwake').is_file()
    assert len(list((out / 'LaunchAgents-templates').glob('*.plist'))) == 2
    assert not (out / 'sudoers.rule').exists()
    (root / 'userland/fxprofile').write_bytes(b'changed')
    try:
        m.package(root, Path(temp) / 'rejected')
    except ValueError:
        assert not (Path(temp) / 'rejected').exists()
    else:
        raise AssertionError('Accepted changed output')
    object_file = Path(temp) / 'object'
    object_file.write_bytes(struct.pack('<IiiIIIII', 0xfeedfacf, 0x1000007, 3, 1, 0, 0, 0, 0))
    try:
        m.executable(object_file)
    except ValueError: pass
    else: raise AssertionError('Accepted MH_OBJECT as application')
print('PASS: synthetic packaging contract, paired app/helper layout, inert startup templates, changed/missing-native/object rejection')
print('NOT RUN: native compilation, signing, installation, login, AppKit or hardware; fixture output removed')
