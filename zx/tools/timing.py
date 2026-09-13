"""
Where the time goes: a game frame, and a room build.

Two questions keep coming back and both were answered from memory once, wrongly.
This answers them from the emulator instead.

A game frame is paced by FRAME_WAIT halts at the top of the main loop, so most
of it is spent waiting; what is left is the machine standing idle and is what
any background work would have to fit into.  A room build runs in one go when
a room is entered, and its five phases differ in whether they write buffers the
game is still reading -- which decides what could be prepared ahead of time.

    timing.py <tap>
"""
import json
import os
import sys

import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
CLOCK = 3500000
FRAME = 70908                           # T between interrupts at 50Hz
SENTINEL = 0x0010
PHASES = ('compose', 'convert', 'build_fore', 'floormasks', 'maketorches')
WALK = ['right@1-40']


def call(cpu, addr):
    """Run one subroutine and hand back what it cost."""
    cpu.sp = (cpu.sp - 2) & 0xffff
    cpu.mem[cpu.sp] = SENTINEL & 0xff
    cpu.mem[cpu.sp + 1] = SENTINEL >> 8
    cpu.pc = addr
    was = cpu.cycles
    while cpu.pc != SENTINEL:
        cpu.step()
    return cpu.cycles - was


def build(tap, sym):
    cpu = runtap.boot(tap)
    runtap.game_frame(cpu, sym['main'], [])
    cpu.mem[sym['roomnum']] = 1
    print('one room build:')
    total = 0
    call(cpu, sym['roomrest'])      # the room code, back from its banks
    for name in PHASES:
        c = call(cpu, sym[name])
        total += c
        print('  %-12s %8d T  %5.2f s  %4.1f frames' % (
            name, c, float(c) / CLOCK, float(c) / FRAME))
    print('  %-12s %8d T  %5.2f s  %4.1f frames' % (
        'all', total, float(total) / CLOCK, float(total) / FRAME))


def frames(tap, sym, n=40):
    """
    Halted against working, over a walk.

    The pace is worked out from the work, not from the halts: the core has no
    interrupt routine, so the periods that pass DURING a frame's work are lost
    on it and it always halts FRAME_WAIT times.  The machine counts them, and
    spends max(FRAME_WAIT, ceil(work / period)) periods on a frame.
    """
    cpu = runtap.boot(tap)
    runtap.game_frame(cpu, sym['main'], [])
    lo, hi = sym['main'], sym['mainrun']
    script = runtap.parse(WALK)
    idle = 0
    each = []
    for _ in range(1, n):
        first = True
        work = 0
        while True:
            p, t = cpu.pc, cpu.cycles
            cpu.step()
            d = cpu.cycles - t
            if lo <= p < hi:
                idle += d
            else:
                work += d
            if cpu.pc == sym['main'] and not first:
                break
            first = False
        each.append(work)
    n -= 1
    wait = sym['FRAME_WAIT']
    work = sum(each) / float(n)
    slots = lambda w: max(wait, -(-int(w) // FRAME))
    print('a walking frame, averaged over %d:' % n)
    print('  halted   %8.0f T  (%.1f interrupt periods)'
          % (idle / float(n), idle / float(n) / FRAME))
    print('  working  %8.0f T  (%.1f interrupt periods)'
          % (work, work / FRAME))
    print('  worst    %8d T  (%.1f interrupt periods)'
          % (max(each), max(each) / float(FRAME)))
    print('  FRAME_WAIT is %d, so a frame takes %d periods and the game runs'
          % (wait, slots(work)))
    print('  at %.1f Hz, with %.0f%% of it spare; the worst of these takes %d'
          % (CLOCK / float(slots(work) * FRAME),
             100.0 * (1 - work / (slots(work) * FRAME)), slots(max(each))))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    frames(argv[1], sym)
    print('')
    build(argv[1], sym)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
