# Complete documented FX505GT Fn matrix

Legend source: ASUS **FX505GT** English E15207 and Chinese C15207, pages36–37.
There are 14 explicitly documented combinations. This inventory is complete
for that chapter; **none is claimed hardware-tested on the user's machine**.
BIOS303 `_Q` routes below come from the exact public issue56 dump and are
source-correlated candidates. Its BIOS/OEM/hash guard is mandatory; a model
name alone is not permission to apply them to another table.

| Fn key | Official legend | BIOS303 query method / original source path | Dedicated event | macOS implementation / remaining limit |
|---|---|---|---|---|
| F1 | Speaker mute | EC0._Q0A; IANE0x32 | 0xF501 | Existing AsusSMC consumer HID mute; audio driver required |
| F2 | Volume down | EC0._Q0B; IANE0x31 | 0xF502 | Existing consumer HID volume down |
| F3 | Volume up | EC0._Q0C; IANE0x30 | 0xF503 | Existing consumer HID volume up |
| F4 | Microphone on/off | EC0._Q0D; IANE0x7C | 0xF504 | New CoreAudio default-input master mute, only if readable/settable; readback required, no fake volume fallback |
| F5 | Fan/performance mode | EC0._Q0E; IANE0xAE | 0xF505 | New bounded profile backend; separate explicit opt-ins, supported-mode cycling, current mode always unknown |
| F6 | Panel on/off | EC0._Q0F; IANE0x33/0x35 and BLCT | 0xF506 | Unique internal AppleBacklightDisplay dsyp power request, exact 0..2 capability range; explicit next press restores a saved driver state (else requests On); no all-display fallback or physical power claim |
| F7 | Display brightness down | EC0._Q10; BRTN0x87 | 0xF507 | Existing AsusSMC top-case brightness-down HID; functional display/backlight driver required |
| F8 | Display brightness up | EC0._Q11; BRTN0x86 | 0xF508 | Existing top-case brightness-up HID |
| F9 | Display mode | EC0._Q12; IANE0x84 | 0xF509 | Existing VideoMirror HID; external display and working graphics/display driver required; not Windows Win+P UI |
| F10 | Touchpad on/off | EC0._Q13; IANE0x6B/0x6F and TPME | 0xF50A | Existing AsusSMC touchpad notification; requires a compatible consumer of RM,deliverNotifications, property toggle alone is not proof |
| F11 | Sleep | EC0._Q14; Notify(SLPB,0x80) | 0xF50B | Real IOPMSleepSystem from active console user; explicit per-launch physical-Fn permission, manual menu confirmation; native sleep-button path is not called again |
| F12 | Airplane mode | EC0._Q15; Notify(ASHS,0x88) | 0xF50C | Wi-Fi + Bluetooth control: all enumerated CoreWLAN interfaces and default Bluetooth controller, explicit private-API opt-in and independent readback; unsupported/partial failures visible, no other-radio or RF-silence guarantee |
| Up | Keyboard light brighter | EC0._Q6B; IANE0xC4 | 0xF50D | Existing illumination HID; includes bounded BIOS303 SKBV→root SLKI adapter; functional keyboard-light path still needs validation |
| Down | Keyboard light dimmer | EC0._Q6C; IANE0xC5 | 0xF50E | Existing illumination HID, same included adapter/dependencies |

The adapter uses existing stock HID paths exactly once. The user-session app
only consumes F4/F6/F11/F12 actions; it does not send volume/brightness keys a
second time. The dedicated FnF5 route uses exactly one capability-selected
firmware backend. The original native 0x99/0xAE fan event route remains available
for a separately validated configuration without the all-key ACPI candidate.

## Why the old generic patches are not a model map

AsusSMC's `patches/f1.txt` assigns sleep and `f4.txt` assigns keyboard light,
which disagree with the FX505GT manual. Their method names cannot be copied
blindly. The actual BIOS303 dump confirms a different contiguous F1–F12 map
and separate arrow methods. Do not combine these independent remappers.

Likewise raw ASUS event meanings are not the legacy AsusSMC private contract:
Linux calls0x35 screen-lock,0x5E WLAN enable,0x7D Bluetooth enable. The dedicated
contract suppresses these ambiguous legacy codes while enabled and uses
0xF501..0xF50E instead. The 16-bit events go through IANE→queue→Notify0xFF→_WED;
no DMES marker or arbitrary userspace event injection is added.

