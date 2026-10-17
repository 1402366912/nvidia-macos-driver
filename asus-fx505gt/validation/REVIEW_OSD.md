# OSD source review

Reviewed new AppKit feedback integration against the unchanged ABI2 action
boundary. No native AppKit SDK or runtime is available here.

Fixed during review:
- Manual/menu session actions invalidate pending delayed HID feedback.
- Old fade timers cannot hide a newer panel; each mutation checks its serial.
- Delayed feedback has one deadline, from poll start through final OS readback.
- Slow polls and long run-loop gaps reset/baseline the observation counter.
- Session/generation/console checks repeat after synchronous profile refresh.
- Dedicated action results cannot overwrite a newer differently categorized key.
- Native-HUD categories default off and explicitly warn about duplicate overlays.
- Physical-feedback dependence on the existing Fn-action listener is explicit.

A second reader found no duplicated hardware writes/HID injection or definite
new compiler blocker. A minimal C++-struct Objective-C property syntax probe
was successful, but it is **not** a compilation of this AppKit app. Full native
compile/link/render and actual runtime QA remain not run. Portable policy and
narrow source-contract tests are recorded separately and do not replace them.

Native follow-up cases when an authorized macOS test host exists: quick and held
keys; alternate categories; newer key during fade; disabled/reenabled categories;
menu/modal interruption; long CoreAudio/IOKit reads; changed default audio device;
no master volume/mute; disconnected bridge; lease loss; console switch, sleep and
wake; authorization cancellation; partial radio result; single/multiple displays,
Spaces/fullscreen, no focus stealing, text clipping and reduced motion.
