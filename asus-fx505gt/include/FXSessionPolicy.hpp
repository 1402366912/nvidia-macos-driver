/* SPDX-License-Identifier: MIT. Pure policies; no hardware or OS operations. */
#ifndef FX_SESSION_POLICY_HPP
#define FX_SESSION_POLICY_HPP
#include <stdint.h>
#include <stddef.h>
#include <sys/stat.h>
namespace fx {
inline bool panelPowerRange(int32_t value,int32_t min,int32_t max) {
    return min==0 && max==2 && value>=0 && value<=2;
}
inline int32_t nextPanelPower(int32_t value,int32_t saved=-1) {
    return value==0 ? ((saved==1 || saved==2)?saved:2) : 0;
}
inline bool radioNodeAllowed(uint32_t owner,uint32_t currentUser,uint32_t mode,uint64_t links,bool file) {
    if(owner!=0 && owner!=currentUser) return false;
    if(mode&(S_IWGRP|S_IWOTH|S_ISUID|S_ISGID)) return false;
    return file ? S_ISREG(mode) && links==1 && (mode&S_IXUSR) : S_ISDIR(mode);
}
inline bool powerBit(int value) { return value==0 || value==1; }
inline bool parseRadioPower(const char *data,size_t size,int &power) {
    if(size!=2 || !data || data[1]!='\n' || (data[0]!='0' && data[0]!='1')) return false;
    power=data[0]-'0'; return true;
}
inline int nextRadioPower(bool anyWifiOn,int bluetoothPower) {
    return anyWifiOn || bluetoothPower==1 ? 0 : 1;
}
}
#endif
