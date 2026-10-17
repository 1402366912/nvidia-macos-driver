// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#include "FXClient.hpp"
#include "FXFnPolicy.hpp"
#include <unistd.h>
#include "FXBuildIdentity.h"
#import "FXFeedback.h"
extern NSString *const FXHelperPath;
extern bool FXHelperTrusted(NSString **reason);
extern bool FXIsConsoleUser();
extern uint64_t FXSessionGeneration();
extern void FXInvalidateSessionActions();
extern bool FXMicrophoneSupported();
extern NSString *FXPerformSessionAction(uint32_t action,bool physicalEvent,fx::Feedback *feedback);
extern bool FXPanelPowerSupported();
extern bool FXReadItlwmPower(int &power);
extern bool FXBluetoothEnabled();
extern void FXEnableBluetooth(bool value);
extern bool FXReadBluetooth(int &power);
static NSString *profile(uint32_t p) {
    switch(p) { case FXNormal:return @"Normal"; case FXOverboost:return @"Overboost"; case FXSilent:return @"Silent"; default:return @"Unknown"; }
}
static NSString *state(uint32_t s) {
    switch(s) {
        case FXDisabled:return @"Disabled"; case FXModelNotDeclared:return @"Model not declared";
        case FXWMIMethodUnverified:return @"WMI method unverified"; case FXUnprobed:return @"Unprobed";
        case FXUnsupported:return @"Unsupported"; case FXFirmwareError:return @"Firmware error";
        case FXReady:return @"Ready"; case FXStopped:return @"Stopped"; case FXSuspended:return @"Suspended";
        case FXPowerNotifierUnavailable:return @"Power notifier unavailable"; default:return @"Invalid state";
    }
}
@interface FXMenu : NSObject <NSApplicationDelegate,NSMenuDelegate> {
    FXClient _client;
    FXProfileSnapshot _snapshot;
    FXSessionBatch _lastEvents;
    NSStatusItem *_item;
    FXFeedbackController *_feedback;
    fx::FeedbackCursor _feedbackCursor;
    uint64_t _feedbackSerial;
    BOOL _feedbackEnabled, _audioFeedback, _brightnessFeedback, _keyboardFeedback;
    NSTimer *_timer;
    NSString *_status, *_helperReason;
    BOOL _valid, _trusted, _listening, _claimed, _busy;
    NSTimeInterval _lastQuery, _lastFeedbackPoll;
}
@end
@implementation FXMenu
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    if(geteuid()==0 || geteuid()!=getuid()) { NSLog(@"Run FX505GT Control as an ordinary console user with matching real/effective UIDs."); [NSApp terminate:nil]; return; }
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier])
        if(app.processIdentifier!=NSProcessInfo.processInfo.processIdentifier) { [app activateWithOptions:NSApplicationActivateIgnoringOtherApps]; [NSApp terminate:nil]; return; }
    _listening=[NSUserDefaults.standardUserDefaults boolForKey:@"HardwareFnEnabled"];
    FXEnableBluetooth([NSUserDefaults.standardUserDefaults boolForKey:@"BluetoothCompanionEnabled"]);
    _status=@"Fn controls ready; individual hardware capabilities are shown below.";
    _feedback=[FXFeedbackController new]; _feedbackEnabled=YES;
    _item=[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength]; _item.button.title=@"FX505GT";
    _item.menu=[NSMenu new]; _item.menu.delegate=self;
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(sessionInactive:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(sessionInactive:) name:NSWorkspaceWillSleepNotification object:nil];
    [self refresh]; [self rebuild];
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification; [_feedback dismiss]; ++_feedbackSerial; [_timer invalidate]; (void)_client.claim(false); _client.close();
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}
- (void)sessionInactive:(NSNotification *)notification {
    (void)notification; [_feedback dismiss]; ++_feedbackSerial; _feedbackCursor.reset(); FXInvalidateSessionActions(); (void)_client.claim(false); _claimed=NO;
}
- (void)refresh {
    IOReturn result=_client.query(_snapshot); _valid=result==kIOReturnSuccess;
    if(!_valid) { _status=[NSString stringWithFormat:@"Bridge query unavailable: 0x%x",result]; _client.close(); _claimed=NO; _feedbackCursor.reset(); ++_feedbackSerial; [_feedback dismiss]; }
    _lastQuery=NSProcessInfo.processInfo.systemUptime;
}
- (void)tick:(NSTimer *)timer {
    (void)timer; if(_busy) return;
    const NSTimeInterval pollNow=NSProcessInfo.processInfo.systemUptime;
    if(pollNow-_lastFeedbackPoll>0.5) { _feedbackCursor.reset(); ++_feedbackSerial; }
    _lastFeedbackPoll=pollNow;
    if(NSProcessInfo.processInfo.systemUptime-_lastQuery>5) [self refresh];
    if(!FXIsConsoleUser()) { if(_claimed) (void)_client.claim(false); _claimed=NO; _feedbackCursor.reset(); ++_feedbackSerial; [_feedback dismiss]; return; }
    if(!_listening) { if(_claimed) (void)_client.claim(false); _claimed=NO; return; }
    if(!_claimed) {
        _feedbackCursor.reset();
        const IOReturn result=_client.claim(true); _claimed=result==kIOReturnSuccess;
        if(!_claimed) { _status=[NSString stringWithFormat:@"Fn claim unavailable: 0x%x",result]; return; }
        NSLog(@"FN_CLAIM active abi=%u",FX_FN_ABI_VERSION);
    }
    FXSessionBatch events {}; IOReturn result=_client.events(events);
    if(result!=kIOReturnSuccess) { _claimed=NO; _feedbackCursor.reset(); ++_feedbackSerial; [_feedback dismiss]; _status=[NSString stringWithFormat:@"Fn consumer unavailable: 0x%x",result]; return; }
    if(events.enabled!=_lastEvents.enabled || events.observedCount!=_lastEvents.observedCount)
        NSLog(@"FN_STATUS enabled=%u observed=%u last=0x%x queued=%u",events.enabled,events.observedCount,events.lastObservedCode,events.count);
    if(NSProcessInfo.processInfo.systemUptime-pollNow>0.5) { _feedbackCursor.reset(); ++_feedbackSerial; }
    _lastEvents=events;
    const bool observed=_feedbackCursor.consume(events.observedCount,events.lastObservedCode,events.enabled && _feedbackEnabled);
    // HID events are only observed, never re-injected. Wait briefly for the OS to
    // process the existing kernel event, then READ its current state. A newer
    // event/session cancels this read/display; held keys coalesce to the latest.
    if(observed) {
        const uint64_t serial=++_feedbackSerial,generation=FXSessionGeneration();
        const uint32_t code=events.lastObservedCode;
        const NSTimeInterval observedAt=pollNow;
        if(![self feedbackAllowed:code]) { [_feedback dismiss]; }
        else if(!fx::fnRoute(code).action) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                if(self->_busy || NSProcessInfo.processInfo.systemUptime-observedAt>0.5 || serial!=self->_feedbackSerial || generation!=FXSessionGeneration() || !self->_claimed || ![self feedbackAllowed:code] || !FXIsConsoleUser()) return;
                if(code==FX_FN_EVENT_BASE+5) [self refresh];
                if(serial!=self->_feedbackSerial || !self->_claimed || generation!=FXSessionGeneration() || !FXIsConsoleUser() || NSProcessInfo.processInfo.systemUptime-observedAt>0.5) return;
                [self->_feedback observeCode:code profile:self->_valid?&self->_snapshot:nullptr deadline:observedAt+0.5];
            });
        }
    }
    // Consume once before dispatch, with no requeue on failure/cancel. ABI 3
    // drains ordered brightness repeats and at most one power/radio/session action.
    const uint64_t batchGeneration=FXSessionGeneration();
    bool sessionHandled=false, brightnessFeedback=false;
    uint32_t actionFeedbackCode=0; fx::Feedback actionFeedback;
    for(uint32_t i=0;i<events.count;++i) {
        if(batchGeneration!=FXSessionGeneration() || !FXIsConsoleUser()) break;
        const auto &event=events.events[i]; const auto route=fx::fnRoute(event.acpiCode);
        if(!events.enabled || !route.recognized || route.action!=event.action || !route.action) continue;
        const bool brightness=event.action==FXBrightnessDown || event.action==FXBrightnessUp;
        if(!brightness && sessionHandled) continue;
        _busy=YES; const uint64_t generation=FXSessionGeneration(); fx::Feedback feedback;
        _status=FXPerformSessionAction(event.action,true,&feedback); _busy=NO;
        NSLog(@"FN_ACTION code=0x%x result=%@",event.acpiCode,_status);
        if([self feedbackAllowed:event.acpiCode] && events.lastObservedCode==event.acpiCode && generation==FXSessionGeneration() && FXIsConsoleUser()) {
            actionFeedbackCode=event.acpiCode; actionFeedback=feedback; brightnessFeedback=brightness;
        }
        if(!brightness) sessionHandled=true;
    }
    // Render once after the ordered drain. Brightness comes from the existing
    // read-only driver query, never from a requested step or a status string.
    if(actionFeedbackCode && batchGeneration==FXSessionGeneration() && _claimed && [self feedbackAllowed:actionFeedbackCode] && FXIsConsoleUser()) {
        ++_feedbackSerial;
        if(brightnessFeedback) [_feedback observeCode:actionFeedbackCode profile:nullptr deadline:pollNow+0.5];
        else [_feedback showCode:actionFeedbackCode feedback:actionFeedback detail:nil];
    }
}
- (BOOL)helperTrusted {
    NSString *reason=nil; BOOL trusted=FXHelperTrusted(&reason);
    _helperReason=reason; return trusted;
}
- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu; [self refresh]; _trusted=[self helperTrusted]; [self rebuild];
}
- (NSMenuItem *)add:(NSString *)title action:(SEL)selector tag:(NSInteger)tag enabled:(BOOL)enabled {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:selector keyEquivalent:@""];
    item.target=self; item.tag=tag; item.enabled=enabled; [_item.menu addItem:item]; return item;
}
- (void)rebuild {
    NSMenu *menu=_item.menu; menu.autoenablesItems=NO; [menu removeAllItems];
    [self add:_valid?[NSString stringWithFormat:@"Bridge: %@",state(_snapshot.state)]:@"Bridge unavailable" action:nullptr tag:0 enabled:NO];
    [self add:@"Current firmware profile: unknown (no readback)" action:nullptr tag:0 enabled:NO];
    [self add:[NSString stringWithFormat:@"Last acknowledged request: %@",_valid?profile(_snapshot.lastAcceptedProfile):@"Unknown"] action:nullptr tag:0 enabled:NO];
    [self add:_valid && (_snapshot.flags&FXModelDeclaredFlag)?@"Model: declared FX505GT; not independently verified":@"Model: not declared" action:nullptr tag:0 enabled:NO];
    [menu addItem:NSMenuItem.separatorItem];
    for(uint32_t p=0;p<3;++p) [self add:[@"Request " stringByAppendingString:profile(p)] action:@selector(setProfile:) tag:p enabled:_valid && _snapshot.state==FXReady && (_snapshot.supportedProfiles&(1u<<p)) && _trusted && !_busy];
    if(!_trusted) [self add:_helperReason?:@"Profile helper has not been validated." action:nullptr tag:0 enabled:NO];
    [menu addItem:NSMenuItem.separatorItem];
    [self add:@"Toggle default-input microphone mute" action:@selector(sessionAction:) tag:FXMicrophoneMute enabled:FXIsConsoleUser() && FXMicrophoneSupported()];
    [self add:@"Toggle internal-panel power" action:@selector(sessionAction:) tag:FXPanelPowerToggle enabled:FXIsConsoleUser() && FXPanelPowerSupported()];
    [self add:@"Sleep system…" action:@selector(sessionAction:) tag:FXSystemSleep enabled:FXIsConsoleUser()];
    [self add:@"Toggle Wi-Fi + Bluetooth…" action:@selector(sessionAction:) tag:FXRadiosToggle enabled:FXIsConsoleUser() && FXBluetoothEnabled()];
    NSMenuItem *radio=[self add:@"Enable Bluetooth control…" action:@selector(toggleBluetooth:) tag:0 enabled:!_busy && FXIsConsoleUser()];
    radio.state=FXBluetoothEnabled()?NSControlStateValueOn:NSControlStateValueOff;
    [self add:@"Open Bluetooth settings" action:@selector(bluetooth:) tag:0 enabled:YES];
    NSMenuItem *listen=[self add:@"Enable Fn shortcuts" action:@selector(toggleListening:) tag:0 enabled:!_busy];
    listen.state=_listening?NSControlStateValueOn:NSControlStateValueOff;
    NSMenuItem *osd=[self add:@"Fn OSD (requires Fn session listener)" action:@selector(toggleFeedback:) tag:0 enabled:YES];
    osd.state=_feedbackEnabled?NSControlStateValueOn:NSControlStateValueOff;
    NSMenuItem *position=[self add:@"Place OSD at exact screen center" action:@selector(toggleFeedbackPosition:) tag:0 enabled:_feedbackEnabled];
    position.state=_feedback.screenCentered?NSControlStateValueOn:NSControlStateValueOff;
    NSMenuItem *audio=[self add:@"Custom volume OSD (may duplicate macOS)" action:@selector(toggleFeedbackCategory:) tag:1 enabled:_feedbackEnabled];
    audio.state=_audioFeedback?NSControlStateValueOn:NSControlStateValueOff;
    NSMenuItem *brightness=[self add:@"Custom brightness OSD (may duplicate macOS)" action:@selector(toggleFeedbackCategory:) tag:2 enabled:_feedbackEnabled];
    brightness.state=_brightnessFeedback?NSControlStateValueOn:NSControlStateValueOff;
    NSMenuItem *keyboard=[self add:@"Custom keyboard-light OSD (may duplicate macOS)" action:@selector(toggleFeedbackCategory:) tag:3 enabled:_feedbackEnabled];
    keyboard.state=_keyboardFeedback?NSControlStateValueOn:NSControlStateValueOff;
    [self add:_claimed?@"Fn consumer: exclusive console claim active":@"Fn consumer: inactive; no queued action replay" action:nullptr tag:0 enabled:NO];
    [menu addItem:NSMenuItem.separatorItem];
    [self add:_status action:nullptr tag:0 enabled:NO];
    [self add:@"Diagnostics / limitations…" action:@selector(diagnostics:) tag:0 enabled:YES];
    [self add:@"Quit" action:@selector(quit:) tag:0 enabled:YES];
}
- (void)setProfile:(NSMenuItem *)sender {
    if(_busy || sender.tag<0 || sender.tag>2 || !FXIsConsoleUser()) return;
    ++_feedbackSerial; [_feedback dismiss];
    [self refresh];
    if(!_valid || _snapshot.state!=FXReady || !(_snapshot.supportedProfiles&(1u<<sender.tag))) return;
    if(![self helperTrusted]) { _status=_helperReason; return; }
    const uint64_t generation=FXSessionGeneration();
    NSAlert *alert=[NSAlert new]; alert.messageText=[@"Request " stringByAppendingString:profile((uint32_t)sender.tag)];
    alert.informativeText=@"This requests a firmware performance/fan policy. It does not measure the current mode or RPM. macOS authorization can be cancelled and may reuse a recent authorization. No password is stored by this app.";
    [alert addButtonWithTitle:@"Request"]; [alert addButtonWithTitle:@"Cancel"];
    _busy=YES;
    if([alert runModal]!=NSAlertFirstButtonReturn) { _status=@"Profile request cancelled; no helper invoked."; _busy=NO; return; }
    if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) { _status=@"Profile request cancelled after session change."; _busy=NO; return; }
    // Repeat trust check after the confirmation. Root can replace a helper,
    // but ordinary users cannot change the validated non-writable path.
    if(![self helperTrusted]) { _status=_helperReason; _busy=NO; return; }
    if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) { _status=@"Profile request cancelled after session change."; _busy=NO; return; }
    NSString *script=nil;
    switch(sender.tag) {
        case FXNormal: script=@"do shell script \"/Library/PrivilegedHelperTools/org.fx505gt.fxprofile set normal\" with administrator privileges"; break;
        case FXOverboost: script=@"do shell script \"/Library/PrivilegedHelperTools/org.fx505gt.fxprofile set overboost\" with administrator privileges"; break;
        case FXSilent: script=@"do shell script \"/Library/PrivilegedHelperTools/org.fx505gt.fxprofile set silent\" with administrator privileges"; break;
    }
    NSDictionary *error=nil; NSAppleEventDescriptor *reply=[[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&error];
    if(!reply) _status=[error[NSAppleScriptErrorNumber] intValue]==-128 ? @"Authorization cancelled; no retry." : @"Profile request failed or was not acknowledged; hardware state is unknown.";
    else _status=@"Helper completed; firmware acknowledgment is not measured current mode.";
    _busy=NO; [self refresh];
}
- (void)sessionAction:(NSMenuItem *)sender {
    if(_busy) return; ++_feedbackSerial; [_feedback dismiss]; _busy=YES; const uint64_t generation=FXSessionGeneration(); fx::Feedback feedback;
    _status=FXPerformSessionAction((uint32_t)sender.tag,false,&feedback); _busy=NO;
    uint32_t key=sender.tag==FXMicrophoneMute?4:(sender.tag==FXPanelPowerToggle?6:(sender.tag==FXSystemSleep?11:12));
    if(_feedbackEnabled && generation==FXSessionGeneration() && FXIsConsoleUser()) [_feedback showCode:FX_FN_EVENT_BASE+key feedback:feedback detail:nil];
}
- (void)toggleFeedbackPosition:(id)sender {
    (void)sender; _feedback.screenCentered=!_feedback.screenCentered; ++_feedbackSerial; [_feedback dismiss];
}
- (BOOL)feedbackAllowed:(uint32_t)code {
    if(!_feedbackEnabled) return NO;
    const uint32_t key=code-FX_FN_EVENT_BASE;
    if(key>=1 && key<=3) return _audioFeedback;
    if(key==7 || key==8) return _brightnessFeedback;
    if(key==13 || key==14) return _keyboardFeedback;
    return fx::feedbackCode(code);
}
- (void)toggleFeedbackCategory:(NSMenuItem *)sender {
    switch(sender.tag) {
        case 1:_audioFeedback=!_audioFeedback; break;
        case 2:_brightnessFeedback=!_brightnessFeedback; break;
        case 3:_keyboardFeedback=!_keyboardFeedback; break;
        default:return;
    }
    ++_feedbackSerial; _feedbackCursor.reset(); [_feedback dismiss];
}
- (void)toggleFeedback:(id)sender {
    (void)sender; _feedbackEnabled=!_feedbackEnabled; ++_feedbackSerial;
    _feedbackCursor.reset(); [_feedback dismiss];
}
- (void)toggleListening:(id)sender {
    (void)sender; if(_busy) return;
    _listening=!_listening; ++_feedbackSerial; _feedbackCursor.reset(); [_feedback dismiss];
    [NSUserDefaults.standardUserDefaults setBool:_listening forKey:@"HardwareFnEnabled"];
    if(!_listening) { FXInvalidateSessionActions(); (void)_client.claim(false); _claimed=NO; }
    _status=_listening?@"Fn shortcuts enabled; preference saved.":@"Fn shortcuts disabled; preference saved.";
}
- (void)toggleBluetooth:(id)sender {
    (void)sender; if(_busy) return;
    ++_feedbackSerial; [_feedback dismiss];
    if(FXBluetoothEnabled()) { FXEnableBluetooth(false); [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"BluetoothCompanionEnabled"]; FXInvalidateSessionActions(); _status=@"Bluetooth companion disabled; no radio state changed."; return; }
    NSAlert *a=[NSAlert new]; a.messageText=@"Enable Bluetooth control?";
    a.informativeText=@"The source-built, hash-pinned companion uses the private power API documented by blueutil. macOS may ask for Bluetooth permission; you can deny it. No privacy setting is bypassed. Controller/OS compatibility is unverified. F12 can disconnect Wi-Fi and Bluetooth devices when the Fn listener is enabled.";
    [a addButtonWithTitle:@"Enable and check power"]; [a addButtonWithTitle:@"Cancel"];
    const uint64_t generation=FXSessionGeneration(); _busy=YES;
    if([a runModal]!=NSAlertFirstButtonReturn || generation!=FXSessionGeneration() || !FXIsConsoleUser()) { _busy=NO; _status=@"Bluetooth companion remains disabled."; return; }
    FXEnableBluetooth(true); int power=-1;
    if(!FXReadBluetooth(power) || generation!=FXSessionGeneration() || !FXIsConsoleUser()) { FXEnableBluetooth(false); _status=@"Bluetooth unavailable, permission denied, or timed out. Companion disabled; no radio changed."; }
    else _status=power?@"Bluetooth controller and preference report On. Control enabled; preference saved.":@"Bluetooth controller and preference report Off. Control enabled; preference saved.";
    [NSUserDefaults.standardUserDefaults setBool:FXBluetoothEnabled() forKey:@"BluetoothCompanionEnabled"];
    _busy=NO;
}
- (void)bluetooth:(id)sender {
    (void)sender; // A settings shortcut, never a private Bluetooth power API.
    BOOL opened=[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Bluetooth"]];
    _status=opened?@"Bluetooth settings opened; no radio state is asserted.":@"Open Bluetooth settings manually; this OS did not accept the settings shortcut.";
}
- (void)diagnostics:(id)sender {
    (void)sender; NSAlert *a=[NSAlert new]; a.messageText=@"FX505GT diagnostics";
    a.informativeText=[NSString stringWithFormat:@"Native components built; individual hardware results appear below.\nProfile ABI %u; Fn ABI %u.\nLast request status=%u, raw status=%u, raw=0x%08x, IOReturn=0x%08x.\nLast observed Fn code=0x%x; observed=%u; dropped=%u.\nModel declaration is not physical verification. F6 uses the unique internal-panel dsyp or bklt parameter. F12 requires explicit Bluetooth opt-in and controls enumerated Wi-Fi plus the default Bluetooth controller. Reports are OS/driver state, not physical panel or RF measurements. F4 needs settable CoreAudio input mute. Other Fn actions depend on the documented ACPI route and compatible macOS drivers.\nSource version: %s",FX_PROFILE_ABI_VERSION,FX_FN_ABI_VERSION,_snapshot.lastRequestStatus,_snapshot.lastWriteRawStatus,_snapshot.lastWriteRaw,_snapshot.lastWriteIOReturn,_lastEvents.lastObservedCode,_lastEvents.observedCount,_lastEvents.dropped,FX_SOURCE_VERSION];
    [a runModal];
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
@end
int main(int argc,const char **argv) {
    if(argc==2 && strcmp(argv[1],"--hardware-status")==0) {
        @autoreleasepool {
            int power=-1; const bool itlwm=FXReadItlwmPower(power);
            printf("microphone_mute=%d internal_panel_toggle=%d itlwm_power_api=%d wifi_power=%d\n",FXMicrophoneSupported(),FXPanelPowerSupported(),itlwm,power);
        }
        return 0;
    }
    @autoreleasepool {
        NSApplication *app=[NSApplication sharedApplication];
        __attribute__((objc_precise_lifetime)) FXMenu *delegate=[FXMenu new];
        app.delegate=delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
