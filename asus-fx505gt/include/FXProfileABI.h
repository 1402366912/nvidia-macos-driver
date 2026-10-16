/* SPDX-License-Identifier: MIT
 * Fixed FX505GT firmware-profile interface. No generic ACPI/WMI/EC selectors.
 */
#ifndef FX_PROFILE_ABI_H
#define FX_PROFILE_ABI_H
#include <stdint.h>
#define FX_PROFILE_ABI_VERSION 1u
#define FX_PROFILE_CONNECT_TYPE 0x46583250u
#define FX_PROFILE_UNKNOWN 0xffffffffu
#define FX_PROFILE_SERVICE "AsusSMC"
enum FXSelector { FXQuery = 0, FXSetProfile = 1 };
enum FXProfile { FXNormal = 0, FXOverboost = 1, FXSilent = 2 };
enum FXBackend { FXNoBackend = 0, FXFanBoost = 1, FXThermalPolicy = 2 };
enum FXState {
    FXDisabled = 0, FXModelNotDeclared = 1, FXWMIMethodUnverified = 2,
    FXUnprobed = 3, FXUnsupported = 4, FXFirmwareError = 5,
    FXReady = 6, FXStopped = 7, FXSuspended = 8, FXPowerNotifierUnavailable = 9
};
enum FXRawStatus { FXNotRead = 0, FXRawOK = 1, FXTransportError = 2, FXInvalidMethod = 3 };
enum FXRequestStatus {
    FXNeverRequested = 0, FXAccepted = 1, FXRejected = 2,
    FXWriteTransportError = 3, FXWriteInvalidMethod = 4, FXWriteUnexpectedResult = 5
};
enum FXSource { FXNoSource = 0, FXCommandLine = 1, FXFnF5 = 2 };
enum FXFlags {
    FXEnabledFlag = 1u << 0, FXModelDeclaredFlag = 1u << 1,
    FXModelVerifiedFlag = 1u << 2, /* Reserved: never asserted by v1. */
    FXWMIVerifiedFlag = 1u << 3, FXFnF5EnabledFlag = 1u << 4
};
/* All fields are fixed-width; no pointers, bools, native enums or padding. */
typedef struct FXProfileSnapshot {
    uint32_t version, size, state, flags;
    uint32_t backend, supportedProfiles, currentProfile, reserved0;
    uint32_t thermalProbeStatus, thermalProbeRaw, thermalProbeIOReturn;
    uint32_t fanProbeStatus, fanProbeRaw, fanProbeIOReturn;
    uint32_t lastRequestedProfile, lastRequestSource, lastRequestStatus;
    uint32_t lastWriteRawStatus, lastWriteRaw, lastWriteIOReturn;
    uint32_t lastAcceptedProfile, lastAcceptedSource, acceptedCount;
    uint32_t fnEventCount, fnSuppressedCount, reserved1;
    uint32_t lastRequestUptimeLo, lastRequestUptimeHi;
    uint32_t lastAcceptedUptimeLo, lastAcceptedUptimeHi;
} FXProfileSnapshot;
#ifdef __cplusplus
static_assert(sizeof(FXProfileSnapshot) == 30 * sizeof(uint32_t), "FX ABI changed");
#endif
#endif
