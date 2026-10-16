# Source review v3 — 2026-10-16

Scope: source-only F6 internal-panel power, F12 Wi-Fi + Bluetooth, and physical
Fn sleep UX. No macOS SDK compile, helper execution, device access, installation
or settings change occurred. Existing ACPICA SSDT source remains unchanged.

Concrete review findings addressed:

- Radio-helper final-file hashing alone did not protect ancestor substitution.
  Every ancestor now requires real root/current-user-owned, non-group/world-
  writable directories, valid Darwin ACLs without allow entries, and no
  symlinks. File hash reads are bounded; fd and final path metadata are checked
  after hashing. Same-user/root replacement of the entire app is outside this
  unprivileged trust boundary, not an elevation boundary.
- F6 now rechecks active console and session generation immediately before its
  fixed dsyp write; saved state is identity-bound and never restored at startup
  or wake. Readback wording explicitly describes the driver parameter cache.
- Ordinary app/helper operations reject root and differing real/effective UIDs.
- Private Bluetooth setters return void. The helper checks both public
  controller state and private preference, and the parent separately rereads
  after setting. Missing/ambiguous support disables the companion.
- Timeout claims were narrowed: helper alarm starts after startup/initial
  console checking; parent deadline is per launched child. There is no overall
  deadline for the synchronous multi-call F12 operation or CoreWLAN latency.
- Fn ABI is2. A new connection type0x46583250 rejects the old kext/client
  cohort; build identity derives ABI macros rather than hardcoding1.
- The first CPU run correctly failed an old hardcoded Fn ABI1 test assertion.
  That failure log is retained. The assertion now uses the actual shared ABI,
  with explicit ABI2/cohort assertions added; the rerun passes.

Portable tests validate the production-shared bounded power range, explicit
restore target, exact radio output parsing and companion node policy. They do
not compile Objective-C++, validate native API availability, prove child
process deadlines under macOS, or exercise real display/Bluetooth/Wi-Fi state.
Source review found no definite native type/API compile error, which is not a
substitute for the pending real Apple SDK build and unified hardware test.
