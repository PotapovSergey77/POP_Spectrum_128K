"""
A pressplate opens a gate, the gate comes back down, and it is drawn right
at every height on the way.

The wiring is POP's own: LINKLOC and LINKMAP say what a plate drives, and a
gate rises four pixels a frame, waits at the top and falls.  None of that is
visible from a screenshot until you happen to be standing in the right room,
so this drives it directly -- push each of level one's plates, then run the
trans list frame by frame and watch what the linked gates do.

Then the drawing: a gate is the one piece whose art depends on a state that
changes while the game runs, and every gate in level one sits at 1 or 2, so
composing the rooms as they ship never draws one more than a pixel off the
floor.  The second half sets each gate to nine heights in turn and compares
the room the game builds with the one renderroom draws, the way roomcheck
does for the rooms as they are.

    gatecheck.py <tap>
"""
import json
import os
import sys

import poplevel
import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
LEVEL = os.path.join(HERE, '..', '..', '01 POP Source', 'Levels', 'LEVEL1')
SENTINEL = 0x0038
GMAXVAL = 188
PRESSPLATE, UPRESSPLATE, GATE, EXIT = 6, 15, 4, 16
EMAXVAL = 172


def call(cpu, addr):
    cpu.sp = (cpu.sp - 2) & 0xffff
    cpu.mem[cpu.sp] = SENTINEL & 0xff
    cpu.mem[cpu.sp + 1] = SENTINEL >> 8
    cpu.pc = addr
    while cpu.pc != SENTINEL:
        cpu.step()


def state(cpu, sym, scrn, block):
    """The live state of one block, out of the blueprint in the bank."""
    call(cpu, sym['page_bg'])
    return cpu.mem[sym['level'] + 720 + (scrn - 1) * 30 + block]


def plates(level):
    for n in range(1, 25):
        types, _ = level.screen(n)
        for i, b in enumerate(types):
            if b & poplevel.IDMASK in (PRESSPLATE, UPRESSPLATE):
                yield n, i, b & poplevel.IDMASK


def chain(level, index):
    """What a plate drives: LINKLOC gives a block and two bits of the room,
    LINKMAP the other three, and bit 7 of LINKLOC ends the chain."""
    out = []
    while index < 256:
        loc = level.data[poplevel.LINKLOC + index]
        if loc == 0xff:
            break
        mapb = level.data[poplevel.LINKMAP + index]
        scrn = ((mapb & 0xe0) + ((loc & 0x60) >> 2)) >> 3
        out.append((scrn, loc & 0x1f))
        if loc & 0x80:
            break
        index += 1
    return out


def gates(level):
    """Everything a plate can drive: gates, and the level's exit."""
    for n in range(1, 25):
        types, _ = level.screen(n)
        for i, b in enumerate(types):
            if b & poplevel.IDMASK in (GATE, EXIT):
                yield n, i


def is_exit(level, scrn, block):
    return level.screen(scrn)[0][block] & poplevel.IDMASK == EXIT


HEIGHTS = (0, 20, 60, 100, 140, EMAXVAL, 180, GMAXVAL, 238, 255)


def drawn(tap, sym):
    """Every gate at every height, the game's room against renderroom's."""
    import roomcheck
    bad = 0
    for scrn, block in gates(poplevel.Level(LEVEL)):
        room = scrn if block % 10 < 9 else None
        if room is None:                # its bars hang in the room to the
            room = poplevel.Level(LEVEL).links(scrn)[1]   # right of this one
            if not room:
                continue
        for st in HEIGHTS:
            level = poplevel.Level(LEVEL)
            d = bytearray(level.data)
            d[720 + (scrn - 1) * 30 + block] = st
            level.data = bytes(d)
            cpu = runtap.boot(tap)
            runtap.game_frame(cpu, sym['main'], [])
            call(cpu, sym['page_bg'])
            cpu.mem[sym['level'] + 720 + (scrn - 1) * 30 + block] = st
            made = roomcheck.compose(cpu, sym, room)
            want = roomcheck.host(level, room)
            n = sum(1 for i in range(6720) if made[i] != want[i])
            if n:
                bad += 1
                print('gate %d/%d at %3d, room %2d: %d of 6720 bytes differ'
                      % (scrn, block, st, room, n))
    print('%d gate heights drawn wrong' % bad)
    return bad


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    level = poplevel.Level(LEVEL)
    allgates = list(gates(level))
    bad = 0

    for scrn, block, kind in plates(level):
        cpu = runtap.boot(argv[1])
        runtap.game_frame(cpu, sym['main'], [])
        before = {g: state(cpu, sym, *g) for g in allgates}

        cpu.mem[sym['trloc']] = block
        cpu.mem[sym['trscrn']] = scrn
        call(cpu, sym['trobat'])
        call(cpu, sym['pushpp'])

        # Run the list until everything has stopped, or long enough that
        # something is stuck.
        seen = {g: {before[g]} for g in allgates}   # where it started counts
        for _ in range(700):
            call(cpu, sym['animtrans'])
            for g in allgates:
                seen[g].add(state(cpu, sym, *g))
            if not cpu.mem[sym['numtrans']]:
                break
        left = cpu.mem[sym['numtrans']]

        moved = [g for g in allgates if len(seen[g]) > 1]
        wired = [g for g in chain(level, level.screen(scrn)[1][block])
                 if g in allgates]
        name = 'plate' if kind == PRESSPLATE else 'spring'
        print('%-7s room %2d block %2d  drives %-24s moved %s'
              % (name, scrn, block,
                 ' '.join('%d/%d' % g for g in wired) or '-',
                 ' '.join('%d/%d' % g for g in moved) or '-'))
        if left:
            bad += 1
            print('   %d objects still going after 700 frames' % left)
        for g in moved:
            if g not in wired:
                bad += 1
                print('   %d/%d moved but is not on the chain' % g)
        for g in wired:
            if g in moved:
                continue
            if before[g] != 0 or kind == UPRESSPLATE:
                bad += 1
                print('   %d/%d is on the chain at %d but never moved'
                      % (g[0], g[1], before[g]))
        for g in moved:
            end = state(cpu, sym, *g)
            if is_exit(level, *g):
                # An exit only ever opens, and then stays open.
                if end < EMAXVAL:
                    bad += 1
                    print('   exit %d/%d stopped at %d, not %d'
                          % (g[0], g[1], end, EMAXVAL))
                continue
            top = max(s for s in seen[g] if s <= GMAXVAL)
            if kind == UPRESSPLATE and top < GMAXVAL:
                bad += 1
                print('   %d/%d never reached the top (%d of %d)'
                      % (g[0], g[1], top, GMAXVAL))
            if end:
                bad += 1
                print('   %d/%d ended at %d, not shut' % (g[0], g[1], end))
    print('%d problems' % bad)
    return 1 if bad + drawn(argv[1], sym) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
