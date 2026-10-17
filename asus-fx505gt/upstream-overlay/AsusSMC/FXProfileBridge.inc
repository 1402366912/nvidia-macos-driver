/* SPDX-License-Identifier: MIT
 * Included by AsusSMC.cpp so the pinned upstream target builds this code
 * without silently omitting an unregistered Xcode translation unit.
 */
#include <kern/clock.h>
#include <kern/task.h>
static_assert(kIOPMSystemCapabilityWillChange == 1 && kIOPMSystemCapabilityDidChange == 2,
              "Power transition flags changed");
static_assert(kIOPMSystemCapabilityCPU == 1 && kIOPMSystemCapabilityGraphics == 2,
              "Power capability mask changed");
OSDefineMetaClassAndStructors(AsusSMCProfileUserClient, IOUserClient)

bool AsusSMCProfileUserClient::initWithTask(task_t task, void *securityID,
                                          UInt32 type, OSDictionary *properties) {
    if (type != FX_PROFILE_CONNECT_TYPE || task == TASK_NULL ||
        !IOUserClient::initWithTask(task, securityID, type, properties)) return false;
    providerLock_ = IOLockAlloc();
    if (!providerLock_) return false;
    ownerTask_ = task;
    task_reference(ownerTask_);
    return true;
}

bool AsusSMCProfileUserClient::start(IOService *provider) {
    auto asus = OSDynamicCast(AsusSMC, provider);
    if (!asus || !IOUserClient::start(provider)) return false;
    asus->retain();
    IOLockLock(providerLock_);
    asus_ = asus;
    IOLockUnlock(providerLock_);
    return true;
}

void AsusSMCProfileUserClient::stop(IOService *provider) {
    IOLockLock(providerLock_);
    auto asus = asus_;
    asus_ = nullptr;
    IOLockUnlock(providerLock_);
    if (asus) {
        FXGateCall call {}; call.operation=FXGateCall::ReleaseSession; call.client=this;
        (void)asus->fxRun(call);
        asus->release();
    }
    IOUserClient::stop(provider);
}

void AsusSMCProfileUserClient::free() {
    if (providerLock_) { IOLockFree(providerLock_); providerLock_ = nullptr; }
    if (ownerTask_ != TASK_NULL) { task_deallocate(ownerTask_); ownerTask_ = TASK_NULL; }
    IOUserClient::free();
}

IOReturn AsusSMCProfileUserClient::clientClose() {
    terminate();
    return kIOReturnSuccess;
}

