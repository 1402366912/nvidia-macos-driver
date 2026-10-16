/* SPDX-License-Identifier: MIT */
#include "FXProfileABI.h"
#include "FXFnABI.h"
_Static_assert(sizeof(FXSessionBatch) == 288, "Fn batch ABI");
#include <stddef.h>
_Static_assert(sizeof(FXProfileSnapshot) == 120, "fixed ABI size");
_Static_assert(offsetof(FXProfileSnapshot, currentProfile) == 24, "fixed current field");
_Static_assert(offsetof(FXProfileSnapshot, lastRequestUptimeLo) == 104, "fixed timestamp field");
int fx_abi_c_check(void) { return FXQuery == 0 && FXSetProfile == 1; }
