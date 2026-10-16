/* SPDX-License-Identifier: MIT */
#ifndef FX_CLIENT_HPP
#define FX_CLIENT_HPP
#include "FXProfileABI.h"
#include "FXFnABI.h"
#include <IOKit/IOKitLib.h>
class FXClient {
    io_connect_t port_ {IO_OBJECT_NULL};
public:
    ~FXClient() { close(); }
    void close() { if (port_) IOServiceClose(port_); port_=IO_OBJECT_NULL; }
    IOReturn open() {
        if (port_) return kIOReturnSuccess;
        io_iterator_t it=IO_OBJECT_NULL;
        auto kr=IOServiceGetMatchingServices(kIOMasterPortDefault,IOServiceMatching(FX_PROFILE_SERVICE),&it);
        if (kr!=KERN_SUCCESS) return kr;
        auto first=IOIteratorNext(it), extra=IOIteratorNext(it); IOObjectRelease(it);
        if (!first || extra) { if(first) IOObjectRelease(first); if(extra) IOObjectRelease(extra); return kIOReturnNotFound; }
        kr=IOServiceOpen(first,mach_task_self(),FX_PROFILE_CONNECT_TYPE,&port_); IOObjectRelease(first); return kr;
    }
    IOReturn query(FXProfileSnapshot &s) {
        auto kr=open(); if(kr!=KERN_SUCCESS) return kr;
        size_t n=sizeof(s); kr=IOConnectCallStructMethod(port_,FXQuery,nullptr,0,&s,&n);
        if(kr==KERN_SUCCESS && (n!=sizeof(s)||s.size!=sizeof(s)||s.version!=FX_PROFILE_ABI_VERSION)) return kIOReturnBadMessageID;
        return kr;
    }
    IOReturn claim(bool enable) {
        if (!enable && !port_) return kIOReturnSuccess;
        auto kr=open(); if(kr!=KERN_SUCCESS) return kr;
        uint64_t value=enable?1:0;
        return IOConnectCallScalarMethod(port_,FXClaimSession,&value,1,nullptr,nullptr);
    }
    IOReturn events(FXSessionBatch &b) {
        if (!port_) return kIOReturnNotOpen;
        size_t n=sizeof(b); auto kr=IOConnectCallStructMethod(port_,FXReadSession,nullptr,0,&b,&n);
        if (kr==KERN_SUCCESS && (n!=sizeof(b)||b.size!=sizeof(b)||b.version!=FX_FN_ABI_VERSION||b.count>FX_FN_CAPACITY)) return kIOReturnBadMessageID;
        return kr;
    }
};
#endif
