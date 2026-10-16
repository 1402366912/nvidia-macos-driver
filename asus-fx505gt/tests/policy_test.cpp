// SPDX-License-Identifier: MIT
#include "FXProfilePolicy.hpp"
#include <cassert>
#include <cstdio>
static fx::Raw ok(uint32_t v) { return fx::Raw::decode(true, v, 0); }
static fx::Policy ready(uint32_t thermal = 0x10000, uint32_t fan = 0) {
    fx::Policy p; p.configure(true, true, true, true); p.probe(ok(thermal), ok(fan)); return p;
}
int main() {
    fx::Policy p;
    assert(p.snapshot().currentProfile == FX_PROFILE_UNKNOWN);
    assert(p.snapshot().lastAcceptedProfile == FX_PROFILE_UNKNOWN);
    assert(!p.prepare(0, FXCommandLine));
    p.configure(false, true, true, true); p.probe(ok(0x10000), ok(0x10003));
    assert(p.snapshot().state == FXDisabled && p.device() == 0);
    p.configure(true, false, true, true); assert(p.snapshot().state == FXModelNotDeclared);
    assert(!p.mayProbe());
    p.configure(true, true, false, true); assert(p.snapshot().state == FXWMIMethodUnverified);
    assert(!p.mayProbe());
    p.configure(true, true, true, true); assert(p.snapshot().state == FXUnprobed);
    p.probe(ok(0), ok(0)); assert(p.snapshot().state == FXUnsupported);
    p.probe(ok(0), ok(0x10000)); assert(p.snapshot().state == FXUnsupported);
    p.probe(fx::Raw::decode(false, 0x10000, 0xe00002bcu), ok(0));
    assert(p.snapshot().state == FXFirmwareError);
    assert(p.snapshot().thermalProbeRaw == 0 && p.snapshot().thermalProbeIOReturn == 0xe00002bcu);
    p.probe(ok(0xfffffffe), ok(0xffffffff));
    assert(p.snapshot().state == FXUnsupported && p.snapshot().supportedProfiles == 0);
    p = ready(0, 0x10001); assert(p.device() == fx::FanBoostDevice && p.snapshot().supportedProfiles == 3);
    assert(p.prepare(FXNormal, FXCommandLine)); assert(p.complete(ok(1)));
    assert(p.prepare(FXOverboost, FXCommandLine)); assert(p.complete(ok(1)));
    assert(!p.prepare(FXSilent, FXCommandLine)); assert(!p.prepare(0xffffffff, FXCommandLine));
    assert(!p.prepare(3, FXCommandLine)); assert(!p.prepare(0, FXNoSource));
    p = ready(0, 0x10002); assert(p.snapshot().supportedProfiles == 5);
    assert(!p.prepare(FXOverboost, FXCommandLine)); assert(p.prepare(FXSilent, FXCommandLine));
    p = ready(0x10000, 0x10003); assert(p.device() == fx::ThermalDevice);
    assert(p.snapshot().supportedProfiles == 7); assert(p.snapshot().currentProfile == FX_PROFILE_UNKNOWN);
    uint32_t mode = 99;
    assert(!p.fnEvent(0xc4, 0, mode));
    assert(!p.fnEvent(0x99, 0, mode)); // wrong event for selected thermal backend
    assert(p.fnEvent(0xae, 0, mode) && mode == FXNormal);
    assert(p.prepare(mode, FXFnF5)); assert(p.complete(ok(1)));
    assert(p.snapshot().lastAcceptedProfile == FXNormal && p.snapshot().lastAcceptedSource == FXFnF5);
    assert(p.snapshot().currentProfile == FX_PROFILE_UNKNOWN);
    assert(!p.fnEvent(0xae, 1000000, mode)); // both firmware notifications: one write
    assert(!p.fnEvent(0xae, 249999999, mode));
    assert(p.fnEvent(0xae, 250000000, mode) && mode == FXOverboost);
    assert(p.prepare(mode, FXFnF5)); assert(p.complete(ok(1)));
    assert(p.fnEvent(0xae, 500000000, mode) && mode == FXSilent);
    assert(p.prepare(mode, FXFnF5)); assert(p.complete(ok(1)));
    assert(p.fnEvent(0xae, 750000000, mode) && mode == FXNormal);
    assert(p.snapshot().acceptedCount == 3 && p.snapshot().fnSuppressedCount == 2);
    assert(p.prepare(FXSilent, FXCommandLine)); assert(!p.complete(ok(0)));
    assert(p.snapshot().lastRequestStatus == FXWriteUnexpectedResult);
    assert(p.snapshot().lastAcceptedProfile == FX_PROFILE_UNKNOWN);
    assert(p.snapshot().lastRequestedProfile == FXSilent);
    assert(p.fnEvent(0xae, 1000000000, mode) && mode == FXNormal);
    assert(p.prepare(mode, FXFnF5)); assert(!p.complete(ok(0xfffffffe)));
    assert(p.snapshot().lastRequestStatus == FXWriteInvalidMethod);
    assert(p.prepare(mode, FXFnF5)); assert(!p.complete(fx::Raw::decode(false, 1, 0xabc)));
    assert(p.snapshot().lastRequestStatus == FXWriteTransportError);
    assert(p.snapshot().lastWriteIOReturn == 0xabc && p.snapshot().currentProfile == FX_PROFILE_UNKNOWN);
    p = ready(0, 0x10002); assert(p.prepare(FXNormal, FXCommandLine)); assert(p.complete(ok(1)));
    assert(p.fnEvent(0x99, 0, mode) && mode == FXSilent); // skip unsupported overboost
    assert(p.prepare(mode, FXFnF5)); assert(p.complete(ok(1)));
    p.probe(ok(0x10000), ok(0x10002)); assert(p.snapshot().lastAcceptedProfile == FX_PROFILE_UNKNOWN);
    assert(p.fnEvent(0xae, 500000000, mode) && mode == FXNormal);
    assert(p.prepare(FXSilent, FXCommandLine, 0x123456789ull));
    assert(p.complete(ok(1), 0x23456789aull));
    assert(p.snapshot().lastRequestUptimeHi == 1 && p.snapshot().lastRequestUptimeLo == 0x23456789u);
    assert(p.snapshot().lastAcceptedUptimeHi == 2 && p.snapshot().lastAcceptedUptimeLo == 0x3456789au);
    p.suspend(); assert(p.snapshot().state == FXSuspended && !p.mayProbe());
    assert(p.snapshot().lastAcceptedProfile == FX_PROFILE_UNKNOWN);
    assert(!p.prepare(FXNormal, FXCommandLine)); assert(p.snapshot().lastRequestStatus == FXRejected);
    assert(!p.fnEvent(0xae, 600000000, mode));
    p.resume(); assert(p.snapshot().state == FXUnprobed && !p.prepare(0, FXCommandLine));
    p.probe(ok(0x10000), ok(0));
    assert(p.fnEvent(0xae, 600000000, mode) && mode == FXNormal);
    p.stop(); assert(p.snapshot().state == FXStopped && !p.prepare(0, FXCommandLine));
    p.probe(ok(0x10000), ok(0)); assert(p.snapshot().state == FXStopped);
    assert(!p.fnEvent(0x99, 1000000000, mode));
    p = ready(); p.configure(true, true, true, false); p.probe(ok(0x10000), ok(0));
    assert(!p.fnEvent(0x99, 0, mode));
    assert(!(p.snapshot().flags & FXModelVerifiedFlag));
    p.suspend(); p.powerCapabilities(0, 0, 3); // initial sync is not DidChange
    assert(p.snapshot().state == FXUnprobed);
    p.probe(ok(0x10000), ok(0));
    p.powerCapabilities(1, 3, 1); assert(p.snapshot().state == FXSuspended);
    p.powerCapabilities(2, 3, 1); assert(p.snapshot().state == FXSuspended); // dark wake
    p.powerCapabilities(2, 1, 3); assert(p.snapshot().state == FXUnprobed);
    p.probe(ok(0x10000), ok(0));
    p.powerCapabilities(0x80, 3, 3); assert(p.snapshot().state == FXSuspended);
    p.powerCapabilities(0, 1, 3); assert(p.snapshot().state == FXSuspended); // malformed initial sync
    p.powerCapabilities(3, 1, 3); assert(p.snapshot().state == FXSuspended); // contradictory flags
    p.powerUnavailable(); assert(p.snapshot().state == FXPowerNotifierUnavailable);
    assert(!p.mayProbe() && !p.prepare(0, FXCommandLine));
    std::puts("PASS: portable policy assertions (capabilities, errors, one backend, unknown state, Fn cycle/debounce, stop)");
}
