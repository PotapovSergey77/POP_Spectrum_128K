"""
Where a late frame's time went: each call the main loop makes, and inside
rq_run each step it took.

    frameprof.py <room> <row> <col> [key@first-last ...]

Plays build/stress_<room>_<row>_<col>.tap (stress.py builds these) and prints,
for every frame over the three periods and the heaviest few besides, what
each part of it cost.  POP_SLOW stretches the instructions as in z80.py.
"""
import json
import os
import sys

import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
FRAME = 70908
SLOT = 3 * FRAME


def profile(tape, script, frames):
    sym = json.load(open(tape.replace('.tap', '.sym.json')))
    names = {}
    for k, v in sym.items():
        if isinstance(v, int) and k[0].islower():
            names.setdefault(v, k)
    cpu = runtap.boot(tape)
    runtap.game_frame(cpu, sym['main'], [])
    lo, hi = sym['main'], sym['mainrun']
    out = []
    for n in range(1, frames):
        runtap.release(cpu)
        for name, a, b in script:
            if a <= n <= b:
                row, bit = runtap.KEYS[name]
                cpu.ports[row] &= ~(1 << bit) & 0xff
        parts = {}
        steps = []
        cur = sub = None
        mainsp = None
        first = True
        while True:
            p, sp, t = cpu.pc, cpu.sp, cpu.cycles
            cpu.step()
            d = cpu.cycles - t
            if p == sym['mainrun']:
                mainsp = sp
            called = (cpu.sp == sp - 2 and cpu.mem[cpu.sp]
                      | cpu.mem[(cpu.sp + 1) & 0xffff] << 8 == p + 3)
            if not (lo <= p < hi) and mainsp is not None:
                if sp == mainsp and called:
                    cur = names.get(cpu.pc, '%04x' % cpu.pc)
                    sub = None
                elif cur == 'rq_run' and sp == mainsp - 2 and called:
                    sub = names.get(cpu.pc, '%04x' % cpu.pc)
                    steps.append([sub, 0, cpu.mem[sym['FRAMES']]
                                  - cpu.mem[sym['frstart']] & 0xff])
                if sp < mainsp or cpu.sp < mainsp:
                    parts[cur] = parts.get(cur, 0) + d
                    if cur == 'rq_run' and sub and sp < mainsp - 2:
                        steps[-1][1] += d
                else:
                    parts['(loop)'] = parts.get('(loop)', 0) + d
            if cpu.pc == sym['main'] and not first:
                break
            first = False
        out.append((n, sum(parts.values()), parts, steps))
    return out


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 1
    room, row, col = (int(a) for a in argv[1:4])
    script = runtap.parse(argv[4:])
    tape = os.path.join(HERE, '..', 'build',
                        'stress_%d_%d_%d.tap' % (room, row, col))
    res = profile(tape, script, 60)[1:]
    heavy = sorted(res, key=lambda r: -r[1])[:6]
    show = sorted(set(r[0] for r in res if r[1] > SLOT)
                  | set(r[0] for r in heavy))
    for n, total, parts, steps in res:
        if n not in show:
            continue
        own = total - parts.get('rq_run', 0)
        print('frame %2d  %6d T (%.2f)  own %6d  queue %6d%s' % (
            n, total, total / float(SLOT), own, parts.get('rq_run', 0),
            '  LATE' if total > SLOT else ''))
        big = sorted(((v, k) for k, v in parts.items() if k != 'rq_run'),
                     reverse=True)
        print('    ' + '  '.join('%s %dk' % (k, v // 1000)
                                 for v, k in big if v >= 3000))
        if steps:
            print('    queue: ' + '  '.join('%s %dk@%d' % (s, c // 1000, f)
                                          for s, c, f in steps if c))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
