/* SPDX-License-Identifier: MIT
 * Dedicated opt-in ACPI contract, NOT claimed native FX505GT event numbers.
 * FXFnBase + 1..12 = F1..F12; +13/+14 = Up/Down.
 */
#ifndef FX_FN_ABI_H
#define FX_FN_ABI_H
#include <stdint.h>
#define FX_FN_ABI_VERSION 1u
#define FX_FN_EVENT_BASE 0x0000f500u
#define FX_FN_CAPACITY 16u
enum FXFnSelector { FXClaimSession = 2, FXReadSession = 3 };
enum FXSessionAction { FXNoAction = 0, FXMicrophoneMute = 1,
    FXDisplaySleep = 2, FXSystemSleep = 3, FXWifiToggle = 4 };
typedef struct FXSessionEvent {
    uint32_t action, acpiCode, uptimeLo, uptimeHi;
} FXSessionEvent;
typedef struct FXSessionBatch {
    uint32_t version, size, enabled, count;
    uint32_t dropped, lastObservedCode, observedCount, reserved;
    FXSessionEvent events[FX_FN_CAPACITY];
} FXSessionBatch;
#ifdef __cplusplus
static_assert(sizeof(FXSessionBatch) == 288, "Fn ABI changed");
#endif
#endif
