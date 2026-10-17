# PR #1 integration audit

Original field-tested PR head: `67a0c9b5c1be6f0ad817b16e74ea74bc61371aac`.
Preserved main OSD parent: `378a82d79699304b49c53322416f474436a26b40`.
Common ancestor: `14ea9f3aad2c1467fe5abb91a71d7a3b98e011eb`.

Five content conflicts were resolved: component manifest, panel actions, session actions,
main app, and app README. Field behavior takes precedence for dsyp/bklt fallback,
ordered ABI3 brightness, saved Fn/Bluetooth preferences, unified platform sleep/lid
handling and itlwm fallback. The generic main OSD remains read-only; typed results
are passed only after actual successful backend readback. The separate field microphone
HUD is replaced by that single controller, avoiding duplicate overlays. A posted sleep
notification is not represented as confirmed system sleep acceptance.

The existing field driver, ACPI, platform and audio implementation is retained.
The pinned build manifest had a pre-existing `fn_abi: 2` mismatch against actual ABI3
headers; it is corrected to 3. The initial failed full preparation receipt is retained.
No firmware, driver, native app or native helper was installed or executed here.

## Scope of original field evidence

- User confirmed F6/F7/F8 physical screen controls.
- F1/F2/F3 were confirmed during VoodooHDA 3.6.8, before the later native audio stack.
- AppleALC 1.9.8 + SimpleHDA 1.0.0 loaded with ALC235/layout24, default input/output
  enumerated, and native F4 mute properties alternated with successful readback.
- Profile silent command received raw1/IOReturn0; this is not measured fan RPM.
- Lid-only/global sleep state separation was observed, including global=1 by user choice.
- These facts do not establish real native recording, full sleep/wake, F12 RF effect,
  F9 external display, F10 touchpad, keyboard lighting, or all 14 physical functions.

## Verification of integrated source

Portable policy tests and source-contract tests are separate from native hardware QA.
The full pinned upstream preparation/overlay/hash/cohort test passes after the metadata
correction. The AppKit build remains blocked on this Linux host: macOS and Apple SDK
are required. The integrated app is therefore not claimed newly hardware-tested.
Historical field receipts are preserved unchanged. GitHub has no workflow definitions;
merge commits use `[skip ci]`, and no Actions workflow is requested.
