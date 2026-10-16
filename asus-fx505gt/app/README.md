# FX505GT Control: native menu-bar app source

Status: source WIP; no native compilation or hardware/runtime validation in
this Linux workspace. This is a real AppKit/IOKit implementation, not an HTML
mock-up. It requires a native Apple SDK build and the matching patched AsusSMC.

## Implemented boundary

- Ordinary console-user process. It refuses to run as root. No login item,
  launch daemon, persistent privileged helper service or auto-installation.
- The profile UI reads fixed ABI v1 directly through IOKit, shows capability
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
unsupported inputs remain explicitly unsupported. F6 requests all-display
sleep using Apple's fixed `pmset displaysleepnow` command, not panel-only on/off.
F11 uses real IOPMSleepSystem after confirmation. F12 confirms and toggles only
the primary CoreWLAN Wi-Fi interface, with readback; Bluetooth and other radios
remain unchanged. Bluetooth settings can be opened separately. This is not a
full airplane-mode implementation or indicator.

## Build only on macOS

```
sh tools/build_app.sh /new/output/path
```

The script uses `xcrun --sdk macosx clang++`, builds the CLI companion first,
embeds its exact hash/ABI/source identity in the app, then builds AppKit source.
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
if it fails, open Bluetooth settings manually. No private radio API is used.

Active-console UID checks are not lock-screen verification. Session-inactive
notifications invalidate pending app confirmations, and console/generation
checks are repeated before actions. An already committed firmware request
cannot be undone by a later session change; its current hardware state remains
unknown. Authorization cancellation never triggers an automatic retry.
