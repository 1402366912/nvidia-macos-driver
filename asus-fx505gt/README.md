# FX505GT macOS profiles and all documented Fn keys: source preview v2

Status: source WIP. Includes native AppKit menu-bar app source, CLI, a bounded
AsusSMC backend, and a complete source-backed Fn matrix. Apple SDK native builds and
hardware validation remain pending; the SSDT has passed an offline ACPICA build. See [FN_MATRIX.md](FN_MATRIX.md),
[app/README.md](app/README.md) and [acpi/README.md](acpi/README.md).

This is an isolated sibling of the NVIDIA GPU work. It adds a real, bounded
IOKit control path to pinned **AsusSMC**, plus a matching command-line client.
It is **source-only and unvalidated on macOS/hardware**. No kext, app binary,
installation, loading, signing change, reboot, or firmware write is delivered
or performed by the portable test command.

## What it implements

- Query firmware **capabilities**, separate raw probe results, supported profile
  mask, backend choice, configuration state, and software command history.
- Request only firmware profiles `normal` (0), `overboost` (1), `silent` (2).
  This controls firmware performance/fan policy, not manual PWM, a fan curve,
  target RPM, or independently addressable CPU/GPU fans.
- Prefer thermal policy `0x00120075` when its DSTS presence bit is set; otherwise
  use fan boost `0x00110018` only with its presence bit and nonzero supported-mode
  mask. A single request writes exactly one selected backend, never both.
- Reuse AsusSMC's ATK notification path (`DMES` or `_WED`) and existing Fn/HID
  mappings. Optional profile events `0x99` (fan-boost backend) / `0xae` (thermal-policy
  backend) cycle supported profiles. Mismatched events are ignored.
  Unknown initial/ambiguous state explicitly requests **normal first**. Later
  steps cycle the last acknowledged request, not a measured hardware state.
  A best-effort 250 ms arrival-time debounce suppresses closely spaced duplicate
  notifications of the matching event; deliberate
  presses inside that interval are also suppressed. Without firmware sequence
  IDs, this is not a guarantee against arbitrarily delayed duplicates. Actual event delivery on
  this user's BIOS remains unverified.

DSTS is **not current-profile readback**. `currentProfile` always stays unknown.
DEVS integer return `1` is a historical strict firmware acknowledgement, not
proof of actual mode, fan speed, or cooling behavior. Other returns, missing
integers, or transport errors are not reported as success; hardware may still
have changed after an ambiguous response. No automatic retry/fallback write
follows an error. An ambiguous write invalidates the software cycle anchor.
`lastAcceptedProfile` is a software command record and may become stale after
firmware actions, another driver or another controller. Priority sleep/wake
notifications suspend new profile I/O, invalidate the cycle anchor and clear
debounce history. The bridge starts suspended, awaiting the root domain's
initial capability synchronization. Only completed/initial CPU+Graphics
capabilities permit new probing; dark wake remains suspended. Wake never
restores a profile automatically. Missing notifier registration or initial
synchronization blocks profile I/O. Runtime ordering still needs native testing.

Stock AsusSMC's fan telemetry is not extended here. It has a single fan key,
an error sentinel and polling limitations; this deliverable makes no claim of
live or dual-fan RPM monitoring.

## Fail-closed configuration

All new profile and dedicated Fn-contract operations are off by default. In a **separately reviewed test
build**, the `AsusSMC` personality in upstream `AsusSMC/Info.plist` must contain:

- `FX505GTProfileBridgeEnabled`: boolean true
- `FX505GTProfileModel`: string exactly `FX505GT`
- `FX505GTDedicatedFnContractEnabled`: boolean true only with the separately
  reviewed exact BIOS-specific ACPI candidate; its app session listener is
  also off until selected each launch
- `FX505GTProfileFnF5Enabled`: boolean true only if Fn-triggered writes are also
  intended; leave false for explicit CLI requests only

The model string is an operator declaration after checking the physical
machine/BIOS, **not detected physical identity**. Query reports
`model_declared=1 model_verified=0`. A wrong or absent declaration blocks the
bridge. The client cannot supply/override this model, enable flags, WMI device
IDs, ACPI methods, EC offsets, buffers or paths. Hackintosh Apple SMBIOS model
strings are not accepted as ASUS model proof. Optional OpenCore OEM NVRAM is
not required or changed by this preview.

Before any profile probe/write the driver also requires the real ATK ACPI
provider, an `_WDG` management GUID entry marked as a method with a valid
instance count, a valid `WMxx` name and an existing method. AsusSMC's historical
`WMNB` guess is never enough to authorize this bridge. Actual DSTS capability
results still decide what can be written.

This declaration gate prevents accidental use without configuration; it is
not cryptographic hardware attestation and cannot protect against a false
operator declaration or a privileged actor changing boot configuration.
The preview does not change original AsusSMC's ALS/battery/keyboard behavior.
In particular it does not make the unmodified upstream driver a no-write
probe-only driver.

## Security and lifecycle

There are four synchronous fixed-size selectors: profile query/set and
exclusive console session claim/read. Session reads expose a bounded queue of
only dedicated kernel-decoded Fn actions, with no arbitrary injection or
firmware write selector. Claim/read require active console ownership; one
client has a two-second lease, released on close/sleep/session loss. Query is read-only and may be opened by an ordinary process.
Writes check the owning and invoking task's root privilege in the kernel on
every request. No caller-provided UID or app-only check grants privilege.