IOReturn AsusSMCProfileUserClient::externalMethod(uint32_t selector,
        IOExternalMethodArguments *args, IOExternalMethodDispatch *, OSObject *, void *) {
    if (!args || isInactive()) return kIOReturnNotAttached;
    /* No async calls, descriptor-backed structures or arbitrary buffers. */
    if (args->asyncWakePort != MACH_PORT_NULL || args->asyncReferenceCount != 0 ||
        args->structureInputSize != 0 || args->structureInputDescriptor ||
        args->structureOutputDescriptor || args->scalarOutputCount != 0)
        return kIOReturnBadArgument;
    FXGateCall call {};
    if (selector == FXQuery) {
        if (args->scalarInputCount != 0 || !args->structureOutput ||
            args->structureOutputSize != sizeof(FXProfileSnapshot)) return kIOReturnBadArgument;
        call.operation = FXGateCall::Query;
        call.snapshot = static_cast<FXProfileSnapshot *>(args->structureOutput);
    } else if (selector == FXSetProfile) {
        if (args->scalarInputCount != 1 || !args->scalarInput ||
            args->structureOutputSize != 0 || args->scalarInput[0] > FXSilent)
            return kIOReturnBadArgument;
        /* Recheck both owning and invoking task: passing a connection port to
         * another task cannot confer the opener's write privilege. */
        if (clientHasPrivilege(ownerTask_, kIOClientPrivilegeAdministrator) != kIOReturnSuccess ||
            clientHasPrivilege(current_task(), kIOClientPrivilegeAdministrator) != kIOReturnSuccess)
            return kIOReturnNotPrivileged;
        call.operation = FXGateCall::Set;
        call.profile = static_cast<uint32_t>(args->scalarInput[0]);
    } else if (selector == FXSetClamshell) {
        if(args->scalarInputCount!=1 || !args->scalarInput || args->scalarInput[0]>1 || args->structureOutputSize) return kIOReturnBadArgument;
        if(clientHasPrivilege(ownerTask_,kIOClientPrivilegeAdministrator)!=kIOReturnSuccess || clientHasPrivilege(current_task(),kIOClientPrivilegeAdministrator)!=kIOReturnSuccess) return kIOReturnNotPrivileged;
        call.operation=FXGateCall::SetClamshell; call.profile=static_cast<uint32_t>(args->scalarInput[0]); call.client=this;
    } else if (selector == FXClaimSession || selector == FXReadSession) {
        // "console" is the XNU console-user privilege string. Unsupported
        // implementations fail closed. Never accept a user-supplied UID.
        if (current_task() != ownerTask_) return kIOReturnNotPrivileged;
        call.client=this; call.task=ownerTask_;
        if (selector == FXClaimSession) {
            if (args->scalarInputCount != 1 || !args->scalarInput ||
                args->scalarInput[0] > 1 || args->structureOutputSize != 0)
                return kIOReturnBadArgument;
            call.operation=args->scalarInput[0] ? FXGateCall::ClaimSession : FXGateCall::ReleaseSession;
        } else {
            if (args->scalarInputCount != 0 || !args->structureOutput ||
                args->structureOutputSize != sizeof(FXSessionBatch)) return kIOReturnBadArgument;
            call.operation=FXGateCall::ReadSession;
            call.batch=static_cast<FXSessionBatch *>(args->structureOutput);
        }
        // The owner may always relinquish its own claim after switching away.
        // Acquiring or consuming still requires active-console privilege.
        if (call.operation != FXGateCall::ReleaseSession &&
            clientHasPrivilege(ownerTask_, "console") != kIOReturnSuccess)
            return kIOReturnNotPrivileged;
    } else return kIOReturnUnsupported;
    IOLockLock(providerLock_);
    auto asus = asus_;
    if (asus) asus->retain();
    IOLockUnlock(providerLock_);
    if (!asus) return kIOReturnNotAttached;
    IOReturn result = asus->fxRun(call);
    asus->release();
    return result;
}

IOReturn AsusSMC::newUserClient(task_t owningTask, void *securityID, UInt32 type,
                               OSDictionary *properties, IOUserClient **handler) {
    if (!handler) return kIOReturnBadArgument;
    *handler = nullptr;
    if (type != FX_PROFILE_CONNECT_TYPE || isInactive()) return kIOReturnUnsupported;
    auto client = new AsusSMCProfileUserClient;
    if (!client) return kIOReturnNoMemory;
    if (!client->initWithTask(owningTask, securityID, type, properties)) {
        client->release();
        return kIOReturnNoResources;
    }
    if (!client->attach(this)) { client->release(); return kIOReturnNotAttached; }
    if (!client->start(this)) {
        client->detach(this);
        client->release();
        return kIOReturnNotAttached;
    }
    *handler = client;
    return kIOReturnSuccess;
}

IOReturn AsusSMC::fxRun(FXGateCall &call) {
    /* Gate lifetime extends to free(), including after stop(). Each client
     * retains the service around this synchronous call. Never remove the gate
     * underneath a queued request. All state below is serialized by it. */
    if (!command_gate) return kIOReturnNotReady;
    return command_gate->runAction(fxGateAction, &call);
}

