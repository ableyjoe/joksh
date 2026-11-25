#!/bin/sh
#
# Build the fuzzing test build of joksh: the source of HEAD with the
# KSH_FUZZ hooks from hooks.diff, under ASan and UBSan. It goes in
# ${JOKSH_FUZZ_DIR:-/tmp/joksh-fuzz}, never in the working tree.
#
# The hooks make the shell report its editor's state to the fuzzer and
# throw away every line it would run. Never install this build.

set -e

top=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
out=${JOKSH_FUZZ_DIR:-${TMPDIR:-/tmp}/joksh-fuzz}
cc=${CC:-clang}

rm -rf "$out"
mkdir -p "$out"
git -C "$top" archive HEAD | tar -xf - -C "$out"
cd "$out"
patch -s -p1 <"$top/tools/fuzz/hooks.diff"
CC=$cc \
    CFLAGS="-g -O1 -DKSH_FUZZ -fsanitize=address,undefined -fno-sanitize=shift-base -fno-omit-frame-pointer" \
    LDFLAGS="-fsanitize=address,undefined" \
    ./configure >configure.log 2>&1
make >build.log 2>&1 || { tail -20 build.log; exit 1; }
echo "$out/joksh"
