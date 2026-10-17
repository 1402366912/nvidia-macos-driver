> Current FX505GT deployment: all fourteen method definitions match this
> fixture, while the complete loaded DSDT differs. The exact current-table
> OpenCore patch generator and enabled SSDT deployment are documented in
> [field-20261017](../field-20261017/README.md). The historical fixture-only
> transformation below remains unchanged; it is not the current install path.

# Exact public FX505GT BIOS303 ACPI candidate

This is a source-derived route, not a claim that the user's firmware is BIOS303
or that physical key delivery has been tested. The public attachment was posted
in faustus issue #56 with FX505GT BIOS303 / 2019-08-29 / board FX505GT 1.0.
The SHA-256, exact OEM header/revision and all 14 method-definition/body hashes
are recorded in `BIOS303-provenance.json`. Other BIOS revisions and even another
different BIOS303 dump are rejected. No firmware dump is redistributed here.

The original source uses `ATKD.IANE(code)` → `IANQ` queue → Notify(ATKD,0xFF) →
`_WED(0xFF)` → `GANQ()`. There is no DMES marker. The synthetic 16-bit values fit
the unmasked queue. **Do not add DMES** or use direct Notify(F5xx): that would
cause AsusSMC to decode the wrong event. This source keeps the original queue.

## Offline preparation only

1. Independently obtain the exact public attachment referenced by the manifest.
   Retain original bytes. Do not substitute a current machine's different dump.
2. `python3 tools/prepare_bios303_dsdt.py original.aml new-renamed.aml`
   verifies the complete SHA-256, original ACPI header/checksum and each unique
   AML MethodOp definition, then changes only its four-byte name to XQxx and
   updates the table checksum. It does not change package lengths, replace
   method bodies, alter a bootloader config, or install/apply anything.
3. Review `SSDT-FX505GT-Fn-BIOS303.dsl`, then build only with an official
   ACPICA iasl tool: `sh tools/build_acpi.sh /new/output/path`. The exact current
   source was compiled offline with ACPICA20250404 and `-we`: **0 errors,
   0 warnings,0 remarks**. No AML was executed or installed.
4. The renamed DSDT and the compiled matching SSDT are an inseparable candidate
   pair. Never deploy only one. Deployment/bootloader configuration is outside
   this source deliverable and requires separate hardware authorization/review.

The SSDT defines the original _Qxx names at the exact EC0 scope. Under
`_OSI("Darwin")` and explicit source flag `EC0.FXEN=One`, each wrapper sends one dedicated event `0xF501..0xF50E`.
For other OSes it calls the preserved XQxx body, preserving original behavior.
The Darwin branch does **not** also call the old body: in particular F11 does
not also send the native sleep-button notification, and F12 does not also
send the ASHS radio notification. This avoids two actions per key. Existing
BIOS/hardware side effects outside these methods still require physical tests.
Do not combine this with another hotkey remapper or old f1–f12 patch set.

This requires `FX505GTDedicatedFnContractEnabled=true`, declared model FX505GT,
a verified AsusSMC WMI method and a fully awake system. FnF5 firmware writes
also require the separate profile/FnF5 opt-ins and a supported backend.
All kext flags remain false and the SSDT itself declares `FXEN=Zero` in the
delivered source. A separately reviewed native test must explicitly change
that source flag before compiling. Without it, wrappers call the original
bodies and the added SKBV adapter makes no firmware call. Session actions need
the foreground app's explicit per-launch listener and exclusive claim.

The source correlation uses both the official keyboard sequence and contiguous
query method bodies; it is strong BIOS-specific evidence, not a measured
physical-key trace. Source metadata alone cannot establish user hardware
identity or native driver functionality.

## Keyboard-light adapter

This exact BIOS303 dump has no SKBV method, but has root `\SLKI` and an ATKD
SLKB wrapper resolving to it. The added bounded SKBV adapter accepts only
integers0..255 from stock AsusSMC, maps `floor(value/16) | 0x80` and calls
`\SLKI` only in the explicitly enabled Darwin branch. This reproduces the
pinned upstream TUF adapter's interface facts using independently written
source, with explicit argument bounds. No EC offset or arbitrary payload is
exposed. The nibble0..15 is a protocol range, not16 hardware-verified brightness
steps. See the pinned KeyImplementations.cpp and kbl_tuf.txt sources.

The exact DSDT namespace checks do not inspect other installed SSDTs. A future
deployment review must also exclude collisions with their FXEN/SKBV/XQ symbols
and any other hotkey remapping; this source does not modify those tables.

## Actual compiler validation

The original and renamed BIOS303 DSDTs both disassembled successfully. Their
recompiles both have the same inherited10 duplicate-Case errors,221 warnings
and637 remarks; normalized diagnostics are identical. This is not a successful
full DSDT source recompile. The transformer operates on the validated original
AML bytes without editing those inherited method bodies. Do not “fix” unrelated
firmware constructs merely to hide compiler diagnostics. Compiler/package
provenance, source/output hashes and retained failure evidence are summarized
in `../validation/ACPI_BUILD.md` and `../validation/acpi-validation.json`.

The actual candidate path is guarded **binary definition-name renaming of the
original AML plus checksum**, paired with the separately compiled new SSDT.
Recompiling the full disassembled DSDT is a diagnostic comparison only, not a
required preparation/deployment step; its inherited errors do not block the
validated byte-preserving transformation.
