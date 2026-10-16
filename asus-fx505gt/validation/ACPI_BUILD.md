# Offline ACPICA validation — 2026-10-16

The delivered SSDT compiled with ACPICA iasl 20250404, `-we` enabled:
**0 errors, 0 warnings, 0 remarks**. Output was 1,289 bytes, SHA-256
`f5caf935e42b0dcb494b833a4ec3f5907be5abd21d7f6b289dd2e60a20f66086`.
`tools/build_acpi.sh` reproduced that output. The binary is a local validation
result only and is not distributed by this source preview.

The first real compile exposed invalid numeric third arguments in 16 ASL
`External` declarations. These were corrected to the valid two-argument form.
The initial failure is preserved in `acpi-initial-failure.txt`; the successful
compiler log is `acpi-compile.txt`. `acpi-validation.json` records exact source,
compiler, package, output and complete-log hashes, commands and exit statuses.
Paths in that record identify the validation workspace, not deployment paths.

## Actual source workflow

1. `tools/prepare_bios303_dsdt.py` accepts only the exact public BIOS303 AML
   fixture after whole-file, table-header, checksum and method-pattern checks.
   It renames 14 method-definition NameSegs and recalculates the checksum.
   Exactly 15 bytes differ; original method bodies and package lengths remain.
2. `tools/build_acpi.sh NEW_OUTPUT_DIRECTORY` separately compiles the new,
   default-off SSDT. The renamed DSDT and SSDT form an inseparable candidate
   pair, still requiring a complete machine-specific ACPI namespace review.

**Recompiling the full DSDT DSL is not a step in this transformation.**
For diagnostic comparison, both original and renamed DSDTs disassembled
successfully. Both full DSL recompiles produced the same 10 inherited
Error 6022 duplicate-Case errors, 221 warnings and 637 remarks. Normalized
multisets matched exactly; no diagnostics were suppressed or source broadly
edited. Full logs were retained locally and their hashes are in the JSON.
No replacement DSDT was produced through that failed recompilation route.

The new SSDT was also disassembled with the exact renamed DSDT for external
resolution, then recompiled with `-we`: again 0 errors/warnings/remarks. This
confirms the resolved method signatures for this pair. The round-trip AML is
not byte-identical and has its separate recorded hash. Other loaded SSDTs and
runtime firmware behavior are not established by this check.

## Compiler provenance and limits

Official Debian package `acpica-tools_20250404-1_amd64.deb`, 865,580 bytes:
[archive](https://deb.debian.org/debian/pool/main/a/acpica-unix/acpica-tools_20250404-1_amd64.deb),
[official checksum page](https://packages.debian.org/trixie/amd64/acpica-tools/download).
SHA-256: `eea598bdb5d10ae51801f7c586a51f33335c60d964f5f18203cdda47fd5ab069`.
The package was checksum-checked and extracted into a local directory, with
no system installation. No AML was executed, loaded or installed. No device
was accessed. Apple SDK compilation of the kext and native app, exact target
BIOS compatibility, and hardware behavior remain unvalidated.
