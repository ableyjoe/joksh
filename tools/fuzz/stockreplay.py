#!/usr/bin/env python3
"""stockreplay.py KSH CASE.json: type a case's keys at a ksh without the
fuzz hooks, with the fuzzer's history and settings, and report what the
sanitizers say."""
import json, os, sys, time, select, fcntl, termios, struct, subprocess, tempfile, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mlfuzz
ksh, path = sys.argv[1], sys.argv[2]
case = json.load(open(path))['case']
for ml in (True, False):
    work = tempfile.mkdtemp(prefix='stock.'); mlfuzz.setup_work(work)
    home = os.path.join(work, 'home'); os.mkdir(home); san = os.path.join(home, 'san'); os.mkdir(san)
    hist = os.path.join(home, 'hist')
    open(hist, 'wb').write(b'\n'.join(mlfuzz.HISTORY) + b'\n')
    rc = os.path.join(home, 'rc')
    with open(rc, 'wb') as f:
        f.write(b'set -o %s\nset %so multiline 2>/dev/null\nset -o ignoreeof\n' % (case['mode'].encode(), b'-' if ml else b'+'))
        for o in case['opts']: f.write(b'set -o %s\n' % o.encode())
        f.write(b"PS1='" + mlfuzz.PROMPTS[case['prompt']][0] + b"'\ncd " + os.path.join(work, 'files').encode() + b'\n')
    env = dict(TERM=case['term'], HOME=home, ENV=rc, HISTFILE=hist, HISTSIZE='100', PATH=os.path.join(work, 'bin'),
               VISUAL='/bin/true', EDITOR='/bin/true', FCEDIT='/bin/true',
               ASAN_OPTIONS='detect_leaks=0:log_path=' + san + '/asan', UBSAN_OPTIONS='print_stacktrace=1:log_path=' + san + '/ubsan')
    m, s = os.openpty()
    fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack('HHHH', case['rows'], case['cols'], 0, 0))
    def pre():
        os.setsid(); fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    p = subprocess.Popen([ksh, '-i'], stdin=s, stdout=s, stderr=s, env=env, preexec_fn=pre, close_fds=True, cwd=home)
    os.close(s)
    def drain(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([m], [], [], 0.05)
            if r:
                try:
                    if not os.read(m, 65536): return
                except OSError: return
    drain(0.8)
    for li, line in enumerate(case['lines']):
        for k in line + ['\r']:
            if p.poll() is not None: break
            os.write(m, k.encode()); drain(0.15)
    drain(0.5)
    alive = p.poll() is None
    p.kill(); p.wait(); os.close(m)
    logs = ''.join(open(os.path.join(san, f)).read() for f in os.listdir(san))
    first = [l.strip() for l in logs.splitlines() if 'ERROR' in l or 'runtime error' in l][:1]
    frames = [l.strip() for l in logs.splitlines() if l.strip().startswith('#')][:4]
    print('multiline %s: %s; %s' % ('on' if ml else 'off', 'alive' if alive else 'died', first[0] if first else 'sanitizers quiet'))
    for fr in frames: print('    ' + fr)
    shutil.rmtree(work, ignore_errors=True)
