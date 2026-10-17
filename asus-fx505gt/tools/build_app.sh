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
xcrun --sdk macosx clang++ -arch x86_64 -std=c++14 -Wall -Wextra -Werror -Wno-deprecated-declarations \
  -mmacosx-version-min=10.15 -I"$base/include" -include "$out/FXBuildIdentity.h" \
  "$base/cli/fxprofile.cpp" -framework IOKit -framework CoreFoundation -o "$out/fxprofile"
helperhash=$(shasum -a 256 "$out/fxprofile" | awk '{print $1}')
printf '#define FX_EXPECTED_HELPER_SHA256 "%s"\n' "$helperhash" >> "$out/FXBuildIdentity.h"
profileabi=$(awk '$2=="FX_PROFILE_ABI_VERSION" {gsub(/u/,"",$3); print $3}' "$base/include/FXProfileABI.h")
fnabi=$(awk '$2=="FX_FN_ABI_VERSION" {gsub(/u/,"",$3); print $3}' "$base/include/FXFnABI.h")
printf '#define FX_EXPECTED_HELPER_IDENTITY "org.fx505gt.fxprofile abi=%s fnabi=%s source=%s\\n"\n' "$profileabi" "$fnabi" "$version" >> "$out/FXBuildIdentity.h"
app="$out/FX505GT Control.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
# Unprivileged fixed-command radio companion. The embedded plist supplies its
# native privacy purpose; neither build nor app accepts a permission prompt.
xcrun --sdk macosx clang++ -arch x86_64 -std=c++14 -fobjc-arc -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -mmacosx-version-min=10.15 -I"$base/include" \
  "$base/helpers/fxradio.mm" -framework Foundation -framework IOBluetooth \
  -framework SystemConfiguration -Wl,-sectcreate,__TEXT,__info_plist,"$base/helpers/Info.plist" \
  -o "$app/Contents/Helpers/fxradio"
radiohash=$(shasum -a 256 "$app/Contents/Helpers/fxradio" | awk '{print $1}')
printf '#define FX_EXPECTED_RADIO_SHA256 "%s"\n' "$radiohash" >> "$out/FXBuildIdentity.h"
xcrun --sdk macosx clang++ -arch x86_64 -std=c++14 -fobjc-arc -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -mmacosx-version-min=10.15 \
  -I"$base/include" -I"$base/app" -I"$out" \
  "$base/app/main.mm" "$base/app/FXHelperTrust.mm" "$base/app/FXSessionActions.mm" \
  "$base/app/FXPanelPower.mm" "$base/app/FXBluetooth.mm" "$base/app/FXFeedback.mm" \
  -framework AppKit -framework CoreGraphics -framework IOKit -framework CoreFoundation -framework CoreAudio \
  -framework CoreWLAN -framework SystemConfiguration -o "$app/Contents/MacOS/FX505GTControl"
cp "$base/app/Info.plist" "$app/Contents/Info.plist"
printf 'Built source preview in %s. Nothing installed or executed.\n' "$out"
printf 'Helper SHA-256: %s\nSource version: %s\n' "$helperhash" "$version"
printf 'Radio companion SHA-256: %s\n' "$radiohash"
