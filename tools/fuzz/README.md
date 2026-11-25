Fuzzing the line editors
========================

`mlfuzz.py` types random keys at joksh's vi and emacs line editors, in a
pseudo terminal, with `multiline` on and off, and checks three things:

* **crash**: a sanitizer report, a death, or no answer for 10 seconds;
* **same**: with `multiline` on and off, every editor state the shell
  reports and every line it returns must be the same, as the option may
  change what is drawn but never what is edited;
* **screen**: with `multiline` on, after each key, a terminal emulator
  ([pyte](https://github.com/selectel/pyte)) must show the prompt and the
  line wrapped at the screen width, nothing after them, the cursor where
  the editor says it is, and no cursor movement while the terminal is in
  its pending-wrap state, where terminals disagree.

It needs Python 3, pyte (`pip install pyte`), clang with ASan and UBSan,
and a Unix with ptys; it has been run on Linux.

Running it
----------

```
$ tools/fuzz/build.sh                     # makes /tmp/joksh-fuzz/joksh
$ tools/fuzz/mlfuzz.py run --cases 1500 --jobs 2 --seed 1
$ tools/fuzz/mlfuzz.py replay /tmp/joksh-fuzz-out/<finding>.json --verbose
$ tools/fuzz/mlfuzz.py shrink /tmp/joksh-fuzz-out/<finding>.json
$ tools/fuzz/stockreplay.py <some other ksh> <finding>.json
```

`build.sh` builds the source of HEAD, with `hooks.diff` applied, under
ASan and UBSan, outside the working tree. The hooks (all `#ifdef
KSH_FUZZ`) make the shell report its editor's state before each key as an
OSC escape on its own output, report and then throw away each line it
would run, and keep each alloc() header poisoned to ASan, so that a read
or write just before a buffer is caught. Never install that build.

Typing random keys still runs whatever completion and expansion do on
the way: run the fuzzer as an ordinary user, in a scratch directory. It
gives the shell its own `PATH`, `HOME` and history in a temporary
directory.

`run` prints a summary line for each kind of finding, and saves one
example of each in the output directory. A run of 1500 cases is about
400,000 keys and takes a minute or two; use `--jobs 1` when the machine is
busy, or the timing-sensitive "no answer" check will fire falsely.
`stockreplay.py` types a finding's keys at a shell without the hooks,
such as stock oksh or OpenBSD ksh built with ASan, to see whether a bug is
joksh's or was there already.

Telling real findings from artefacts
------------------------------------

Every crash and every `same` finding so far has been a real bug. Screen
findings need judgement; these kinds have been looked at and are the
model's strictness, or terminals differing, rather than bugs:

* moving the cursor in the pending-wrap state, from emacs mode's
  incremental search prompt and at exact margins in window mode, which
  `multiline` does not draw;
* a line drawn in the window after `multiline` gave up on it, for
  example for a character of uncertain width or for invalid UTF-8;
* anything just after a change of screen size, which the fuzzer skips;
* prompts with `\001`-delimited invisible sequences, whose layout pyte
  and the shell agree on only roughly.

When a finding is new, replay it against the build from before the
change being tested: if it shows there too, it is not that change's.

Keeping the hooks up to date
----------------------------

`hooks.diff` is a patch against joksh's own sources. When it stops
applying, apply it by hand to a copy of the tree, fix the rejects, and
make a new one with `diff -u` between the two copies, file by file, with
`a/` and `b/` labels.
