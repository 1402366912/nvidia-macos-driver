#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/fxprofile-tests.XXXXXX")
trap 'rm -f "$build/policy_test" "$build/fxprofile" "$build/abi_c_test.o" "$build/fn_policy_test" "$build/helper_policy_test" "$build/session_policy_test" "$build/feedback_policy_test"; rmdir "$build"' EXIT HUP INT TERM
cxx=${CXX:-c++}
"$cxx" -std=c++14 -Wall -Wextra -Werror -pedantic -I"$base/include" "$base/tests/policy_test.cpp" -o "$build/policy_test"
"$cxx" -std=c++14 -Wall -Wextra -Werror -pedantic -I"$base/include" "$base/tests/fn_policy_test.cpp" -o "$build/fn_policy_test"
"$build/fn_policy_test"
"$build/policy_test"
"$cxx" -std=c++14 -Wall -Wextra -Werror -pedantic -I"$base/include" "$base/tests/helper_policy_test.cpp" -o "$build/helper_policy_test"
"$build/helper_policy_test"
"$cxx" -std=c++14 -Wall -Wextra -Werror -pedantic -I"$base/include" "$base/tests/session_policy_test.cpp" -o "$build/session_policy_test"
"$build/session_policy_test"
"$cxx" -std=c++14 -Wall -Wextra -Werror -pedantic -I"$base/include" "$base/tests/feedback_policy_test.cpp" -o "$build/feedback_policy_test"
"$build/feedback_policy_test"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -pedantic -I"$base/include" -c "$base/tests/abi_c_test.c" -o "$build/abi_c_test.o"
echo 'PASS: shared C ABI size and offsets'
case $(uname -s) in
  Darwin) echo 'Native CLI not run by portable tests; no device access.' ;;
  *) "$cxx" -std=c++14 -Wall -Wextra -Werror -pedantic -I"$base/include" "$base/cli/fxprofile.cpp" -o "$build/fxprofile"
     "$build/fxprofile" --help >/dev/null
     if "$build/fxprofile" set turbo >/dev/null 2>&1; then echo 'FAIL: invalid CLI mode accepted'; exit 1; else test "$?" -eq 2; fi
     if "$build/fxprofile" query >/dev/null 2>&1; then echo 'FAIL: non-macOS fake device'; exit 1; else test "$?" -eq 3; fi
     echo 'PASS: host CLI parser and explicit non-macOS failure (no device access)' ;;
esac
