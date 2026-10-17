// SPDX-License-Identifier: MIT
#ifndef FX_FEEDBACK_POLICY_HPP
#define FX_FEEDBACK_POLICY_HPP
#include "FXFnABI.h"
#include <stdint.h>
namespace fx {
enum class FeedbackState { Unknown, Readback, Accepted, Cancelled, Disabled, Dispatched };
struct Feedback {
    FeedbackState state=FeedbackState::Unknown;
    double level=-1; // Only independently read normalized values; -1 means unknown.
    int on=-1; // Readback semantics depend on action; never infer from the key.
};
inline bool feedbackCode(uint32_t code) { return code>FX_FN_EVENT_BASE && code<=FX_FN_EVENT_BASE+14; }
inline bool validLevel(double level) { return level>=0 && level<=1; }
// Readback fields are independent: a volume level does not establish mute.
inline bool knownSwitch(const Feedback &value) {
    return value.state==FeedbackState::Readback && (value.on==0 || value.on==1);
}
inline double normalizedLevel(int64_t value,int64_t minimum,int64_t maximum) {
    if(minimum!=0 || maximum<=minimum || value<minimum || value>maximum) return -1;
    return static_cast<double>(value)/static_cast<double>(maximum);
}
inline Feedback sanitizedFeedback(Feedback value) {
    if(value.state!=FeedbackState::Readback) { value.level=-1; value.on=-1; }
    else { if(!validLevel(value.level)) value.level=-1; if(!knownSwitch(value)) value.on=-1; }
    return value;
}
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
