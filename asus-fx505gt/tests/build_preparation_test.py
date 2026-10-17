#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Offline preparation tests. Optional exact upstream project enables edge tests."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cohort', BASE / 'tools/build_cohort.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
p = argparse.ArgumentParser(); p.add_argument('--upstream-project', type=Path); args = p.parse_args()
assert m.safe_name('AsusSMC/test.cpp')
assert not any(m.safe_name(s) for s in ('/etc/passwd', '../test', 'a/../test', 'a\\b'))
assert m.exported_path('AsusSMC', '.travis.yml') is None
assert m.exported_path('AsusSMC', 'AsusSMCDaemon/install_daemon.sh') is None
assert m.exported_path('Lilu', 'Lilu/Headers/hde64.h') is None
assert m.exported_path('Lilu', 'Lilu/Headers/capstone') is None
assert m.exported_path('MacKernelSDK', 'Library/arm64e/libkmod.a') is None
with tempfile.TemporaryDirectory(prefix='fx-cohort-prepare-') as t:
    root = Path(t); repo = root / 'input'; repo.mkdir(); out = root / 'output'; out.mkdir()
    env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')
    def git(*a):
        return subprocess.run(['git', '-C', str(repo), *a], env=env, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    git('init'); (repo / 'AsusSMC').mkdir(); (repo / 'AsusSMC/test.cpp').write_text('/* test fixture */\n')
    (repo / '.travis.yml').write_text('excluded fixture\n'); git('add', '.')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@invalid', 'commit', '-m', 'fixture')
    pin = git('rev-parse', 'HEAD').decode().strip()
    tree = m.source_tree(repo, pin)
    items = m.export_sources('AsusSMC', repo, tree, out)
    assert len(items) == 1 and (out / 'AsusSMC/test.cpp').read_bytes() == (repo / 'AsusSMC/test.cpp').read_bytes()
    assert not (out / '.travis.yml').exists()
    (repo / 'AsusSMC/test.cpp').write_text('dirty\n')
    try: m.source_tree(repo, pin)
    except ValueError: pass
    else: raise AssertionError('dirty source accepted')
    try: m.source_tree(repo, '0' * 40)
    except ValueError: pass
    else: raise AssertionError('wrong pin accepted')
    try: m.export_sources('AsusSMC', repo, [('AsusSMC/link', '120000', 'blob', items[0]['git_blob'])], root / 'bad')
    except ValueError: pass
    else: raise AssertionError('symlink export accepted')
print('PASS: Git pin, clean input, selected verified blob export, CI/installer exclusion and symlink rejection')
if args.upstream_project:
    data = args.upstream_project.read_bytes()
    expected = json.loads((BASE / 'build/inputs.json').read_text())['upstream_project_sha256']
    result = m.prepare_project(data, expected)
    assert b'shellScript =' not in result and b'PBXShellScriptBuildPhase' not in result
    for edge in (b'4CC5A8C1244611D300AB526E /* CopyFiles */,', b'4C8C666424460F3C00D694EB /* Archive */,', b'4C8C666324460F2D00D694EB /* PBXTargetDependency */,'):
        assert edge not in result
    assert result.count(b'AsusSMC.cpp in Sources */,') == 1
    try: m.prepare_project(data + b'\n', expected)
    except ValueError: pass
    else: raise AssertionError('modified project accepted')
    print('PASS: exact upstream project hash; archive/installer/daemon target edges removed; source target retained')
    print('Prepared project SHA256:', hashlib.sha256(result).hexdigest())
    original_root = args.upstream_project.parent.parent
    manifest = json.loads((BASE / 'upstream-manifest.json').read_text())
    with tempfile.TemporaryDirectory(prefix='fx-cohort-overlay-') as directory:
        dest = Path(directory)
        for name in manifest['sha256_before']:
            path = dest / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((original_root / name).read_bytes())
        m.apply_overlay(dest)
        for name, expected_hash in manifest['sha256_after'].items():
            assert hashlib.sha256((dest / name).read_bytes()).hexdigest() == expected_hash
        import plistlib
        personality = plistlib.loads((dest / 'AsusSMC/Info.plist').read_bytes())['IOKitPersonalities']['AsusSMC']
        for key in ('FX505GTProfileBridgeEnabled', 'FX505GTProfileFnF5Enabled', 'FX505GTDedicatedFnContractEnabled'):
            assert personality[key] is False
    print('PASS: exact expanded overlay, shared ABI1/FnABI3/cohort check, all new enable flags remain false')
else:
    print('SKIP: exact upstream project transform test needs --upstream-project')
print('No native compiler, build output or hardware operation was invoked.')
