// SPDX-License-Identifier: MIT
// Independent bounded adapter. Private API names/semantics are referenced from
// MIT blueutil v2.14.0, commit 60d8411fa3f9968ab6f05e198b486fe89961e18f.
// There is no device-list, pairing, arbitrary command, root or privacy bypass.
#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <dlfcn.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>
#include "FXSessionPolicy.hpp"
using GetInt=int (*)();
using SetInt=void (*)(int);
static bool consoleUser() {
    uid_t uid=static_cast<uid_t>(-1); gid_t gid=0;
    CFStringRef user=SCDynamicStoreCopyConsoleUser(nullptr,&uid,&gid);
    bool result=user && uid==getuid() && uid!=0 && geteuid()==getuid();
    if(user) CFRelease(user); return result;
}
template<class F> static F symbol(void *library,const char *name) {
    void *address=dlsym(library,name); F result=nullptr;
    static_assert(sizeof(result)==sizeof(address),"Unexpected macOS function-pointer size");
    memcpy(&result,&address,sizeof(result)); return result;
}
static bool readPower(GetInt available,GetInt preference,int &state) {
    if(available()!=1) return false;
    IOBluetoothHostController *host=[IOBluetoothHostController defaultController];
    if(!host) return false;
    const int value=preference(); const int reported=static_cast<int>(host.powerState);
    if(!fx::powerBit(value) || !fx::powerBit(reported) || value!=reported) return false;
    state=reported; return true;
}
int main(int argc,const char **argv) {
    int target=-1;
    if(argc==3 && strcmp(argv[1],"power")==0 && (strcmp(argv[2],"0")==0 || strcmp(argv[2],"1")==0)) target=argv[2][0]-'0';
    else if(argc!=2 || strcmp(argv[1],"power")!=0) { fputs("Usage: fxradio power [0|1]\n",stderr); return 2; }
    if(!consoleUser()) { fputs("Active ordinary console user required.\n",stderr); return 3; }
    // Deadline starts after process startup and this initial console check.
    // Parent separately bounds the launched child, including pre-main loading.
    signal(SIGALRM,SIG_DFL); sigset_t alarmSet; sigemptyset(&alarmSet); sigaddset(&alarmSet,SIGALRM); sigprocmask(SIG_UNBLOCK,&alarmSet,nullptr); alarm(5);
    @autoreleasepool {
        void *library=dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth",RTLD_NOW|RTLD_LOCAL);
        if(!library) return 4;
        GetInt available=symbol<GetInt>(library,"IOBluetoothPreferencesAvailable");
        GetInt preference=symbol<GetInt>(library,"IOBluetoothPreferenceGetControllerPowerState");
        SetInt set=symbol<SetInt>(library,"IOBluetoothPreferenceSetControllerPowerState");
        if(!available || !preference || !set) { dlclose(library); return 4; }
        int state=-1;
        if(!readPower(available,preference,state)) { dlclose(library); return 4; }
        if(target>=0 && state!=target) {
            if(!consoleUser()) { dlclose(library); return 3; }
            set(target); // void: never interpreted as an acknowledgement.
            bool reached=false;
            for(unsigned i=0;i<20;++i) {
                if(!consoleUser()) break;
                if(readPower(available,preference,state) && state==target) { reached=true; break; }
                usleep(100000);
            }
            if(!reached) { dlclose(library); return 5; }
        }
        // A separate parent read follows a write; this line is only a report
        // from the public controller and private preference, never RF proof.
        printf("%d\n",state); fflush(stdout); dlclose(library); alarm(0); return 0;
    }
}
