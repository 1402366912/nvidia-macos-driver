// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#include "FXClient.hpp"
#include "FXFnPolicy.hpp"
#include <unistd.h>
#include "FXBuildIdentity.h"
extern NSString *const FXHelperPath;
extern bool FXHelperTrusted(NSString **reason);
extern bool FXIsConsoleUser();
extern uint64_t FXSessionGeneration();
extern void FXInvalidateSessionActions();
extern bool FXMicrophoneSupported();
extern NSString *FXPerformSessionAction(uint32_t action,bool physicalEvent);
extern bool FXPanelPowerSupported();
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
    NSTimer *_timer;
    NSString *_status, *_helperReason;
    BOOL _valid, _trusted, _listening, _claimed, _busy;
    NSTimeInterval _lastQuery;
}
@end
@implementation FXMenu
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    if(geteuid()==0 || geteuid()!=getuid()) { NSLog(@"Run FX505GT Control as an ordinary console user with matching real/effective UIDs."); [NSApp terminate:nil]; return; }
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier])
        if(app.processIdentifier!=NSProcessInfo.processInfo.processIdentifier) { [app activateWithOptions:NSApplicationActivateIgnoringOtherApps]; [NSApp terminate:nil]; return; }
    _status=@"Source preview: hardware validation pending.";
    _item=[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength]; _item.button.title=@"FX505GT";
    _item.menu=[NSMenu new]; _item.menu.delegate=self;
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(sessionInactive:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(sessionInactive:) name:NSWorkspaceWillSleepNotification object:nil];
    [self refresh]; [self rebuild];
    _timer=[NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification; [_timer invalidate]; (void)_client.claim(false); _client.close();
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}
- (void)sessionInactive:(NSNotification *)notification {
    (void)notification; FXInvalidateSessionActions(); (void)_client.claim(false); _claimed=NO;
}
- (void)refresh {
    IOReturn result=_client.query(_snapshot); _valid=result==kIOReturnSuccess;
    if(!_valid) { _status=[NSString stringWithFormat:@"Bridge query unavailable: 0x%x",result]; _client.close(); _claimed=NO; }
    _lastQuery=NSProcessInfo.processInfo.systemUptime;
}
- (void)tick:(NSTimer *)timer {
    (void)timer; if(_busy) return;
    if(NSProcessInfo.processInfo.systemUptime-_lastQuery>5) [self refresh];
    if(!_listening || !FXIsConsoleUser()) { if(_claimed) (void)_client.claim(false); _claimed=NO; return; }
    if(!_claimed) { _claimed=_client.claim(true)==kIOReturnSuccess; if(!_claimed) return; }
    FXSessionBatch events {}; IOReturn result=_client.events(events);
    if(result!=kIOReturnSuccess) { _claimed=NO; _status=[NSString stringWithFormat:@"Fn consumer unavailable: 0x%x",result]; return; }
    _lastEvents=events;
    // Consume once before dispatch. No requeue on failure/cancel, no action
    // injection selector, no forwarding to another client. Only one action is
    // acted on per poll: discard a burst rather than chain power/radio dialogs.
    if(events.count) {
        const auto route=fx::fnRoute(events.events[0].acpiCode);
        if(!events.enabled || !route.recognized || route.action!=events.events[0].action || !route.action) { _status=@"Invalid dedicated Fn event refused."; return; }
        _busy=YES; _status=FXPerformSessionAction(events.events[0].action,true); _busy=NO;
        if(events.count>1) _status=[_status stringByAppendingString:@" Additional queued actions were discarded."];
    }
}
- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu; [self refresh]; _trusted=FXHelperTrusted(&_helperReason); [self rebuild];
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
    NSMenuItem *radio=[self add:@"Enable Bluetooth companion this launch…" action:@selector(toggleBluetooth:) tag:0 enabled:!_busy && FXIsConsoleUser()];
    radio.state=FXBluetoothEnabled()?NSControlStateValueOn:NSControlStateValueOff;
    [self add:@"Open Bluetooth settings" action:@selector(bluetooth:) tag:0 enabled:YES];
    NSMenuItem *listen=[self add:@"Handle dedicated Fn session actions this launch" action:@selector(toggleListening:) tag:0 enabled:!_busy];
    listen.state=_listening?NSControlStateValueOn:NSControlStateValueOff;
    [self add:_claimed?@"Fn consumer: exclusive console claim active":@"Fn consumer: inactive; no queued action replay" action:nullptr tag:0 enabled:NO];
    [menu addItem:NSMenuItem.separatorItem];
    [self add:_status action:nullptr tag:0 enabled:NO];
    [self add:@"Diagnostics / limitations…" action:@selector(diagnostics:) tag:0 enabled:YES];
    [self add:@"Quit" action:@selector(quit:) tag:0 enabled:YES];
}
- (void)setProfile:(NSMenuItem *)sender {
    if(_busy || sender.tag<0 || sender.tag>2 || !FXIsConsoleUser()) return;
    [self refresh];
    if(!_valid || _snapshot.state!=FXReady || !(_snapshot.supportedProfiles&(1u<<sender.tag))) return;
    if(!FXHelperTrusted(&_helperReason)) { _status=_helperReason; return; }
    const uint64_t generation=FXSessionGeneration();
    NSAlert *alert=[NSAlert new]; alert.messageText=[@"Request " stringByAppendingString:profile((uint32_t)sender.tag)];
    alert.informativeText=@"This requests a firmware performance/fan policy. It does not measure the current mode or RPM. macOS authorization can be cancelled and may reuse a recent authorization. No password is stored by this app.";
    [alert addButtonWithTitle:@"Request"]; [alert addButtonWithTitle:@"Cancel"];
    _busy=YES;
    if([alert runModal]!=NSAlertFirstButtonReturn) { _status=@"Profile request cancelled; no helper invoked."; _busy=NO; return; }
    if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) { _status=@"Profile request cancelled after session change."; _busy=NO; return; }
    // Repeat trust check after the confirmation. Root can replace a helper,
    // but ordinary users cannot change the validated non-writable path.
    if(!FXHelperTrusted(&_helperReason)) { _status=_helperReason; _busy=NO; return; }
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
    if(_busy) return; _busy=YES; _status=FXPerformSessionAction((uint32_t)sender.tag,false); _busy=NO;
}
- (void)toggleListening:(id)sender {
    (void)sender; if(_busy) return;
    if(_listening) { _listening=NO; FXInvalidateSessionActions(); (void)_client.claim(false); _claimed=NO; _status=@"Fn session actions disabled for this launch."; return; }
    NSAlert *a=[NSAlert new]; a.messageText=@"Enable physical Fn actions for this launch?";
    a.informativeText=@"Genuine dedicated Fn+F4/F6/F11/F12 events may mute input, toggle the internal panel, sleep this Mac, or change Wi-Fi/Bluetooth without another per-key confirmation. Radio control also requires its separate Bluetooth opt-in. Existing kernel HID keys are not duplicated. This session permission is not saved.";
    [a addButtonWithTitle:@"Enable for this launch"]; [a addButtonWithTitle:@"Cancel"];
    const uint64_t generation=FXSessionGeneration(); _busy=YES;
    BOOL accepted=[a runModal]==NSAlertFirstButtonReturn; _busy=NO;
    _listening=accepted && generation==FXSessionGeneration() && FXIsConsoleUser();
    _status=_listening?@"Waiting for the dedicated Fn ABI 2 contract and exclusive console claim.":@"Fn listener remains disabled.";
}
- (void)toggleBluetooth:(id)sender {
    (void)sender; if(_busy) return;
    if(FXBluetoothEnabled()) { FXEnableBluetooth(false); FXInvalidateSessionActions(); _status=@"Bluetooth companion disabled; no radio state changed."; return; }
    NSAlert *a=[NSAlert new]; a.messageText=@"Enable Bluetooth control for this launch?";
    a.informativeText=@"The source-built, hash-pinned companion uses the private power API documented by blueutil. macOS may ask for Bluetooth permission; you can deny it. No privacy setting is bypassed. Controller/OS compatibility is unverified. F12 can disconnect Wi-Fi and Bluetooth devices when the Fn listener is enabled.";
    [a addButtonWithTitle:@"Enable and check power"]; [a addButtonWithTitle:@"Cancel"];
    const uint64_t generation=FXSessionGeneration(); _busy=YES;
    if([a runModal]!=NSAlertFirstButtonReturn || generation!=FXSessionGeneration() || !FXIsConsoleUser()) { _busy=NO; _status=@"Bluetooth companion remains disabled."; return; }
    FXEnableBluetooth(true); int power=-1;
    if(!FXReadBluetooth(power) || generation!=FXSessionGeneration() || !FXIsConsoleUser()) { FXEnableBluetooth(false); _status=@"Bluetooth unavailable, permission denied, or timed out. Companion disabled; no radio changed."; }
    else _status=power?@"Bluetooth controller and preference report On. Control enabled for this launch.":@"Bluetooth controller and preference report Off. Control enabled for this launch.";
    _busy=NO;
}
- (void)bluetooth:(id)sender {
    (void)sender; // A settings shortcut, never a private Bluetooth power API.
    BOOL opened=[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Bluetooth"]];
    _status=opened?@"Bluetooth settings opened; no radio state is asserted.":@"Open Bluetooth settings manually; this OS did not accept the settings shortcut.";
}
- (void)diagnostics:(id)sender {
    (void)sender; NSAlert *a=[NSAlert new]; a.messageText=@"FX505GT source preview";
    a.informativeText=[NSString stringWithFormat:@"Native build and hardware validation are pending.\nProfile ABI %u; Fn ABI %u.\nLast request status=%u, raw status=%u, raw=0x%08x, IOReturn=0x%08x.\nLast observed Fn code=0x%x; observed=%u; dropped=%u.\nModel declaration is not physical verification. F6 requires a unique internal-panel dsyp 0..2 parameter. F12 requires explicit Bluetooth opt-in and controls enumerated Wi-Fi plus the default Bluetooth controller. Reports are OS/driver state, not physical panel or RF measurements. F4 needs settable CoreAudio input mute. Other Fn actions depend on the documented ACPI route and compatible macOS drivers.\nSource version: %s",FX_PROFILE_ABI_VERSION,FX_FN_ABI_VERSION,_snapshot.lastRequestStatus,_snapshot.lastWriteRawStatus,_snapshot.lastWriteRaw,_snapshot.lastWriteIOReturn,_lastEvents.lastObservedCode,_lastEvents.observedCount,_lastEvents.dropped,FX_SOURCE_VERSION];
    [a runModal];
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
@end
int main(int argc,const char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app=[NSApplication sharedApplication];
        __attribute__((objc_precise_lifetime)) FXMenu *delegate=[FXMenu new];
        app.delegate=delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
