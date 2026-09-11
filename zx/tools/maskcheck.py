"""
The partial floor mask update against the whole one.

The two floorpiece masks are made when a room is entered, but a floor that
gives way changes them -- the wedge is a floor's near edge and the block to
the right of the hole has just gained one.  maskblock redoes the two blocks
that change instead of the room; what it leaves behind has to be byte for
byte what floormasks would have made.

So: build a room, turn one block into space, keep what floormasks says, put
the old masks back and let maskblock do the same two blocks.  Over every
block of a room, and over as many rooms as asked for.

Then the other half: a room's masks must not depend on what was built before
it.  onemask asked which canvas to clear AFTER paging, and pageset hands back
the port value in A, so it cleared the half canvas twice and the floor canvas
never -- the floor mask carried the ink of every room already walked through,
which is the mask that hung in the air by the torches at the exit.

    maskcheck.py <tap> [rooms]
"""
import json
import os
import sys

import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
SENTINEL = 0x0038
ROWS, WIDTH = 45, 35
BG_SPACE = 0


def call(cpu, addr, limit=20000000):
    cpu.sp = (cpu.sp - 2) & 0xffff
    cpu.mem[cpu.sp] = SENTINEL & 0xff
    cpu.mem[cpu.sp + 1] = SENTINEL >> 8
    cpu.pc = addr
    n = 0
    while cpu.pc != SENTINEL and n < limit:
        cpu.step()
        n += 1
    if cpu.pc != SENTINEL:
        raise SystemExit('ran away at %04X' % cpu.pc)
    return n


def masks(cpu, sym):
    a, b = sym['floormask'], sym['halfmask']
    n = ROWS * WIDTH
    return bytes(cpu.mem[a:a + n]), bytes(cpu.mem[b:b + n])


def putmasks(cpu, sym, m):
    a, b = sym['floormask'], sym['halfmask']
    cpu.mem[a:a + len(m[0])] = m[0]
    cpu.mem[b:b + len(m[1])] = m[1]


def where(got, want):
    """The first row and byte that differ, as a mask row is a band row."""
    for i, (g, w) in enumerate(zip(got, want)):
        if g != w:
            return 'row %d byte %d, %02X not %02X' % (
                i // WIDTH, i % WIDTH, g, w)
    return ''


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    rooms = [int(x) for x in argv[2:]] or [1]
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    cpu = runtap.boot(argv[1])
    runtap.game_frame(cpu, sym['main'], [])

    bad = 0
    for n in rooms:
        cpu.mem[sym['roomnum']] = n
        call(cpu, sym['newroom'])
        ids = bytes(cpu.mem[sym['roomids']:sym['roomids'] + 60])
        whole = masks(cpu, sym)
        for loc in range(30):
            row, col = loc // 10, loc % 10
            if ids[loc] & 0x1f == BG_SPACE:
                continue                        # nothing there to give way
            cpu.mem[sym['roomids']:sym['roomids'] + 60] = ids
            cpu.mem[sym['roomids'] + loc] = BG_SPACE
            cpu.mem[sym['roomids'] + 30 + loc] = 0
            call(cpu, sym['floormasks'])
            want = masks(cpu, sym)

            putmasks(cpu, sym, whole)
            cpu.mem[sym['blockrow']] = row
            cpu.mem[sym['blockcol']] = col
            call(cpu, sym['maskblock'])
            if col < 9:
                cpu.mem[sym['blockrow']] = row
                cpu.mem[sym['blockcol']] = col + 1
                call(cpu, sym['maskblock'])
            got = masks(cpu, sym)
            if got != want:
                bad += 1
                print('room %2d block %d/%d  floor %-28s half %s'
                      % (n, row, col, where(got[0], want[0]) or '-',
                         where(got[1], want[1]) or '-'))
        cpu.mem[sym['roomids']:sym['roomids'] + 60] = ids
        putmasks(cpu, sym, whole)
    print('%d blocks the partial update gets wrong' % bad)

    carried = 0
    for n in rooms:
        cpu.mem[sym['roomnum']] = n
        call(cpu, sym['newroom'])
        alone = masks(cpu, sym)
        for other in rooms:
            if other == n:
                continue
            cpu.mem[sym['roomnum']] = other
            call(cpu, sym['newroom'])
        cpu.mem[sym['roomnum']] = n
        call(cpu, sym['newroom'])
        if masks(cpu, sym) != alone:
            carried += 1
            print('room %2d  floor %-28s half %s'
                  % (n, where(masks(cpu, sym)[0], alone[0]) or '-',
                     where(masks(cpu, sym)[1], alone[1]) or '-'))
    print('%d rooms whose masks depend on what came before' % carried)

    # And the picture: a block redrawn with nothing changed has to leave the
    # room exactly as it was -- every pass, the wipe, the repack -- and the
    # working copy under the rectangle it sends has to be the room.
    import zxscreen
    redraw = 0
    for n in rooms:
        cpu.mem[sym['roomnum']] = n
        call(cpu, sym['newroom'])
        call(cpu, sym['repaint'])
        room0 = bytes(cpu.mem[sym['room']:sym['room'] + 6720])
        for h in (16, 63):
            for loc in range(30):
                row, col = loc // 10, loc % 10
                cpu.mem[sym['blockrow']] = row
                cpu.mem[sym['blockcol']] = col
                cpu.mem[sym['redh']] = h
                call(cpu, sym['redblock'])
                now = bytes(cpu.mem[sym['room']:sym['room'] + 6720])
                cam = cpu.mem[sym['cam']]
                d = [i for i in range(6720) if now[i] != room0[i]]
                w = [(y, c) for y in range(192) for c in range(32 - cam)
                     if cpu.mem[sym['work'] + zxscreen.bitmap_offset(c, y)]
                     != now[y * 35 + c + cam]
                     and (lambda top, bot: top <= y <= bot)(
                         [2, 65, 128, 191][row + 1] - h + 1,
                         [2, 65, 128, 191][row + 1])
                     and col * 28 // 8 - cam <= c < col * 28 // 8 - cam + 5]
                if d or w:
                    redraw += 1
                    print('room %2d block %d/%d, %2d rows: room %d bytes, '
                          'working copy %d bytes' % (n, row, col, h, len(d),
                                                      len(w)))
                    cpu.mem[sym['room']:sym['room'] + 6720] = room0
    print('%d block redraws that change what nothing changed' % redraw)
    return 1 if bad or carried or redraw else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
