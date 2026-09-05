"""
Run the demo a game frame at a time and print the prince's state, so a
sequence that misbehaves can be watched doing it.

Keys are given as name@first-last in game frames, and any number of them may
overlap:

    trace.py build/pop.tap 200 left@0-45 up@60-65 right@70-110 down@130-135

Usage: trace.py <tap> <frames> [key@first-last ...]
"""
import json
import os
import sys

import runtap

WATCH = ('charx', 'chary', 'blocky', 'charact', 'seqid', 'frame', 'facing',
         'blocked')


def main(argv):
    tap = argv[1]
    frames = int(argv[2]) if len(argv) > 2 else 40
    script = runtap.parse(argv[3:])
    here = os.path.dirname(os.path.abspath(__file__))
    sym = json.load(open(os.path.join(here, '..', 'build', 'sym.json')))

    cpu = runtap.boot(tap)
    print('%-5s ' % 'frame' + ' '.join('%-7s' % w for w in WATCH) + ' keys')
    last = None
    for n in range(frames):
        runtap.release(cpu)
        down = [k for k, a, b in script if a <= n <= b]
        for name in down:
            row, bit = runtap.KEYS[name]
            cpu.ports[row] &= ~(1 << bit) & 0xFF
        before = cpu.frames
        steps = cpu.run(1, limit=3000000)
        vals = [cpu.mem[sym[w]] for w in WATCH]
        line = '%-5d ' % n + ' '.join('%-7d' % v for v in vals) + ' ' + ','.join(down)
        if cpu.frames == before:
            print(line + '  STUCK at %04X after %d' % (cpu.pc, steps))
            break
        if line[6:] != last:            # only when something moves
            print(line)
            last = line[6:]
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
