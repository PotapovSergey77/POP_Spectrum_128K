"""
Walking out of a room must land him in the next one, with the program still
running.

The room change is the one thing that swaps code in and out: the block that
builds a room is put back over the working copy, run, and then written over
by the repaint that follows.  Called from the wrong side of that, the repaint
goes over the code that is running and the machine comes back up executing
room pixels -- which is what happened, and what nothing here caught: the
camera scenes walk left and right WITHIN a room, and the only crossing under
test was falling.

So this walks him over an edge each way and watches two things: that the room
number changes to the one the map names, and that the program never leaves
its own code -- a runaway is a reset on the real machine.

    crosscheck.py

The tapes are built with POP_START_ROOM, _ROW and _COL and kept as
build/cross_<name>.tap.
"""
import json
import os
import subprocess
import sys

import runtap

HERE = os.path.dirname(os.path.abspath(__file__))
ZX = os.path.join(HERE, '..')

# name, room, row, col, key held, frames, the room the map puts that way
SCENES = [
    ('right out of 2', 2, 1, 8, 'right', 110, 3),
    ('up out of 10', 10, 0, 6, 'up', 110, 15),
    ('right out of 1', 1, 0, 5, 'right', 60, None),   # nothing that way
]


def build(env):
    e = dict(os.environ)
    e.update(env)
    out = subprocess.run(['sh', os.path.join(ZX, 'build.sh')], env=e,
                         capture_output=True, text=True, encoding='utf-8',
                         errors='replace').stdout
    if 'рабочий буфер' not in out:
        raise SystemExit('build failed:\n' + out[-600:])


def tape_for(name, room, row, col):
    tag = 'cross_%d_%d_%d' % (room, row, col)
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


def play(tape, key, frames):
    """(the rooms he was in, in order, what went wrong or None)."""
    sym = json.load(open(tape.replace('.tap', '.sym.json')))
    cpu = runtap.boot(tape)
    lo, hi = sym['stubs'], sym['work'] + 6144
    runtap.game_frame(cpu, sym['main'], [])
    rooms = [cpu.mem[sym['roomnum']]]
    for n in range(1, frames):
        runtap.release(cpu)
        row, bit = runtap.KEYS[key]
        cpu.ports[row] &= ~(1 << bit) & 0xff
        steps, first = 0, True
        while True:
            cpu.step()
            steps += 1
            if steps > 4000000:
                return rooms, ('frame %d never finished: PC %04X, SP %04X'
                               % (n, cpu.pc, cpu.sp))
            if cpu.pc == sym['main'] and not first:
                break
            first = False
        if not lo <= cpu.pc < hi:
            return rooms, 'frame %d: the program left its own code, at %04X' % (
                n, cpu.pc)
        room = cpu.mem[sym['roomnum']]
        if room != rooms[-1]:
            rooms.append(room)
    return rooms, None


def main(argv):
    bad = 0
    try:
        for name, room, row, col, key, frames, want in SCENES:
            tape = tape_for(name, room, row, col)
            rooms, trouble = play(tape, key, frames)
            if trouble:
                print('%-16s %s' % (name, trouble))
                bad += 1
            elif want is None:
                print('%-16s stayed in %d, as the map says' % (name, rooms[-1]))
            elif want in rooms:
                print('%-16s %s' % (name, ' -> '.join(str(r) for r in rooms)))
            else:
                print('%-16s never reached %d: %s'
                      % (name, want, ' -> '.join(str(r) for r in rooms)))
                bad += 1
    finally:
        build({})
    print('%d crossings wrong' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