IOReturn AsusSMC::fxGateAction(OSObject *owner, void *arg0, void *, void *, void *) {
    auto self = OSDynamicCast(AsusSMC, owner);
    auto call = static_cast<FXGateCall *>(arg0);
    if (!self || !call) return kIOReturnBadArgument;
    if (call->operation == FXGateCall::Stop) {
        self->fxReleaseSession();
        if(self->fxLidClient) { if(auto root=self->getPMRootDomain()) root->receivePowerNotification(kIOPMEnableClamshell); self->fxLidClient=nullptr; self->setProperty("FX505GTLidSleepDisabled",false); }
        self->fxFullyAwake=false;
        self->fxRunning = false;
        self->fxPolicy.stop();
        return kIOReturnSuccess;
    }
    if (call->operation == FXGateCall::ReleaseSession) {
        if (self->fxSessionClient == call->client) self->fxReleaseSession();
        if(self->fxLidClient==call->client) { if(auto root=self->getPMRootDomain()) root->receivePowerNotification(kIOPMEnableClamshell); self->fxLidClient=nullptr; self->setProperty("FX505GTLidSleepDisabled",false); }
        return kIOReturnSuccess;
    }
    if (call->operation == FXGateCall::Initialize) {
        auto enabled = OSDynamicCast(OSBoolean, self->getProperty("FX505GTProfileBridgeEnabled"));
        auto model = OSDynamicCast(OSString, self->getProperty("FX505GTProfileModel"));
        auto fn = OSDynamicCast(OSBoolean, self->getProperty("FX505GTProfileFnF5Enabled"));
        self->fxPolicy.configure(enabled && enabled->isTrue(),
            model && model->isEqualTo("FX505GT"), self->fxWmiVerified,
            fn && fn->isTrue());
        auto routes = OSDynamicCast(OSBoolean, self->getProperty("FX505GTDedicatedFnContractEnabled"));
        self->fxFnQueue.configure(routes && routes->isTrue() && model &&
            model->isEqualTo("FX505GT") && self->fxWmiVerified);
        self->fxFullyAwake=false;
        self->fxRunning = true;
        self->fxPolicy.suspend(); // No I/O until initial full-wake capability synchronization.
        self->fxPowerNotifier = registerPrioritySleepWakeInterest(fxPowerInterest, self);
        if (!self->fxPowerNotifier) self->fxPolicy.powerUnavailable();
        self->fxRefresh();
        return kIOReturnSuccess;
    }
    if (!self->fxRunning || self->isInactive() || !self->atkDevice ||
        self->atkDevice != self->getProvider()) return kIOReturnNotAttached;
    if(call->operation==FXGateCall::SetClamshell) {
        auto root=self->getPMRootDomain(); if(!root) return kIOReturnNotReady;
        if(call->profile) {
            if(self->fxLidClient && self->fxLidClient!=call->client) return kIOReturnExclusiveAccess;
            IOReturn result=root->receivePowerNotification(kIOPMDisableClamshell);
            if(result==kIOReturnSuccess) { self->fxLidClient=call->client; self->setProperty("FX505GTLidSleepDisabled",true); }
            return result;
        }
        if(self->fxLidClient!=call->client) return kIOReturnSuccess;
        IOReturn result=root->receivePowerNotification(kIOPMEnableClamshell);
        if(result==kIOReturnSuccess) { self->fxLidClient=nullptr; self->setProperty("FX505GTLidSleepDisabled",false); }
        return result;
    }
    if (call->operation == FXGateCall::Suspend) {
        self->fxPolicy.suspend();
        self->fxFullyAwake=false; self->fxReleaseSession();
        return kIOReturnSuccess;
    }
    if (call->operation == FXGateCall::Capabilities) {
        self->fxPolicy.powerCapabilities(call->powerFlags, call->powerFrom, call->powerTo);
        self->fxFullyAwake=!(call->powerFlags & ~3u) && !(call->powerFlags & 1u) &&
            ((call->powerFlags & 2u) || (!call->powerFlags && !call->powerFrom)) &&
            (call->powerTo & 3u)==3u;
        if (!self->fxFullyAwake) self->fxReleaseSession();
        else if(self->fxLidClient) { if(auto root=self->getPMRootDomain()) root->receivePowerNotification(kIOPMDisableClamshell); }
        return kIOReturnSuccess;
    }
    if (call->operation == FXGateCall::Message) {
        if (self->fxPolicy.snapshot().state == FXSuspended) return kIOReturnNotReady;
        return self->fxMessage(call->messageType, call->messageProvider,
                               call->messageArgument, call->arrivalNS);
    }
    if (call->operation == FXGateCall::ClaimSession || call->operation == FXGateCall::ReadSession) {
        if (!self->fxFnQueue.enabled() || !self->fxFullyAwake) return kIOReturnNotReady;
        if (!call->task || IOUserClient::clientHasPrivilege(call->task,"console") != kIOReturnSuccess) return kIOReturnNotPrivileged;
        uint64_t now=fxTimestamp();
        if (self->fxSessionClient && (now < self->fxSessionPollNS || now-self->fxSessionPollNS>2000000000ull ||
            IOUserClient::clientHasPrivilege(self->fxSessionTask, "console") != kIOReturnSuccess))
            self->fxReleaseSession();
        if (call->operation == FXGateCall::ClaimSession) {
            if (self->fxSessionClient && self->fxSessionClient != call->client) return kIOReturnExclusiveAccess;
            if (!self->fxSessionClient) {
                self->fxSessionClient=call->client; self->fxSessionTask=call->task;
                task_reference(self->fxSessionTask);
            }
            self->fxFnQueue.clear(); // Explicit re-claim never replays an old batch.
        } else {
            if (self->fxSessionClient != call->client || !call->batch) return kIOReturnNotOpen;
            *call->batch=self->fxFnQueue.drain(now);
        }
        self->fxSessionPollNS=now;
        return kIOReturnSuccess;
    }
    self->fxRefresh();
    if (call->operation == FXGateCall::Query) {
        if (!call->snapshot) return kIOReturnBadArgument;
        *call->snapshot = self->fxPolicy.snapshot();
        return kIOReturnSuccess;
    }
    if (call->operation == FXGateCall::Set)
        return self->fxSet(call->profile, FXCommandLine);
    return kIOReturnUnsupported;
}

