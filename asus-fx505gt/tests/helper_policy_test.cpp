// SPDX-License-Identifier: MIT
#include "FXHelperPolicy.hpp"
#include <cassert>
#include <cstdio>
int main() {
    assert(fx::helperNodeAllowed(0,S_IFDIR|0755,2,false));
    assert(fx::helperNodeAllowed(0,S_IFREG|0755,1,true));
    assert(!fx::helperNodeAllowed(501,S_IFREG|0755,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFREG|0775,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFREG|0757,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFREG|04755,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFREG|02755,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFREG|0755,2,true));
    assert(!fx::helperNodeAllowed(0,S_IFREG|0644,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFLNK|0777,1,true));
    assert(!fx::helperNodeAllowed(0,S_IFLNK|0755,1,false));
    assert(!fx::helperNodeAllowed(0,S_IFDIR|0777,2,false));
    assert(fx::helperACLAllowed(true,-1,EINVAL));
    assert(!fx::helperACLAllowed(true,0,0)); // Darwin returned an ACE, not empty.
    assert(!fx::helperACLAllowed(true,1,0)); // Linux semantics never accepted.
    assert(!fx::helperACLAllowed(false,-1,EINVAL));
    assert(!fx::helperACLAllowed(true,-1,EIO));
    std::puts("PASS: root-only nonwritable real helper nodes; no symlink/setuid/hardlink; Darwin ACL semantics fail closed");
}
