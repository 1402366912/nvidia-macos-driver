# Source and licensing register

Audited 2026-10-16. This component is a source preview, not evidence of operation
on the user's FX505GT. All new code is independently authored MIT. Protocol
constants, mode meanings and error semantics are referenced from the projects
below; their GPL implementation text is not transplanted. No G-Helper source,
Armoury Crate binary, third-party kernel binary, or proprietary asset is included.

## Applied source dependency

- AsusSMC, MIT, pinned commit
  `c15d2f297c86b65a3cb866cc2bcece595c136417` (2020-10-02).
  [Tree](https://github.com/hieplpvip/AsusSMC/tree/c15d2f297c86b65a3cb866cc2bcece595c136417)
- [AsusSMC.cpp](https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/AsusSMC/AsusSMC.cpp):
  ATK provider, `_UID`, `_WDG`, WMI argument layout, DMES/_WED notifications,
  existing HID maps and command gate.
- [AsusSMC.hpp](https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/AsusSMC/AsusSMC.hpp)
  and [Info.plist](https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/AsusSMC/Info.plist).
- The complete upstream [MIT notice](https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/LICENSE.md)
  is preserved in `licenses/AsusSMC-MIT.txt`; source copyright headers remain.
- The upstream Xcode target uses C++14. New implementation is included in its
  existing `AsusSMC.cpp`; adding it does not require an unchecked Xcode target
  registration. Lilu, VirtualSMC and SDK compatibility are not pinned/validated
  by the portable tests and remain prerequisites for a native build.

## Protocol evidence, not copied code

- Faustus pin `ab4c215564cacc8e3b84cec09b5df07147803179` (2021-04-18),
  C source GPL-2.0-or-later, repository COPYING GPL v2.
- [Model evidence](https://github.com/hackbnw/faustus/blob/ab4c215564cacc8e3b84cec09b5df07147803179/README.md):
  FX505GT tested historically with BIOS 303/304/305.
- [Profile implementation](https://github.com/hackbnw/faustus/blob/ab4c215564cacc8e3b84cec09b5df07147803179/src/faustus.c#L2014-L2233):
  DSTS presence bit `0x10000`; fan-boost `0x00110018` with low-two-bit mode
  capability mask; thermal policy `0x00120075`; normal/overboost/silent values
  0/1/2; strict historical DEVS acknowledgement integer 1.
- [Events](https://github.com/hackbnw/faustus/blob/ab4c215564cacc8e3b84cec09b5df07147803179/src/faustus.c#L2527-L2536):
  fan-boost `0x99`, thermal policy `0xae`. The bridge accepts only the event
  corresponding to the single selected backend. No FX505GT-specific event
  substitution has been assumed.
- Linux pin `70dd4ee72eb2d5793c62e71c14e3aba78e5a4e56`,
  [asus-wmi.c](https://github.com/torvalds/linux/blob/70dd4ee72eb2d5793c62e71c14e3aba78e5a4e56/drivers/platform/x86/asus-wmi.c#L4101-L4252)
  (GPL-2.0-or-later): modern thermal-policy implementation tolerates ambiguous
  return values on some firmware. This unvalidated bridge deliberately does
  not generalize that tolerance into a success claim.

DSTS here reports capabilities; cached software getters in those drivers do
not establish active firmware readback. This preview always exposes unknown
current profile, and separately records requested/acknowledged command state.

## Kernel API review references

Apple XNU pin `f6217f891ac0bb64f3d375211650a4c1ff8ca1ea`:

- [IOUserClient.cpp](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOUserClient.cpp):
  `clientHasPrivilege(task, kIOClientPrivilegeAdministrator)` tests root via
  the task security token. Both owning and invoking task are checked.
- [IOUserClient.h](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/IOKit/IOUserClient.h):
  legacy IOUserClient fixed external-method argument shape.
- [IONotifier.h](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/IOKit/IONotifier.h)
  and [IOService.cpp](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOService.cpp):
  `remove()` synchronizes callback completion and consumes the notifier's
  reference; the patch avoids the inherited remove-plus-release pattern.
- [IOServicePM.cpp](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOServicePM.cpp):
  kernel priority-interest callbacks receive a notification structure, not a
  raw acknowledgement cookie. This bridge completes synchronously, requiring
  no deferred acknowledgement or sleep veto.
- [RootDomain.h](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/IOKit/pwr_mgt/RootDomain.h):
  priority sleep/wake registration declarations.
- [10.11-era priority registration and initial synchronization](https://github.com/apple-oss-distributions/xnu/blob/xnu-3248.60.10/iokit/Kernel/IOPMrootDomain.cpp):
  `registerPrioritySleepWakeInterest` queues a kernel capability client and an
  initial `kIOMessageSystemCapabilityChange` synchronization with zero flags
  and zero from-capabilities. The bridge starts suspended until a valid initial
  sync or DidChange reports CPU+Graphics. Missing/dark-wake sync fails closed.
  These public flags are WillChange=1, DidChange=2, CPU=1, Graphics=2.

These source inspections are not a successful macOS SDK compilation or proof
that a particular macOS release permits this legacy kext.

## Model identity limitation

OpenCore's optional OEM fields are GUID-qualified NVRAM variables, not the
ordinary injected Apple SMBIOS model. [Pinned OpenCore documentation](https://github.com/acidanthera/OpenCorePkg/blob/81ecf1a7e75c318dfc859ddabe5b91f4af757231/Docs/Configuration.tex#L4459-L4496)
requires optional exposure settings. This preview does not change them or
assume those fields exist. Its explicit model declaration remains visibly
unverified. Actual FX505GT model/BIOS and ACPI tables still require validation.

## Destination boundary

Intended sibling destination: `1402366912/nvidia-macos-driver`, base reviewed
as `0960b2ef5dbc4a573056d4c8e042a5bd2e15d651`. Its root license is PolyForm
Noncommercial 1.0.0. This component and AsusSMC changes retain their separate
MIT licenses; no GPU source is altered by this standalone patch.

## Full FX505GT Fn matrix and native session app (source preview v2)

- ASUS English E15207 (July 2019), FX505GT, pp36–37:
  https://dlcdnets.asus.com/pub/ASUS/GamingNB/FX505GT/0409_E15207_FX505GT_A.pdf
- ASUS Simplified Chinese C15207 (February 2019), pp36–37:
  https://dlcdnets.asus.com/pub/ASUS/GamingNB/FX505GT/0804_C15207_FX505GT_B.pdf
- Linux asus-nb-wmi event table at the existing pinned Linux commit:
  https://github.com/torvalds/linux/blob/70dd4ee72eb2d5793c62e71c14e3aba78e5a4e56/drivers/platform/x86/asus-nb-wmi.c#L590-L693
  `0x7c` is mic mute, but `0x35`, `0x5e`, `0x7d` do NOT universally mean
  display-off, sleep, airplane. Legacy AsusSMC deliberately uses its own patched
  event meanings. No GPL code is copied into the independently authored router.
- Apple CoreAudio `kAudioDevicePropertyMute` and property access APIs:
  https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertymute
  https://developer.apple.com/documentation/coreaudio/audioobjectispropertysettable(_:_:_:)
- Apple IOPMSleepSystem: root or console user, return value is request status:
  https://developer.apple.com/documentation/iokit/1557121-iopmsleepsystem
- Apple AppleScript command reference: native administrator authorization,
  cancellation/errors; authentication may be reused for five minutes:
  https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_cmds.html
- Apple CoreWLAN interface power API (primary interface only in this preview):
  https://developer.apple.com/documentation/corewlan/cwinterface/setpower(_:)
- Apple `pmset` source identifies the fixed `displaysleepnow` operation:
  https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m
  This is API/command evidence, not imported code or a pinned runtime binary.
- The existing pinned XNU IOUserClient.cpp interprets the private privilege
  string `console` against the owning task's active console UID. This is
  checked on every claim/read and again at dispatch. If unsupported, the
  consumer fails closed; no client-provided UID is trusted. This internal
  privilege check requires native compatibility validation on the target OS.

The base app uses public CoreAudio, CoreWLAN, IOKit, AppKit and Foundation
APIs. The v2 Bluetooth settings URL remains a best-effort shortcut. The v3
opt-in companion below deliberately uses a verified private power API; it is
not represented as a public Bluetooth setter. No old daemon private
Bluetooth/BezelServices/OSD implementation was copied.

- Apple Darwin ACL semantics (0 means an entry was returned, not an empty ACL):
  https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/acl_get_entry.3.html
  https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/acl_valid.3.html

- Exact public BIOS303 ACPI provenance and byte hashes are in
  `acpi/BIOS303-provenance.json`; original attachment:
  https://github.com/hackbnw/faustus/files/5759074/dsdt.aml.gz
  report: https://github.com/hackbnw/faustus/issues/56 .
  No original firmware dump or third-party AML method bodies are redistributed.

- Keyboard-light protocol facts: stock KeyImplementations produces a12-bit
  value, AsusSMC divides by16 before SKBV, and the TUF adapter divides by16
  again then ORs0x80. The BIOS303 dump resolves SLKI at the root namespace:
  https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/AsusSMC/KeyImplementations.cpp
  https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/patches/kbl_tuf.txt
  New adapter is independently written MIT, retains explicit0..255 bounds;
  this does not establish16 physically measured keyboard brightness levels.

## Offline ACPI compiler evidence

- Official Debian ACPICA package `acpica-tools_20250404-1_amd64.deb`:
  https://deb.debian.org/debian/pool/main/a/acpica-unix/acpica-tools_20250404-1_amd64.deb
  Official checksum page:
  https://packages.debian.org/trixie/amd64/acpica-tools/download
- Package SHA-256:
  `eea598bdb5d10ae51801f7c586a51f33335c60d964f5f18203cdda47fd5ab069`.
  The compiler was extracted locally for source validation only. No compiler,
  package, firmware dump or AML binary is included in this component.
- The corrected new SSDT compiles with warnings-as-errors and zero diagnostics.
  Exact commands, hashes, retained initial failure and inherited DSDT diagnostic
  comparison are recorded under `validation/ACPI_BUILD.md` and
  `validation/acpi-validation.json`. This is not a macOS or hardware test.

## Internal-panel and Bluetooth implementation evidence (source preview v3)

Apple IOGraphics pin `76285384ff0ce63965a21b8023bf6d7e447fcc19`:

- [AppleBacklightDisplay probe and power handling](https://github.com/apple-oss-distributions/IOGraphics/blob/76285384ff0ce63965a21b8023bf6d7e447fcc19/IOGraphicsFamily/IOBacklightDisplay.cpp):
  the class requires a built-in LCD connection; its power handling uses the
  `dsyp` parameter when supplied by the parameter handler.
- [Parameter dispatch](https://github.com/apple-oss-distributions/IOGraphics/blob/76285384ff0ce63965a21b8023bf6d7e447fcc19/IOGraphicsFamily/IODisplay.cpp):
  setForKey calls the handler and updates a driver-maintained value after
  acceptance. Reading that dictionary is not a fresh physical sensor query.
- [Parameter constants](https://github.com/apple-oss-distributions/IOGraphics/blob/76285384ff0ce63965a21b8023bf6d7e447fcc19/IOGraphicsFamily/IOKit/graphics/IOGraphicsTypes.h):
  `kIODisplayPowerStateKey` is `dsyp`, Off0, MinUsable1 and On2.

Apple IOKitUser pin `323ead896d04424f87184d8f6ff0cce811aab106`:

- [IODisplayLib.c](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/graphics.subproj/IODisplayLib.c)
  and [IOGraphicsLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/graphics.subproj/IOGraphicsLib.h):
  IODisplayForFramebuffer retains an already supplied IODisplay rather than
  choosing another display; CopyParameters and SetIntegerParameter provide
  the public read/set path. The new reader validates CF types and every field.
- [Apple public setter reference](https://developer.apple.com/documentation/iokit/1574915-iodisplaysetintegerparameter).

No Apple source implementation text is transplanted into this MIT component.
The independent adapter writes only the fixed, advertised power parameter to
one unique internal-panel class. The BIOS303 BLCT/SPBI flag and constant GPBL
return are expressly not treated as hardware control or state.

Bluetooth reference: **blueutil2.14.0**, MIT, pin
`60d8411fa3f9968ab6f05e198b486fe89961e18f`:

- [Power API implementation](https://github.com/toy/blueutil/blob/60d8411fa3f9968ab6f05e198b486fe89961e18f/blueutil.m#L161-L188)
  verifies private IOBluetoothPreferencesAvailable, GetControllerPowerState
  and void SetControllerPowerState semantics. A setter return is not an ACK.
- [MIT license](https://github.com/toy/blueutil/blob/60d8411fa3f9968ab6f05e198b486fe89961e18f/LICENSE.txt),
  retained as `licenses/blueutil-MIT-reference.txt` for attribution.
- Inspected blueutil.m SHA-256:
  `01a440077071620f50a773f57308385d3633f4a01bf9608ba8df7ba8c8cd2211`.
- The shipped helper is independently authored fixed-operation source, not
  the full utility or a downloaded executable. It dynamically checks those
  symbols, enforces ordinary console ownership, validates0/1, and additionally
  requires agreement with the public default-controller power state.
- [Apple public controller readback](https://developer.apple.com/documentation/iobluetooth/iobluetoothhostcontroller/powerstate?language=objc)
  is read-only and documents power-off support for Apple adapters. Third-party
  FX505GT controllers/OS versions may therefore remain unsupported; no
  universal private-API or physical RF-state guarantee is made.

No Bluetooth permission is accepted or privacy/security setting changed by
these source-only build/tests. The future native app must preserve OS prompts
and report API errors/ambiguous readbacks rather than bypass them.

## Fixed build inputs and object-check provenance

The exact AsusSMC/Lilu/VirtualSMC/MacKernelSDK source pins, license roles and
build-only contract are in [build/inputs.json](build/inputs.json) and
[BUILD_COHORT.md](BUILD_COHORT.md). The four-TU object check uses a separately
documented reused Apple/XNU/public-SDK closure, with original Git blob URLs
where established and SHA-only inherited generated-header labels otherwise.
See [validation/kernel-object-compile.json](validation/kernel-object-compile.json).
No dependency implementation, CI secrets, Apple SDK package or compiled object
is redistributed by this build-readiness update.

## OSD visual/state source addition (2026-10-17)

[OSD_REFERENCE.md](OSD_REFERENCE.md) records the ASUS-published touchpad screenshot,
firsthand FX505DY photographs, ASUS hotkey/component documentation and Microsoft
Windows flyout version evidence, including the limits of each. Neither an
FX505GT-exact appearance nor timing is claimed. Reference assets are not part of
this source distribution. The AppKit renderer and its functional vector artwork
are independent MIT implementations. Existing upstream notices are unchanged.
