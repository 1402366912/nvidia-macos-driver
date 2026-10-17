# FX505GT Control: native menu-bar app source

Status: source WIP; no native compilation or hardware/runtime validation in
this Linux workspace. This is a real AppKit/IOKit implementation, not an HTML
mock-up. It requires a native Apple SDK build and the matching patched AsusSMC.

## Implemented boundary

- Ordinary console-user process. It refuses root or differing real/effective UIDs. No login item,
  launch daemon, persistent privileged helper service or auto-installation.
- The profile UI reads fixed profile ABI1 directly through IOKit, shows capability
  support and always labels **current profile unknown** separately from the
  last firmware-acknowledged command. Unsupported/unavailable states disable
  profile controls. Firmware errors and raw results remain inspectable.
- Each profile write requires an explicit app confirmation, then invokes
  macOS administrator authorization for one of three constant shell commands.
  No user-supplied shell string, profile text, path, UID or password is used.
  Cancellation is terminal; no automatic retries. macOS may reuse a recent
  authorization for five minutes, so a fresh password dialog is not promised.
- Only `/Library/PrivilegedHelperTools/org.fx505gt.fxprofile` is accepted.
  Every path component must be a real root-owned, non-group/other-writable
  directory; the file must be regular, root-owned, executable, single-link,
  non-setuid/non-setgid and non-writable by nonroot. All extended ACL entries
  are conservatively rejected. `O_NOFOLLOW` and inode/device checks defend
  the final open. The helper's SHA-256 must equal this app's exact build
  companion; `--identity` must match profile/Fn ABI and compiled source hash.
  A privileged/root actor remains able to change system files/configuration.
- The helper is an ordinary CLI executable, not a setuid file or daemon. It
  checks effective UID; the kernel separately rechecks root on every write.
  Validating `--identity` never opens a device; the three profile commands do.

## Full Fn session actions

Enable the dedicated ACPI contract only after reviewing `../FN_MATRIX.md` and
its BIOS-specific source evidence. The app's “Handle dedicated Fn session
  actions this launch” option starts off each launch. The kernel grants one
exclusive lease to one active-console userclient; it cannot be stolen by a
second client while live. The owner must poll within two seconds. Switching
console user, sleep, close, lease expiry and disconnect clear queued actions.
No-client presses are dropped. Old events are not replayed when the app starts.
The queue accepts only kernel-decoded fixed ACPI events, no injection selector.
A malicious same-console process can compete for the claim (denial of service),
but this API does not confer root or allow injected power/profile commands.

Normal HID Fn actions stay in AsusSMC and are not synthesized again by this app.
F4 toggles only a readable, settable master mute on the default input device;
unsupported inputs remain explicitly unsupported.

F6 uses only a unique AppleBacklightDisplay internal panel advertising a
well-formed `dsyp` power parameter with range0..2. Public IODisplay calls
request Off0 or the saved prior state1/2; if already Off without a saved state,
the explicit request is On2. The prior state is bound to the same registry ID
and discarded on session/sleep notifications or a failed/changed service.
There is no automatic startup/wake restoration, no brightness substitution,
and no all-display fallback. The returned value is a driver-maintained
parameter after handler acceptance, not measured physical panel power. BIOS303
BLCT/SPBI/GPBL are not used as a hardware control/readback interface.

F11 uses real IOPMSleepSystem. Enabling physical Fn actions each launch grants
explicit permission for genuine queued Fn events, so a physical FnF11 does not
show a redundant per-press dialog. The manual menu action still confirms.
Queued events are checked against their dedicated code/action mapping. No
power action runs at startup or merely because the listener is enabled.

F12 is labeled **Wi-Fi + Bluetooth control**, not universal RF silence. The
Bluetooth companion is separately off by default each launch. Its enable
confirmation explains private-API compatibility, possible native Bluetooth
permission prompts and connection loss. Denial/timeout/unknown state disables
it. The helper cannot pair, scan, list devices, accept arbitrary commands or
run with root/differing UIDs. It reads only power state and optionally requests
fixed0/1 using symbols verified in pinned blueutil; public controller state
and private preference must agree. Availability is not a promise that a
particular non-Apple adapter supports power-off. Each set has an independent
post-read, and failure never becomes a success indicator.

