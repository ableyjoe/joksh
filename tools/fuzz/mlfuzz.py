#!/usr/bin/env python3
"""
mlfuzz: fuzz ksh's line editors, with and without the multiline option.

Runs a test build of ksh (KSH_FUZZ hooks, ASan and UBSan, alloc() headers
poisoned) in a pty and types random keys at it in vi or emacs mode.  Three
oracles:

  crash   the sanitizers' logs, a death, or no answer for too long
  same    the editing must be the same with multiline on and off: every
          state ksh reports and every line it returns
  screen  with multiline on, after every key, a terminal emulator's screen
          must show the prompt and the buffer, wrapped at the width, with
          nothing after them, and the cursor where the editor says; and
          nothing may move the cursor while the terminal is in its
          pending-wrap state, where terminals disagree

The KSH_FUZZ build reports, before each read from the terminal, the
editor's state as an OSC 777 sequence on the terminal itself, and each
line it returns; it then replaces the line with an empty one, so nothing
typed here is ever run.

  mlfuzz.py run    [--ksh K] [--cases N] [--seed S] [--jobs J] [--out D]
  mlfuzz.py replay CASE [--ksh K] [--ml on|off] [--verbose]
  mlfuzz.py shrink CASE [--ksh K]
"""

import argparse
import fcntl
import hashlib
import json
import multiprocessing
import os
import random
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import re
import termios
import time

import pyte

# The test build that tools/fuzz/build.sh makes, unless $JOKSH_FUZZ says.
KSH = os.environ.get('JOKSH_FUZZ',
    os.path.join(tempfile.gettempdir(), 'joksh-fuzz', 'joksh'))
OSC = b'\x1b]777;'
SYNC_TIMEOUT = 10.0

# Prompts: (PS1 bytes, glyphs of its last line as the terminal shows it).
PROMPTS = [
    (b'$ ', list('$ ')),
    (b'', []),
    (b'a-rather-long-prompt-that-goes-on-and-on-for-a-while> ',
     list('a-rather-long-prompt-that-goes-on-and-on-for-a-while> ')),
    (b'first line of the prompt\n> ', list('> ')),
    (b'x\t> ', list('x       > ')),
    (b'\x01\r\x01\x1b[1m\x01$\x01\x1b[0m\x01 ', list('$ ')),
    ('é→ '.encode(), ['é', '→', ' ']),
]

HISTORY = [
    b'echo hello',
    b'ls -l /tmp',
    b'printf "%s\\n" one two three four five six seven eight nine ten',
    b'x' * 150,
    b'for i in 1 2 3; do echo $i; done',
    b'echo\ttabs\tin\tthe\tline',
    'echo café naïve €'.encode(),
    b'a b c d e f g h i j k l m n o p q r s t u v w x y z',
    b'cd /usr/share/doc && ls | head',
    b'echo ' + b'word ' * 40,
]

FILES = ['alpha', 'alphabet', 'alpine', 'beta gamma', 'café',
         'a-very-long-file-name-that-wraps-on-narrow-screens',
         'dir1/', 'dir1/inner', 'dir2/', 'x1', 'x2', 'x3']
COMMANDS = ['fuzzcmd', 'fuzzcommand-with-a-long-name', 'fz']

TEXT = ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        '      -_./=,:;+%*()[]{}<>?~"\'#$|\\&')
UTF8 = ['é', 'ß', 'ñ', '€', 'ǅ', 'ü', 'Ω',
        'ж']
ESC = '\x1b'
# Not ^S or ^Q: the terminal driver keeps those for flow control (IXON).
CONTROLS = [c for c in range(1, 32) if c not in (17, 19)]


def C(ch):
    return chr(ord(ch) & 0x1f) if ch != '?' else '\x7f'


# Keys that take one more character after them.
def anychar(r):
    x = r.random()
    if x < 0.6:
        return r.choice(TEXT)
    if x < 0.75:
        return r.choice(UTF8)
    if x < 0.9:
        return chr(r.choice(CONTROLS))
    return r.choice(['\t', '\x7f', ESC])


