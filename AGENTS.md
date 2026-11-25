Notes for agents working on joksh
=================================

joksh is oksh, the portable OpenBSD Korn shell, with `set -o multiline`
and fixes to the vi and emacs line editors. Read `README.md` first: it
says what joksh is, why it exists, and which changes it carries. This
file is the rest of what you need to change it without finding things
out again the hard way.

The people, and the rules that follow from them
-----------------------------------------------

* joksh belongs to Joe Abley (GitHub `ableyjoe`). Its changes are
  written by Claude, and it says so plainly; keep it that way. Commits
  you write are authored by Claude, with the trailers your session asks
  for. Work by anyone else keeps its own author, with a note of where it
  came from.
* Joe is happy with *BSD and less so with GitHub: when he has to do
  something on GitHub, spell out each click.
* Nothing goes upstream without Joe. OpenBSD's developers have said they
  cannot accept code written by AI, so the multiline feature is never
  offered to OpenBSD, and small fixes are offered only by Joe, as plain
  diffs to tech@openbsd.org that apply with `patch -p0` in `/usr/src`.
  Never open a pull request against openbsd/src or ibara/oksh. If an
  `openbsd-contribution` skill is available, load it before any work
  meant for upstream.
* Writing, in prose, comments and commit messages alike: one space after
  a full stop, never two; English plurals, not Latin ones; plain ASCII in
  commit messages, wrapped at 72 columns. In scripts, no perl: use POSIX
  sh and POSIX awk, without gawk extensions.

Branches and history
--------------------

* `vendor` is ibara/oksh exactly as released, with its whole history. It
  only ever moves to a new oksh release.
* `main` is `vendor` with joksh's commits on top, as a series of small
  commits in this order: the tests and their portability, the bug fixes
  (Kirill A. Korinsky's, then ours), the test harness options for
  multiline, multiline itself in three steps (the display in edit.c, vi,
  emacs), the name joksh, the README and manual history, then this file,
  the fuzzer and the packaging.
* `main` is rebased, not merged, onto each new `vendor`, and pushed with
  `git push --force-with-lease origin main`. Between those rebases, add
  fixes as new commits on top, so that clones (Joe has several) pull
  cleanly and Joe's own commits are left alone; at the next rebase, fold
  each into the commit where it belongs. Releases are tagged
  (`joksh-1.0`) so that they stay reachable.
* Interactive rebases have no editor here: give `git rebase -i` a
  `GIT_SEQUENCE_EDITOR` script that turns chosen `pick` lines into `edit`
  or `fixup`, or commit an `amend! <subject>` commit and run
  `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash vendor`.
* Every commit must build and pass `make test` on its own. Check the
  whole series after a rebase:

  ```
  for c in $(git rev-list --reverse vendor..main); do
      (git checkout -q $c && git clean -qfdx && ./configure >/dev/null &&
       make >/dev/null && make test >/dev/null 2>&1)
      echo "$? $(git log -1 --format='%h %s' $c)"
  done
  ```

  in a spare worktree, on a machine that is otherwise idle (see the
  timing note under Testing).
* Remotes: `origin` is github.com/ableyjoe/joksh; add `oksh` as
  https://github.com/ibara/oksh to follow upstream.

Layout
------

oksh flattens OpenBSD's `bin/ksh` into the top directory, so OpenBSD's
`bin/ksh/X` is `X` here, and OpenBSD's `regress/bin/ksh/edit/X` is
`regress/edit/X`. When taking a patch from OpenBSD or from Kirill, move
the paths with sed before `git am`, and keep the author.

joksh changes oksh's files as little as it can, so that oksh's changes
keep applying: `oksh.1` is renamed `joksh.1`, oksh's README is
`README.oksh`, and everything else joksh adds is new files or additions.
Where multiline needs to hook into code that also runs without it, add
to that code under `x_ml_on` rather than rewrite it, so that, bug fixes
aside, what runs with the option off is oksh's. `ksh.1` (installed with
`--enable-ksh`) carries the same joksh text as `joksh.1`; change both.

Commit messages
---------------

