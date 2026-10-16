# Validation record

Checked 2026-10-16, CPU-only Linux environment.

Passed:
- Production portable policy compiled as C++14 with `-Wall -Wextra -Werror
  -pedantic` and ran assertions for capability masks, one-backend selection,
  unsupported/invalid/error values, strict acknowledgements, unknown current
  state, rejection recording, timestamps, Fn backend filtering/cycling/debounce,
  suspend/resume, initial zero-flag synchronization, full-wake/dark-wake
  capability changes, missing power synchronization and stopped state.
- Shared C ABI compiled with C11 strict warnings; size is 120 bytes with checked
  field offsets.
- Actual CLI compiled on Linux; help and invalid mode parsing work; valid query
  explicitly exits unavailable instead of simulating a driver connection.
- Complete patch applies to the downloaded pinned upstream source bytes; all
  seven resulting file hashes match `upstream-manifest.json`.
- Apply-tool Python syntax, shell syntax, XML plist parsing and default-off
  feature/model settings checked.

Source review fixes included:
- Ambiguous `OSNumber::withNumber(0u, 32)` changed to exact integer `0ULL`.
- `_UID` failure path initializes and releases returned objects safely.
- Notifier removal consumes its reference; no second release follows it.
- Synchronous priority power callbacks do not mistake the notification
  structure for an asynchronous acknowledgement cookie.
- Power registration occurs inside the state initialization gate; removal
  occurs outside it so a callback waiting on the gate can finish.
- Initial profile I/O is blocked until an initial or completed full-wake
  CPU+Graphics capability synchronization; missing sync remains suspended.
- Fn timestamps are captured before waiting on the gate and before ACPI probes.
- Backend-specific event filtering precedes debounce; debounce is best-effort.

The initial strict-compiler warning is retained in
`portable-initial-failure.txt`, followed by passing final logs. A compile check
of portable files is not a build of the driver.

Not run / not established:
- No macOS, Apple SDK, `xcrun` or `xcodebuild` was available. The build-only
  CLI script's expected Linux refusal is recorded in `native-build-blocker.txt`.
- Upstream VirtualSMC plugin unload remains unsupported; defensive client
  lifetime handling does not establish safe driver unload/reload.
- No native driver/CLI link, kext signature/load, native kernel ABI or ABI client
  connection; no privilege, attach/close/stop race or power-transition test.
- No source checkout with the original Git object database was materialized.
  The patch itself was applied to exact pinned file bytes. The applicator's
  additional Git HEAD guard was not exercised on a real pinned checkout here.
- No target model/BIOS/ACPI table inspection; no DSTS, DEVS, EC, kext load,
  installation, reboot, fan measurement, Fn key or physical cooling test.
- Current firmware profile remains unreadable in this protocol contract.

Next validation gate: native SDK compile and kernel review against the intended
macOS release. Hardware validation needs separate explicit authorization and a
verified FX505GT/BIOS, one allowed transition, observable response and power
lifecycle testing. This source preview must not be labeled hardware-ready.
