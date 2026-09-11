"""
Two builds' draw_prince, set against each other byte for byte.

    drawcmp.py <old.tap> <new.tap>

A rewrite of how he is drawn must draw exactly what the old one did, and
the play-throughs only ever see him where the game happens to take him.
This puts him everywhere that matters instead: a spread of his pictures,
facing either way, at every shift, and at both edges of the screen where
the picture is cut.  Each case starts from the same state -- one frame into
the game -- with the working copy filled with a pattern, calls draw_prince,
and compares the whole working copy and the rectangle it reports.
"""
import copy
import json
import os
import sys

import runtap

SENTINEL = 0x0038
FRAMES = [1, 5, 9, 13, 17, 30, 45, 60, 80, 100, 107, 120, 135, 150, 160, 170,
          185, 200, 217, 230]
# charx and the view's left byte: cut at the left, whole, cut at the right
PLACES = ([(x, 0) for x in range(-52, 12, 3)] +
          [(x, 1) for x in range(120, 128)] +
          [(x, 3) for x in range(226, 300, 3)])


def call(cpu, addr, limit=3000000):
    cpu.sp = (cpu.sp - 2) & 0xffff
    cpu.mem[cpu.sp] = SENTINEL & 0xff
    cpu.mem[cpu.sp + 1] = SENTINEL >> 8
    cpu.pc = addr
    t = cpu.cycles
    while cpu.pc != SENTINEL:
        cpu.step()
        if cpu.cycles - t > limit:
            return None
    return cpu.cycles - t


def run(tape):
    sym = json.load(open(tape.replace('.tap', '.sym.json')))
    cpu = runtap.boot(tape)
    runtap.game_frame(cpu, sym['main'], [])
    snap = copy.deepcopy(cpu)
    work = sym['work']
    pattern = bytes((i * 37 + 11) & 0xff for i in range(6144))
    out = {}
    cost = 0
    for f in FRAMES:
        for face in (0, 1):
            for x, cam in PLACES:
                cpu = copy.deepcopy(snap)
                cpu.mem[sym['frame']] = f
                cpu.mem[sym['facing']] = face
                cpu.mem[sym['charx']] = x & 0xff
                cpu.mem[sym['charx'] + 1] = (x >> 8) & 0xff
                cpu.mem[sym['cam']] = cam
                cpu.mem[work:work + 6144] = pattern
                t = call(cpu, sym['draw_prince'])
                if t is None:
                    out[(f, face, x, cam)] = None
                    continue
                cost += t
                rect = tuple(cpu.mem[sym['newcol']:sym['newcol'] + 4])
                out[(f, face, x, cam)] = (rect, bytes(cpu.mem[work:work + 6144]),
                                          t, cpu.mem[sym['curw']],
                                          cpu.mem[sym['curh']])
    return out, cost


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    a, ca = run(argv[1])
    b, cb = run(argv[2])
    bad = 0
    for k in sorted(a):
        if a[k] is None or b[k] is None:
            if a[k] != b[k]:
                print('%r: one of them did not come back' % (k,))
                bad += 1
            continue
        if a[k][3] == 0 or a[k][4] == 0:    # no picture: the old loop went
            continue                        # round 256 times on garbage
        if a[k][0] != b[k][0]:
            print('%r: rectangle %r against %r' % (k, a[k][0], b[k][0]))
            bad += 1
            continue
        diff = [i for i in range(6144) if a[k][1][i] != b[k][1][i]]
        if diff:
            bad += 1
            if bad <= 12:
                print('%r: %d bytes differ, first at %d (rect %r, width %d)'
                      % (k, len(diff), diff[0], a[k][0], a[k][3]))
    print('%d cases, %d differ; draw_prince %d T against %d, %.0f%%' % (
        len(a), bad, cb, ca, 100.0 * cb / max(ca, 1)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