OpenBSD style. The subject says what the change does, with a prefix:
`ksh:` for the shell, `regress/edit:` for the tests, none for repository
matters. The body says what was wrong, how to see it, what the change
does, and that a test was added. Then a bracketed note on provenance and
upstream status, such as:

```
[joksh: from https://github.com/catap/openbsd-src/commit/7a566dc1d484;
the same change, with paths moved to suit oksh's flat layout.]

[joksh: not yet offered upstream when joksh was put together.]
```

When a fix is added or dropped, or its upstream status changes, update
the table in `README.md`.

Building and testing
--------------------

* `./configure && make && make test`, in the tree. `make test` builds
  the pty harness in `regress/edit` and runs `emacs.sh` and `vi.sh` with
  the built shell as the interpreter (their `echo` needs ksh's), then
  runs both again with `multiline` set on a dumb terminal, where nothing
  may change.
* The generated Makefile has no header dependencies. After changing a
  header, `make clean` first, or you will test a shell built from old and
  new objects mixed (a changed `enum sh_flag` once made every option
  look wrong).
* configure adds `-w`. For warnings, configure with `--cflags="-O2 -Wall
  -Wextra -Wno-unused-parameter -Wno-sign-compare -DEMACS -DVI"`, delete
  ` -w ` from the generated Makefile, and compare with the same build of
  `vendor`: report only what a change adds.
* ASan and UBSan:
  `CC=clang CFLAGS="-g -O1 -fsanitize=address,undefined -fno-sanitize=shift-base -fno-omit-frame-pointer" LDFLAGS="-fsanitize=address,undefined" ./configure`,
  then `make` and `ASAN_OPTIONS=detect_leaks=0 make test`.
* Also: `mandoc -Tlint joksh.1 ksh.1`, `clang --analyze` on the editors,
  each against `vendor`.

Writing tests
-------------

A test is `testseq "keys typed" "what the terminal is sent"`, in
`regress/edit/emacs.sh` or `vi.sh`, both strings through ksh's `echo`
(octal as `\0033`). Build what you expect by running the fixed shell,
check it by eye, and check that it fails without the fix. Helpers in
`subr.sh`: `rep n string`, `$EDITFLAGS` for the harness (`-w` columns,
`-l` lines; 80 by 24 otherwise), `$KSHFLAGS` for the shell (the
multiline tests use `-o multiline`), and `$PROMPT` when the prompt shown
is not `$PS1` as written. `\000RS<n>` in the keys resizes the terminal to
`n` columns. The multiline tests set `TERM=xterm` and use `$ED` and `$UP`
for its clear-to-end and cursor-up.

The harness has quirks worth knowing:

* After sending `\n`, `\003` or `\004` it waits for the prompt. If the
  shell prints the prompt again in the middle of a line, as when
  multiline gives up and shows the line in the window, a `\n` after that
  can race: the harness finds the reprinted prompt and sends the next
  keys too soon. Load such a line from a history file instead
  (`HISTFILE=$(mktemp)`, then `echo "..." >$HISTFILE`).
* Its output buffer is `BUFSIZ`. Typing thousands of characters fills
  it and the harness spins; load long lines from history too.
* It decides the shell has finished when no output comes for 50ms, so
  tests can fail on a heavily loaded or slow machine. Run them alone
  before believing a failure. `EDITWAIT=200 make test` (`edit -t 200`)
  waits 200ms instead; the tests then take about four times as long.
* OpenBSD runs its own version on OpenBSD; joksh's has been run on
  Linux, and on macOS 15 on Intel and macOS 27 on Apple silicon, where
  it passed with joksh 1.0 under `port test`, in spite of poll(2)'s
  reputation there for not supporting devices. Its first run on OpenBSD
  (8.0 on amd64, in a VM) failed once, in the `TERM=dumb` multiline
  pass of emacs.sh, at the test on line 84: nothing came after the
  prompt. The same test passed in the first pass, and the one before it
  passed in the same pass, so the 50ms timeout is the first suspect;
  this is not yet settled.

How multiline works
-------------------

Read the comments at the top of the multi-line display in `edit.c`. In
brief:

* The editors call `x_ml_init()` for each line with a function saying
  how many cells a byte is shown as, `x_ml_start()` once the prompt is
  printed, `x_ml_refresh()` after each change, and `x_ml_below()` or
  `x_ml_finish()` before printing anything else. `x_ml_on` says the
  display is in use for the line; `x_ml_held` that it is waiting for the
  prompt to be printed again.
* Positions count columns from the start of the row where the last line
  of the prompt begins, and turn into rows and columns with `ml_cols`,
  the width the line was laid out for. `ml_obuf` is the line as on the
  screen, and a refresh redraws from the first changed character.
* `x_ml_refresh()` gives up, and the editor shows the line in its
  window, on a new line, when the line is taller than the screen, when
  `ml_check()` finds a character outside `ml_narrow()`'s list of blocks
  known to be one column wide, or bytes that are not valid UTF-8, or when
  the length or cursor makes no sense. It never sends part of a
  character: one cut short at the cursor, as vi mode types it a byte at a
  time, waits until it is whole. These guards exist because the display
  moves the cursor up rows it believes it drew; if it is wrong about a
  width, it can clear the output above the prompt.
* On a change of width, Kirill's resize callbacks call `x_ml_top()`,
  which goes up the fewer of the rows the cursor is down at the old and
  the new width, since some terminals re-wrap old lines and some do not,
  and never more.
* vi: `vi_cells()` repeats `display()`'s rules for showing a byte, so
  that `display()` itself stays as upstream has it. If those rules
  change upstream, change `vi_cells()` to match.
* emacs: the editor keeps its own window bookkeeping running underneath,
  and `x_e_putc()` drops what would draw the line while the display is in
  use, as does a guard at the top of Kirill's `x_zotcp()`, which writes
  to the terminal itself. Anything new in `emacs.c` that draws the line
  directly needs the same guard. `emacs_refresh()` brings the display up
  to date before each key is read.

Fuzzing
-------

`tools/fuzz` has a fuzzer that types random keys at both editors with
multiline on and off, under ASan and UBSan, checking for crashes, for
any difference in editing between on and off, and for a correct screen.
Run it after any change to the editors; its README says how, and which
screen findings are known not to be bugs. A short run:
`tools/fuzz/build.sh && tools/fuzz/mlfuzz.py run --cases 1500 --jobs 2`.

A fresh reviewer, reading the series cold, has found real bugs each time
it was asked: for a change of any size to the editors, it is worth it.

Following oksh and OpenBSD
--------------------------

`README.md` gives the steps for a new oksh release. When OpenBSD takes
one of joksh's fixes, oksh picks it up, and the rebase drops or
conflicts with joksh's commit: drop joksh's. OpenBSD changes that oksh
has not yet taken are left for oksh to bring; do not take them by hand.
Kirill's fixes may reach OpenBSD in another form, and joksh's "window
buffers big enough for stray UTF-8 bytes" builds on his vi fix, so check
it when his changes land.

Known gaps: oksh's own `--disable-curses` build does not compile (not
joksh's doing), `t;` in vi mode stays put as it does upstream, and a
byte that cuts short a character after `f`, `t` or `r` is swallowed with
the error.

Releases and packages
---------------------

`packaging/README.md` covers versions, making a release, and the
MacPorts and OpenBSD ports. Releases are made by Joe on GitHub, from a
tarball `packaging/release.sh` makes; pushing tags from the cloud session
is refused by its proxy, so do not try.

Where things can and cannot be tested
-------------------------------------

The cloud session runs Linux. It can build and test joksh, run the
sanitizers and the fuzzer, and reach GitHub with git, but not GitHub's
archive downloads or OpenBSD's mirrors, so it cannot build either
package. Joe tests on an OpenBSD amd64 machine and on macOS with a local
MacPorts ports tree (the port built, installed and passed its tests
with joksh 1.0, on macOS 15 on Intel and macOS 27 on Apple silicon),
and has a QEMU harness for other OpenBSD architectures; ask him to run
what needs those, and give him the commands.
