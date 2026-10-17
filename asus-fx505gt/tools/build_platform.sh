#!/bin/sh
# SPDX-License-Identifier: MIT
# Build only. Never executes helpers, changes permissions, or installs anything.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then echo 'Platform app build requires macOS and the Apple SDK.' >&2; exit 3; fi
out=${1:?Choose a new output directory}
if [ -e "$out" ] || [ -L "$out" ]; then echo 'Refusing to overwrite output.' >&2; exit 2; fi
mkdir -p "$out"
app="$out/华硕控制.app"
mkdir -p "$app/Contents/MacOS"
xcrun --sdk macosx clang -arch x86_64 -fobjc-arc -Wno-deprecated-declarations -Werror=unguarded-availability-new \
  -mmacosx-version-min=10.15 -I"$base/include" "$base/platform/AsusControl.m" \
  -framework Cocoa -framework IOKit -o "$app/Contents/MacOS/AsusControl"
xcrun --sdk macosx clang -arch x86_64 -fobjc-arc -Wno-deprecated-declarations -Werror=unguarded-availability-new \
  -mmacosx-version-min=10.15 -I"$base/include" "$base/platform/AsusAwake.m" \
  -framework Foundation -framework IOKit -o "$out/AsusAwake"
cp "$base/platform/Info.plist" "$app/Contents/Info.plist"
printf 'Built platform application and helper only: %s\n' "$out"
