#!/bin/sh
#
# Build the joksh package on OpenBSD from the port beside this script:
# copy it into the ports tree as mystuff/shells/joksh, then fetch the
# release tarball, build, test and package it there. Run it as root, or
# as a user allowed to build ports; see packaging/README.md.
#
# usage: packaging/openbsd/build.sh [-n]
#	-n	do not run the tests

set -e

die() {
	echo "build.sh: $*" >&2
	exit 1
}

test=1
[ "$1" = -n ] && test=0

[ "$(uname -s)" = OpenBSD ] || die "this is for OpenBSD"
ports=${PORTSDIR:-/usr/ports}
[ -f "$ports/infrastructure/mk/bsd.port.mk" ] ||
    die "no ports tree in $ports: see packaging/README.md"

here=$(cd "$(dirname "$0")" && pwd)
dest=$ports/mystuff/shells/joksh
mkdir -p "$dest/pkg"
for f in Makefile distinfo pkg/DESCR pkg/PLIST; do
	cp "$here/shells/joksh/$f" "$dest/$f"
done

cd "$dest"
make clean
[ $test -eq 0 ] || make test
make package
pkg=$(make show=PKGFILE)

cat <<EOF

Built $pkg. To install it, or put it in place of an
older joksh:

	cd $dest && doas make update-or-install

or, on another machine of the same architecture, with the package copied
there:

	doas pkg_add -D unsigned -r joksh-*.tgz
EOF
