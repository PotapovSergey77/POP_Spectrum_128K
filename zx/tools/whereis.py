"""
Where is the prince actually drawn, in pixels, against the block he stands on?

Compares the screen with the bare room and reports the columns that differ,
which is the figure itself rather than the byte rectangle around it.

Usage: whereis.py <tap> [x=156 row=0 face=0]
"""
import json
import os
import sys

import runtap
import zxscreen


def main(argv):
    tap = argv[1]
    args = dict(a.split('=') for a in argv[2:])
    x = int(args.get('x', 156))
    row = int(args.get('row', 0))
    face = int(args.get('face', 0))
    here = os.path.dirname(os.path.abspath(__file__))
    sym = json.load(open(os.path.join(here, '..', 'build', 'sym.json')))
    room = open(os.path.join(here, '..', 'build', 'bin', 'bank_art.bin'),
                'rb').read()

    cpu = runtap.boot(tap)
    runtap.play(cpu, 3, [])
    cpu.mem[sym['charx']] = x
    cpu.mem[sym['chary']] = (248, 55, 118, 181, 244)[row + 1]
    cpu.mem[sym['blocky']] = row
    cpu.mem[sym['facing']] = face
    runtap.play(cpu, 3, [])

    cols = set()
    for y in range(192):
        for c in range(32):
            off = zxscreen.bitmap_offset(c, y)
            d = cpu.mem[16384 + off] ^ room[off]
            for b in range(8):
                if d & (0x80 >> b):
                    cols.add(c * 8 + b)
    if not cols:
        print('его не видно')
        return 1
    lo, hi = min(cols), max(cols)
    b = cpu.mem[sym['blockof'] + x]
    print('charx %d, лицом %s, блок %s' % (x, 'вправо' if face else 'влево', b))
    print('  фигура в пикселях %d..%d, центр %d' % (lo, hi, (lo + hi) // 2))
    print('  блок %s нарисован %d..%d, центр %d'
          % (b, 28 * b - 12, 28 * b + 15, 28 * b + 1))
    print('  смещение центра фигуры от центра плитки: %+d'
          % ((lo + hi) // 2 - (28 * b + 1)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
