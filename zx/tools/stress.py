"""
The heavy moments, measured: does anything make his frame late?

The game runs a frame in three interrupt periods, 212724 T, and the rule is
that nothing happening around him -- a plate, a loose floor giving way, a
gate or the exit door rising, the view scrolling -- may push a frame past
that.  Each scenario here starts a tape in the room it is about, plays it,
and counts the frames that were late -- the ones the next frame began more
than three periods after, by the ROM's own count; the view made ahead
fills what a frame leaves over, so a frame's work alone no longer says --
then it lets things settle and sets the room against a fresh build of it,
since the redraw queue puts off drawing and must not lose any.

    stress.py            build the tapes it needs, report, and put the game
                         tape back in build/
    stress.py guard      only the scenes whose name has that in it

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
SENTINEL = 0x0010
FRAMES = 23672

# name, room, row, column, keys held on game frame n, frames, frames to settle
SCENES = [
    ('walk right, view scrolls', 1, 0, 5, lambda n: ['right'], 45, 5),
    ('gate rises', 6, 0, 2, lambda n: [], 60, 8),
    ('loose floors', 7, 0, 8, lambda n: ['left'] if n >= 3 else [], 60, 20),
    ('exit opens', 9, 0, 0, lambda n: [], 70, 8),
    # Two of them on the screen: he walks at the guard unarmed and is cut
    # down, then armed he draws, strikes and is struck at.
    ('a guard cuts him down', 3, 1, 2,
     lambda n: ['right'] if 5 <= n <= 40 else [], 60, 8),
    # A flask's bubbles are a redraw every frame; he turns, stoops to it and
    # drinks it.
    ('a flask bubbles', 5, 2, 2,
     lambda n: ['right'] if 2 <= n <= 3 else
     (['space'] if n in (10, 14, 18) else []), 50, 8),
    # Spikes spring under him as he steps into the shaft, and he falls on
    # to them and is impaled.
    ('spikes', 6, 0, 2, lambda n: ['right'] if 2 <= n <= 3 or 8 <= n <= 12
     else [], 40, 8),
    ('the sword fight', 3, 1, 2,
     lambda n: ['right'] if 2 <= n <= 3 else
     (['space'] if n % 6 == 0 else []), 110, 8, {'POP_GOTSWORD': '1'}),
]


def build(env=None):
    e = dict(os.environ)
    e.update(env or {})
    out = subprocess.run(['sh', os.path.join(ZX, 'build.sh')], env=e,
                         capture_output=True, text=True, encoding='utf-8',
                         errors='replace').stdout
    if 'рабочий буфер' not in out:
        raise SystemExit('build failed:\n' + out[-600:])


def tape_for(name, room, row, col, extra=None):
    tag = 'stress_%d_%d_%d%s' % (room, row, col, '_sw' if extra else '')
    env = {'POP_START_ROOM': str(room), 'POP_START_ROW': str(row),
           'POP_START_COL': str(col)}
    env.update(extra or {})
    build(env)
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
    fill = sym.get('vw_fill', -1)
    works = []
    began = None
    for n in range(1, frames + settle):
        runtap.release(cpu)
        for k in (script(n) if n < frames else []):
            row, bit = runtap.KEYS[k]
            cpu.ports[row] &= ~(1 << bit) & 0xff
        work = 0
        first = True
        filling = False
        periods = None
        while True:
            p, t = cpu.pc, cpu.cycles
            if p == sym['mainrun']:             # this frame begins: the last
                now = cpu.mem[FRAMES]           # took this many periods
                if began is not None:
                    periods = (now - began) & 0xff
                began = now
            if p == fill:
                filling = True
            cpu.step()
            if not (lo <= p < hi) and not filling:
                work += cpu.cycles - t
            if cpu.pc == sym['main'] and not first:
                break
            first = False
        if n < frames:
            works.append((n, work, periods))
    live = bytes(cpu.mem[sym['room']:sym['room'] + 6720])
    call(cpu, sym['roomrest'])
    call(cpu, sym['newroom'])
    fresh = bytes(cpu.mem[sym['room']:sym['room'] + 6720])
    stale = sum(1 for i in range(6720) if live[i] != fresh[i])
    return works[1:], stale


def main(argv):
    bad = 0
    try:
        for scene in SCENES:
            name, room, row, col, script, frames, settle = scene[:7]
            if len(argv) > 1 and argv[1] not in name:
                continue                # stress.py <part of a name>
            tape = tape_for(name, room, row, col, *scene[7:])
            works, stale = play(tape, script, frames, settle)
            # frame n's periods are the ones frame n - 1 took; frame 1 is
            # the one that painted the room and is left out, as ever
            over = [(n - 1, p) for n, w, p in works if n > 2 and p and p > 3]
            worst = max(works, key=lambda x: x[1])
            print('%-26s %2d of %2d frames late, heaviest %6d T (%.2f of the '
                  'slot)%s' % (name, len(over), len(works), worst[1],
                               worst[1] / float(SLOT),
                               ': ' + ' '.join('%d:%d periods' % o
                                               for o in over[:8])
                               if over else ''))
            if stale:
                print('%-26s the room, settled, is %d bytes off a fresh '
                      'build' % ('', stale))
            bad += len(over)
    finally:
        build()
    print('%d frames late' % bad)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
