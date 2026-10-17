// SPDX-License-Identifier: MIT
#ifndef FX_FEEDBACK_POLICY_HPP
#define FX_FEEDBACK_POLICY_HPP
#include "FXFnABI.h"
#include <stdint.h>
namespace fx {
enum class FeedbackState { Unknown, Readback, Accepted, Cancelled, Disabled };
struct Feedback {
    FeedbackState state=FeedbackState::Unknown;
    double level=-1; // Only independently read normalized values; -1 means unknown.
    int on=-1; // Readback semantics depend on action; never infer from the key.
};
inline bool feedbackCode(uint32_t code) { return code>FX_FN_EVENT_BASE && code<=FX_FN_EVENT_BASE+14; }
inline bool validLevel(double level) { return level>=0 && level<=1; }
// Observation counter is only a coalesced notification, never an action queue.
// Baseline every new lease so startup/session changes cannot replay old OSDs.
class FeedbackCursor {
    bool initialized_=false;
    uint32_t count_=0;
public:
    void reset() { initialized_=false; }
    bool consume(uint32_t count,uint32_t code,bool enabled) {
        if(!enabled) { reset(); return false; }
        if(!initialized_) { count_=count; initialized_=true; return false; }
        bool changed=count!=count_; count_=count;
        return changed && feedbackCode(code);
    }
};
}
#endif
