# Full-Fn/menu app source review, 2026-10-16

Scope: the new fixed Fn ABI/router/queue, native app source, helper permission
boundary, and exact public BIOS303 offline ACPI candidate. This is a source
review and portable CPU validation, **not native compilation or hardware QA**.

Reviewed corrections applied:

- Exact FX505GT manual14-key layout replaces guesses based on generic ASUS
  patch filenames. BIOS303 public DSDT source resolves each candidate _Q method.
- Conflicting raw ASUS0x35/0x5E/0x7D meanings are not mapped to new power actions.
  Dedicated routes preserve IANE→queue→0xFF→_WED and do not create DMES.
- Source-only DSDT transformation verifies the exact whole-file hash, original
  OEM/header/revision/checksum and method-body hashes. It changes14 definition
  name bytes plus the checksum only. SSDT defaults off; original bodies remain
  the non-Darwin/disabled path. Native F11 sleep notification is not duplicated.
- Missing SKBV is addressed with a typed0..255 adapter to the verified root
  SLKI method, with explicit source opt-in and no arbitrary EC interface.
- Claim/read identity checks bind to the userclient owner and active console.
  One live client has a bounded lease. Owner-only release remains possible
  after console loss, explicit reclaim clears old queue, and lease age uses
  current gated time rather than an older ACPI arrival timestamp.
- Queue consumption is once-only, expired/no-consumer events are dropped,
  suspension/close/session loss clear state, and no userspace injection selector
  exists. Same-console denial-of-service competition remains possible; this
  is not cryptographic app authentication or a lock-screen attestation.
- Session changes invalidate pending app confirmations via a generation
  counter; console/generation are rechecked after dialogs before action.
- Helper parent/file checks reject nonroot ownership, writable permissions,
  symlinks, hardlinks, setuid/setgid and any extended ACL. Darwin ACL semantics
  differ from Linux and are explicitly handled/tested in shared policy.
- The exact helper binary SHA-256 plus ABI/source identity are pinned into the
  companion app. No arbitrary shell text/input/path or stored password exists.
  Native authorization may be cached by macOS; every app write still requires
  explicit user confirmation. No installer/login item/daemon is supplied.
- Objective-C++ helper-path linkage is explicit; app delegate lifetime is
  retained across the run loop. Build-only scripts refuse existing outputs.

Independent portable reruns passed profile policy, all14 dedicated routes,
queue debounce/expiry/no-replay, shared C ABI, helper metadata/ACL decisions,
and Linux CLI parser/no-fake-device checks. Exact BIOS303 offline test passed
and rejected truncated, mutated, wrong-signature and already-patched inputs.

Remaining boundaries:

- Apple SDK/Xcode/IOKit runtime are unavailable here. App/kext native builds
  remain pending. After this source review, an official locally extracted
  Debian ACPICA package was used: an ASL External syntax defect was found,
  corrected, and the actual SSDT now compiles cleanly with warnings as errors.
  See ACPI_BUILD.md for the inherited DSDT baseline failures. No AML was
  executed or installed. Source/static review cannot prove macOS compatibility.
- BIOS303 source-derived physical key correlation is not an observed event
  trace from this user's machine. Other tables/BIOS versions are rejected.
  Other installed SSDTs also require namespace/collision review.
- F4 needs a settable input mute; F6 is all-display sleep rather than panel
  on/off; F9 needs graphics/external-display support; F10 depends on compatible
  touchpad notification consumers; F12 controls primary Wi-Fi only and leaves
  Bluetooth/other radios unchanged. These limits stay visible in the app/matrix.
- Existing AsusSMC VirtualSMC integration refuses unloading and retains
  inherited notifier/poller teardown limitations. New defensive userclient
  teardown does not make the full upstream kext unload/reload-safe.
- Firmware result1 acknowledges a request, never measured mode/RPM. No
  runtime device access, kext/app installation or execution, ACPI deployment,
  profile write, reboot or OS security change was performed.
