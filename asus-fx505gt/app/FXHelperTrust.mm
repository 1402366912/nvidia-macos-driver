// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <sys/acl.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include "FXBuildIdentity.h"
#include "FXHelperPolicy.hpp"
// No path is supplied by UI, preferences, environment, or a downloaded file.
extern NSString *const FXHelperPath=@"/Library/PrivilegedHelperTools/org.fx505gt.fxprofile";
static bool trustedNode(const char *path, bool file, struct stat *out) {
    struct stat st {};
    if (lstat(path,&st) || !fx::helperNodeAllowed(st.st_uid,st.st_mode,st.st_nlink,file)) return false;
    // Conservatively reject ALL extended ACL entries, including deny-only
    // entries. POSIX mode alone does not exclude an ACL write grant.
    acl_t acl=acl_get_file(path,ACL_TYPE_EXTENDED);
    if (!acl) return false;
    if (acl_valid(acl)!=0) { acl_free(acl); return false; }
    // Darwin differs from Linux: 0 means an entry WAS returned; empty ACL
    // yields -1/EINVAL. Validate the ACL first, then accept only that empty case.
    acl_entry_t entry; errno=0;
    int result=acl_get_entry(acl,ACL_FIRST_ENTRY,&entry), savedError=errno;
    acl_free(acl);
    if (!fx::helperACLAllowed(true,result,savedError)) return false;
    if(out) *out=st; return true;
}
bool FXHelperTrusted(NSString **reason) {
    const char *parents[]={"/","/Library","/Library/PrivilegedHelperTools"};
    for (const char *p:parents) if(!trustedNode(p,false,nullptr)) {
        if(reason) *reason=@"Helper parent is missing, writable, symlinked, or has an extended ACL."; return false;
    }
    const char *path=FXHelperPath.fileSystemRepresentation; struct stat expected {}, actual {};
    if(!trustedNode(path,true,&expected)) { if(reason) *reason=@"Matching root-owned helper is not provisioned securely."; return false; }
    int fd=open(path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if(fd<0 || fstat(fd,&actual) || actual.st_dev!=expected.st_dev || actual.st_ino!=expected.st_ino) {
        if(fd>=0) close(fd); if(reason) *reason=@"Helper changed during validation."; return false;
    }
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); unsigned char buffer[8192],digest[CC_SHA256_DIGEST_LENGTH];
    ssize_t n; while((n=read(fd,buffer,sizeof(buffer)))>0) CC_SHA256_Update(&ctx,buffer,(CC_LONG)n);
    close(fd); if(n<0) { if(reason) *reason=@"Cannot read helper identity."; return false; }
    CC_SHA256_Final(digest,&ctx); char hex[65];
    for(unsigned i=0;i<sizeof(digest);++i) snprintf(hex+2*i,3,"%02x",digest[i]);
    if(strcmp(hex,FX_EXPECTED_HELPER_SHA256)) { if(reason) *reason=@"Helper binary differs from this app's exact build companion."; return false; }
    // The binary hash above pins the compiled ABI/source identity too. Check
    // the companion's non-device identity command for clear version failures.
    NSTask *task=[NSTask new]; NSPipe *pipe=[NSPipe pipe];
    task.executableURL=[NSURL fileURLWithPath:FXHelperPath]; task.arguments=@[@"--identity"];
    task.environment=@{@"PATH":@"/usr/bin:/bin"};
    task.standardOutput=pipe; task.standardError=[NSFileHandle fileHandleWithNullDevice];
    NSError *error=nil; if(![task launchAndReturnError:&error]) { if(reason) *reason=@"Cannot execute validated helper identity check."; return false; }
    NSData *data=[pipe.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
    NSString *identity=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(task.terminationStatus || ![identity isEqualToString:@FX_EXPECTED_HELPER_IDENTITY]) {
        if(reason) *reason=@"Helper ABI/source identity mismatch."; return false;
    }
    return true;
}
