"""
The heavy moments, measured: does anything make his frame late?

The game runs a frame in three interrupt periods, 212724 T, and the rule is
that nothing happening around him -- a plate, a loose floor giving way, a
gate or the exit door rising, the view scrolling -- may push a frame past
that.  Each scenario here starts a tape in the room it is about, plays it,
and counts the frames whose work went over; then it lets things settle and
sets the room against a fresh build of it, since the redraw queue puts off
drawing and must not lose any.

    stress.py            build the tapes it needs, report, and put the game
                         tape back in build/

The tapes are built with POP_START_ROOM, _ROW and _COL and kept as
build/stress_<name>.tap.  The first frame after starting builds the room and
is left out.
"""
import json
import os
import subprocess
import sys

import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
ZX = os.path.join(HERE, '..')
FRAME = 70908
SLOT = 3 * FRAME
SENTINEL = 0x0038

# name, room, row, column, keys held on game frame n, frames, frames to settle
SCENES = [
    ('walk right, view scrolls', 1, 0, 5, lambda n: ['right'], 45, 5),
    ('gate rises', 6, 0, 2, lambda n: [], 60, 8),
    ('loose floors', 7, 0, 8, lambda n: ['left'] if n >= 3 else [], 60, 20),
    ('exit opens', 9, 0, 0, lambda n: [], 70, 8),
]


def build(env=None):
    e = dict(os.environ)
    e.update(env or {})
    out = subprocess.run(['sh', os.path.join(ZX, 'build.sh')], env=e,
                         capture_output=True, text=True, encoding='utf-8',
                         errors='replace').stdout
    if 'рабочий буфер' not in out:
        raise SystemExit('build failed:\n' + out[-600:])


def tape_for(name, room, row, col):
    tag = 'stress_%d_%d_%d' % (room, row, col)
    build({'POP_START_ROOM': str(room), 'POP_START_ROW': str(row),
           'POP_START_COL': str(col)})
    b = os.path.join(ZX, 'build')
    for src, dst in (('pop.tap', tag + '.tap'), ('sym.json', tag + '.sym.json'),
                     ('pop.banks.json', tag + '.banks.json')):
        with open(os.path.join(b, src), 'rb') as f:
            data = f.read()
        with open(os.path.join(b, dst), 'wb') as f:
            f.write(data)
    return os.path.join(b, tag + '.tap')


def call(cpu, addr):
    cpu.sp = (cpu.sp - 2) & 0xffff
    cpu.mem[cpu.sp] = SENTINEL & 0xff
    cpu.mem[cpu.sp + 1] = SENTINEL >> 8
    cpu.pc = addr
    while cpu.pc != SENTINEL:
        cpu.step()


def play(tape, script, frames, settle):
    sym = json.load(open(tape.replace('.tap', '.sym.json')))
    cpu = runtap.boot(tape)
    runtap.game_frame(cpu, sym['main'], [])
    lo, hi = sym['main'], sym['mainrun']
    works = []
    for n in range(1, frames + settle):
        runtap.release(cpu)
        for k in (script(n) if n < frames else []):
            row, bit = runtap.KEYS[k]
            cpu.ports[row] &= ~(1 << bit) & 0xff
        work = 0
        first = True
        while True:
            p, t = cpu.pc, cpu.cycles
            cpu.step()
            if not (lo <= p < hi):
                work += cpu.cycles - t
            if cpu.pc == sym['main'] and not first:
                break
            first = False
        if n < frames:
            works.append((n, work))
    live = bytes(cpu.mem[sym['room']:sym['room'] + 6720])
    call(cpu, sym['newroom'])
    fresh = bytes(cpu.mem[sym['room']:sym['room'] + 6720])
    stale = sum(1 for i in range(6720) if live[i] != fresh[i])
    return works[1:], stale


def main(argv):
    bad = 0
    try:
        for name, room, row, col, script, frames, settle in SCENES:
            tape = tape_for(name, room, row, col)
            works, stale = play(tape, script, frames, settle)
            over = [(n, w) for n, w in works if w > SLOT]
            worst = max(works, key=lambda x: x[1])
            print('%-26s %2d of %2d frames over, worst %6d T (%.2f of the '
                  'slot)%s' % (name, len(over), len(works), worst[1],
                               worst[1] / float(SLOT),
                               ': ' + ' '.join('%d:%dk' % (n, w // 1000)
                                               for n, w in over[:8])
                               if over else ''))
            if stale:
                print('%-26s the room, settled, is %d bytes off a fresh '
                      'build' % ('', stale))
            bad += len(over)
    finally:
        build()
    print('%d frames over the three periods' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
