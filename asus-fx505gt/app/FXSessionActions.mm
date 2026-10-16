// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import <CoreWLAN/CoreWLAN.h>
#import <CoreAudio/CoreAudio.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <unistd.h>
#include "FXFnABI.h"
static uint64_t sessionGeneration=0; // Main-thread only.
uint64_t FXSessionGeneration() { return sessionGeneration; }
void FXInvalidateSessionActions() { ++sessionGeneration; }
bool FXIsConsoleUser() {
    uid_t uid=static_cast<uid_t>(-1); gid_t gid=0;
    CFStringRef name=SCDynamicStoreCopyConsoleUser(nullptr,&uid,&gid);
    bool present=name!=nullptr; if(name) CFRelease(name); return present && uid==getuid() && uid!=0;
}
static bool inputMute(AudioDeviceID &device, UInt32 &muted) {
    device=kAudioObjectUnknown; muted=0;
    AudioObjectPropertyAddress def={kAudioHardwarePropertyDefaultInputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMaster};
    UInt32 size=sizeof(device);
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&def,0,nullptr,&size,&device)!=noErr || size!=sizeof(device) || device==kAudioObjectUnknown) return false;
    AudioObjectPropertyAddress mute={kAudioDevicePropertyMute,kAudioDevicePropertyScopeInput,kAudioObjectPropertyElementMaster};
    Boolean settable=false; size=sizeof(muted);
    return AudioObjectHasProperty(device,&mute) &&
        AudioObjectIsPropertySettable(device,&mute,&settable)==noErr && settable &&
        AudioObjectGetPropertyData(device,&mute,0,nullptr,&size,&muted)==noErr && size==sizeof(muted) && muted<=1;
}
bool FXMicrophoneSupported() { AudioDeviceID device; UInt32 muted; return inputMute(device,muted); }
static bool confirm(NSString *title, NSString *detail) {
    NSAlert *alert=[NSAlert new]; alert.messageText=title; alert.informativeText=detail;
    [alert addButtonWithTitle:@"Continue"]; [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal]==NSAlertFirstButtonReturn;
}
NSString *FXPerformSessionAction(uint32_t action) {
    if(!FXIsConsoleUser()) return @"Action refused: this is not the active console user.";
    const uint64_t generation=FXSessionGeneration();
    switch(action) {
        case FXMicrophoneMute: {
            AudioDeviceID device; UInt32 muted;
            if(!inputMute(device,muted)) return @"Unsupported: default input has no readable, settable master mute. Nothing changed.";
            UInt32 wanted=muted?0:1;
            AudioObjectPropertyAddress mute={kAudioDevicePropertyMute,kAudioDevicePropertyScopeInput,kAudioObjectPropertyElementMaster};
            OSStatus result=AudioObjectSetPropertyData(device,&mute,0,nullptr,sizeof(wanted),&wanted);
            UInt32 actual=0,size=sizeof(actual);
            if(result!=noErr || AudioObjectGetPropertyData(device,&mute,0,nullptr,&size,&actual)!=noErr || size!=sizeof(actual) || actual!=wanted)
                return @"Microphone mute request failed or readback differed; current mute is unknown.";
            AudioDeviceID currentDevice; UInt32 currentMute;
            if(!inputMute(currentDevice,currentMute) || currentDevice!=device || currentMute!=wanted)
                return @"Default input changed or its mute became unavailable; current default-input mute is unknown.";
            return wanted ? @"Default input device reports muted. This does not cover other recording devices." : @"Default input device reports unmuted.";
        }
        case FXDisplaySleep: {
            // Apple ships pmset; fixed executable and argument, no shell or
            // administrator escalation. This requests ALL displays to sleep,
            // not a panel-only power toggle or a current-state measurement.
            NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/pmset"];
            task.arguments=@[@"displaysleepnow"]; task.standardOutput=[NSFileHandle fileHandleWithNullDevice];
            task.standardError=[NSFileHandle fileHandleWithNullDevice]; NSError *error=nil;
            if(![task launchAndReturnError:&error]) return @"Display-sleep request could not be launched.";
            [task waitUntilExit];
            return task.terminationStatus==0 ? @"Display-sleep request sent; panel power is not measured. Use a normal key/trackpad to wake." : @"Display-sleep request failed.";
        }
        case FXSystemSleep: {
            if(!confirm(@"Put this Mac to sleep?",@"This sends a real system-sleep request, not only an on-screen icon.")) return @"Sleep cancelled.";
            if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Sleep cancelled after session change.";
            io_connect_t root=IOPMFindPowerManagement(MACH_PORT_NULL);
            if(!root) return @"Power-management service unavailable.";
            IOReturn result=IOPMSleepSystem(root); IOServiceClose(root);
            return result==kIOReturnSuccess ? @"System-sleep request accepted; actual sleep depends on macOS." : [NSString stringWithFormat:@"System-sleep request failed: 0x%x",result];
        }
        case FXWifiToggle: {
            CWInterface *wifi=[[CWWiFiClient sharedWiFiClient] interface];
            if(!wifi) return @"Unsupported: CoreWLAN exposes no primary Wi-Fi interface.";
            BOOL target=!wifi.powerOn;
            if(!confirm(target?@"Turn primary Wi-Fi on?":@"Turn primary Wi-Fi off?",@"Only the primary Wi-Fi interface is controlled. Bluetooth and other radios are unchanged. Turning Wi-Fi off can disconnect this session.")) return @"Wi-Fi request cancelled.";
            if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Wi-Fi request cancelled after session change.";
            NSError *error=nil;
            if(![wifi setPower:target error:&error] || wifi.powerOn!=target)
                return @"Wi-Fi request failed or readback differed. This is not an airplane-mode indicator.";
            return target?@"Primary Wi-Fi reports on; Bluetooth unchanged.":@"Primary Wi-Fi reports off; Bluetooth unchanged. This is not full airplane mode.";
        }
        default: return @"Unknown session action refused.";
    }
}
