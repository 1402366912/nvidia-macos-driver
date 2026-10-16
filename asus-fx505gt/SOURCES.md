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
