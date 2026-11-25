#!/bin/sh
#
# Make the release tarball for the joksh version in version.c from HEAD, as
# dist/joksh-VERSION.tar.gz, and set the MacPorts and OpenBSD ports to
# that version and the tarball's size and checksums. See README.md.
#
# usage: packaging/release.sh [version]

set -e

die() {
	echo "release.sh: $*" >&2
	exit 1
}

top=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$top"

v=$(sed -n 's/^#define[	 ]*JOKSH[	 ]*"joksh \([0-9][0-9.]*\)".*/\1/p' version.c)
[ -n "$v" ] || die "cannot find the version in version.c"
[ $# -eq 0 ] || [ "$1" = "$v" ] || die "version.c says joksh $v, not $1"
case $v in
[0-9]*.[0-9]*) ;;
*) die "version $v is not dotted numbers, as in 1.0" ;;
esac
[ -z "$(git status --porcelain -- . ':!packaging')" ] ||
    die "commit everything outside packaging/ first: the tarball is HEAD"

name=joksh-$v
tarball=dist/$name.tar.gz
mkdir -p dist
git archive --format=tar --prefix="$name/" HEAD | gzip -n -9 >"$tarball"

size=$(wc -c <"$tarball" | tr -d ' ')
sha256=$(openssl dgst -sha256 "$tarball" | awk '{ print $NF }')
rmd160=$(openssl dgst -rmd160 "$tarball" | awk '{ print $NF }')
sha256b64=$(openssl dgst -sha256 -binary "$tarball" | openssl base64)

# MacPorts: a new version starts again at revision 0.
pf=packaging/macports/shells/joksh/Portfile
old=$(awk '$1 == "github.setup" { print $4 }' "$pf")
[ "$old" = "$v" ] || sed -i.bak 's/^revision\( *\)[0-9][0-9]*$/revision\10/' "$pf"
sed -i.bak \
    -e "s/^\(github.setup *ableyjoe joksh \)[^ ]*\( joksh-\)$/\1$v\2/" \
    -e "s/^\(checksums *rmd160  \)[0-9a-f]*\( \\\\\)$/\1$rmd160\2/" \
    -e "s/^\( *sha256  \)[0-9a-f]*\( \\\\\)$/\1$sha256\2/" \
    -e "s/^\( *size    \)[0-9]*$/\1$size/" \
    "$pf"
rm -f "$pf.bak"

# OpenBSD: a new version drops any REVISION.
mk=packaging/openbsd/shells/joksh/Makefile
old=$(awk '$1 == "V=" { print $2 }' "$mk")
sed -i.bak -e "s/^V=\(	*\).*/V=\1$v/" "$mk"
[ "$old" = "$v" ] || sed -i.bak '/^REVISION=/d' "$mk"
rm -f "$mk.bak"
printf 'SHA256 (%s.tar.gz) = %s\nSIZE (%s.tar.gz) = %s\n' \
    "$name" "$sha256b64" "$name" "$size" \
    >packaging/openbsd/shells/joksh/distinfo

cat <<EOF
$tarball: $size bytes
sha256 $sha256

Next:
1. Commit the changes to packaging/ and push main.
2. Make a GitHub release with the tag joksh-$v on that commit, and
   attach $tarball to it, as it is: the ports check its checksums.
EOF
