"""
Every room of the level, composed by the game, against the host renderer.

The room used to be built here and shipped as a bitmap; now the game builds
it out of POP's image tables when it is walked into.  That is a lot of ported
code -- five section passes, the piece tables of BGDATA.S, the image records
-- and one wrong table entry would show up in a room nobody had looked at.

So this drives the game's own `newroom` for each of the twenty four rooms and
compares the result with what renderroom.py draws.  They have to be identical:
the host renderer is the reference the port was written against, and it is
checked against the original's own output in turn.

    roomcheck.py <tap>
"""
import json
import os
import sys

import poplevel
import renderroom
import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
LEVEL = os.path.join(HERE, '..', '..', '01 POP Source', 'Levels', 'LEVEL1')
SENTINEL = 0x0038               # somewhere the game never runs


def host(level, n):
    """The room as renderroom draws it, packed the way the game holds it."""
    room = renderroom.Room('DUN')
    room.hatch_walls = lambda ids: None      # our own touch, not POP's
    room.build(level, n)
    px = renderroom.normalise_hatch(room.to_pixels(), level, n)
    out = bytearray()
    for y in range(192):
        line = bytearray(35)
        for x in range(280):
            if px[y][x]:
                line[x >> 3] |= 0x80 >> (x & 7)
        out += line
    return bytes(out)


def compose(cpu, sym, n):
    """Have the game build room n, and hand back what it made."""
    cpu.mem[sym['roomnum']] = n
    cpu.sp = (cpu.sp - 2) & 0xffff
    cpu.mem[cpu.sp] = SENTINEL & 0xff
    cpu.mem[cpu.sp + 1] = SENTINEL >> 8
    cpu.pc = sym['newroom']
    steps = 0
    while cpu.pc != SENTINEL and steps < 8000000:
        cpu.step()
        steps += 1
    base = sym['room']
    return bytes(cpu.mem[base:base + 6720])


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    level = poplevel.Level(LEVEL)
    cpu = runtap.boot(argv[1])
    runtap.game_frame(cpu, sym['main'], [])

    bad = 0
    for n in range(1, 25):
        made = compose(cpu, sym, n)
        want = host(level, n)
        d = sum(1 for i in range(6720) if made[i] != want[i])
        if d:
            bad += 1
            rows = sorted({i // 35 for i in range(6720) if made[i] != want[i]})
            print('room %2d: %d of 6720 bytes differ, rows %d..%d'
                  % (n, d, rows[0], rows[-1]))
    print('%d of 24 rooms differ' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