The user client checks its provider class, locks and retains its provider
around each call, and holds a reference to its owning task. Requests and accepted
commands carry monotonic uptime timestamps, not sensor sampling timestamps. All new profile
state, probes, writes and decoded Fn notifications use AsusSMC's command gate.
Stop marks the bridge unavailable on that gate; gate/workloop lifetime extends
to `free()` so retained clients/queued calls cannot use a freed gate. No raw
WMI/ACPI/EC interface, memory mapping, async notification or generic write
selector is added.

## Apply and build, without installing

1. Obtain a clean source checkout of `hieplpvip/AsusSMC` at
   `c15d2f297c86b65a3cb866cc2bcece595c136417`.
2. The expanded `upstream-overlay/AsusSMC/` contains the exact patched files
   for direct review. To apply them with input/output hash checks, run:

   ```sh
   python3 tools/apply_to_asussmc.py /path/to/AsusSMC
   ```

   The script verifies the source hashes, pinned Git HEAD, absent added files,
   and checks the whole patch before applying. It neither fetches dependencies
   nor installs/builds/loads anything. The patch includes all new driver/ABI
   files. `FXProfileBridge.inc` is deliberately included by `AsusSMC.cpp`, so
   the pinned Xcode source target cannot silently omit the implementation.
3. Use the upstream build requirements, Apple kernel SDK, and compatible
   Lilu/VirtualSMC source dependencies. Review upstream bootstrap before using
   it; this preview does not execute it or pin/download its transitive inputs.
   List the existing Xcode schemes with `xcodebuild -list -project
   AsusSMC.xcodeproj`, then build the desired AsusSMC target with signing disabled
   only as a **build option**, not a system security change. Building the dated
   upstream against a current SDK may require separate compatibility work.
4. On a macOS build host, build only the matching CLI:

   ```sh
   ./tools/build_cli.sh /desired/output/fxprofile
   ```

   This does not run it. On a separately authorized/validated machine with the
   patched kext already present, explicit runtime commands would be:

   ```sh
   fxprofile query
   sudo fxprofile set normal
   sudo fxprofile set overboost
   sudo fxprofile set silent
   ```

   Those `set` commands change firmware policy. They were **not run** here.
   CLI matching refuses a missing or ambiguous AsusSMC service, and stock
   AsusSMC refuses the new connection type.

Upstream VirtualSMC plugins explicitly reject unloading; this bridge does not
make hot-unload/reload safe. Do not infer unload support from the defensive
client stop/free paths.

No automatic installation instructions, system security relaxation, persistent
agent, LaunchDaemon, default profile write, or sleep/wake restoration is
included. Those are outside this source integration milestone.

## Validation

Run `sh tests/run.sh` on a CPU-only host. It compiles the production policy
header with strict C++14 warnings and tests capability/error handling, backend
selection, unsupported modes, unknown versus acknowledged state, Fn cycling,
backend-matched duplicate suppression, sleep/wake invalidation, power-notifier
unavailability and shutdown. A C compilation also checks the shared ABI size
and offsets. On Linux it also tests the actual CLI's
argument parser and explicit refusal to fake a macOS device connection.

`validation/portable-v2-tests.txt` records the expanded current suite;
`validation/bios303-offline-tests.txt` records the exact public fixture test.
`validation/portable-tests.txt` retains the first source milestone result. The initial strict
compiler warning and its fix are retained separately. Portable tests do **not**
compile or validate the IOKit adapter, privileges, driver attachment, command
gate lifecycle, Xcode target, macOS ABI, ACPI methods, physical fan response,
Fn event routing, or sleep/wake behavior. Those still need an Apple SDK build,
independent kernel review, and separately authorized hardware testing.

## Layout and licensing

- `upstream-overlay/`: all nine modified/new AsusSMC files expanded as readable
  source, plus the unchanged upstream MIT license; this is not a full upstream
  checkout and still needs its unchanged dependencies
- `patches/AsusSMC-FX505GT.patch`: complete patch against the fixed upstream
- `include/`: shared stable ABI and actual portable policy used by the driver
- `driver/`: same driver additions embedded in the patch
- `app/`: native menu-bar app and session actions, companion-helper trust
- `acpi/`: default-off exact BIOS303 source candidate and provenance guards
- `FN_MATRIX.md`: all14 officially documented combinations and limits
- `cli/`: IOKit client source
- `tests/`: CPU-only policy/CLI checks
- `tools/`: pinned apply and build-only tools
- `SOURCES.md`: fixed upstream provenance and protocol evidence

New code is independently authored under MIT; original AsusSMC copyright and
MIT notice are preserved. Faustus/Linux are cited for protocol facts, not
copied into the NVIDIA codebase; G-Helper code is not included. This directory
has its own license and does not relicense the surrounding GPU project.

## Native menu app and complete Fn source route

Run `sh tools/build_app.sh /new/output/path` only on a prepared macOS build
host. It builds the CLI companion and embeds its exact binary hash/ABI/source
identity in the app. It does not install, execute, sign or load anything.
The exact public BIOS303 ACPI candidate is hash/header/method guarded and
preserves non-Darwin original methods. It is not a universal FX505GT patch.
F6 all-display sleep and F12 Wi-Fi-only control are explicit semantic limits;
see the full matrix rather than treating all14 as hardware-tested.

## Requested semantics still open

The14-key source routing matrix does **not** mean all requested Fn behavior is
complete. Two functional gaps remain explicit work items: F6 panel-only on/off
rather than all-display sleep, and F12 full Wi-Fi/Bluetooth radio semantics
rather than primary Wi-Fi plus a settings shortcut. Their next implementation
must be source-backed and capability/readback checked; unsupported hardware
must remain visibly unsupported. Keyboard/light/touchpad/display paths also
still require the unified native/hardware test, not a simulated success.
