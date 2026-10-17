#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Stage native cohort userland + deployment templates. No install/run/sign step."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import sys

BASE = Path(__file__).resolve().parents[1]
APPS = {'userland/FX505GT Control.app': ('org.fx505gt.control', 'FX505GTControl'),
        'platform/华硕控制.app': ('local.asus.platform.ui', 'AsusControl')}
HELPERS = {'userland/fxprofile': 'org.fx505gt.fxprofile',
           'userland/FX505GT Control.app/Contents/Helpers/fxradio': 'org.fx505gt.fxradio',
           'platform/AsusAwake': 'ASUSPlatform/AsusAwake'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def checked(root, name, receipt):
    path = root / name
    if path.is_symlink() or any(p.is_symlink() for p in path.parents if p != root.parent):
        raise ValueError('Symlink input refused: ' + name)
    record = receipt['outputs'].get(name)
    if not record or not path.is_file() or path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
        raise ValueError('Missing/changed native output: ' + name)
    return path

def executable(path):
    data = path.read_bytes()
    # Native script builds thin x86_64 MH_EXECUTE, not object files or scripts.
    if len(data) < 32 or struct.unpack('<IiiI', data[:16])[:2] != (0xfeedfacf, 0x1000007) or struct.unpack('<I', data[12:16])[0] != 2:
        raise ValueError('Expected linked x86_64 Mach-O executable: ' + str(path))

def package(root, out):
    if root.is_symlink() or out.is_symlink() or out.exists():
        raise ValueError('Use a real build directory and new output directory')
    root = root.resolve()
    destination = out.resolve()
    if destination == root or root in destination.parents or destination == BASE or BASE in destination.parents:
        raise ValueError('Package output must be outside build and source trees')
    receipt = json.loads((root / 'BUILD_RECEIPT.json').read_text())
    if receipt.get('state') != 'built-not-installed-or-executed' or not receipt.get('native_tools'):
        raise ValueError('A completed native cohort receipt is required; source/objects are not apps')
    if not {'kext', 'userland', 'platform', 'acpi'}.issubset({step.get('label') for step in receipt.get('steps', [])}):
        raise ValueError('Incomplete native build steps')
    if any(step.get('exit') != 0 for step in receipt.get('steps', [])):
        raise ValueError('Build receipt contains a failed step')
    files = {}
    for app, (bundle, binary) in APPS.items():
        plist = checked(root, app + '/Contents/Info.plist', receipt)
        info = plistlib.loads(plist.read_bytes())
        if info.get('CFBundleIdentifier') != bundle or info.get('CFBundleExecutable') != binary:
            raise ValueError('Unexpected application identity: ' + app)
        exe = checked(root, app + '/Contents/MacOS/' + binary, receipt); executable(exe)
        target = 'Applications/' + Path(app).name
        files[target + '/Contents/Info.plist'] = plist
        files[target + '/Contents/MacOS/' + binary] = exe
    for name, target in HELPERS.items():
        path = checked(root, name, receipt); executable(path)
        files['PrivilegedHelperTools/' + target] = path
    identity = checked(root, 'userland/FXBuildIdentity.h', receipt).read_text()
    for macro, name in [('FX_EXPECTED_HELPER_SHA256', 'userland/fxprofile'), ('FX_EXPECTED_RADIO_SHA256', 'userland/FX505GT Control.app/Contents/Helpers/fxradio')]:
        if '#define ' + macro + ' "' + digest(root / name) + '"' not in identity:
            raise ValueError('App/helper cohort hash mismatch')
    # Retain embedded companion as well as its fixed deployment-path copy.
    files['Applications/FX505GT Control.app/Contents/Helpers/fxradio'] = root / 'userland/FX505GT Control.app/Contents/Helpers/fxradio'
    out.mkdir(parents=True)
    for name, source in files.items():
        target = out / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755 if '/MacOS/' in name or '/Helpers/' in name or name.startswith('PrivilegedHelperTools/') else 0o644)
    launch = out / 'LaunchAgents-templates'; launch.mkdir()
    for app, (bundle, binary) in APPS.items():
        # Templates are inert here. Deployment/startup is a separate user choice.
        value = {'Label': bundle, 'ProgramArguments': ['/Applications/' + Path(app).name + '/Contents/MacOS/' + binary], 'RunAtLoad': True, 'LimitLoadToSessionType': 'Aqua'}
        (launch / (bundle + '.plist')).write_bytes(plistlib.dumps(value))
    shutil.copyfile(BASE / 'DEPLOY_USERLAND.md', out / 'DEPLOY_USERLAND.md')
    shutil.copyfile(BASE / 'LICENSE', out / 'LICENSE')
    shutil.copyfile(root / 'BUILD_RECEIPT.json', out / 'BUILD_RECEIPT.json')
    record = {'status': 'native-built-staged-not-installed', 'signed_or_notarized': False,
              'hardware_testing': 'not performed by build/package',
              'files': {p.relative_to(out).as_posix(): digest(p) for p in sorted(out.rglob('*')) if p.is_file()}}
    (out / 'PACKAGE_RECEIPT.json').write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n')
    print('Staged native userland package; no installation, startup, signing or hardware action.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        package(args.build, args.output)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
