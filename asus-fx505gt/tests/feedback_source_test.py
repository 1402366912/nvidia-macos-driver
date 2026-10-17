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
# ABI 3 drains every ordered brightness repeat, but only one session action.
assert 'for(uint32_t i=0;i<events.count;++i)' in ui
assert 'const auto &event=events.events[i]' in ui
assert 'route.action!=event.action' in ui
assert 'event.action==FXBrightnessDown || event.action==FXBrightnessUp' in ui
assert 'if(!brightness && sessionHandled) continue;' in ui
assert 'if(!brightness) sessionHandled=true;' in ui
assert 'FXPerformSessionAction(event.action,true,&feedback)' in ui
assert 'events.events[0]' not in ui
assert 'events.lastObservedCode==event.acpiCode' in ui
assert '[self feedbackAllowed:event.acpiCode]' in ui
assert 'actionFeedbackCode=event.acpiCode; actionFeedback=feedback; brightnessFeedback=brightness;' in ui
assert 'if(brightnessFeedback) [_feedback observeCode:actionFeedbackCode profile:nullptr deadline:pollNow+0.5];' in ui
assert 'else [_feedback showCode:actionFeedbackCode feedback:actionFeedback detail:nil];' in ui
assert ui.index('if(!brightness) sessionHandled=true;') < ui.index('if(brightnessFeedback) [_feedback observeCode:')
assert 'batchGeneration!=FXSessionGeneration() || !FXIsConsoleUser()' in ui
# The generic controller owns microphone OSD; do not revive the field-only HUD.
assert '_microphoneHUD' not in ui and 'showMicrophoneResult:' not in ui
assert 'FXFeedbackController *_feedback' in ui
assert '_feedback=[FXFeedbackController new]' in ui
# Menu-triggered feedback still works while the physical Fn listener is off.
assert 'if(!_listening) { if(_claimed) (void)_client.claim(false); _claimed=NO; return; }' in ui
assert 'FXPerformSessionAction((uint32_t)sender.tag,false,&feedback)' in ui
# Keep hardware-tested preferences, ARC-safe helper trust, and diagnostics.
for preference in ('HardwareFnEnabled', 'BluetoothCompanionEnabled'):
    assert f'boolForKey:@"{preference}"' in ui
    assert f'forKey:@"{preference}"' in ui
assert 'NSString *reason=nil; BOOL trusted=FXHelperTrusted(&reason);' in ui
assert 'FXHelperTrusted(&_helperReason)' not in ui
assert '--hardware-status' in ui and 'FXReadItlwmPower(power)' in ui
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
print('PASS: limited source-contract assertions for ABI 3 ordered brightness drain, single session action, saved field preferences, OSD build inclusion, read-only renderer, actual-action feedback, freshness, nonactivation, timer guards and opt-in native-HUD categories')
print('NOT RUN: Objective-C++ AppKit compile/link, native rendering or hardware/runtime behavior')
