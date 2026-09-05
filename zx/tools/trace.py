"""
Run the demo one game frame at a time and print the prince's state, so a
sequence that gets stuck can be seen doing it.

Usage: trace.py <tap> <frames> [key ...]
"""
import json
import os
import sys

import runtap
import z80

WATCH = ('charx', 'chary', 'blocky', 'falling', 'seqid', 'frame', 'newcol',
         'neww', 'newtop', 'newh',
         'facing')


def main(argv):
    tap = argv[1]
    frames = int(argv[2]) if len(argv) > 2 else 40
    held = argv[3:]
    here = os.path.dirname(os.path.abspath(__file__))
    sym = json.load(open(os.path.join(here, '..', 'build', 'sym.json')))

    cpu = runtap.boot(tap, held)

    print('%-5s ' % 'frame' + ' '.join('%-7s' % w for w in WATCH))
    for n in range(frames):
        before = cpu.frames
        steps = cpu.run(1, limit=400000)
        vals = [cpu.mem[sym[w]] for w in WATCH]
        stuck = '  STUCK' if cpu.frames == before else ''
        print('%-5d ' % n + ' '.join('%-7d' % v for v in vals) + stuck)
        if stuck:
            print('PC=%04X after %d instructions' % (cpu.pc, steps))
            break
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
