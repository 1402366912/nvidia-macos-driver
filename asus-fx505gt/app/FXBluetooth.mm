// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <sys/acl.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "FXBuildIdentity.h"
#include "FXSessionPolicy.hpp"
extern bool FXIsConsoleUser();
// The companion is unprivileged and built from this source with a pinned
// digest. This is not the root-only profile helper and never escalates.
static bool enabled=false;
void FXEnableBluetooth(bool value) { enabled=value; }
bool FXBluetoothEnabled() { return enabled; }
static bool radioNode(NSString *path,bool file,struct stat *out) {
    struct stat st {};
    if(lstat(path.fileSystemRepresentation,&st)!=0 || !fx::radioNodeAllowed(st.st_uid,getuid(),st.st_mode,st.st_nlink,file)) return false;
    acl_t acl=acl_get_file(path.fileSystemRepresentation,ACL_TYPE_EXTENDED);
    if(!acl) return false;
    if(acl_valid(acl)!=0) { acl_free(acl); return false; }
    acl_entry_t entry; int which=ACL_FIRST_ENTRY; bool safe=true;
    for(;;) {
        errno=0; int result=acl_get_entry(acl,which,&entry); which=ACL_NEXT_ENTRY;
        if(result==-1 && errno==EINVAL) break; // Darwin end-of-ACL.
        acl_tag_t tag;
        // Deny-only ACLs cannot grant writes; reject every allow/unknown entry.
        if(result!=0 || acl_get_tag_type(entry,&tag)!=0 || tag!=ACL_EXTENDED_DENY) { safe=false; break; }
    }
    acl_free(acl); if(!safe) return false;
    if(out) *out=st; return true;
}
static bool radioPath(NSString *path,struct stat *out) {
    if(!path.isAbsolutePath || ![path isEqualToString:path.stringByStandardizingPath]) return false;
    NSArray<NSString *> *parts=path.pathComponents; NSString *current=@"/";
    for(NSUInteger i=0;i<parts.count;++i) {
        if(i) current=[current stringByAppendingPathComponent:parts[i]];
        if(!radioNode(current,i+1==parts.count,i+1==parts.count?out:nullptr)) return false;
    }
    return true;
}
static bool companion(NSString **path) {
    NSString *candidate=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/fxradio"];
    struct stat before {},after {};
    if(!radioPath(candidate,&before) || before.st_size<=0 || before.st_size>4*1024*1024) return false;
    int fd=open(candidate.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if(fd<0) return false;
    bool valid=fstat(fd,&after)==0 && before.st_ino==after.st_ino && before.st_dev==after.st_dev && before.st_size==after.st_size;
    CC_SHA256_CTX context; CC_SHA256_Init(&context); unsigned char buffer[4096]; ssize_t count=0; size_t total=0;
    while(valid && (count=read(fd,buffer,sizeof(buffer)))>0) { total+=static_cast<size_t>(count); if(total>4*1024*1024) { valid=false; break; } CC_SHA256_Update(&context,buffer,static_cast<CC_LONG>(count)); }
    if(count<0) valid=false;
    struct stat end {};
    if(fstat(fd,&end)!=0 || end.st_dev!=after.st_dev || end.st_ino!=after.st_ino || end.st_size!=after.st_size ||
       end.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec || end.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec ||
       end.st_ctimespec.tv_sec!=after.st_ctimespec.tv_sec || end.st_ctimespec.tv_nsec!=after.st_ctimespec.tv_nsec) valid=false;
    close(fd);
    struct stat pathAfter {};
    if(!radioPath(candidate,&pathAfter) || pathAfter.st_dev!=after.st_dev || pathAfter.st_ino!=after.st_ino ||
       pathAfter.st_size!=after.st_size || pathAfter.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec ||
       pathAfter.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec || pathAfter.st_ctimespec.tv_sec!=after.st_ctimespec.tv_sec ||
       pathAfter.st_ctimespec.tv_nsec!=after.st_ctimespec.tv_nsec) valid=false;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&context);
    char hex[CC_SHA256_DIGEST_LENGTH*2+1];
    for(unsigned i=0;i<CC_SHA256_DIGEST_LENGTH;++i) snprintf(hex+i*2,3,"%02x",digest[i]);
    if(!valid || strcmp(hex,FX_EXPECTED_RADIO_SHA256)!=0) return false;
    *path=candidate; return true;
}
static bool runRadio(int target,int &power) {
    if(!enabled || !FXIsConsoleUser() || target<-1 || target>1) return false;
    NSString *path=nil; if(!companion(&path)) return false;
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:path];
    task.arguments=target<0 ? @[@"power"] : @[@"power",target==0?@"0":@"1"];
    // No inherited loader override, shell or user-supplied argument.
    task.environment=@{@"PATH":@"/usr/bin:/bin",@"LANG":@"C"};
    NSPipe *pipe=[NSPipe pipe]; task.standardOutput=pipe; task.standardError=[NSFileHandle fileHandleWithNullDevice];
    NSError *error=nil; if(![task launchAndReturnError:&error]) return false;
    [pipe.fileHandleForWriting closeFile];
    int fd=pipe.fileHandleForReading.fileDescriptor;
    int flags=fcntl(fd,F_GETFL,0); if(flags<0 || fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0) { [task terminate]; if(task.running) kill(task.processIdentifier,SIGKILL); [pipe.fileHandleForReading closeFile]; return false; }
    char output[16]; size_t used=0; bool malformed=false;
    const NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+6.0;
    while(task.running && NSProcessInfo.processInfo.systemUptime<deadline) {
        char chunk[32]; ssize_t count=read(fd,chunk,sizeof(chunk));
        if(count>0) {
            if(used+static_cast<size_t>(count)>sizeof(output)) malformed=true;
            else { memcpy(output+used,chunk,static_cast<size_t>(count)); used+=static_cast<size_t>(count); }
        } else if(count<0 && errno!=EAGAIN && errno!=EINTR) malformed=true;
        if(malformed) break;
        usleep(10000);
    }
    if(task.running) {
        // NSTask retains the live child identity; no independent PID search.
        [task terminate]; if(task.running) kill(task.processIdentifier,SIGKILL);
        [pipe.fileHandleForReading closeFile]; return false;
    }
    // A final nonblocking read, never an unbounded readToEndOfFile.
    char chunk[32]; ssize_t count;
    while((count=read(fd,chunk,sizeof(chunk)))>0) {
        if(used+static_cast<size_t>(count)>sizeof(output)) { malformed=true; break; }
        memcpy(output+used,chunk,static_cast<size_t>(count)); used+=static_cast<size_t>(count);
    }
    if(count<0 && errno!=EAGAIN && errno!=EINTR) malformed=true;
    [pipe.fileHandleForReading closeFile];
    return !malformed && task.terminationReason==NSTaskTerminationReasonExit && task.terminationStatus==0 && fx::parseRadioPower(output,used,power);
}
bool FXReadBluetooth(int &power) { bool result=runRadio(-1,power); if(!result) enabled=false; return result; }
bool FXWriteBluetooth(int target) {
    int reported=-1;
    if(!runRadio(target,reported) || reported!=target) { enabled=false; return false; }
    bool result=runRadio(-1,reported) && reported==target; if(!result) enabled=false; return result; // Independent post-read.
}
