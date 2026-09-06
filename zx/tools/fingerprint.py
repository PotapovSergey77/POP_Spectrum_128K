"""
A number per frame, so a broken sprite cannot pass unnoticed.

The stray-ink check looks at the screen OUTSIDE the sprite's rectangle and
says nothing about the sprite itself; a register clobbered in the blitter
draws garbage that it happily passes.  This counts the lit pixels inside the
rectangle instead, frame by frame, over a handful of scenarios.  The numbers
mean nothing on their own -- what matters is that they do not move when a
change was not supposed to move them.

    fingerprint.py <tap>             print the counts
    fingerprint.py <tap> --save      write tools/fingerprint.txt
    fingerprint.py <tap> --check     compare against it, and say where

Both checks together -- stray ink outside, this inside -- cover the two ways
the drawing has gone wrong so far.
"""
import json
import os
import sys

import runtap
import zxscreen

HERE = os.path.dirname(os.path.abspath(__file__))
BASELINE = os.path.join(HERE, 'fingerprint.txt')

SCENES = [
    ('walk left',   44, ['left@1-60']),
    ('walk right',  60, ['right@1-60']),
    ('fall',        44, ['left@1-20', 'down@26-34']),
    ('jump up',     40, ['up@14-20']),
    ('crouch',      30, ['down@7-14']),
]


def counts(tap, sym):
    """[(scene, [(frame, ink, col, top, width, height)])]"""
    out = []
    for name, frames, keys in SCENES:
        cpu = runtap.boot(tap)
        script = runtap.parse(keys)
        rows = []
        for n in range(1, frames):
            runtap.game_frame(cpu, sym['main'], runtap.held(script, n))
            # The screen is written at the top of a frame and composed after,
            # so what is on it is the rectangle keep_rect has just filed away.
            col, top, w, h = (cpu.mem[sym[k]]
                              for k in ('oldcol', 'oldtop', 'oldw', 'oldh'))
            ink = 0
            for j in range(h):
                y = (top + j) & 0xff
                if y >= 192:
                    continue
                for xb in range(col, min(32, col + w)):
                    b = cpu.mem[16384 + zxscreen.bitmap_offset(xb, y)]
                    ink += bin(b).count('1')
            rows.append((n, ink, col, top, w, h))
        out.append((name, rows))
    return out


def render(data):
    lines = []
    for name, rows in data:
        for n, ink, col, top, w, h in rows:
            lines.append('%s %d %d %d %d %d %d' % (name, n, ink, col, top, w, h))
    return lines


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    tap = argv[1]
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    lines = render(counts(tap, sym))

    if '--save' in argv:
        open(BASELINE, 'w').write('\n'.join(lines) + '\n')
        print('%d frames written to %s' % (len(lines), BASELINE))
        return 0

    if '--check' in argv:
        want = open(BASELINE).read().split('\n')
        want = [l for l in want if l.strip()]
        if len(want) != len(lines):
            print('the baseline has %d frames, this has %d' % (len(want), len(lines)))
            return 1
        bad = [(a, b) for a, b in zip(want, lines) if a != b]
        for a, b in bad[:8]:
            print('  was %s\n  now %s' % (a, b))
        print('%d of %d frames differ' % (len(bad), len(lines)))
        return 1 if bad else 0

    for line in lines:
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
