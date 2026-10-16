// SPDX-License-Identifier: MIT
#include "FXSessionPolicy.hpp"
#include <cassert>
#include <cstdio>
int main() {
    for(int i=0;i<=2;++i) assert(fx::panelPowerRange(i,0,2));
    assert(!fx::panelPowerRange(-1,0,2)); assert(!fx::panelPowerRange(3,0,2));
    assert(!fx::panelPowerRange(1,1,2)); assert(!fx::panelPowerRange(1,0,255));
    assert(fx::nextPanelPower(0)==2 && fx::nextPanelPower(1)==0 && fx::nextPanelPower(2)==0);
    assert(fx::nextPanelPower(0,1)==1 && fx::nextPanelPower(0,2)==2);
    assert(fx::nextPanelPower(0,-1)==2 && fx::nextPanelPower(2,1)==0);
    assert(fx::radioNodeAllowed(501,501,S_IFREG|0700,1,true));
    assert(fx::radioNodeAllowed(0,501,S_IFDIR|0755,2,false));
    assert(!fx::radioNodeAllowed(502,501,S_IFREG|0700,1,true));
    assert(!fx::radioNodeAllowed(501,501,S_IFREG|0770,1,true));
    assert(!fx::radioNodeAllowed(501,501,S_IFLNK|0700,1,true));
    assert(!fx::radioNodeAllowed(501,501,S_IFREG|S_ISUID|0700,1,true));
    assert(!fx::radioNodeAllowed(501,501,S_IFREG|0700,2,true));
    int state=-1; assert(fx::parseRadioPower("0\n",2,state) && state==0);
    assert(fx::parseRadioPower("1\n",2,state) && state==1);
    assert(!fx::parseRadioPower("2\n",2,state)); assert(!fx::parseRadioPower("1\nextra",7,state));
    assert(!fx::parseRadioPower("1",1,state)); assert(!fx::parseRadioPower(nullptr,2,state));
    assert(fx::nextRadioPower(false,0)==1); assert(fx::nextRadioPower(true,0)==0);
    assert(fx::nextRadioPower(false,1)==0); assert(fx::nextRadioPower(true,1)==0);
    std::puts("PASS: exact internal-panel power range, bounded toggle, strict Bluetooth readback and dual-radio target policy");
}
