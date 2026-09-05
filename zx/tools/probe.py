"""
Put the prince somewhere and see what he does.

Driving him across the room to reach a situation costs a lot of emulated
frames; this drops him where the situation is and presses the key.

    probe.py <tap> x=130 row=2 face=0 keys=up@4-8 frames=40

x is his charx, row the block row, face 0 left 1 right.  chary follows from
the row.  Everything else is as the game left it.

Usage: probe.py <tap> [name=value ...] [key@first-last ...]
"""
import json
import os
import sys

import runtap

FLOORY = (248, 55, 118, 181, 244)


def basex(cpu, sym):
    """GETBASEX and the block it lands in, as the program works them out."""
    f = cpu.mem[sym['frame']]
    foot = cpu.mem[sym['fcheck'] + f] & 0x1f
    dx = cpu.mem[sym['fdx'] + f]
    dx = dx - 256 if dx > 127 else dx
    off = 2 * (dx - foot)
    if not cpu.mem[sym['facing']]:
        off = -off
    x = (cpu.mem[sym['charx']] + off) & 0xff
    b = cpu.mem[sym['blockof'] + x]
    return x, ('%d' % b) if b < 10 else '-'


def main(argv):
    tap = argv[1]
    args = {}
    keys = []
    for a in argv[2:]:
        if '=' in a and '@' not in a:
            k, v = a.split('=', 1)
            args[k] = int(v)
        else:
            keys.append(a)
    here = os.path.dirname(os.path.abspath(__file__))
    sym = json.load(open(os.path.join(here, '..', 'build', 'sym.json')))

    cpu = runtap.boot(tap)
    runtap.play(cpu, 3, [])             # let it draw once
    row = args.get('row', 0)
    cpu.mem[sym['charx']] = args.get('x', cpu.mem[sym['charx']])
    cpu.mem[sym['chary']] = args.get('y', FLOORY[row + 1])
    cpu.mem[sym['blocky']] = row
    cpu.mem[sym['facing']] = args.get('face', 0)
    cpu.mem[sym['tilerow']] = (row * 10 + sym['tiles']) & 0xff
    cpu.mem[sym['tilerow'] + 1] = ((row * 10 + sym['tiles']) >> 8) & 0xff

    watch = ('charx', 'chary', 'blocky', 'charact', 'frame', 'facing')
    print('%-5s ' % 'frame' + ' '.join('%-7s' % w for w in watch)
          + ' %-7s %-4s keys' % ('basex', 'блок'))
    script = runtap.parse(keys)
    last = None
    for n in range(args.get('frames', 40)):
        runtap.release(cpu)
        down = [k for k, a, b in script if a <= n <= b]
        for name in down:
            r, bit = runtap.KEYS[name]
            cpu.ports[r] &= ~(1 << bit) & 0xFF
        cpu.run(1, limit=3000000)
        vals = [cpu.mem[sym[w]] for w in watch]
        line = (' '.join('%-7d' % v for v in vals)
                + ' %-7d %-4s' % basex(cpu, sym) + ' ' + ','.join(down))
        if line != last:
            print('%-5d ' % n + line)
            last = line
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
