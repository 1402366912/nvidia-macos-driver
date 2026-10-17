// SPDX-License-Identifier: MIT
#include "FXFeedbackPolicy.hpp"
#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/graphics/IOGraphicsTypes.h>
#include "FXSessionPolicy.hpp"
extern bool FXIsConsoleUser();
extern uint64_t FXSessionGeneration();
static uint64_t savedPanel=0;
static SInt32 savedPower=-1;
static CFStringRef savedParameter=nullptr;
void FXForgetPanelPower() { savedPanel=0; savedPower=-1; savedParameter=nullptr; }
// Apple's pinned AppleBacklightDisplay::probe requires a built-in LCD panel.
// Never select a generic IODisplay, the first framebuffer, or external display.
static io_service_t uniquePanel() {
    io_iterator_t iterator=IO_OBJECT_NULL;
    if(IOServiceGetMatchingServices(kIOMasterPortDefault,IOServiceMatching("AppleBacklightDisplay"),&iterator)!=KERN_SUCCESS) return IO_OBJECT_NULL;
    io_service_t first=IOIteratorNext(iterator), extra=IOIteratorNext(iterator);
    const bool valid=IOIteratorIsValid(iterator); IOObjectRelease(iterator);
    if(!valid || !first || extra) { if(first) IOObjectRelease(first); if(extra) IOObjectRelease(extra); return IO_OBJECT_NULL; }
    return first;
}
static bool integer(CFDictionaryRef dict,CFStringRef key,SInt32 &value) {
    CFTypeRef object=CFDictionaryGetValue(dict,key);
    return object && CFGetTypeID(object)==CFNumberGetTypeID() && CFNumberGetValue(static_cast<CFNumberRef>(object),kCFNumberSInt32Type,&value);
}
static bool readPanel(io_service_t panel, CFStringRef &parameter, SInt32 &value, SInt32 &maximum) {
    CFDictionaryRef params=nullptr;
    if(IODisplayCopyParameters(panel,0,&params)!=kIOReturnSuccess || !params) return false;
    bool valid=false;
    const CFStringRef choices[]={CFSTR(kIODisplayPowerStateKey),CFSTR("bklt")};
    for(CFStringRef key:choices) {
        CFTypeRef object=CFDictionaryGetValue(params,key);
        if(!object || CFGetTypeID(object)!=CFDictionaryGetTypeID()) continue;
        auto range=static_cast<CFDictionaryRef>(object); SInt32 minimum=-1;
        if(!integer(range,CFSTR(kIODisplayValueKey),value) || !integer(range,CFSTR(kIODisplayMinValueKey),minimum) || !integer(range,CFSTR(kIODisplayMaxValueKey),maximum)) continue;
        if(minimum!=0 || maximum<=0 || value<0 || value>maximum) continue;
        if(CFEqual(key,CFSTR(kIODisplayPowerStateKey)) && maximum!=2) continue;
        parameter=key; valid=true; break;
    }
    CFRelease(params); return valid;
}
bool FXPanelPowerSupported() {
    io_service_t panel=uniquePanel(); if(!panel) return false;
    CFStringRef parameter=nullptr; SInt32 state=-1,maximum=0; bool valid=readPanel(panel,parameter,state,maximum); IOObjectRelease(panel); return valid;
}
NSString *FXTogglePanelPower(fx::Feedback *feedback) {
    if(!FXIsConsoleUser()) return @"Panel request refused: inactive console user.";
    const uint64_t generation=FXSessionGeneration();
    io_service_t panel=uniquePanel();
    if(!panel) return @"Unsupported: no unique AppleBacklightDisplay internal panel. No display changed.";
    CFStringRef parameter=nullptr; SInt32 before=-1,maximum=0;
    if(!readPanel(panel,parameter,before,maximum)) { IOObjectRelease(panel); return @"Unsupported: internal panel has neither a dsyp power nor bklt backlight parameter."; }
    uint64_t identity=0;
    if(IORegistryEntryGetRegistryEntryID(panel,&identity)!=KERN_SUCCESS || !identity) { IOObjectRelease(panel); return @"Internal-panel identity unavailable. No display changed."; }
    const bool restoring=before==0 && savedPanel==identity && savedParameter && CFEqual(savedParameter,parameter) && savedPower>0 && savedPower<=maximum;
    const SInt32 target=before>0?0:(restoring?savedPower:maximum);
    // Fixed documented parameter only. No direct ACPI, EC or framebuffer call.
    if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) { IOObjectRelease(panel); FXForgetPanelPower(); if(feedback) feedback->state=fx::FeedbackState::Cancelled; return @"Panel request cancelled after session change."; }
    IOReturn result=IODisplaySetIntegerParameter(panel,0,parameter,target);
    CFStringRef afterParameter=nullptr; SInt32 actual=-1,afterMax=0; bool matched=readPanel(panel,afterParameter,actual,afterMax) && CFEqual(afterParameter,parameter) && actual==target;
    io_service_t current=uniquePanel();
    bool same=current && IOObjectIsEqualTo(panel,current); if(current) IOObjectRelease(current);
    IOObjectRelease(panel);
    if(result!=kIOReturnSuccess || !matched || !same) { FXForgetPanelPower();
        return @"Internal-panel power request failed, changed identity, or driver readback differed; current panel power is unknown."; }
    if(target==0) { savedPanel=identity; savedPower=before; savedParameter=parameter; } else FXForgetPanelPower();
    if(feedback) { feedback->state=fx::FeedbackState::Readback; feedback->on=target!=0; }
    const bool backlight=CFEqual(parameter,CFSTR("bklt"));
    return [NSString stringWithFormat:@"Internal-panel %@ reports %@; external displays unchanged.",backlight?@"backlight":@"power parameter",target==0?@"Off":@"restored/On"];
}