## Other combinations and non-hotkey legends

- Fn+Esc, Space, Left, Right, A, C, V, and Windows-lock shortcuts are **not
  documented in this model's hotkey chapter**. Their absence from the manual
  does not prove firmware absence; no imported newer-ROG mapping is installed.
- The English manual p79 has a generic “selected models” Fn+Num Lock FAQ. It
  does not establish that combination for this dedicated-keypad FX505GT.
- Secondary Insert/Break/SysRq/End key legends appear in the keyboard drawing,
  but their modifier mechanics are not specified by this hotkey chapter. These
  remain ordinary keyboard-driver/layout validation items, not invented ACPI
  fan/function events.
- Ordinary F1–F12 operation and Fn-lock preferences are outside the 14 printed
  Fn actions. No Fn-lock firmware control is claimed or synthesized.

## Validation status and next unified test

Completed here: primary manual comparison, exact public DSDT checksum/hash
and method inspection, offline guarded transformation, portable routing/queue
and profile/ABI tests, and an actual warning-as-error ACPICA build of the SSDT
(0 errors/warnings/remarks). Original/renamed DSDT recompiles share identical
inherited errors; see validation/ACPI_BUILD.md. Pending: Apple SDK native compilation,
actual BIOS/table comparison, physical one-press/one-event correlation,
compatible audio/display/touchpad/keyboard-light drivers, privilege and
sleep/wake behavior. No firmware, bootloader or OS setting was modified.

Before a future single authorized native test, review the complete source
pair and build logs; verify this machine's exact identity/table first. A
mismatched dump must be researched as a new source profile, not accepted by
loosening the SHA/header/method guards. F6/F12 now have source-backed native implementations rather than the earlier
all-display/Wi-Fi-only approximations, but their capability-dependent support
and OS-reported-state limits remain visible. No key is declared operational
until the unified native/hardware test passes.

Sources: [English manual](https://dlcdnets.asus.com/pub/ASUS/GamingNB/FX505GT/0409_E15207_FX505GT_A.pdf),
[Chinese manual](https://dlcdnets.asus.com/pub/ASUS/GamingNB/FX505GT/0804_C15207_FX505GT_B.pdf),
[BIOS303 public report](https://github.com/hackbnw/faustus/issues/56),
[AsusSMC pinned handler](https://github.com/hieplpvip/AsusSMC/blob/c15d2f297c86b65a3cb866cc2bcece595c136417/AsusSMC/AsusSMC.cpp#L482-L628),
[Linux pinned event table](https://github.com/torvalds/linux/blob/70dd4ee72eb2d5793c62e71c14e3aba78e5a4e56/drivers/platform/x86/asus-nb-wmi.c#L590-L693).

## Cohort and power/radio boundary (source preview v3)

The profile snapshot remains ABI1; Fn actions are ABI2. Connection type
`0x46583250` deliberately rejects clients/kexts from the earlier cohort. Build
and deploy the matching kext, CLI and app together in a future authorized test.
BIOS303 dedicated event values and default-off SSDT are unchanged.

F6 does not use BIOS303 BLCT as hardware status: SPBI changes only that flag
and GPBL always returns0. The macOS implementation requires the unique
AppleBacklightDisplay service and a well-formed driver `dsyp` range0..2.
Only that parameter is written; readback is the driver's cached parameter,
not an independent electrical measurement. Saved state is bound to registry
identity and cleared on session/sleep notifications. Restoration happens only
on an explicit next request, never at startup or wake.

F12 does not pretend macOS supplies a universal airplane-mode switch. The
radio companion is initially disabled, requires explicit per-launch enable,
and uses dynamically verified private IOBluetooth power symbols referenced
from pinned MIT blueutil. Both the public default-controller power and private
preference must agree before writes. Missing APIs, permissions or ambiguous
readback disable it. Each write is followed by independent readback. A mixed
result is reported without automatic rollback, fallback or retry. Other RF
hardware, WWAN and physical radio silence are not measured.

See [native app boundary](app/README.md) and [source evidence](SOURCES.md).