fx::Raw AsusSMC::fxEvaluate(uint32_t method, uint32_t device, uint32_t value) {
    /* Only private callers select these two method IDs and two fixed devices.
     * A guessed WMNB fallback is never accepted for this bridge. */
    if (!fxWmiVerified || !atkDevice || atkDevice != getProvider() ||
        (method != ASUS_WMI_METHODID_DSTS && method != ASUS_WMI_METHODID_DEVS) ||
        (device != fx::ThermalDevice && device != fx::FanBoostDevice))
        return fx::Raw::decode(false, 0, kIOReturnUnsupported);
    wmi_args input {device, value};
    OSObject *args[3] = {OSNumber::withNumber(0ULL, 32),
        OSNumber::withNumber(method, 32), OSData::withBytes(&input, sizeof(input))};
    if (!args[0] || !args[1] || !args[2]) {
        for (unsigned i = 0; i < 3; ++i) if (args[i]) args[i]->release();
        return fx::Raw::decode(false, 0, kIOReturnNoMemory);
    }
    uint32_t raw = 0;
    IOReturn ret = atkDevice->evaluateInteger(wmi_method, &raw, args, 3);
    for (unsigned i = 0; i < 3; ++i) args[i]->release();
    return fx::Raw::decode(ret == kIOReturnSuccess, raw, ret);
}

void AsusSMC::fxRefresh() {
    if (!fxPolicy.mayProbe()) return;
    auto thermal = fxEvaluate(ASUS_WMI_METHODID_DSTS, fx::ThermalDevice, 0);
    auto fan = fxEvaluate(ASUS_WMI_METHODID_DSTS, fx::FanBoostDevice, 0);
    fxPolicy.probe(thermal, fan);
}

IOReturn AsusSMC::fxSet(uint32_t profile, uint32_t source) {
    if (!fxPolicy.prepare(profile, source, fxTimestamp())) return kIOReturnUnsupported;
    auto result = fxEvaluate(ASUS_WMI_METHODID_DEVS, fxPolicy.device(), profile);
    return fxPolicy.complete(result, fxTimestamp()) ? kIOReturnSuccess : kIOReturnIOError;
}

