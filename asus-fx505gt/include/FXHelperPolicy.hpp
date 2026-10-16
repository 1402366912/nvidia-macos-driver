/* SPDX-License-Identifier: MIT. Portable decisions; OS metadata is read by the native adapter. */
#ifndef FX_HELPER_POLICY_HPP
#define FX_HELPER_POLICY_HPP
#include <stdint.h>
#include <cerrno>
#include <sys/stat.h>
namespace fx {
inline bool helperNodeAllowed(uint32_t uid, uint32_t mode, uint64_t links, bool file) {
    if(uid!=0 || (mode & (S_IWGRP|S_IWOTH|S_ISUID|S_ISGID))) return false;
    return file ? S_ISREG(mode) && links==1 && (mode&S_IXUSR) : S_ISDIR(mode);
}
// Darwin acl_get_entry: zero=entry, -1/EINVAL=no entry on a valid ACL.
inline bool helperACLAllowed(bool valid, int firstEntryResult, int error) {
    return valid && firstEntryResult==-1 && error==EINVAL;
}
}
#endif
