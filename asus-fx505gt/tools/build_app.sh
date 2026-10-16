#!/bin/sh
# SPDX-License-Identifier: MIT. Build only: never installs, runs, signs or loads.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then echo 'Native app build requires macOS and the Apple SDK.' >&2; exit 3; fi
out=${1:-./fx505gt-build}
if [ -e "$out" ] || [ -L "$out" ]; then echo 'Choose a new output directory; refusing to overwrite existing results.' >&2; exit 2; fi
mkdir -p "$out"
out=$(CDPATH= cd -- "$out" && pwd)
# Version binds the helper to the exact compiled CLI/ABI source bytes. The
# companion app also pins the resulting helper binary's SHA-256, so signing
# or rebuilding that binary requires regenerating/rebuilding the app.
version=$(cat "$base/cli/fxprofile.cpp" "$base/include/FXProfileABI.h" "$base/include/FXFnABI.h" | shasum -a 256 | awk '{print $1}')
printf '#define FX_SOURCE_VERSION "%s"\n' "$version" > "$out/FXBuildIdentity.h"
xcrun --sdk macosx clang++ -std=c++14 -Wall -Wextra -Werror -Wno-deprecated-declarations \
  -mmacosx-version-min=10.15 -I"$base/include" -include "$out/FXBuildIdentity.h" \
  "$base/cli/fxprofile.cpp" -framework IOKit -framework CoreFoundation -o "$out/fxprofile"
helperhash=$(shasum -a 256 "$out/fxprofile" | awk '{print $1}')
printf '#define FX_EXPECTED_HELPER_SHA256 "%s"\n' "$helperhash" >> "$out/FXBuildIdentity.h"
printf '#define FX_EXPECTED_HELPER_IDENTITY "org.fx505gt.fxprofile abi=1 fnabi=1 source=%s\\n"\n' "$version" >> "$out/FXBuildIdentity.h"
app="$out/FX505GT Control.app"
mkdir -p "$app/Contents/MacOS"
xcrun --sdk macosx clang++ -std=c++14 -fobjc-arc -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -mmacosx-version-min=10.15 \
  -I"$base/include" -I"$base/app" -I"$out" \
  "$base/app/main.mm" "$base/app/FXHelperTrust.mm" "$base/app/FXSessionActions.mm" \
  -framework AppKit -framework IOKit -framework CoreFoundation -framework CoreAudio \
  -framework CoreWLAN -framework SystemConfiguration -o "$app/Contents/MacOS/FX505GTControl"
cp "$base/app/Info.plist" "$app/Contents/Info.plist"
printf 'Built source preview in %s. Nothing installed or executed.\n' "$out"
printf 'Helper SHA-256: %s\nSource version: %s\n' "$helperhash" "$version"
