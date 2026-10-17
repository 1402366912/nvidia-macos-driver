// SPDX-License-Identifier: MIT
#include "FXFeedbackPolicy.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
int main() {
    fx::Feedback value;
    assert(value.state==fx::FeedbackState::Unknown && value.level==-1 && value.on==-1);
    assert(fx::validLevel(0) && fx::validLevel(1) && fx::validLevel(0.5));
    assert(!fx::validLevel(-0.01) && !fx::validLevel(1.01) && !fx::validLevel(NAN));
    for(uint32_t key=1;key<=14;++key) assert(fx::feedbackCode(FX_FN_EVENT_BASE+key));
    assert(!fx::feedbackCode(FX_FN_EVENT_BASE) && !fx::feedbackCode(FX_FN_EVENT_BASE+15));
    assert(!fx::feedbackCode(0x32) && !fx::feedbackCode(0x5e));
    fx::FeedbackCursor cursor;
    assert(!cursor.consume(100,FX_FN_EVENT_BASE+3,true)); // Never replay initial state.
    assert(!cursor.consume(100,FX_FN_EVENT_BASE+3,true));
    assert(cursor.consume(101,FX_FN_EVENT_BASE+3,true));
    assert(cursor.consume(110,FX_FN_EVENT_BASE+2,true)); // Held keys coalesce, no synthetic presses.
    assert(!cursor.consume(111,0x5e,true)); // Raw/other notifications aren't dedicated keys.
    assert(!cursor.consume(111,FX_FN_EVENT_BASE+3,true));
    cursor.reset(); assert(!cursor.consume(112,FX_FN_EVENT_BASE+3,true));
    assert(cursor.consume(113,FX_FN_EVENT_BASE+3,true));
    assert(!cursor.consume(114,FX_FN_EVENT_BASE+3,false));
    assert(!cursor.consume(115,FX_FN_EVENT_BASE+3,true));
    assert(cursor.consume(116,FX_FN_EVENT_BASE+3,true));
    cursor.reset(); assert(!cursor.consume(UINT32_MAX,FX_FN_EVENT_BASE+1,true));
    assert(cursor.consume(0,FX_FN_EVENT_BASE+1,true)); // Counter wraps safely.
    std::cout << "PASS: feedback range/readback defaults, all 14 keys, baseline, stale/repeat/coalesced, reset, disabled, wrap\n";
}
