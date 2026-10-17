#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Narrow source guard, not SDK compilation or runtime verification."""
from pathlib import Path
import plistlib
base = Path(__file__).resolve().parents[1]
ui = (base / 'platform/AsusControl.m').read_text()
helper = (base / 'platform/AsusAwake.m').read_text()
build = (base / 'tools/build_platform.sh').read_text()
assert 'if(@available(macOS 11.0,*)) im=[NSImage imageWithSystemSymbolName:' in ui
assert 'else self.status.button.title=@"ASUS"' in ui
assert 'kIOMainPortDefault' not in ui + helper
assert ui.count('kIOMasterPortDefault') == 2
assert helper.count('kIOMasterPortDefault') == 2
assert build.count('-Werror=unguarded-availability-new') == 2
assert build.count('-mmacosx-version-min=10.15') == 2
assert plistlib.loads((base / 'platform/Info.plist').read_bytes())['LSMinimumSystemVersion'] == '10.15'
print('PASS: platform source minimum-version guards, missing-symbol fallback and native availability diagnostics')
print('NOT RUN: Apple SDK compile/link or macOS runtime; tested hardware logic unchanged')
