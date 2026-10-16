/* SPDX-License-Identifier: MIT
 * Independently written policy. Protocol facts: pinned faustus, see SOURCES.md.
 * This file deliberately contains no IOKit, ACPI or device I/O.
 */
#ifndef FX_PROFILE_POLICY_HPP
#define FX_PROFILE_POLICY_HPP
#include "FXProfileABI.h"
namespace fx {
static const uint32_t ThermalDevice = 0x00120075u;
static const uint32_t FanBoostDevice = 0x00110018u;
static const uint32_t Presence = 0x00010000u;
static const uint64_t DebounceNS = 250000000ull;
struct Raw {
    uint32_t status, value, ioReturn;
    static Raw unread() { return {FXNotRead, 0, 0}; }
    static Raw decode(bool ok, uint32_t value, uint32_t ioReturn) {
        if (!ok) return {FXTransportError, 0, ioReturn};
        if (value == 0xfffffffeu || value == 0xffffffffu)
            return {FXInvalidMethod, value, ioReturn};
        return {FXRawOK, value, ioReturn};
    }
};
class Policy {
    FXProfileSnapshot s_ {};
    bool fnSeen_ {false};
    uint64_t lastFnNS_ {0};
public:
    Policy() {
        s_.version = FX_PROFILE_ABI_VERSION;
        s_.size = sizeof(s_);
        s_.currentProfile = FX_PROFILE_UNKNOWN;
        s_.lastRequestedProfile = FX_PROFILE_UNKNOWN;
        s_.lastAcceptedProfile = FX_PROFILE_UNKNOWN;
    }
    const FXProfileSnapshot &snapshot() const { return s_; }
    void configure(bool enabled, bool modelDeclared, bool wmiVerified, bool fnEnabled) {
        s_.flags = (enabled ? static_cast<uint32_t>(FXEnabledFlag) : 0u) |
            (modelDeclared ? static_cast<uint32_t>(FXModelDeclaredFlag) : 0u) |
            (wmiVerified ? static_cast<uint32_t>(FXWMIVerifiedFlag) : 0u) |
            (fnEnabled ? static_cast<uint32_t>(FXFnF5EnabledFlag) : 0u);
        s_.state = !enabled ? FXDisabled : !modelDeclared ? FXModelNotDeclared :
            !wmiVerified ? FXWMIMethodUnverified : FXUnprobed;
    }
    bool mayProbe() const {
        return s_.state == FXUnprobed || s_.state == FXUnsupported ||
            s_.state == FXFirmwareError || s_.state == FXReady;
    }
    void probe(Raw thermal, Raw fan) {
        if (!mayProbe()) return;
        s_.thermalProbeStatus = thermal.status;
        s_.thermalProbeRaw = thermal.value;
        s_.thermalProbeIOReturn = thermal.ioReturn;
        s_.fanProbeStatus = fan.status;
        s_.fanProbeRaw = fan.value;
        s_.fanProbeIOReturn = fan.ioReturn;
        uint32_t oldBackend = s_.backend, oldMask = s_.supportedProfiles;
        s_.backend = FXNoBackend;
        s_.supportedProfiles = 0;
        if (thermal.status == FXRawOK && (thermal.value & Presence)) {
            s_.backend = FXThermalPolicy;
            s_.supportedProfiles = 7u;
        } else if (fan.status == FXRawOK && (fan.value & Presence) && (fan.value & 3u)) {
            s_.backend = FXFanBoost;
            s_.supportedProfiles = 1u | ((fan.value & 3u) << 1);
        }
        if (s_.backend != FXNoBackend) s_.state = FXReady;
        else if (thermal.status == FXTransportError || fan.status == FXTransportError) s_.state = FXFirmwareError;
        else s_.state = FXUnsupported;
        if (oldBackend != s_.backend || oldMask != s_.supportedProfiles) {
            s_.lastAcceptedProfile = FX_PROFILE_UNKNOWN;
            s_.lastAcceptedSource = FXNoSource;
            s_.lastAcceptedUptimeLo = s_.lastAcceptedUptimeHi = 0;
        }
        /* Never derive currentProfile from DSTS: low bits are capabilities. */
    }
    uint32_t device() const {
        return s_.backend == FXThermalPolicy ? ThermalDevice :
            s_.backend == FXFanBoost ? FanBoostDevice : 0u;
    }
    bool prepare(uint32_t profile, uint32_t source, uint64_t nowNS = 0) {
        if (source != FXCommandLine && source != FXFnF5) return false;
        s_.lastRequestedProfile = profile;
        s_.lastRequestSource = source;
        s_.lastRequestStatus = FXRejected;
        s_.lastRequestUptimeLo = static_cast<uint32_t>(nowNS);
        s_.lastRequestUptimeHi = static_cast<uint32_t>(nowNS >> 32);
        s_.lastWriteRawStatus = FXNotRead;
        s_.lastWriteRaw = s_.lastWriteIOReturn = 0;
        if (s_.state != FXReady || profile > FXSilent ||
            !(s_.supportedProfiles & (1u << profile))) return false;
        s_.lastRequestStatus = FXNeverRequested;
        return true;
    }
    bool complete(Raw result, uint64_t nowNS = 0) {
        s_.lastWriteRawStatus = result.status;
        s_.lastWriteRaw = result.value;
        s_.lastWriteIOReturn = result.ioReturn;
        if (result.status == FXTransportError) s_.lastRequestStatus = FXWriteTransportError;
        else if (result.status == FXInvalidMethod) s_.lastRequestStatus = FXWriteInvalidMethod;
        else if (result.status != FXRawOK || result.value != 1u)
            s_.lastRequestStatus = FXWriteUnexpectedResult;
        else {
            s_.lastRequestStatus = FXAccepted;
            s_.lastAcceptedProfile = s_.lastRequestedProfile;
            s_.lastAcceptedSource = s_.lastRequestSource;
            s_.lastAcceptedUptimeLo = static_cast<uint32_t>(nowNS);
            s_.lastAcceptedUptimeHi = static_cast<uint32_t>(nowNS >> 32);
            ++s_.acceptedCount;
            return true;
        }
        /* A failed/ambiguous write may have changed hardware. Never treat an
         * earlier accepted command as the current state or cycle anchor. */
        s_.lastAcceptedProfile = FX_PROFILE_UNKNOWN;
        s_.lastAcceptedSource = FXNoSource;
        s_.lastAcceptedUptimeLo = s_.lastAcceptedUptimeHi = 0;
        return false;
    }
    bool fnEvent(uint32_t code, uint64_t nowNS, uint32_t &requested) {
        if (code != 0x99u && code != 0xaeu) return false;
        ++s_.fnEventCount;
        if (s_.state != FXReady || !(s_.flags & FXFnF5EnabledFlag)) return false;
        if ((s_.backend == FXFanBoost && code != 0x99u) ||
            (s_.backend == FXThermalPolicy && code != 0xaeu)) return false;
        if (fnSeen_ && nowNS >= lastFnNS_ && nowNS - lastFnNS_ < DebounceNS) {
            ++s_.fnSuppressedCount;
            return false;
        }
        fnSeen_ = true;
        lastFnNS_ = nowNS;
        /* Unknown after attach/error/backend change: explicitly request normal
         * first. Otherwise cycle the last accepted command, not a measurement. */
        if (s_.lastAcceptedProfile == FX_PROFILE_UNKNOWN) { requested = FXNormal; return true; }
        for (uint32_t n = 1; n <= 3; ++n) {
            uint32_t p = (s_.lastAcceptedProfile + n) % 3;
            if (s_.supportedProfiles & (1u << p)) { requested = p; return true; }
        }
        return false;
    }
    void invalidate() {
        s_.lastAcceptedProfile = FX_PROFILE_UNKNOWN;
        s_.lastAcceptedSource = FXNoSource;
        s_.lastAcceptedUptimeLo = s_.lastAcceptedUptimeHi = 0;
        fnSeen_ = false;
        lastFnNS_ = 0;
    }
    void suspend() { invalidate(); if (mayProbe()) s_.state = FXSuspended; }
    void resume() { invalidate(); if (s_.state == FXSuspended) s_.state = FXUnprobed; }
    // Public IOPM flags: WillChange=1, DidChange=2; CPU|Graphics=3.
    // Initial priority-interest synchronization has flags=0, from=0.
    void powerCapabilities(uint32_t flags, uint32_t from, uint32_t to) {
        if (flags & ~3u) { suspend(); return; }
        if (flags & 1u) { suspend(); return; }
        if ((flags & 2u) || (flags == 0 && from == 0)) {
            if ((to & 3u) == 3u) resume(); else suspend();
        } else suspend();
    }
    void powerUnavailable() {
        invalidate();
        if (mayProbe() || s_.state == FXSuspended) s_.state = FXPowerNotifierUnavailable;
    }
    void stop() { invalidate(); s_.state = FXStopped; }
};
}
#endif
