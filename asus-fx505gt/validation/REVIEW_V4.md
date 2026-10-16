# Build-readiness review v4

## Changed implementation

- Narrow PRIVATE macro scope around the new IOUserClient SDK imports. Real
  KeyImplementations.cpp object compilation exposed the collision; the original
  failure and successful final compile are retained. No platform header edit or
  mock was used to suppress the error.
- App, CLI and radio source build scripts explicitly target x86_64; standalone
  CLI now shares the macOS 10.15 minimum.
- Fixed-input clean source exporter and native cohort builder. All source bytes
  come from the fixed Git objects or the hash-verified expanded overlay.
- No upstream shell build phase remains after exact-project transformation.
  Original source target entries stay intact; daemon, installer and ZIP target
  edges are removed. No input checkout is edited.
- Output hashes cover the kext/app/CLI/radio/plists/identity header/SSDT. App
  companion hashes are independently checked against its generated header.
- No profile, power, radio or ACPI runtime action was added or executed.

## Actual checks

- All four kext target translation units compile to real x86_64 Mach-O objects
  with no final diagnostics. Exact second replay matches all four object hashes.
- 392 used dependency files are separately hashed. The mixed public header
  closure and inherited/generated-header limitations are explicit; this is not
  claimed to be a full pure-MacKernelSDK or final Apple SDK build.
- Source exporter tests reject dirty/wrong-pin inputs and symlink blobs; exclude
  CI/installer inputs. Exact original project transformation and nine-file
  expanded overlay pass, with shared ABI checks and default-off flags preserved.
- Fresh patch application equals the expanded overlay. Portable policy/ABI/parser
  tests pass; unchanged SSDT retains its prior actual ACPICA pass.
- Python/shell/plist syntax checked. Published material is UTF-8 source/text only.

## Remaining qualification

The complete four-checkout native cohort command, native final linkage and
Objective-C++ app/helper builds have not run. There is no Apple SDK in this
workspace. A successful object compile does not qualify runtime kernel ABI,
privileges, attachment, sleep/wake, UI, permission behavior, or physical keys,
fan policy, panel power or radios. No hardware/environment settings were changed.
