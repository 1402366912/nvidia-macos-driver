#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fixed-input native build only. No fetching, signing, installation or execution.

Exports selected verified Git blobs into a fresh directory; input worktrees are
never modified. Build scripts do not invoke upstream bootstrap or archive phases.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys

BASE = Path(__file__).resolve().parents[1]

def sha(data):
    return hashlib.sha256(data).hexdigest()

def capture(args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def safe_name(name):
    p = PurePosixPath(name)
    return bool(name) and not p.is_absolute() and all(x not in ('.', '..') for x in p.parts) and '\\' not in name

def verify_delivery():
    entries = {}
    for line in (BASE / 'MANIFEST.sha256').read_text().splitlines():
        digest, name = line.split('  ', 1)
        if not safe_name(name) or name in entries or not re.fullmatch('[0-9a-f]{64}', digest):
            raise ValueError('Malformed component manifest')
        p = BASE / name
        if p.is_symlink() or not p.is_file() or sha(p.read_bytes()) != digest:
            raise ValueError('Changed component input: ' + name)
        entries[name] = digest
    if any(p.is_symlink() for p in BASE.rglob('*')):
        raise ValueError('Symlinks are not allowed in delivered source')
    actual = {p.relative_to(BASE).as_posix() for p in BASE.rglob('*') if p.is_file()}
    actual.discard('MANIFEST.sha256')
    if actual != set(entries):
        raise ValueError('Unmanifested/missing component files; use a clean delivered source directory')
    return entries

def source_tree(repo, pin):
    if capture(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip() != pin:
        raise ValueError('Wrong pinned HEAD: ' + str(repo))
    if capture(['git', '-C', str(repo), 'status', '--porcelain', '--untracked-files=all']):
        raise ValueError('Dirty/untracked input checkout: ' + str(repo))
    result = []
    for raw in capture(['git', '-C', str(repo), 'ls-tree', '-rz', '--full-tree', pin]).split(b'\0'):
        if not raw:
            continue
        meta, name = raw.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        name = name.decode('utf-8')
        if not safe_name(name):
            raise ValueError('Unsafe Git path')
        result.append((name, mode, kind, oid))
    return result

def exported_path(label, name):
    # Only build inputs are exported. CI, daemon/installer, Xcode user schemes,
    # and bootstrap files never enter the build workspace.
    if label == 'AsusSMC':
        if name == 'LICENSE.md' or name == 'AsusSMC.xcodeproj/project.pbxproj' or any(name.startswith(p) for p in ('AsusSMC/', 'Global/', 'VirtualAppleKeyboard/', 'KernEventServer/')):
            return name
    elif label == 'Lilu':
        root = 'Lilu.kext/Contents/Resources/'
        if name == 'LICENSE.txt':
            return root + 'LICENSE.txt'
        # These two links are unused by the target's verified TU closure.
        # Explicitly omit them instead of exporting a dangling/escaping link.
        if name.startswith('Lilu/Headers/') and name not in ('Lilu/Headers/capstone', 'Lilu/Headers/hde64.h'):
            return root + name[len('Lilu/'):]
    elif label == 'VirtualSMC':
        if name == 'LICENSE.txt' or name.startswith('VirtualSMCSDK/'):
            return 'VirtualSMC.kext/Contents/Resources/' + name
    elif label == 'MacKernelSDK':
        if name == 'LICENSE.txt' or name.startswith('Headers/') or name == 'Library/x86_64/libkmod.a':
            return 'MacKernelSDK/' + name
    return None

def export_sources(label, repo, tree, dest):
    selected = [(name, mode, kind, oid, exported_path(label, name)) for name, mode, kind, oid in tree if exported_path(label, name)]
    if not selected:
        raise ValueError('No build inputs: ' + label)
    # Batch object reads avoid copying .git, symlinks or local ignored files.
    proc = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    records = []
    try:
        for name, mode, kind, oid, target in selected:
            if kind != 'blob' or mode not in ('100644', '100755'):
                raise ValueError('Unexpected symlink/submodule input: ' + name)
            proc.stdin.write((oid + '\n').encode()); proc.stdin.flush()
            response = proc.stdout.readline().decode().split()
            if len(response) != 3 or response[0] != oid or response[1] != 'blob':
                raise ValueError('Invalid Git blob response')
            data = proc.stdout.read(int(response[2]))
            if proc.stdout.read(1) != b'\n' or hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() != oid:
                raise ValueError('Git blob integrity failure: ' + name)
            p = dest / target
            p.parent.mkdir(parents=True, exist_ok=True)
            with p.open('xb') as f:
                f.write(data)
            records.append({'repository': label, 'source': name, 'output': target,
                            'git_blob': oid, 'sha256': sha(data), 'bytes': len(data)})
    finally:
        proc.stdin.close()
        proc.stdout.close()
        if proc.wait() != 0:
            raise RuntimeError('Git object reader failed')
    return records

def prepare_project(data, expected):
    if sha(data) != expected:
        raise ValueError('Unexpected upstream Xcode project')
    text = data.decode()
    # Remove only the three exact target edges: daemon dependency, installer
    # copy and ZIP archive. Remove the now-unreferenced shell phase definition
    # too, so no shell build phase exists in the prepared project.
    for line in ('\t\t\t\t4CC5A8C1244611D300AB526E /* CopyFiles */,\n',
                 '\t\t\t\t4C8C666424460F3C00D694EB /* Archive */,\n',
                 '\t\t\t\t4C8C666324460F2D00D694EB /* PBXTargetDependency */,\n'):
        if text.count(line) != 1:
            raise ValueError('Unexpected project build edge')
        text = text.replace(line, '')
    start = '/* Begin PBXShellScriptBuildPhase section */'
    end = '/* End PBXShellScriptBuildPhase section */'
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError('Unexpected project shell phases')
    a = text.index(start); b = text.index(end) + len(end)
    text = text[:a] + text[b:]
    if 'shellScript =' in text or 'PBXShellScriptBuildPhase' in text:
        raise ValueError('Remaining shell phase')
    return text.encode()

def apply_overlay(dest):
    m = json.loads((BASE / 'upstream-manifest.json').read_text())
    for name, digest in m['sha256_before'].items():
        if sha((dest / name).read_bytes()) != digest:
            raise ValueError('Unexpected upstream patch input: ' + name)
    for name in m['added_paths']:
        if (dest / name).exists():
            raise ValueError('Added patch path already exists: ' + name)
    for name, digest in m['sha256_after'].items():
        data = (BASE / 'upstream-overlay' / name).read_bytes()
        if sha(data) != digest:
            raise ValueError('Unexpected expanded overlay: ' + name)
        (dest / name).write_bytes(data)
    # These are the exact expanded outputs of the independently checked patch.
    for name in ('FXProfileABI.h', 'FXFnABI.h'):
        if (dest / 'AsusSMC' / name).read_bytes() != (BASE / 'include' / name).read_bytes():
            raise ValueError('Kernel/client ABI header mismatch')
    spec = json.loads((BASE / 'build/inputs.json').read_text())['build']
    for name, macro, expected in [('FXProfileABI.h', 'FX_PROFILE_ABI_VERSION', spec['profile_abi']),
                                  ('FXFnABI.h', 'FX_FN_ABI_VERSION', spec['fn_abi']),
                                  ('FXProfileABI.h', 'FX_PROFILE_CONNECT_TYPE', int(spec['connection_type'], 16))]:
        text = (dest / 'AsusSMC' / name).read_text()
        match = re.search(r'^#define ' + macro + r' (0x[0-9a-fA-F]+|[0-9]+)u$', text, re.M)
        if not match or int(match.group(1), 0) != expected:
            raise ValueError('Manifest ABI value mismatch: ' + macro)

def run_logged(command, output, label, receipt, cwd=None, env=None):
    log = output / (label + '.log')
    with log.open('xb') as stream:
        p = subprocess.run(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
    receipt['steps'].append({'label': label, 'command': command, 'exit': p.returncode,
                             'log': log.name, 'log_sha256': sha(log.read_bytes())})
    write_json(output / 'BUILD_RECEIPT.json', receipt)
    if p.returncode:
        raise RuntimeError(label + ' failed; partial output and log retained')

def native_tools(iasl):
    if platform.system() != 'Darwin':
        raise ValueError('Native cohort build requires macOS, Xcode and the Apple SDK; Linux object checks are separate')
    for tool in ('xcodebuild', 'xcrun', 'sh', 'git'):
        if not shutil.which(tool):
            raise ValueError('Missing build tool: ' + tool)
    iasl_path = shutil.which(iasl)
    if not iasl_path:
        raise ValueError('Missing existing ACPICA iasl; this recipe installs nothing')
    iasl_path = str(Path(iasl_path).resolve())
    version = capture([iasl_path, '-v']).decode()
    if not re.search(r'ASL\+ Optimizing Compiler/Disassembler version 20250404\b', version):
        raise ValueError('Use the fixed ACPICA 20250404 compiler; got ' + version.strip())
    sdk = Path(capture(['xcrun', '--sdk', 'macosx', '--show-sdk-path']).decode().strip())
    settings = next((p for p in (sdk / 'SDKSettings.json', sdk / 'SDKSettings.plist') if p.is_file()), None)
    if not settings:
        raise ValueError('Cannot identify Apple SDK settings')
    info = {'xcode': capture(['xcodebuild', '-version']).decode(),
            'compiler': capture(['xcrun', '--sdk', 'macosx', 'clang++', '--version']).decode(),
            'sdk_version': capture(['xcrun', '--sdk', 'macosx', '--show-sdk-version']).decode().strip(),
            'sdk_path': str(sdk), 'sdk_settings_sha256': sha(settings.read_bytes()),
            'iasl_version': version, 'iasl_sha256': sha(Path(iasl_path).read_bytes())}
    return iasl_path, info

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', required=True, type=Path, help='Directory containing four clean pinned Git checkouts named as build/inputs.json')
    p.add_argument('--output', required=True, type=Path, help='New directory only')
    p.add_argument('--iasl', default='iasl', help='Already installed official ACPICA 20250404 compiler')
    p.add_argument('--prepare-only', action='store_true', help='Verify/export/patch source only; works without Apple tools')
    args = p.parse_args()
    delivery = verify_delivery()
    spec = json.loads((BASE / 'build/inputs.json').read_text())
    tools = None
    if not args.prepare_only:
        tools = native_tools(args.iasl)
    inputs = args.inputs.resolve()
    trees = {name: source_tree(inputs / name, item['commit']) for name, item in spec['sources'].items()}
    if args.output.is_symlink():
        raise ValueError('Output cannot be a symlink')
    out = args.output.resolve()
    for protected in (BASE.resolve(), inputs):
        if out == protected or protected in out.parents:
            raise ValueError('Output must be outside component and input source directories')
    if out.exists() or out.is_symlink():
        raise ValueError('Choose a new output directory; never overwrite prior results')
    out.mkdir(parents=True)
    out = out.resolve()
    source = out / 'source'; source.mkdir()
    receipt = {'state': 'preparing', 'source_pins': spec['sources'], 'steps': [],
               'component_manifest_sha256': sha((BASE / 'MANIFEST.sha256').read_bytes()),
               'component_files': delivery, 'build': spec['build'],
               'hardware_testing': 'not performed', 'native_tools': tools[1] if tools else None}
    write_json(out / 'BUILD_RECEIPT.json', receipt)
    try:
        exported = []
        for name in spec['sources']:
            exported += export_sources(name, inputs / name, trees[name], source)
        write_json(out / 'EXPORTED_INPUTS.json', exported)
        project = source / 'AsusSMC.xcodeproj/project.pbxproj'
        project.write_bytes(prepare_project(project.read_bytes(), spec['upstream_project_sha256']))
        apply_overlay(source)
        receipt['prepared_project_sha256'] = sha(project.read_bytes())
        receipt['state'] = 'source-prepared'
        write_json(out / 'BUILD_RECEIPT.json', receipt)
        if args.prepare_only:
            print('Prepared pinned source only; no compiler or hardware operation invoked.')
            return
        command = ['xcodebuild', '-project', str(project.parent), '-target', 'AsusSMC',
                   '-configuration', 'Release', '-sdk', 'macosx', 'build',
                   'ARCHS=x86_64', 'VALID_ARCHS=x86_64', 'ONLY_ACTIVE_ARCH=NO',
                   'MACOSX_DEPLOYMENT_TARGET=10.15', 'CODE_SIGNING_ALLOWED=NO',
                   'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=',
                   'RUN_CLANG_STATIC_ANALYZER=NO', 'DEPLOYMENT_POSTPROCESSING=NO',
                   'STRIP_INSTALLED_PRODUCT=NO', 'COPY_PHASE_STRIP=NO',
                   'SYMROOT=' + str(out / 'products'), 'OBJROOT=' + str(out / 'objects'),
                   'DSTROOT=' + str(out / 'unused-dst')]
        run_logged(command, out, 'kext', receipt, cwd=source)
        run_logged(['sh', str(BASE / 'tools/build_app.sh'), str(out / 'userland')], out, 'userland', receipt)
        env = dict(os.environ, IASL=tools[0])
        run_logged(['sh', str(BASE / 'tools/build_acpi.sh'), str(out / 'acpi')], out, 'acpi', receipt, env=env)
        required = ['products/Release/AsusSMC.kext/Contents/MacOS/AsusSMC',
                    'products/Release/AsusSMC.kext/Contents/Info.plist', 'userland/fxprofile',
                    'userland/FX505GT Control.app/Contents/MacOS/FX505GTControl',
                    'userland/FX505GT Control.app/Contents/Helpers/fxradio',
                    'userland/FX505GT Control.app/Contents/Info.plist', 'userland/FXBuildIdentity.h',
                    'acpi/SSDT-FX505GT-Fn-BIOS303.aml']
        receipt['outputs'] = {n: {'sha256': sha((out / n).read_bytes()), 'bytes': (out / n).stat().st_size} for n in required}
        identity = (out / 'userland/FXBuildIdentity.h').read_text()
        for macro, name in [('FX_EXPECTED_HELPER_SHA256', 'userland/fxprofile'),
                            ('FX_EXPECTED_RADIO_SHA256', 'userland/FX505GT Control.app/Contents/Helpers/fxradio')]:
            if '#define ' + macro + ' "' + receipt['outputs'][name]['sha256'] + '"' not in identity:
                raise ValueError('Companion identity/hash mismatch: ' + macro)
        receipt['state'] = 'built-not-installed-or-executed'
        write_json(out / 'BUILD_RECEIPT.json', receipt)
        print('Built one default-off cohort; output hashes recorded. Native runtime/hardware validation remains pending.')
    except Exception as error:
        receipt['state'] = 'failed'; receipt['failure'] = str(error)
        write_json(out / 'BUILD_RECEIPT.json', receipt)
        raise

if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError, OSError) as error:
        sys.exit(str(error))
