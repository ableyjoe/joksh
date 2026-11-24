joksh
=====

joksh is the portable OpenBSD Korn shell, [oksh](https://github.com/ibara/oksh),
with multi-line command-line editing (`set -o multiline`) and a handful of
fixes to the vi and emacs line editors. It is not an official OpenBSD project,
and it is not part of oksh.

**joksh is written by a robot engineering team.** Its changes were written,
tested and documented by Claude, an AI model made by
[Anthropic](https://www.anthropic.com), managed by Joe Abley, human overlord
(wannabe). The commit history says who wrote what: commits by Claude are
authored by Claude, and changes by other people keep their own names.

Why?
----

OpenBSD's ksh edits a long command line in a one-row window that scrolls
sideways. ksh93 has `set -o multiline`, which lets the line run on over as
many rows of the screen as it needs, and that is what joksh adds, for both vi
and emacs mode.

The OpenBSD developers have said that they cannot accept code written by AI:
its copyright status is unclear, so whoever submits it cannot grant OpenBSD
the licence it needs. That is a fair position, and joksh does not try to argue
with it. The multiline feature is several hundred lines written mostly by
Claude, so it lives here instead. The smaller bug fixes found along the way are
being offered to OpenBSD on the tech@ mailing list, where OpenBSD can take them
or leave them; joksh carries them either way.

Using it
--------

Build and install it as you would oksh:

```
$ ./configure
$ make
$ make test
$ sudo make install
```

This installs `joksh` and its manual page, `joksh.1`; add the path to
`/etc/shells` if you want it as a login shell. `--enable-ksh` and
`--enable-sh` work as they do for oksh. `make test`, in a tree built in
place, runs OpenBSD's line editing tests, joksh's own, and each set again
with `multiline` on a terminal that cannot support it, where nothing may
change. To install joksh with MacPorts, or as an OpenBSD package, see
`packaging/README.md`.

Then, in `~/.kshrc` or wherever you set your editing mode:

```
set -o vi -o multiline
```

`multiline` is off unless you set it. It needs a terminal with automatic
margins that can move the cursor up and clear to the end of the screen; on any
other terminal the line is shown in the usual scrolling window, as is a line
taller than the screen, one with a character that may not take exactly one
column, such as a combining mark, an East Asian character or an emoji, or one
with bytes that are not valid UTF-8. When the terminal changes width the line
is drawn again, though part of the old one may be left above it. See
`multiline` under `set` in `joksh(1)`.

`$JOKSH_VERSION` says which joksh you have, such as `joksh 1.0`; joksh
numbers its own releases. `$OKSH_VERSION` says which release of oksh it is
built on, and `$KSH_VERSION` is as in oksh.

So far joksh itself has been built and tested on Linux. It is meant for
OpenBSD and macOS as well, as oksh is, and an earlier, vi-only version of the
multiline code has been in daily use on macOS. Reports from those and other
systems are welcome; the tests' pty harness, in particular, has not yet been
run on macOS.

What joksh changes
------------------

Everything else is oksh 7.9 as released. In the order of the commits on
`main`:

| Change | By | Upstream |
| --- | --- | --- |
| Import OpenBSD's line editing tests, and run them from `make test` | Claude | joksh only |
| Fix emacs and vi mode using the wrong terminal width after a resize | Kirill A. Korinsky | [Kirill's ksh branch](https://github.com/catap/openbsd-src/commits/ksh); not in OpenBSD as of November 2026 |
| Fix emacs mode's UTF-8 display | Kirill A. Korinsky | as above |
| Fix vi mode's UTF-8 window display | Kirill A. Korinsky | as above |
| Don't count newlines and tabs twice in the prompt width | Claude | sent to tech@, November 2026 |
| Keep the vi cursor inside the line at UTF-8 continuation bytes | Claude | sent to tech@, November 2026 |
| Count a prompt's width in columns, not bytes | Claude | sent to tech@, November 2026 |
| Don't let vi `cw` on an empty line read before the line buffer | Claude | sent to tech@, November 2026 |
| Make vi mode's window buffers big enough for stray UTF-8 bytes | Claude | the part of a tech@ fix that Kirill's does not cover |
| Let emacs `^]` and `^[^]` search for a UTF-8 character | Claude | sent to tech@, November 2026 |
| Clear the emacs mark when a history line replaces the buffer | Claude | not yet offered |
| Let vi `f`, `F`, `t`, `T` and `r` act on a whole UTF-8 character | Claude | not yet offered |
| Don't complete a command from a word with a control character, which could run a command | Claude | not yet offered |
| Start every vi search with an empty pattern on a saved line | Claude | not yet offered |
| Don't let emacs yank-pop go back past a yank that did not fit | Claude | not yet offered |
| The `multiline` option, for vi and emacs mode | Claude | joksh only |
| The name joksh, `$JOKSH_VERSION`, this README and the manual's history | Claude | joksh only |

Each commit message explains its change, and most fixes come with a test that
fails without them. The bug fixes come first, directly on top of oksh, so that
each can be dropped once oksh has it from OpenBSD.

How joksh follows oksh
----------------------

joksh is meant to stay a small, separate set of changes on top of oksh, which
follows OpenBSD's ksh, so that a new release of either is easy to take.

* The `vendor` branch is oksh exactly as released, with its full history.
* `main` is `vendor` with joksh's commits on top, in the order above.
* Each joksh release is tagged, as `joksh-1.0`, so that it stays reachable
  when `main` moves on.

For a new oksh release:

```
$ git remote add oksh https://github.com/ibara/oksh   # once
$ git fetch oksh --tags
$ git branch -f vendor oksh/main
$ git rebase vendor main
$ make test
```

A rebase drops a joksh fix that has arrived upstream unchanged; one that
arrived in another form shows up as a conflict, and the joksh commit should
then be dropped by hand. Taking a new oksh release makes a new joksh
release: give it a new `$JOKSH_VERSION` in `main.c`, update the table
above, then push `vendor`, push `main` with `--force-with-lease` (it has
been rebased), and make the release.

joksh changes the files it shares with oksh as little as it can: the `oksh.1`
manual page is renamed `joksh.1`, oksh's README is kept as `README.oksh`, and
apart from the fixes themselves its changes are additions. Where `multiline`
hooks into code that also runs without it, joksh adds to that code rather
than rewriting it, so that, fixes aside, what runs with the option off is
oksh's.

Reporting problems
------------------

Please report problems with joksh as issues on
[ableyjoe/joksh](https://github.com/ableyjoe/joksh), not to oksh or OpenBSD,
unless you can show them with a stock oksh or OpenBSD ksh too.

Thanks
------

joksh stands on a great deal of other people's work:

* **pdksh**, the public domain Korn shell, created by Eric Gisin from Charles
  Forsyth's public domain Bourne shell clone, and maintained over the years by
  John R. MacMillan, Simon J. Gerraty and Michael Rendell, with many others
  listed in `CONTRIBUTORS`.
* **The [OpenBSD project](https://www.openbsd.org)**, which has kept pdksh
  alive and well as its `ksh` for decades. Its source is at
  [openbsd/src](https://github.com/openbsd/src/tree/master/bin/ksh), mirrored
  from OpenBSD's CVS. The line editing tests joksh runs are OpenBSD's, by
  Ingo Schwarze and Anton Lindqvist.
* **[oksh](https://github.com/ibara/oksh)**, Brian Callahan's portable
  OpenBSD ksh, which joksh is built on; see `README.oksh` for its own README,
  with the systems and compilers it is known to work with.
* **Kirill A. Korinsky**, whose ksh fixes joksh carries from
  [his branch](https://github.com/catap/openbsd-src/commits/ksh).

Licence
-------

As for oksh: the main Korn shell files are public domain (see `LEGAL`), and
the portability files are BSD or ISC licensed, as their headers say. joksh's
own changes are offered on the same terms as the files they are in. As they
were written mostly by an AI model, it is not settled whether copyright
applies to them at all; where it does, those are the terms.
