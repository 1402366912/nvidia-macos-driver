// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/graphics/IOGraphicsTypes.h>
#include "FXSessionPolicy.hpp"
extern bool FXIsConsoleUser();
extern uint64_t FXSessionGeneration();
static uint64_t savedPanel=0;
static SInt32 savedPower=-1;
void FXForgetPanelPower() { savedPanel=0; savedPower=-1; }
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
static bool readPower(io_service_t panel,SInt32 &value) {
    CFDictionaryRef params=nullptr;
    if(IODisplayCopyParameters(panel,0,&params)!=kIOReturnSuccess || !params) { if(params) CFRelease(params); return false; }
    bool valid=false;
    if(CFGetTypeID(params)==CFDictionaryGetTypeID()) {
        CFTypeRef object=CFDictionaryGetValue(params,CFSTR(kIODisplayPowerStateKey));
        if(object && CFGetTypeID(object)==CFDictionaryGetTypeID()) {
            auto range=static_cast<CFDictionaryRef>(object); SInt32 min=-1,max=-1;
            valid=integer(range,CFSTR(kIODisplayValueKey),value) && integer(range,CFSTR(kIODisplayMinValueKey),min) &&
                integer(range,CFSTR(kIODisplayMaxValueKey),max) && fx::panelPowerRange(value,min,max);
        }
    }
    CFRelease(params); return valid;
}
bool FXPanelPowerSupported() {
    io_service_t panel=uniquePanel(); if(!panel) return false;
    SInt32 state=-1; bool valid=readPower(panel,state); IOObjectRelease(panel); return valid;
}
NSString *FXTogglePanelPower() {
    if(!FXIsConsoleUser()) return @"Panel request refused: inactive console user.";
    const uint64_t generation=FXSessionGeneration();
    io_service_t panel=uniquePanel();
    if(!panel) return @"Unsupported: no unique AppleBacklightDisplay internal panel. No display changed.";
    SInt32 before=-1;
    if(!readPower(panel,before)) { IOObjectRelease(panel); return @"Unsupported: internal panel has no valid dsyp power parameter with range 0..2. No brightness or all-display fallback."; }
    uint64_t identity=0;
    if(IORegistryEntryGetRegistryEntryID(panel,&identity)!=KERN_SUCCESS || !identity) { IOObjectRelease(panel); return @"Internal-panel identity unavailable. No display changed."; }
    const bool restoring=before==0 && savedPanel==identity && (savedPower==1 || savedPower==2);
    const SInt32 target=fx::nextPanelPower(before,restoring?savedPower:-1);
    // Fixed documented parameter only. No direct ACPI, EC or framebuffer call.
    if(generation!=FXSessionGeneration() || !FXIsConsoleUser()) { IOObjectRelease(panel); FXForgetPanelPower(); return @"Panel request cancelled after session change."; }
    IOReturn result=IODisplaySetIntegerParameter(panel,0,CFSTR(kIODisplayPowerStateKey),target);
    SInt32 actual=-1; bool matched=readPower(panel,actual) && actual==target;
    io_service_t current=uniquePanel();
    bool same=current && IOObjectIsEqualTo(panel,current); if(current) IOObjectRelease(current);
    IOObjectRelease(panel);
    if(result!=kIOReturnSuccess || !matched || !same) { FXForgetPanelPower();
        return @"Internal-panel power request failed, changed identity, or driver readback differed; current panel power is unknown."; }
    if(target==0) { savedPanel=identity; savedPower=before; } else FXForgetPanelPower();
    return target==0 ? @"Internal-panel driver reports power parameter Off. External displays unchanged; physical panel power is not measured. Press Fn+F6 again to request the previous driver state."
        : (restoring?@"Internal-panel driver reports the previous power parameter restored by this request. Physical panel power is not measured.":@"Internal-panel driver reports On. No previous state was saved; On was the explicit fallback request. Physical panel power is not measured.");
}
