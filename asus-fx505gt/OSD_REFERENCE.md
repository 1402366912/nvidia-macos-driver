# Fn on-screen feedback: evidence and implementation boundary

This is an independent AppKit source implementation, **not a verified pixel-exact
FX505GT replica**. No native Apple SDK build or AppKit screenshot has been produced
in this Linux workspace. No ASUS executable, resource, font or icon is bundled.
The implementation is original MIT code; upstream licenses remain separate.

## Which Windows component owns the effect?

Primary sources checked on 2026-10-17:

- [ASUS Keyboard Hotkeys, ASUS-published Store listing](https://apps.microsoft.com/detail/9pk20dg5fb6b?gl=US&hl=en-US)
  identifies hotkey OSD support. This supports attributing ordinary ASUS hotkey
  feedback to the hotkey stack, not assigning all keys to Armoury Crate.
- [ASUS hotkey driver explanation](https://www.asus.com/global/support/faq/1043050/)
  says some models integrate the hotkey driver into System Control Interface V2;
  the correct combination depends on the model.
- [FX505GT official downloads](https://www.asus.com/supportonly/fx505gt/helpdesk_download/)
  list System Control Interface, Armoury Crate, and Wireless Radio Control
  separately. The radio utility description includes airplane-mode OSD.
- [ASUS hotkeys introduction](https://www.asus.com/support/faq/1038312/)
  explicitly warns that the key functions differ by model. Its current examples
  must not replace the already sourced FX505GT Fn matrix.
- [Microsoft Windows 11 build 22533 announcement](https://blogs.windows.com/windows-insider/2022/01/12/announcing-windows-11-insider-preview-build-22533/)
  documents redesigned native volume/brightness and other hardware flyouts.
  Windows version therefore matters. A Windows volume popup is not sufficient
  evidence of ASUS or Armoury Crate ownership.

The exact executable responsible on the user's old installation is unknown.
In particular, these sources do not prove an ASUSOptimization binary/version or
that Armoury Crate renders every Fn popup. No package was installed, executed,
reverse engineered or redistributed; no new license was accepted.

## Pixels actually inspected

1. **Official ASUS Windows 10 touchpad screenshot**, in
   [FAQ 1042539](https://www.asus.com/support/faq/1042539/),
   [original image](https://kmpic.asus.com/images/2021/11/15/6f01eab1-dfca-4fc1-bcbd-107553af163c.png).
   The desktop identifies itself as VivoBook, **not FX505GT**. The 1920×1080 image
   contains a dark translucent near-square panel at approximately x823..1092,
   y604..873: about 270×270 pixels, centered horizontally and at 68.4% of screen
   height from the top. The bright touchpad glyph spans approximately 105×117
   pixels. Its caption is below the glyph. Rounding is small, approximately 7px.
   The orange rectangle and red annotation number are editorial markup and are
   not part of the OSD.
2. **Firsthand FX505DY-BQ009 owner photographs**, dated 2020-02-24, in
   [this owner review](https://dpg.danawa.com/mobile/community/view?boardSeq=28&listSeq=4164837&past=YES).
   These are model-family evidence, not ASUS official publication and not an
   FX505GT screenshot. The inspected keyboard-light photo shows a white
   keyboard/sun glyph, caption below, and a thin continuous meter at the bottom.
   The Silent photo shows an angular feather-like glyph and `Silent`, without
   a meter. Perspective, camera exposure and raster resampling prevent reliable
   absolute size, color or opacity measurements from these photos.

These images establish a relevant visual family. They do **not** establish all
14 FX505GT glyphs, every enabled/disabled state, Windows build, software version,
DPI scaling, font identity, opacity, hold duration or fade curve. No exact
FX505GT-specific visual or timing reference was found. The user's original
Windows screenshot/video and software version would resolve that remaining
visual target; hardware tests are not needed just to supply a visual reference.

## Independent implementation

- `app/FXFeedback.mm` draws original white vector icons on a dark translucent
  small-corner square. It uses the official screenshot's 270-pixel geometry as a
  provisional **270 AppKit-point** reference. That pixel-to-point choice is not
  a verified DPI equivalence. The lower-center placement follows the observed
  68.4% screen-height reference; an exact-screen-center menu option is available.
- Touchpad is drawn vertically; keyboard lighting uses a keyboard/sun motif.
  A thin bottom meter appears only for a valid independently read normalized
  level. Missing levels never become fake full/empty meters.
- A neutral fan glyph is intentional: the bridge cannot measure current fan
  profile. The caption distinguishes last acknowledged request from current
  unknown mode, rather than displaying a current-mode claim with a Silent logo.
- Other icons are independently drawn functional symbols, not traced or copied
  vendor assets. Status qualifiers and sometimes extra text differ from Windows
  intentionally so unsupported/unknown results cannot look like success.
- Opacity 0.78, AppKit system font, 1.5-second hold and 0.18-second fade are
  provisional design choices, **not measurements** from a reference video.
  Native rendering, clipping, multi-display/Spaces behavior, focus and timing
  remain untested. There is no generated mockup presented as an AppKit render.

## Event/state behavior

The kernel ABI, ACPI source and hardware paths are unchanged. The existing
exclusive Fn listener must be enabled for physical-key OSDs; the menu says so.
The listener still requires the existing per-launch action opt-in. Merely
checking the OSD option does not grant or enable hardware actions.

The UI observes genuine decoded dedicated Fn events. HID actions are never
injected a second time. It waits 80ms after the existing 250ms poll to read
OS state; this is not an exact Windows key-to-popup latency guarantee. Repeat
keys coalesce to the latest observation. Startup, new leases, session changes,
long poll gaps and turning feedback back on baseline the observation counter.
Delayed reads expire after 0.5 seconds. Timer/serial checks prevent an old read
or old dismissal from replacing or hiding a newer popup.

- F1–F3: default-output CoreAudio volume/mute readback when those properties
  exist; unavailable master properties remain unknown, with no channel guess.
- F4: the existing successful set and independent default-input readback yield
  muted/unmuted. Failure remains unconfirmed.
- F5: last acknowledged request only; current hardware profile remains unknown.
- F6: existing panel power driver readback only, not measured physical power.
- F7/F8: unique internal-panel brightness driver readback if available.
- F9/F10: observed key and explicitly unverified outcome. The existing
  `IsTouchpadEnabled` registry property is a commanded value, so is deliberately
  not promoted to confirmed hardware state.
- F11: accepted sleep request, not a promise that the machine slept. No delayed
  success is shown after the session/sleep generation changes.
- F12: existing independent final Wi-Fi and Bluetooth readback; partial failure,
  timeout or permission denial stays unconfirmed. It never claims RF silence.
- Up/Down: observed keyboard-light key; level unavailable, no invented bar.

Custom volume, brightness and keyboard-light OSDs each default **off** because
macOS may already show its native HUD. Their per-launch menu switches explicitly
warn about duplicates. Enabling them does not suppress the macOS HUD. No private
OSD interception, Accessibility/Input Monitoring grant, global key tap, OS
security change or install is added. Other supported category feedback defaults
on, subject to the listener opt-in.

## Validation

`tests/feedback_policy_test.cpp` covers all 14 codes, unknown readback defaults,
level validation, baseline/no replay, coalescing, repeats, resets, disabled
feedback and counter wrap. The full portable suite is recorded in
`validation/portable-osd-tests.txt`. The native build attempt truthfully stops
with `Native app build requires macOS and the Apple SDK.` See
`validation/osd-native-build-blocker.txt`.

Before any claim of an exact match, a native build/render must be compared with
the actual FX505GT Windows reference at known scaling. Before any runtime-ready
claim, native focus/Spaces, repeated keys, session interruption, cancellation,
unsupported devices and real state-readback behavior must also be tested.
