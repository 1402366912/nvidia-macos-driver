#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include "FXProfileABI.h"
static int setSleep(NSString *value) {
 NSTask *t=[NSTask new];t.launchPath=@"/usr/bin/pmset";t.arguments=@[@"-a",@"disablesleep",value];
 t.standardInput=[NSFileHandle fileHandleWithNullDevice];t.standardOutput=[NSFileHandle fileHandleWithNullDevice];
 [t launch];[t waitUntilExit];return t.terminationStatus;
}
static BOOL disabled(void) {
 io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOPMrootDomain"));
 if(!s)return NO;
 id v=CFBridgingRelease(IORegistryEntryCreateCFProperty(s,CFSTR("SleepDisabled"),kCFAllocatorDefault,0));IOObjectRelease(s);return [v boolValue];
}
int main(int argc,char **argv){@autoreleasepool{
 if(geteuid()!=0||argc!=2)return 2;
 if(!strcmp(argv[1],"--normal"))return setSleep(@"0");
 if(!strcmp(argv[1],"--sleep")) {
  int status=setSleep(@"0");if(status)return status;
  io_connect_t root=IOPMFindPowerManagement(MACH_PORT_NULL);if(!root)return 3;
  IOReturn result=IOPMSleepSystem(root);IOServiceClose(root);
  printf("sleep_result=0x%08x\n",result);return result==kIOReturnSuccess?0:4;
 }
 if(!strcmp(argv[1],"--lid-hold")) {
  io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(FX_PROFILE_SERVICE));if(!service)return 3;
  io_connect_t connection=IO_OBJECT_NULL;IOReturn result=IOServiceOpen(service,mach_task_self(),FX_PROFILE_CONNECT_TYPE,&connection);IOObjectRelease(service);if(result!=kIOReturnSuccess)return 4;
  uint64_t on=1;result=IOConnectCallScalarMethod(connection,FXSetClamshell,&on,1,NULL,NULL);
  if(result!=kIOReturnSuccess){fprintf(stderr,"lid_hold=0x%08x\n",result);IOServiceClose(connection);return 5;}
  puts("READY");fflush(stdout);char bytes[64];ssize_t n;do{n=read(STDIN_FILENO,bytes,sizeof(bytes));}while(n>0||(n<0&&errno==EINTR));
  on=0;IOConnectCallScalarMethod(connection,FXSetClamshell,&on,1,NULL,NULL);IOServiceClose(connection);return 0;
 }
 if(strcmp(argv[1],"--hold"))return 2;
 int r=setSleep(@"1");
 if(r)return r;puts("READY");fflush(stdout);
 char b[64];ssize_t n;do{n=read(STDIN_FILENO,b,sizeof(b));}while(n>0||(n<0&&errno==EINTR));
 // The UI owns the pipe. Closing it, quitting or force quitting releases the hold.
 return setSleep(@"0");
}}
