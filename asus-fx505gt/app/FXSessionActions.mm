// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import <CoreWLAN/CoreWLAN.h>
#import <CoreAudio/CoreAudio.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <unistd.h>
#include "FXFnABI.h"
#include "FXSessionPolicy.hpp"
extern bool FXPanelPowerSupported();
extern void FXForgetPanelPower();
extern NSString *FXTogglePanelPower();
extern NSString *FXAdjustPanelBrightness(int direction);
extern bool FXBluetoothEnabled();
extern bool FXReadBluetooth(int &power);
extern bool FXWriteBluetooth(int target);
// Independently declared itlwm legacy POWER ABI: ClientKit/Common.h and
// IoctlId.h at AirportItlwm-AX211 030ef90b (version1, selector2, set bit23).
// This is the existing HeliPort control path, not a raw/AWDL session.
struct FXItlPower { uint32_t version, enabled, maxsleep; };
static IOReturn itlPower(int target, int &power) {
    io_iterator_t iterator=IO_OBJECT_NULL;
    IOReturn result=IOServiceGetMatchingServices(kIOMasterPortDefault,IOServiceMatching("itlwm"),&iterator);
    if(result!=kIOReturnSuccess) return result;
    io_service_t service=IOIteratorNext(iterator), extra=IOIteratorNext(iterator); IOObjectRelease(iterator);
    if(!service || extra) { if(service) IOObjectRelease(service); if(extra) IOObjectRelease(extra); return kIOReturnNotFound; }
    io_connect_t connection=IO_OBJECT_NULL;
    result=IOServiceOpen(service,mach_task_self(),0,&connection); IOObjectRelease(service);
    if(result!=kIOReturnSuccess) return result;
    FXItlPower state {}; size_t size=sizeof(state);
    result=IOConnectCallStructMethod(connection,2,nullptr,0,&state,&size);
    if(result==kIOReturnSuccess && (size!=sizeof(state) || state.version!=1 || state.enabled>1)) result=kIOReturnBadMessageID;
    if(result==kIOReturnSuccess && target>=0) {
        state.enabled=static_cast<uint32_t>(target);
        result=IOConnectCallStructMethod(connection,0x800002,&state,sizeof(state),nullptr,nullptr);
        if(result==kIOReturnSuccess) {
            size=sizeof(state); result=IOConnectCallStructMethod(connection,2,nullptr,0,&state,&size);
            if(result==kIOReturnSuccess && (size!=sizeof(state) || state.version!=1 || state.enabled!=static_cast<uint32_t>(target))) result=kIOReturnNotReady;
        }
    }
    if(result==kIOReturnSuccess) power=static_cast<int>(state.enabled);
    IOServiceClose(connection); return result;
}
bool FXReadItlwmPower(int &power) { return itlPower(-1,power)==kIOReturnSuccess; }
static uint64_t sessionGeneration=0; // Main-thread only.
uint64_t FXSessionGeneration() { return sessionGeneration; }
void FXInvalidateSessionActions() { ++sessionGeneration; FXForgetPanelPower(); }
bool FXIsConsoleUser() {
    uid_t uid=static_cast<uid_t>(-1); gid_t gid=0;
    CFStringRef name=SCDynamicStoreCopyConsoleUser(nullptr,&uid,&gid);
    bool present=name!=nullptr; if(name) CFRelease(name); return present && uid==getuid() && uid!=0 && geteuid()==getuid();
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
NSString *FXPerformSessionAction(uint32_t action,bool physicalEvent) {
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
        case FXPanelPowerToggle: return FXTogglePanelPower();
        case FXBrightnessDown: return FXAdjustPanelBrightness(-1);
        case FXBrightnessUp: return FXAdjustPanelBrightness(1);
        case FXSystemSleep: {
            if(!physicalEvent && !confirm(@"Put this Mac to sleep?",@"This sends a real system-sleep request, not only an on-screen icon.")) return @"Sleep cancelled.";
            if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Sleep cancelled after session change.";
            if(![NSRunningApplication runningApplicationsWithBundleIdentifier:@"local.asus.platform.ui"].count)
                return @"Open 华硕控制 first; it owns the unified sleep/lid policy.";
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"org.fx505gt.sleep-request" object:nil userInfo:nil deliverImmediately:YES];
            return @"Sleep requested through 华硕控制; its existing lid policy will be restored after wake.";
        }
        case FXRadiosToggle: {
            if(!FXBluetoothEnabled()) return @"Radio control is disabled. Enable Bluetooth control first.";
            NSArray<CWInterface *> *interfaces=[[CWWiFiClient sharedWiFiClient] interfaces];
            if(!interfaces.count) {
                int wifi=-1, bluetooth=-1;
                if(!FXReadItlwmPower(wifi)) return @"Neither CoreWLAN nor the itlwm POWER interface is available. No radio changed.";
                if(!FXReadBluetooth(bluetooth)) return @"Bluetooth power unavailable. No radio changed.";
                const int target=fx::nextRadioPower(wifi!=0,bluetooth);
                if(!physicalEvent && !confirm(target?@"Turn Wi-Fi and Bluetooth on?":@"Turn Wi-Fi and Bluetooth off?",@"Uses itlwm/HeliPort power control and the default Bluetooth controller. Network connections may disconnect.")) return @"Radio request cancelled.";
                if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Radio request cancelled after session change.";
                if(bluetooth!=target && !FXWriteBluetooth(target)) return @"Bluetooth request failed; Wi-Fi unchanged.";
                if(wifi!=target && itlPower(target,wifi)!=kIOReturnSuccess) return @"Partial result: itlwm Wi-Fi request failed or readback differed.";
                if(!FXReadBluetooth(bluetooth) || bluetooth!=target || !FXReadItlwmPower(wifi) || wifi!=target) return @"Radio readback differs; current states are unverified.";
                return target?@"itlwm Wi-Fi and Bluetooth report On.":@"itlwm Wi-Fi and Bluetooth report Off.";
            }
            if(interfaces.count>8) return @"Unsupported: too many CoreWLAN interfaces. No radio changed.";
            NSMutableSet<NSString *> *names=[NSMutableSet set]; NSMutableDictionary<NSString *,NSNumber *> *beforePower=[NSMutableDictionary dictionary]; bool anyOn=false;
            for(CWInterface *wifi in interfaces) {
                if(!wifi.interfaceName.length || [names containsObject:wifi.interfaceName]) return @"Wi-Fi interface identity is ambiguous. No radio changed.";
                [names addObject:wifi.interfaceName]; const BOOL power=wifi.powerOn; beforePower[wifi.interfaceName]=@(power); anyOn|=power;
            }
            int bluetooth=-1;
            if(!FXReadBluetooth(bluetooth)) return @"Bluetooth power is unsupported, permission denied, timed out, or readback disagrees. No radio changed.";
            const int target=fx::nextRadioPower(anyOn,bluetooth);
            if(!physicalEvent && !confirm(target?@"Turn Wi-Fi and Bluetooth on?":@"Turn Wi-Fi and Bluetooth off?",@"This controls all enumerated CoreWLAN interfaces and the default Bluetooth controller. Connections and Bluetooth input devices may disconnect. No other radio or RF-silence guarantee is provided.")) return @"Radio request cancelled.";
            if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Radio request cancelled after session change.";
            // Recheck identities/state after any modal delay, before the first write.
            NSArray<CWInterface *> *current=[[CWWiFiClient sharedWiFiClient] interfaces];
            NSMutableSet<NSString *> *currentNames=[NSMutableSet set];
            for(CWInterface *wifi in current) if(wifi.interfaceName.length) [currentNames addObject:wifi.interfaceName];
            if(current.count!=interfaces.count || ![currentNames isEqualToSet:names]) return @"Radio request cancelled after Wi-Fi topology change.";
            int freshBluetooth=-1;
            if(!FXReadBluetooth(freshBluetooth) || freshBluetooth!=bluetooth) return @"Bluetooth state changed or became unavailable. No radio changed.";
            for(CWInterface *wifi in interfaces) {
                CWInterface *fresh=[[CWWiFiClient sharedWiFiClient] interfaceWithName:wifi.interfaceName];
                if(!fresh || fresh.powerOn!=beforePower[wifi.interfaceName].boolValue) return @"Wi-Fi state changed before the request. No radio changed.";
            }
            if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Radio request cancelled after session change.";
            // Bluetooth first: if it cannot reach target, do not disconnect Wi-Fi.
            // These APIs are not transactional. Never silently roll back or retry.
            if(bluetooth!=target && !FXWriteBluetooth(target)) return @"Bluetooth request failed or timed out; Bluetooth state is unknown. Wi-Fi was not changed. No rollback or retry was attempted.";
            for(CWInterface *wifi in current) {
                if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) return @"Radio operation stopped after session change; some radios may already have changed.";
                if(wifi.powerOn!=(target!=0)) {
                    NSError *error=nil;
                    if(![wifi setPower:target!=0 error:&error] || wifi.powerOn!=(target!=0))
                        return @"Partial radio result: Bluetooth reached target, but a Wi-Fi request failed or readback differed. States may be mixed; no rollback or retry.";
                }
            }
            int after=-1;
            if(!FXReadBluetooth(after) || after!=target) return @"Radio result is unverified: final Bluetooth readback differs or is unavailable.";
            NSArray<CWInterface *> *afterWifi=[[CWWiFiClient sharedWiFiClient] interfaces];
            NSMutableSet<NSString *> *afterNames=[NSMutableSet set];
            for(CWInterface *wifi in afterWifi) {
                if(!wifi.interfaceName.length || wifi.powerOn!=(target!=0)) return @"Radio result is unverified: final Wi-Fi readback differs.";
                [afterNames addObject:wifi.interfaceName];
            }
            if(afterWifi.count!=interfaces.count || ![afterNames isEqualToSet:names]) return @"Radio result is unverified: Wi-Fi topology changed.";
            return target?@"All enumerated Wi-Fi interfaces and the default Bluetooth controller report On.":@"All enumerated Wi-Fi interfaces and the default Bluetooth controller report Off. Other radios and RF silence are not measured.";
        }
        default: return @"Unknown session action refused.";
    }
}
