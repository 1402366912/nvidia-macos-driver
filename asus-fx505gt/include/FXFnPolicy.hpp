/* SPDX-License-Identifier: MIT. Pure bounded routing/queue logic, no device I/O. */
#ifndef FX_FN_POLICY_HPP
#define FX_FN_POLICY_HPP
#include "FXFnABI.h"
namespace fx {
struct FnRoute {
    uint32_t hidCode, action;
    bool fan, recognized;
};
inline FnRoute fnRoute(uint32_t code) {
    switch (code) {
        case FX_FN_EVENT_BASE+1: return {0x32, 0, false, true};
        case FX_FN_EVENT_BASE+2: return {0x31, 0, false, true};
        case FX_FN_EVENT_BASE+3: return {0x30, 0, false, true};
        case FX_FN_EVENT_BASE+4: return {0, FXMicrophoneMute, false, true};
        case FX_FN_EVENT_BASE+5: return {0, 0, true, true};
        case FX_FN_EVENT_BASE+6: return {0, FXPanelPowerToggle, false, true};
        case FX_FN_EVENT_BASE+7: return {0x20, 0, false, true};
        case FX_FN_EVENT_BASE+8: return {0x10, 0, false, true};
        case FX_FN_EVENT_BASE+9: return {0x61, 0, false, true};
        case FX_FN_EVENT_BASE+10: return {0x6b, 0, false, true};
        case FX_FN_EVENT_BASE+11: return {0, FXSystemSleep, false, true};
        case FX_FN_EVENT_BASE+12: return {0, FXRadiosToggle, false, true};
        case FX_FN_EVENT_BASE+13: return {0xc4, 0, false, true};
        case FX_FN_EVENT_BASE+14: return {0xc5, 0, false, true};
        default: return {0, 0, false, false};
    }
}
class FnQueue {
    FXSessionBatch batch_ {};
    uint64_t lastNS_[5] {};
    bool seen_[5] {};
public:
    FnQueue() { batch_.version=FX_FN_ABI_VERSION; batch_.size=sizeof(batch_); }
    void configure(bool enabled) { batch_.enabled=enabled; clear(); }
    bool enabled() const { return batch_.enabled != 0; }
    void observe(uint32_t code) { batch_.lastObservedCode=code; ++batch_.observedCount; }
    void clear() { batch_.count=0; for (unsigned i=0;i<5;++i) { lastNS_[i]=0; seen_[i]=false; } }
    void push(uint32_t action, uint32_t code, uint64_t now) {
        if (!enabled() || action<FXMicrophoneMute || action>FXRadiosToggle) return;
        if (seen_[action] && now>=lastNS_[action] && now-lastNS_[action]<250000000ull) return;
        lastNS_[action]=now; seen_[action]=true;
        if (batch_.count==FX_FN_CAPACITY) { ++batch_.dropped; return; }
        batch_.events[batch_.count++]={action,code,static_cast<uint32_t>(now),static_cast<uint32_t>(now>>32)};
    }
    FXSessionBatch drain(uint64_t now) {
        FXSessionBatch out=batch_; out.count=0;
        for (uint32_t i=0;i<batch_.count;++i) {
            auto e=batch_.events[i]; uint64_t t=(static_cast<uint64_t>(e.uptimeHi)<<32)|e.uptimeLo;
            if (now>=t && now-t<=2000000000ull) out.events[out.count++]=e;
            else ++batch_.dropped;
        }
        out.dropped=batch_.dropped;
        // No stale memory, and never return a consumed event twice.
        for (uint32_t i=out.count;i<FX_FN_CAPACITY;++i) out.events[i]={0,0,0,0};
        batch_.count=0;
        return out;
    }
};
}
#endif
