// SPDX-License-Identifier: MIT
#include "FXProfileABI.h"
#include "FXFnABI.h"
#ifndef FX_SOURCE_VERSION
#define FX_SOURCE_VERSION "unversioned"
#endif
#include <cstdio>
#include <cstring>
#ifdef __APPLE__
#include <IOKit/IOKitLib.h>
#include <unistd.h>
#endif

static const char *profileName(uint32_t p) {
    switch (p) { case FXNormal: return "normal"; case FXOverboost: return "overboost";
        case FXSilent: return "silent"; default: return "unknown"; }
}
static const char *stateName(uint32_t s) {
    switch (s) {
        case FXDisabled: return "disabled"; case FXModelNotDeclared: return "model-not-declared";
        case FXWMIMethodUnverified: return "wmi-method-unverified"; case FXUnprobed: return "unprobed";
        case FXUnsupported: return "unsupported"; case FXFirmwareError: return "firmware-error";
        case FXReady: return "ready"; case FXStopped: return "stopped";
        case FXSuspended: return "suspended"; case FXPowerNotifierUnavailable: return "power-notifier-unavailable"; default: return "invalid-abi-state";
    }
}
static void print(const FXProfileSnapshot &s) {
    std::printf("abi=%u state=%s backend=%u supported_profile_mask=0x%x\n", s.version,
        stateName(s.state), s.backend, s.supportedProfiles);
    std::printf("enabled=%u model_declared=%u model_verified=%u wmi_verified=%u fn_f5_enabled=%u\n",
        !!(s.flags & FXEnabledFlag), !!(s.flags & FXModelDeclaredFlag),
        !!(s.flags & FXModelVerifiedFlag), !!(s.flags & FXWMIVerifiedFlag),
        !!(s.flags & FXFnF5EnabledFlag));
    std::printf("current_profile=%s current_profile_readback=unavailable\n", profileName(s.currentProfile));
    std::printf("last_requested=%s request_source=%u request_status=%u\n",
        profileName(s.lastRequestedProfile), s.lastRequestSource, s.lastRequestStatus);
    std::printf("last_accepted=%s accepted_source=%u accepted_count=%u\n",
        profileName(s.lastAcceptedProfile), s.lastAcceptedSource, s.acceptedCount);
    std::printf("last_request_uptime_ns=%llu last_accepted_uptime_ns=%llu\n",
        static_cast<unsigned long long>((static_cast<uint64_t>(s.lastRequestUptimeHi) << 32) | s.lastRequestUptimeLo),
        static_cast<unsigned long long>((static_cast<uint64_t>(s.lastAcceptedUptimeHi) << 32) | s.lastAcceptedUptimeLo));
    std::printf("last_write_raw_status=%u raw=0x%08x ioreturn=0x%08x\n",
        s.lastWriteRawStatus, s.lastWriteRaw, s.lastWriteIOReturn);
    std::printf("thermal_probe_status=%u raw=0x%08x ioreturn=0x%08x\n",
        s.thermalProbeStatus, s.thermalProbeRaw, s.thermalProbeIOReturn);
    std::printf("fan_probe_status=%u raw=0x%08x ioreturn=0x%08x\n",
        s.fanProbeStatus, s.fanProbeRaw, s.fanProbeIOReturn);
    std::printf("fn_events=%u fn_suppressed=%u\n", s.fnEventCount, s.fnSuppressedCount);
}
static void usage() {
    std::puts("Usage: fxprofile query | set normal|overboost|silent\n"
        "query only reads capabilities and software command history.\n"
        "set requires root and explicitly requests one firmware performance/fan profile.\n"
        "A successful set means firmware returned 1, not that current mode/RPM was measured.\n"
        "The bridge must be explicitly enabled for a declared FX505GT in the kext personality.");
}
int main(int argc, char **argv) {
    if (argc == 2 && !std::strcmp(argv[1], "--identity")) {
        std::printf("org.fx505gt.fxprofile abi=%u fnabi=%u source=%s\n",
            FX_PROFILE_ABI_VERSION, FX_FN_ABI_VERSION, FX_SOURCE_VERSION);
        return 0;
    }
    if (argc == 2 && (!std::strcmp(argv[1], "--help") || !std::strcmp(argv[1], "-h"))) {
        usage(); return 0;
    }
    bool query = argc == 2 && !std::strcmp(argv[1], "query");
    bool set = argc == 3 && !std::strcmp(argv[1], "set");
    uint64_t requested = FX_PROFILE_UNKNOWN;
    if (set) for (uint32_t p = FXNormal; p <= FXSilent; ++p)
        if (!std::strcmp(argv[2], profileName(p))) requested = p;
    if ((!query && !set) || (set && requested == FX_PROFILE_UNKNOWN)) { usage(); return 2; }
#ifndef __APPLE__
    (void)print; // Keep host-only compilation honest; no fake device backend.
    std::fputs("fxprofile requires macOS IOKit. No driver connection or firmware operation occurred.\n", stderr);
    return 3;
#else
    if (set && geteuid() != 0) { std::fputs("set requires root.\n", stderr); return 4; }
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t ret = IOServiceGetMatchingServices(kIOMasterPortDefault,
        IOServiceMatching(FX_PROFILE_SERVICE), &iterator);
    if (ret != KERN_SUCCESS) { std::fprintf(stderr, "Service lookup failed: 0x%x\n", ret); return 3; }
    io_service_t service = IOIteratorNext(iterator);
    io_service_t extra = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!service || extra) {
        if (service) IOObjectRelease(service);
        if (extra) IOObjectRelease(extra);
        std::fputs("Expected exactly one AsusSMC service; refusing ambiguous or missing device.\n", stderr);
        return 3;
    }
    io_connect_t connection = IO_OBJECT_NULL;
    ret = IOServiceOpen(service, mach_task_self(), FX_PROFILE_CONNECT_TYPE, &connection);
    IOObjectRelease(service);
    if (ret != KERN_SUCCESS) {
        std::fprintf(stderr, "Bridge open failed: 0x%x (stock AsusSMC has no profile client).\n", ret);
        return 3;
    }
    int exitStatus = 0;
    if (set) {
        ret = IOConnectCallScalarMethod(connection, FXSetProfile, &requested, 1, nullptr, nullptr);
        if (ret != KERN_SUCCESS) {
            std::fprintf(stderr, "Profile request failed or was not acknowledged: 0x%x. Do not assume the firmware stayed unchanged.\n", ret);
            exitStatus = 5;
        } else std::puts("Firmware acknowledged the request (raw result 1); actual current profile is unverified.");
    }
    FXProfileSnapshot snapshot {};
    size_t size = sizeof(snapshot);
    ret = IOConnectCallStructMethod(connection, FXQuery, nullptr, 0, &snapshot, &size);
    IOServiceClose(connection);
    if (ret != KERN_SUCCESS || size != sizeof(snapshot) ||
        snapshot.version != FX_PROFILE_ABI_VERSION || snapshot.size != sizeof(snapshot)) {
        std::fprintf(stderr, "Query failed or returned incompatible ABI: 0x%x\n", ret);
        return exitStatus ? exitStatus : 6;
    }
    print(snapshot);
    return exitStatus;
#endif
}