def emacs_key(r):
    simple = [C('A'), C('B'), C('E'), C('F'), C('G'), C('H'), C('?'), C('K'),
              C('L'), C('N'), C('P'), C('T'), C('U'), C('W'), C('Y'),
              C('I'), C('X') + C('X'), C('X') + '?', C('X') + C('Y'),
              C('@'), ESC + ' ',
              ESC + 'b', ESC + 'f', ESC + 'd', ESC + C('?'), ESC + 'h',
              ESC + '.', ESC + '_', ESC + 'c', ESC + 'C', ESC + 'l',
              ESC + 'u', ESC + '<', ESC + '>', ESC + 'y', ESC + '#',
              ESC + '=', ESC + '?', ESC + '*', ESC + ESC, ESC + C('X'),
              C('X') + ESC, ESC + '[A', ESC + '[B', ESC + '[C', ESC + '[D',
              ESC + '[3~', ESC + '[H', ESC + '[F', ESC + 'OA', ESC + 'OD',
              ESC + '[1~', ESC + '[4~', ESC + 'g']
    x = r.random()
    if x < 0.80:
        return r.choice(simple)
    if x < 0.85:
        return r.choice([C(']'), ESC + C(']')]) + anychar(r)
    if x < 0.90:
        return r.choice([C('V'), C('^')]) + anychar(r)
    if x < 0.94:
        return ESC + str(r.randrange(1, 10)) + r.choice(
            [C('F'), C('B'), C('?'), C('D'), 'x', C('W'), ESC + 'f'])
    if x < 0.97:
        pat = ''.join(r.choice(TEXT[:26]) for _ in range(r.randrange(0, 4)))
        end = r.choice([C('R'), C('G'), ESC, '\r', C('A'), 'z'])
        return C('R') + pat + end
    if x < 0.985:
        return C('D')
    if x < 0.99:
        return C('C')
    return chr(r.choice([2, 3, 5, 15, 26, 28, 29, 30]))


def vi_key(r):
    motions = ['h', 'l', 'w', 'W', 'b', 'B', 'e', 'E', '0', '^', '$', '|',
               ';', ',', '%', ' ', C('H')]
    simple = motions + ['x', 'X', '~', 'D', 'C', 'S', 's', 'Y', 'p', 'P',
                        'u', 'U', '.', 'a', 'A', 'i', 'I', 'k', 'j', '-',
                        '+', 'G', 'n', 'N', '=', '*', '\\', C('L'), C('R'),
                        '_', 'R', ESC, ESC, ESC, C('W'), C('U'), C('?'),
                        C('V') + 'x', '\t', C('I'), ESC + ESC, '#']
    x = r.random()
    if x < 0.60:
        return r.choice(simple)
    if x < 0.72:
        return r.choice('dcy') + r.choice(motions + ['d', 'c', 'y'])
    if x < 0.82:
        return r.choice('fFtTr') + anychar(r)
    if x < 0.90:
        return str(r.randrange(1, 4)) + r.choice(
            ['x', 'l', 'h', 'w', 'b', 'p', 'P', '.', 'k', 'dw', 'cw',
             '~', 'X', 'e'])
    if x < 0.95:
        pat = ''.join(r.choice(TEXT[:26]) for _ in range(r.randrange(0, 4)))
        return r.choice('/?') + pat + r.choice(['\r', '\r', ESC])
    if x < 0.98:
        return C('V') + anychar(r)
    return C('D')


def gen_case(r):
    mode = r.choice(['vi', 'emacs'])
    cols = r.choice([12, 13, 15, 17, 20, 24, 31, 40, 64, 80, 132,
                     r.randrange(12, 100), r.choice([1, 2, 5, 8, 11])])
    rows = r.choice([3, 4, 5, 8, 12, 24, 40, r.randrange(2, 30)])
    opts = []
    if mode == 'vi':
        for o, p in (('vi-show8', 0.25), ('vi-tabcomplete', 0.5),
                     ('vi-esccomplete', 0.3)):
            if r.random() < p:
                opts.append(o)
    case = dict(mode=mode, cols=cols, rows=rows,
                term=r.choice(['xterm', 'xterm', 'vt100']),
                prompt=r.randrange(len(PROMPTS)), opts=opts,
                lines=[], resize={})
    keyfn = vi_key if mode == 'vi' else emacs_key
    for li in range(r.randrange(2, 12)):
        keys = []
        n = r.choice([3, 8, 15, 30, 60, r.randrange(1, 150)])
        while len(keys) < n:
            if r.random() < 0.5:
                burst = r.choice([1, 2, 5, 10, 25, 60])
                for _ in range(r.randrange(1, burst + 1)):
                    if r.random() < 0.15:
                        keys.append(r.choice(UTF8))
                    else:
                        keys.append(r.choice(TEXT))
            else:
                keys.append(keyfn(r))
        case['lines'].append(keys)
        if li and r.random() < 0.15:
            case['resize'][str(li)] = [
                r.choice([12, 15, 20, 40, 80, r.randrange(12, 90)]),
                r.choice([3, 5, 10, 24, r.randrange(2, 30)])]
    return case


