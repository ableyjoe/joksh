Releases and packages
=====================

This directory holds what is needed to release joksh and to package it
for MacPorts and OpenBSD. None of it goes into the release tarball.

```
release.sh                      makes a release tarball, updates the ports
macports/shells/joksh/Portfile  the MacPorts port
openbsd/shells/joksh/           the OpenBSD port
openbsd/build.sh                builds the OpenBSD package from that port
```

Versions
--------

joksh numbers its own releases, from `joksh 1.0`; they do not follow
oksh's. The version is set in one place, `$JOKSH_VERSION` in `main.c`,
and `$OKSH_VERSION` says which release of oksh a joksh is built on.
Taking a new oksh release makes a new joksh release. The tag for a
release is `joksh-` and the version, as in `joksh-1.0`. A version is
dotted numbers only, as neither MacPorts nor OpenBSD packages can have a
hyphen in one.

Making a release
----------------

1. Set the version in `main.c`, if it is new, commit it, and check that
   `make test` passes on a clean tree.
2. Run `packaging/release.sh`. It makes `dist/joksh-VERSION.tar.gz` from
   HEAD, leaving out what `.gitattributes` marks `export-ignore`, and
   puts the version and the tarball's size and checksums into both ports.
3. Commit the changes in `packaging/` ("packaging: joksh 1.1") and push
   `main`.
4. Make the release on GitHub, from that commit:
   1. Go to https://github.com/ableyjoe/joksh/releases and click **Draft
      a new release**.
   2. Click **Choose a tag**, type `joksh-VERSION`, and click **Create new
      tag: joksh-VERSION on publish**.
   3. Leave **Target** as `main`.
   4. Give it a title, `joksh VERSION`, and a few lines on what changed,
      including the release of oksh it is built on.
   5. Drag `dist/joksh-VERSION.tar.gz` into the box for attachments. It
      must be that file, unchanged: the ports check its checksums, and
      the same source tarred again would not match.
   6. Click **Publish release**.

Both ports fetch the tarball from the release, at
https://github.com/ableyjoe/joksh/releases/download/joksh-VERSION/joksh-VERSION.tar.gz,
so build them only once the release is published.

MacPorts
--------

The port is not in MacPorts itself; use it from a local ports tree. If
you have one already, such as `~/ports` listed in
`/opt/local/etc/macports/sources.conf` before the default source:

```
$ mkdir -p ~/ports/shells
$ cp -R packaging/macports/shells/joksh ~/ports/shells/
$ cd ~/ports && portindex
$ port lint --nitpick joksh
$ sudo port install joksh
$ sudo port test joksh                # optional: the line editing tests
```

To make a local ports tree: create the directory, add a line such as
`file:///Users/you/ports` to `sources.conf` above the `rsync://` line,
and run `portindex` in it after adding or changing a port. To update
joksh after a new release, copy the Portfile across again, run
`portindex`, and `sudo port upgrade joksh`.

MacPorts builds as the `macports` user, which has to be able to reach
the ports tree. If `port install` says it cannot open the Portfile
("Permission denied"), your home directory is shut to other users; let
that one user through it, without letting it list what is there:

```
$ chmod +a "user:macports allow search" ~
```

To make joksh a login shell, add `/opt/local/bin/joksh` to `/etc/shells`
and run `chsh -s /opt/local/bin/joksh`.

OpenBSD
-------

The port builds a package with OpenBSD's ports system, so the machine
building it needs the ports tree for its release in `/usr/ports`. To get
it, as the OpenBSD FAQ says:

```
$ cd /tmp
$ ftp https://cdn.openbsd.org/pub/OpenBSD/$(uname -r)/{ports.tar.gz,SHA256.sig}
$ signify -Cp /etc/signify/openbsd-$(uname -r | cut -c 1,3)-base.pub -x SHA256.sig ports.tar.gz
$ cd /usr && doas tar xzf /tmp/ports.tar.gz
```

Then, from a checkout of joksh:

```
$ doas packaging/openbsd/build.sh
```

That copies the port to `/usr/ports/mystuff/shells/joksh`, fetches the
release tarball, builds joksh, runs its tests (`-n` skips them), and makes
the package, `/usr/ports/packages/$(arch -s)/all/joksh-VERSION.tgz`. It
then says how to install it: `doas make update-or-install` in the port
directory, or, on another machine of the same architecture,
`doas pkg_add -D unsigned -r joksh-VERSION.tgz`. The package is not
signed, hence `-D unsigned`. pkg_add adds `/usr/local/bin/joksh` to
`/etc/shells` and pkg_delete takes it out again.

After changing the port, `make port-lib-depends-check` in its directory
says whether `WANTLIB` is right, and `make update-plist` whether the
packing list is.