NSString *FXAdjustPanelBrightness(int direction) {
    if(!FXIsConsoleUser() || (direction!=-1 && direction!=1)) return @"Brightness request refused.";
    io_service_t panel=uniquePanel(); if(!panel) return @"No unique internal panel.";
    CFDictionaryRef params=nullptr; CFStringRef key=nullptr;
    SInt32 before=0,minimum=0,maximum=0;
    if(IODisplayCopyParameters(panel,0,&params)==kIOReturnSuccess && params) {
        const CFStringRef choices[]={CFSTR("bklt"),CFSTR("brightness")};
        for(CFStringRef candidate:choices) {
            CFTypeRef object=CFDictionaryGetValue(params,candidate);
            if(!object || CFGetTypeID(object)!=CFDictionaryGetTypeID()) continue;
            auto range=static_cast<CFDictionaryRef>(object);
            if(integer(range,CFSTR(kIODisplayValueKey),before) && integer(range,CFSTR(kIODisplayMinValueKey),minimum) && integer(range,CFSTR(kIODisplayMaxValueKey),maximum) && minimum==0 && maximum>0 && before>=0 && before<=maximum) { key=candidate; break; }
        }
        CFRelease(params);
    }
    if(!key) { IOObjectRelease(panel); return @"Internal-panel brightness parameter unavailable."; }
    const SInt32 step=maximum/16+(maximum%16!=0);
    SInt32 target=direction>0 ? (before>maximum-step?maximum:before+step) : (before<step?minimum:before-step);
    IOReturn result=IODisplaySetIntegerParameter(panel,0,key,target);
    SInt32 actual=-1; result=result==kIOReturnSuccess?IODisplayGetIntegerRangeParameter(panel,0,key,&actual,&minimum,&maximum):result;
    IOObjectRelease(panel); FXForgetPanelPower();
    return result==kIOReturnSuccess && actual==target ? [NSString stringWithFormat:@"Internal-panel brightness %d/%d",actual,maximum] : @"Internal-panel brightness write/readback failed.";
}