# --- The model of what ksh shows: a byte's cells, as emacs_cells() and
# vi_cells() say, written independently of them.

def is_cont(c, mode, show8):
    if mode == 'vi' and show8:
        return False
    return (c & 0xc0) == 0x80


def ctl(c):
    return ['^', chr(c ^ 0x40)]


def cells_of(c, col, mode, show8):
    """Cells for byte c at column col after the prompt: a list of glyphs,
    with the raw byte (as an int) for a byte shown as itself."""
    if c == 9:
        n = 4 if mode == 'emacs' else 8 - (col & 7)
        return [' '] * n
    if mode == 'emacs':
        if c < 32 or c == 127:
            return ctl(c)
        if is_cont(c, mode, show8):
            return []
        return [c]
    if is_cont(c, mode, show8):
        return []
    out = []
    if (c & 0x80) and show8:
        out = ['M', '-']
        c &= 0x7f
    if c < 32 or c == 127:
        return out + ctl(c)
    return out + [c]


def layout(buf, mode, show8, pw):
    """Glyph at each position, first position and cells of each byte, end
    of line, and whether the terminal will show it as ksh counts it."""
    glyph = {}
    first = []
    ncell = []
    valid = True
    pos = pw
    owned = set()
    for i, c in enumerate(buf):
        cells = cells_of(c, pos - pw, mode, show8)
        first.append(pos)
        ncell.append(len(cells))
        if not cells:
            if i not in owned:
                valid = False	# a stray continuation byte
            continue
        if len(cells) == 1 and isinstance(cells[0], int):
            j = i + 1
            while j < len(buf) and is_cont(buf[j], mode, show8):
                owned.add(j)
                j += 1
            try:
                g = bytes(buf[i:j]).decode('utf-8')
            except UnicodeDecodeError:
                g = None
            if g is None or len(g) != 1:
                valid = False
                g = '?'
            glyph[pos] = g
        else:
            for k, ch in enumerate(cells):
                glyph[pos + k] = chr(ch) if isinstance(ch, int) else ch
        pos += len(cells)
    return glyph, first, ncell, pos, valid


class Screen(pyte.Screen):
    """A screen that notes anything done in the pending-wrap state."""

    def __init__(self, cols, rows):
        super().__init__(cols, rows)
        self.pending = []
        self._drawing = False

    # A CR then LF in the pending-wrap state is ordinary output ending a
    # full row, prompts and lists of completions included: on terminals
    # without xenl it gives a blank row, and nothing worse.  Anything else
    # done there is noted.
    _cr = False

    def _flushcr(self):
        if self._cr:
            self._cr = False
            self.pending.append('CR')

    def _note(self, what):
        if self._drawing:
            return
        self._flushcr()
        if self.cursor.x >= self.columns:
            self.pending.append(what)

    def draw(self, data):
        self._flushcr()
        self._drawing = True
        try:
            super().draw(data)
        finally:
            self._drawing = False

    def backspace(self):
        self._note('BS')
        super().backspace()

    def carriage_return(self):
        if not self._drawing:
            self._flushcr()
            if self.cursor.x >= self.columns:
                self._cr = True
        super().carriage_return()

    def linefeed(self):
        if self._cr and not self._drawing:
            self._cr = False
        else:
            self._note('LF')
        super().linefeed()

    def takepending(self):
        self._flushcr()
        ops = self.pending
        self.pending = []
        return ops

    def cursor_up(self, count=None):
        self._note('CUU')
        super().cursor_up(count)

    def cursor_forward(self, count=None):
        self._note('CUF')
        super().cursor_forward(count)

    def erase_in_display(self, how=0, *args, **kwargs):
        self._note('ED')
        super().erase_in_display(how, *args, **kwargs)