void AsusSMC::fxHandleFn(uint32_t code, uint64_t arrivalNS) {
    if (code != 0x99u && code != 0xaeu) return;
    fxRefresh();
    uint32_t requested = FX_PROFILE_UNKNOWN;
    if (fxPolicy.fnEvent(code, arrivalNS, requested))
        (void)fxSet(requested, FXFnF5);
}

uint64_t AsusSMC::fxTimestamp() {
    uint64_t uptime = 0, nanoseconds = 0;
    clock_get_uptime(&uptime);
    absolutetime_to_nanoseconds(uptime, &nanoseconds);
    return nanoseconds;
}

IOReturn AsusSMC::fxPowerInterest(void *target, void *, UInt32 type,
                                  IOService *, void *argument, vm_size_t size) {
    auto self = static_cast<AsusSMC *>(target);
    if (!self) return kIOReturnBadArgument;
    FXGateCall call {};
    switch (type) {
        case kIOMessageSystemWillSleep:
            call.operation = FXGateCall::Suspend;
            (void)self->fxRun(call); // Serialize with any in-flight request.
            // Priority-interest callbacks receive a notification structure,
            // not an acknowledgement cookie. Synchronous completion leaves
            // its initialized returnValue=0: no asynchronous ack is needed.
            return kIOReturnSuccess;
        case kIOMessageSystemCapabilityChange: {
            if (!argument || size < sizeof(IOPMSystemCapabilityChangeParameters)) {
                call.operation = FXGateCall::Suspend;
            } else {
                auto change = static_cast<const IOPMSystemCapabilityChangeParameters *>(argument);
                call.operation = FXGateCall::Capabilities;
                call.powerFlags = change->changeFlags;
                call.powerFrom = change->fromCapabilities;
                call.powerTo = change->toCapabilities;
            }
            (void)self->fxRun(call);
            return kIOReturnSuccess; // Synchronous; maxWaitForReply remains zero.
        }
        case kIOMessageSystemHasPoweredOn:
        case kIOMessageSystemWillNotSleep:
            // Capability synchronization, not this legacy message, permits I/O.
            return kIOReturnSuccess;
        case kIOMessageCanSystemSleep:
            return kIOReturnSuccess;
        default: return kIOReturnSuccess;
    }
}

void AsusSMC::fxReleaseSession() {
    fxSessionClient=nullptr;
    if (fxSessionTask != TASK_NULL) { task_deallocate(fxSessionTask); fxSessionTask=TASK_NULL; }
    fxSessionPollNS=0; fxFnQueue.clear();
}

bool AsusSMC::fxRouteFn(uint32_t code, uint64_t now) {
    if (!fxFnQueue.enabled()) return false;
    // In the dedicated contract, conflicting legacy synthetic/raw meanings
    // are deliberately suppressed, never reinterpreted as power actions.
    if (code==0x33 || code==0x34 || code==0x35 || code==0x5e || code==0x7d) return true;
    auto route=fx::fnRoute(code);
    if (!route.recognized) return false;
    if (!fxFullyAwake) return true;
    if (route.hidCode) handleMessage(route.hidCode); // Exactly one stock HID action.
    else if (route.fan) {
        fxRefresh();
        auto backend=fxPolicy.snapshot().backend;
        if (backend==FXThermalPolicy) fxHandleFn(0xae,now);
        else if (backend==FXFanBoost) fxHandleFn(0x99,now);
    } else if (route.action) {
        const uint64_t leaseNow=fxTimestamp(); // Arrival can predate a newer gated poll.
        if (!fxSessionClient || leaseNow<fxSessionPollNS || leaseNow-fxSessionPollNS>2000000000ull ||
            IOUserClient::clientHasPrivilege(fxSessionTask,"console") != kIOReturnSuccess) {
            fxReleaseSession(); return true; // No consumer: no deferred replay.
        }
        fxFnQueue.push(route.action,code,now);
    }
    return true;
}
