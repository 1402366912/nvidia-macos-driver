/* SPDX-License-Identifier: MIT */
#ifndef FX_PROFILE_BRIDGE_HPP
#define FX_PROFILE_BRIDGE_HPP
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLocks.h>
#include "FXProfilePolicy.hpp"
#include "FXFnPolicy.hpp"
class AsusSMC;
class AsusSMCProfileUserClient;
struct FXGateCall {
    enum Operation { Initialize, Query, Set, Message, Suspend, Capabilities, ClaimSession, ReadSession, ReleaseSession, Stop } operation;
    uint64_t arrivalNS {0};
    uint32_t powerFlags {0}, powerFrom {0}, powerTo {0};
    uint32_t profile {0}, messageType {0};
    IOService *messageProvider {nullptr};
    void *messageArgument {nullptr};
    FXProfileSnapshot *snapshot {nullptr};
    FXSessionBatch *batch {nullptr};
    AsusSMCProfileUserClient *client {nullptr};
    task_t task {TASK_NULL};
};
class AsusSMCProfileUserClient : public IOUserClient {
    OSDeclareDefaultStructors(AsusSMCProfileUserClient)
    IOLock *providerLock_ {nullptr};
    AsusSMC *asus_ {nullptr};
    task_t ownerTask_ {TASK_NULL};
public:
    bool initWithTask(task_t task, void *securityID, UInt32 type,
                      OSDictionary *properties) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *arguments,
                           IOExternalMethodDispatch *dispatch = nullptr,
                           OSObject *target = nullptr, void *reference = nullptr) override;
};
#endif