class Dead(Exception):
    pass


class Hung(Exception):
    pass


class Session:
    def __init__(self, ksh, case, ml, work, verbose=False):
        self.ksh = ksh
        self.case = case
        self.ml = ml
        self.work = work
        self.verbose = verbose
        self.trace = []
        self.findings = []
        self.stats = dict(keys=0, checked=0, skipped_size=0, invalid=0,
                          held=0, off=0)
        self.sent = 0
        self.buf = b''
        self.last = None
        self.keyno = -1
        self.pending_seen = 0
        self.grace = 0
        self.resized = False

    # -- process
    def start(self):
        c = self.case
        w = self.work
        home = tempfile.mkdtemp(dir=w, prefix='home.')
        self.home = home
        hist = os.path.join(home, 'hist')
        with open(hist, 'wb') as f:
            f.write(b'\n'.join(HISTORY) + b'\n')
        rc = os.path.join(home, 'rc')
        ps1 = PROMPTS[c['prompt']][0]
        with open(rc, 'wb') as f:
            f.write(b'set -o %s\nset %so multiline\nset -o ignoreeof\n'
                    % (c['mode'].encode(), b'-' if self.ml else b'+'))
            for o in c['opts']:
                f.write(b'set -o %s\n' % o.encode())
            f.write(b"PS1='" + ps1 + b"'\n")
            f.write(b'cd %s\n' % os.path.join(w, 'files').encode())
        self.asandir = os.path.join(home, 'san')
        os.mkdir(self.asandir)
        env = dict(TERM=c['term'], HOME=home, ENV=rc, HISTFILE=hist,
                   HISTSIZE='100', PATH=os.path.join(w, 'bin'),
                   VISUAL=os.path.join(w, 'bin', 'empty'),
                   EDITOR=os.path.join(w, 'bin', 'empty'),
                   FCEDIT=os.path.join(w, 'bin', 'empty'), KSH_FUZZ='1',
                   ASAN_OPTIONS='detect_leaks=0:halt_on_error=1:log_path='
                   + self.asandir + '/asan',
                   UBSAN_OPTIONS='print_stacktrace=1:halt_on_error=1:'
                   'log_path=' + self.asandir + '/ubsan')
        self.m, s = os.openpty()
        self.setsize(c['cols'], c['rows'], fd=s)
        self.screen = Screen(c['cols'], c['rows'])
        self.stream = pyte.ByteStream(self.screen)

        def pre():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        self.p = subprocess.Popen([self.ksh, '-i'], stdin=s, stdout=s,
                                  stderr=s, env=env, preexec_fn=pre,
                                  close_fds=True, cwd=home)
        os.close(s)
        self.sync()

    def setsize(self, cols, rows, fd=None):
        fcntl.ioctl(self.m if fd is None else fd, termios.TIOCSWINSZ,
                    struct.pack('HHHH', rows, cols, 0, 0))

    def close(self):
        try:
            self.p.kill()
        except OSError:
            pass
        self.p.wait()
        os.close(self.m)
        shutil.rmtree(self.home, ignore_errors=True)

    def sanlogs(self):
        out = []
        for f in sorted(os.listdir(self.asandir)):
            with open(os.path.join(self.asandir, f), errors='replace') as fh:
                out.append(fh.read())
        return '\n'.join(out)

    # -- reading the terminal
    def pump(self, timeout):
        r, _, _ = select.select([self.m], [], [], timeout)
        if not r:
            return
        try:
            data = os.read(self.m, 65536)
        except OSError:
            data = b''
        if not data:
            raise Dead()
        self.buf += data
        self.parse()

    def parse(self):
        while True:
            i = self.buf.find(OSC)
            if i < 0:
                k = 0
                for n in range(min(len(OSC) - 1, len(self.buf)), 0, -1):
                    if self.buf.endswith(OSC[:n]):
                        k = n
                        break
                self.feed(self.buf[:len(self.buf) - k])
                self.buf = self.buf[len(self.buf) - k:]
                return
            self.feed(self.buf[:i])
            j = self.buf.find(b'\x07', i)
            if j < 0:
                self.buf = self.buf[i:]
                return
            self.event(self.buf[i + len(OSC):j].decode())
            self.buf = self.buf[j + 1:]

    # C0 controls that terminals ignore but pyte's draw() stops at,
    # dropping the rest of the text with it: the \001 delimiters that ksh
    # prompts use around escape sequences, for one.
    IGNORED = bytes(c for c in range(32) if c not in (7, 8, 9, 10, 11, 12,
                                                       13, 27))

    def feed(self, data):
        if data:
            self.stream.feed(data.translate(None, self.IGNORED))

    def event(self, s):
        f = s.split(' ')
        if f[0] == 'L':
            line = bytes.fromhex(f[1]) if len(f) > 1 else b''
            self.trace.append(('L', line.hex()))
            if self.grace > 0:
                self.grace -= 1
            return
        d = dict(tag=f[1], extra=int(f[2]), on=int(f[3]), held=int(f[4]),
                 cols=int(f[5]), lins=int(f[6]), nread=int(f[7]),
                 cursor=int(f[8]), len=int(f[9]),
                 buf=bytes.fromhex(f[10]) if len(f) > 10 else b'')
        self.last = d

    def sync(self):
        """Wait until ksh has read everything sent and waits for more."""
        end = time.time() + SYNC_TIMEOUT
        while True:
            if self.last is not None and self.last['nread'] == self.sent:
                d = self.last
                self.last = None
                return d
            if self.p.poll() is not None:
                # Drain what is left, then report the death.
                try:
                    while True:
                        r, _, _ = select.select([self.m], [], [], 0.2)
                        if not r:
                            break
                        data = os.read(self.m, 65536)
                        if not data:
                            break
                        self.buf += data
                except OSError:
                    pass
                raise Dead()
            if time.time() > end:
                raise Hung()
            try:
                self.pump(0.5)
            except Dead:
                time.sleep(0.2)
                if self.p.poll() is None:
                    self.p.wait(5)
                raise

    # -- typing
    def send(self, keys):
        data = keys.encode() if isinstance(keys, str) else keys
        # Pass the keys through as bytes, one character at a time.
        os.write(self.m, data)
        self.sent += len(data)
        self.stats['keys'] += 1
        d = self.sync()
        self.after(d, keys)
        return d

    def after(self, d, keys):
        self.trace.append(('D', d['tag'], d['extra'], d['cursor'],
                           d['buf'].hex(), self.keyno))
        if self.ml:
            why = self.check(d)
            if why:
                self.findings.append(dict(kind='screen', key=self.keyno,
                                          keys=keys, why=why,
                                          screen=self.picture(d)))
        if self.verbose:
            print(repr(keys), d['tag'], d['extra'], 'on=%d held=%d' % (
                d['on'], d['held']), d['cursor'], d['buf'])
            print(self.picture(d))

    def picture(self, d):
        cx, cy = self.screen.cursor.x, self.screen.cursor.y
        rows = []
        for y in range(self.screen.lines):
            line = ''.join(self.screen.buffer[y][x].data or '?'
                           for x in range(self.screen.columns))
            mark = '>' if y == cy else ' '
            rows.append('%s|%s|' % (mark, line))
        rows.append(' cursor at row %d column %d; buffer %r cursor %d' % (
            cy, cx, d['buf'], d['cursor']))
        return '\n'.join(rows)

    # -- the screen oracle
    def check(self, d):
        sc = self.screen
        cols, rows = sc.columns, sc.lines
        show8 = 'vi-show8' in self.case['opts']
        pglyph = PROMPTS[self.case['prompt']][1]
        pw = len(pglyph)
        buf = d['buf']
        glyph, first, ncell, eol, valid = layout(buf, self.case['mode'],
                                                 show8, pw)
        # A stray UTF-8 continuation byte takes no column for ksh but one
        # for the terminal, so nothing after it lines up: skip such lines.
        if not valid:
            self.prev_valid = False
        ops = sc.takepending()
        # ksh learns of a resize only when a line ends, so the line being
        # edited then, and the one after it, which starts wherever that
        # one left the cursor, are drawn for a width the screen does not
        # have.  Leftovers may lie anywhere below after that.
        if self.grace > 0:
            self.stats['resize'] = self.stats.get('resize', 0) + 1
            self.prev_live = False
            return None
        if ops and self.prev_live and self.prev_valid and valid:
            return 'moved in the pending-wrap state: ' + ' '.join(ops)
        self.prev_live = False
        self.prev_valid = valid
        if d['tag'] not in 'EV':
            return None
        if not d['on']:
            self.stats['off'] += 1
            return None
        if d['held']:
            self.stats['held'] += 1
            return None
        if d['cols'] != cols or d['lins'] != rows:
            self.stats['skipped_size'] += 1
            return None
        self.prev_live = True
        if not valid:
            self.stats['invalid'] += 1
            return None
        self.stats['checked'] += 1
        cur = d['cursor']
        if cur < len(buf):
            p = first[cur]
            cands = [p, p + max(ncell[cur], 1) - 1]
        else:
            cands = [eol]
        cx, cy = sc.cursor.x, sc.cursor.y
        if cx >= cols:
            return 'cursor left in the pending-wrap state'
        ok = [q for q in cands if q % cols == cx]
        if not ok:
            return 'cursor in column %d, not %s' % (
                cx, ' or '.join(str(q % cols) for q in sorted(set(cands))))
        cpos = ok[0]
        r0 = cy - cpos // cols
        # If the start of the line scrolled off the top, the absolute
        # rows no longer line up: the terminal scrolled, which this
        # simple model does not follow.
        if r0 < 0:
            return None
        for q in range(eol):
            y = r0 + q // cols
            if y < 0:
                continue
            want = pglyph[q] if q < pw else glyph.get(q, '?')
            got = sc.buffer[y][q % cols].data
            if got != want:
                return ('%s at row %d column %d is %r, not %r' %
                        ('prompt' if q < pw else 'line', y, q % cols, got,
                         want))
        lastrow = r0 + max(eol, cpos) // cols
        if lastrow >= rows:
            return 'line goes below the screen'
        for q in range(eol, (max(eol, cpos) // cols + 1) * cols):
            y = r0 + q // cols
            if y >= 0 and sc.buffer[y][q % cols].data != ' ':
                return 'left over %r at row %d column %d after the line' % (
                    sc.buffer[y][q % cols].data, y, q % cols)
        for y in range(lastrow + 1, rows if not self.resized else 0):
            for x in range(cols):
                if sc.buffer[y][x].data != ' ':
                    return 'left over %r at row %d column %d below the line'\
                        % (sc.buffer[y][x].data, y, x)
        return None

    def run(self):
        self.prev_live = False
        self.prev_valid = True
        self.grace = 0
        self.resized = False
        self.start()
        c = self.case
        for li, keys in enumerate(c['lines']):
            if str(li) in c['resize']:
                cols, rows = c['resize'][str(li)]
                self.setsize(cols, rows)
                self.screen.resize(rows, cols)
                # Tab stops every eight columns, as a terminal keeps them.
                self.screen.tabstops = set(range(8, cols, 8))
                self.prev_live = False
                self.grace = 2
                self.resized = True
            for k in keys:
                self.keyno += 1
                self.send(k)
            self.keyno += 1
            self.send('\r')


def setup_work(work):
    os.makedirs(os.path.join(work, 'files'), exist_ok=True)
    os.makedirs(os.path.join(work, 'bin'), exist_ok=True)
    for f in FILES:
        p = os.path.join(work, 'files', f)
        if f.endswith('/'):
            os.makedirs(p, exist_ok=True)
        else:
            open(p, 'a').close()
    for cmd in COMMANDS:
        p = os.path.join(work, 'bin', cmd)
        with open(p, 'w') as fh:
            fh.write('#!/bin/sh\nexit 0\n')
        os.chmod(p, 0o755)
    # vi's v runs fc, which runs whatever its editor leaves in the file,
    # and not through x_read(): so the editor leaves nothing.
    p = os.path.join(work, 'bin', 'empty')
    with open(p, 'w') as fh:
        fh.write('#!/bin/sh\n: > "$1"\n')
    os.chmod(p, 0o755)


def run_one(ksh, case, ml, work, verbose=False):
    """Run a case once; return (trace, findings, stats)."""
    s = Session(ksh, case, ml, work, verbose)
    findings = s.findings
    try:
        s.run()
    except Dead:
        time.sleep(0.3)
        logs = s.sanlogs()
        status = s.p.poll()
        if logs or (status not in (0, None)):
            findings.append(dict(kind='crash', key=s.keyno, why='status %s'
                                 % status, log=logs[-6000:],
                                 tail=s.buf[-500:].decode('latin-1')))
        else:
            s.trace.append(('EXIT', status))
    except Hung:
        findings.append(dict(kind='hang', key=s.keyno,
                             why='no answer in %ds' % SYNC_TIMEOUT,
                             screen=s.picture(dict(buf=b'', cursor=-1))))
    finally:
        logs = s.sanlogs()
        if logs and not any(f['kind'] == 'crash' for f in findings):
            findings.append(dict(kind='crash', key=s.keyno, why='sanitizer',
                                 log=logs[-6000:]))
        s.close()
    return s.trace, findings, s.stats


def flatten(case):
    keys = []
    for li, line in enumerate(case['lines']):
        keys.extend(line)
        keys.append('\r')
    return keys


def compare(on, off):
    """The first point where the two traces differ, or None."""
    a = [t[:5] if t[0] == 'D' else t for t in on]
    b = [t[:5] if t[0] == 'D' else t for t in off]
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            key = on[i][5] if on[i][0] == 'D' else None
            return 'entry %d (key %s): on %r, off %r' % (i, key, x, y)
    if len(a) != len(b):
        return 'traces differ in length: on %d, off %d' % (len(a), len(b))
    return None


def test_case(ksh, case, work):
    on_t, on_f, stats = run_one(ksh, case, True, work)
    off_t, off_f, _ = run_one(ksh, case, False, work)
    findings = on_f + [dict(f, ml='off') for f in off_f]
    if not any(f['kind'] in ('crash', 'hang') for f in findings):
        why = compare(on_t, off_t)
        if why:
            findings.append(dict(kind='same', why=why))
    return findings, stats


def signature(case, f):
    why = f.get('why', '')
    if f['kind'] == 'crash':
        frames = [l.split(' in ')[1].split(' ')[0] for l in
                  f.get('log', '').splitlines() if ' in ' in l and '#' in l]
        why = re.sub(r'0x[0-9a-f]+|\d+', '_', f.get('log', '').split(
            'ERROR: ')[-1].split(' on ')[0][:60]) + ' ' + ' '.join(frames[:3])
    elif f['kind'] == 'screen':
        why = re.sub(r"'.*?'|\d+", '_', why)[:50]
    elif f['kind'] == 'same':
        why = 'same'
    return '%s|%s|%s' % (f['kind'], case['mode'], why)


def worker(args):
    ksh, seed, n, out, wid = args
    work = tempfile.mkdtemp(prefix='w%d.' % wid, dir=out)
    setup_work(work)
    r = random.Random(seed)
    seen = {}
    total = dict(cases=0, keys=0, checked=0, skipped_size=0, invalid=0,
                 held=0, off=0, resize=0)
    for i in range(n):
        cs = r.randrange(1 << 30)
        case = gen_case(random.Random(cs))
        case['seed'] = cs
        findings, stats = test_case(ksh, case, work)
        total['cases'] += 1
        for k in stats:
            total[k] = total.get(k, 0) + stats[k]
        for f in findings:
            sig = signature(case, f)
            seen[sig] = seen.get(sig, 0) + 1
            if seen[sig] <= 3:
                h = hashlib.sha1(sig.encode()).hexdigest()[:10]
                name = '%s-%s-%s-%d.json' % (f['kind'], case['mode'], h,
                                            seen[sig])
                with open(os.path.join(out, name), 'w') as fh:
                    json.dump(dict(case=case, finding=f, sig=sig), fh,
                              indent=1)
    shutil.rmtree(work, ignore_errors=True)
    return total, seen


def cmd_run(a):
    os.makedirs(a.out, exist_ok=True)
    per = (a.cases + a.jobs - 1) // a.jobs
    jobs = [(a.ksh, a.seed * 1000 + j, per, a.out, j) for j in range(a.jobs)]
    t0 = time.time()
    with multiprocessing.Pool(a.jobs) as pool:
        results = pool.map(worker, jobs)
    total = {}
    seen = {}
    for t, s in results:
        for k, v in t.items():
            total[k] = total.get(k, 0) + v
        for k, v in s.items():
            seen[k] = seen.get(k, 0) + v
    print('%d cases, %d keys, in %ds' % (total['cases'], total['keys'],
                                         time.time() - t0))
    print('screen checks: %(checked)d done; skipped: %(skipped_size)d size, '
          '%(invalid)d invalid UTF-8, %(held)d held, %(off)d display off, '
          '%(resize)d after a resize' % total)
    for sig, n in sorted(seen.items(), key=lambda x: -x[1]):
        print('%6d  %s' % (n, sig))


def load(path):
    with open(path) as fh:
        return json.load(fh)


def cmd_replay(a):
    d = load(a.case)
    case = d['case']
    work = tempfile.mkdtemp(prefix='replay.')
    setup_work(work)
    for ml in ([True, False] if a.ml is None else [a.ml == 'on']):
        print('=== multiline %s' % ('on' if ml else 'off'))
        trace, findings, stats = run_one(a.ksh, case, ml, work, a.verbose)
        for f in findings:
            print(json.dumps({k: v for k, v in f.items() if k != 'screen'},
                             indent=1))
            if 'screen' in f:
                print(f['screen'])
    shutil.rmtree(work, ignore_errors=True)


def still_fails(ksh, case, sig, work):
    findings, _ = test_case(ksh, case, work)
    return any(signature(case, f) == sig for f in findings)


def cmd_shrink(a):
    d = load(a.case)
    case = d['case']
    sig = d['sig']
    work = tempfile.mkdtemp(prefix='shrink.')
    setup_work(work)
    if not still_fails(a.ksh, case, sig, work):
        print('does not fail now')
        return
    # Drop resizes, then whole lines, then keys, while it still fails.
    for k in list(case['resize']):
        c2 = json.loads(json.dumps(case))
        del c2['resize'][k]
        if still_fails(a.ksh, c2, sig, work):
            case = c2
    changed = True
    while changed:
        changed = False
        li = 0
        while li < len(case['lines']) and len(case['lines']) > 1:
            c2 = json.loads(json.dumps(case))
            del c2['lines'][li]
            c2['resize'] = {str(int(k) - (int(k) > li)): v for k, v in
                            case['resize'].items() if int(k) != li}
            if still_fails(a.ksh, c2, sig, work):
                case = c2
                changed = True
            else:
                li += 1
        for li in range(len(case['lines'])):
            chunk = max(1, len(case['lines'][li]) // 2)
            while chunk >= 1:
                ki = 0
                while ki < len(case['lines'][li]):
                    c2 = json.loads(json.dumps(case))
                    del c2['lines'][li][ki:ki + chunk]
                    if still_fails(a.ksh, c2, sig, work):
                        case = c2
                        changed = True
                    else:
                        ki += chunk
                chunk //= 2
    out = a.case.replace('.json', '.min.json')
    with open(out, 'w') as fh:
        json.dump(dict(case=case, sig=sig, finding=d['finding']), fh,
                  indent=1)
    print('shrunk to %d lines, %d keys: %s' % (
        len(case['lines']), sum(len(l) for l in case['lines']), out))
    print(json.dumps(case['lines']))
    shutil.rmtree(work, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run')
    r.add_argument('--ksh', default=KSH)
    r.add_argument('--cases', type=int, default=100)
    r.add_argument('--seed', type=int, default=1)
    r.add_argument('--jobs', type=int, default=2)
    r.add_argument('--out', default=os.path.join(tempfile.gettempdir(),
        'joksh-fuzz-out'))
    p = sub.add_parser('replay')
    p.add_argument('case')
    p.add_argument('--ksh', default=KSH)
    p.add_argument('--ml', choices=['on', 'off'])
    p.add_argument('--verbose', action='store_true')
    s = sub.add_parser('shrink')
    s.add_argument('case')
    s.add_argument('--ksh', default=KSH)
    a = ap.parse_args()
    {'run': cmd_run, 'replay': cmd_replay, 'shrink': cmd_shrink}[a.cmd](a)


if __name__ == '__main__':
    main()
