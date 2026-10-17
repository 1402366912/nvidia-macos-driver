#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Narrow source-contract assertions; not a substitute for native AppKit tests."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]
ui=(p/'app/main.mm').read_text()
osd=(p/'app/FXFeedback.mm').read_text()
act=(p/'app/FXSessionActions.mm').read_text()
panel=(p/'app/FXPanelPower.mm').read_text()
build=(p/'tools/build_app.sh').read_text()
assert 'FXFeedback.mm' in build and '-framework CoreGraphics' in build
assert 'fx::Feedback *feedback' in act and 'fx::Feedback *feedback' in panel
assert 'FXPerformSessionAction(events.events[0].action,true,&feedback)' in ui
assert 'events.lastObservedCode==events.events[0].acpiCode' in ui
assert 'pollNow-_lastFeedbackPoll>0.5' in ui
assert 'NSProcessInfo.processInfo.systemUptime-pollNow>0.5' in ui
assert ui.count('NSProcessInfo.processInfo.systemUptime-observedAt>0.5')==2
assert 'generation!=FXSessionGeneration()' in osd and 'systemUptime>deadline' in osd
assert '_feedbackCursor.reset()' in ui and 'FXIsConsoleUser()' in osd
assert 'NSWindowStyleMaskNonactivatingPanel' in osd and '_panel.ignoresMouseEvents=YES' in osd
assert '_serial!=serial' in osd and 'NSRunLoopCommonModes' in osd
assert 'accessibilityDisplayShouldReduceMotion' in osd
assert 'Custom volume OSD (may duplicate macOS)' in ui
assert 'Custom brightness OSD (may duplicate macOS)' in ui
assert 'Custom keyboard-light OSD (may duplicate macOS)' in ui
assert '_audioFeedback=YES' not in ui and '_brightnessFeedback=YES' not in ui and '_keyboardFeedback=YES' not in ui
for forbidden in ('AudioObjectSetPropertyData','IODisplaySet','IOConnectCall','CGEventPost','CGEventTapCreate','setPower:','IOPMSleepSystem','AXIsProcessTrusted','NSTask'):
    assert forbidden not in osd, forbidden
print('PASS: limited source-contract assertions for OSD build inclusion, read-only renderer, actual-action feedback, freshness, nonactivation, timer guards and opt-in native-HUD categories')
print('NOT RUN: Objective-C++ AppKit compile/link, native rendering or hardware/runtime behavior')
