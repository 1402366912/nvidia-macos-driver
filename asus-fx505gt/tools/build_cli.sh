#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then echo 'Native CLI build requires macOS and the Apple SDK.' >&2; exit 3; fi
output=${1:-./fxprofile}
if [ -e "$output" ] || [ -L "$output" ]; then echo "Refusing to overwrite existing output: $output" >&2; exit 2; fi
xcrun --sdk macosx clang++ -arch x86_64 -std=c++14 -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -mmacosx-version-min=10.15 -I"$base/include" "$base/cli/fxprofile.cpp" \
  -framework IOKit -framework CoreFoundation -o "$output"
printf 'Built %s. This script does not run it or access devices.\n' "$output"
