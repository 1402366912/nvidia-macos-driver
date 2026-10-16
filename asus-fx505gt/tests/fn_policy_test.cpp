// SPDX-License-Identifier: MIT
#include "FXFnPolicy.hpp"
#include <cassert>
#include <initializer_list>
#include <cstdio>
int main() {
    for(uint32_t key=1;key<=14;++key) assert(fx::fnRoute(FX_FN_EVENT_BASE+key).recognized);
    assert(!fx::fnRoute(FX_FN_EVENT_BASE).recognized);
    assert(!fx::fnRoute(FX_FN_EVENT_BASE+15).recognized);
    for(uint32_t raw:{0x33u,0x35u,0x5eu,0x7du,0x7cu,0x88u}) assert(!fx::fnRoute(raw).recognized);
    assert(fx::fnRoute(0xf504).action==FXMicrophoneMute);
    assert(fx::fnRoute(0xf505).fan);
    assert(fx::fnRoute(0xf507).hidCode==0x20);
    assert(fx::fnRoute(0xf508).hidCode==0x10);
    assert(fx::fnRoute(0xf50b).action==FXSystemSleep);
    assert(fx::fnRoute(0xf50c).action==FXWifiToggle);
    fx::FnQueue q; q.push(FXSystemSleep,0xf50b,1); assert(q.drain(1).count==0);
    q.configure(true); q.observe(0x7c); q.push(FXMicrophoneMute,0xf504,1000);
    q.push(FXMicrophoneMute,0xf504,1001); auto b=q.drain(1002);
    assert(b.version==1 && b.size==288 && b.count==1 && b.lastObservedCode==0x7c);
    assert(q.drain(1003).count==0); // No replay.
    q.push(FXDisplaySleep,0xf506,2000); assert(q.drain(2000002001ull).count==0);
    q.clear();
    for(uint32_t i=0;i<20;++i) q.push(FXMicrophoneMute,0xf504,3000000000ull+300000000ull*i);
    b=q.drain(8700000000ull); assert(b.dropped>=4 && b.count<=16);
    q.configure(false); q.push(FXWifiToggle,0xf50c,9000000000ull); assert(q.drain(9000000000ull).count==0);
    std::puts("PASS: 14 dedicated Fn routes, conflicting raw codes excluded, bounded queue, debounce, stale-drop, no replay");
}
