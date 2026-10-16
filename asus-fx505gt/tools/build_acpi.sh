#!/bin/sh
# SPDX-License-Identifier: MIT. Compile source only, never execute/install AML.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
iaslv=${IASL:-iasl}
if ! command -v "$iaslv" >/dev/null 2>&1; then
  echo 'ACPICA iasl is required. Use an official OS package or ACPICA source build; this script installs nothing.' >&2
  exit 3
fi
out=${1:-./fx505gt-acpi-build}
if [ -e "$out" ] || [ -L "$out" ]; then echo 'Choose a new output directory; refusing to overwrite results.' >&2; exit 2; fi
mkdir -p "$out"
out=$(CDPATH= cd -- "$out" && pwd)
"$iaslv" -v > "$out/tool-version.txt"
if "$iaslv" -we -p "$out/SSDT-FX505GT-Fn-BIOS303" "$base/acpi/SSDT-FX505GT-Fn-BIOS303.dsl" > "$out/compiler.log" 2>&1; then
  cat "$out/compiler.log"
else
  status=$?; cat "$out/compiler.log" >&2; exit "$status"
fi
printf 'Compiled default-off SSDT source in %s. No AML was executed, loaded or installed.\n' "$out"
printf 'The matching exact-hash DSDT rename and full ACPI namespace review remain required before any authorized deployment.\n'