F12 first validates Bluetooth and every enumerated CoreWLAN interface (1..8,
unique nonempty names). If any is On, the target is Off; only when all report
Off does it request On. Bluetooth is processed before Wi-Fi so an unsupported
Bluetooth write does not also disconnect Wi-Fi. Every interface is reread;
identity/state changes cancel before writes where possible. Partial failure
is explicitly mixed/unknown, with no rollback, fallback or automatic retry.
Other radios/WWAN and physical RF output are outside these reported states.

The companion's fixed app-bundle path and every ancestor must be real,
root/current-user-owned and non-group/world-writable, with no ACL allow entry.
The final file must be executable, regular, single-link, non-setuid/non-setgid
and match the build-embedded SHA-256. Hashing is size-bounded and followed by
fd/path identity/metadata checks. A same-user or root actor able to replace the
app itself remains outside this trust boundary; it is not a privilege boundary.
Use a trusted nonshared app location for a future test, not a writable /tmp
ancestor. No permission or ownership changes are performed by the build.

The helper starts a five-second alarm after startup/initial console checking;
the parent gives each launched child a separate six-second deadline and kills
only that task on timeout. Output is bounded and must be exactly`0\n`or`1\n`.
These are per-child deadlines, **not an end-to-end F12/UI latency guarantee**.
Foundation/CoreWLAN calls are synchronous and can still block; this requires
native validation. No framework hang is reported as a successful request.

## Cohort compatibility

Profile ABI1, Fn ABI2 and connection type`0x46583250` are a matching cohort.
The connection-type change rejects the earlier kext/client cohort before any
command. The app also checks Fn batch version and both profile-helper
ABI/source identity and exact compiled binary hash. Rebuild all members.

## Build only on macOS

```
sh tools/build_app.sh /new/output/path
```

The script uses `xcrun --sdk macosx clang++`, builds the CLI companion first,
embeds its exact hash/ABI/source identity in the app, builds the fixed radio
companion with its native privacy-purpose plist, pins its resulting SHA-256,
then builds AppKit source. Neither helper is executed by this script.
It neither executes the results nor accesses IOKit devices, installs software,
signs/notarizes, changes OS security, or places a helper. Any compiler/linker
failure is a real native-build blocker, not a simulated success. It requires
macOS 10.15+ with a current Apple SDK; compatibility remains untested.

A future separately authorized native test must provision the exact built
`fxprofile` at the fixed helper path with appropriate root ownership and
permissions. This preview supplies no installer and performs no provisioning.
Do not make it setuid. Do not weaken Gatekeeper/SIP or add broad writable paths.
Signing/rebuilding the CLI changes its digest: regenerate/rebuild the matching
app, never edit the expected digest to admit an unrelated executable.

The `x-apple.systempreferences` Bluetooth shortcut may differ by macOS release;
if it fails, open Bluetooth settings manually. The separate opt-in radio
companion does use the explicitly documented private power API boundary.

Active-console UID checks are not lock-screen verification. Session-inactive
notifications invalidate pending app confirmations, and console/generation
checks are repeated before actions. An already committed firmware request
cannot be undone by a later session change; its current hardware state remains
unknown. Authorization cancellation never triggers an automatic retry.

## On-screen Fn feedback (source v5)

See [OSD_REFERENCE.md](../OSD_REFERENCE.md) for the inspected ASUS Windows visual
references and exact-match limits. `FXFeedback.mm` is a native AppKit nonactivating
panel, not a web mockup. It uses original vector artwork, optional per-category
OSD settings, a lower-center ASUS-family reference position or exact-center menu
option, state-qualified captions, and cancellation-safe timers. Physical-key
feedback requires the existing Fn listener; the OSD switch alone cannot enable
hardware actions. Volume/brightness/keyboard-light custom overlays default off
to avoid duplicating macOS. Native SDK build, rendering and runtime QA remain
pending. No proprietary assets or Windows components are bundled.
