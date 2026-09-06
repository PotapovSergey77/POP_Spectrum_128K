"""
The moved view must be the pinned view, shifted.  Nothing else.

The working copy is only ever put right under the two rectangles the sprite
covers; everywhere else it holds whatever was there last.  After the view has
moved that is the room a byte out, and walking him into it drew the old
background under him -- old floors and old brickwork surfacing for a moment
after a scroll.  Neither of the other checks could see it: the stray-ink one
looks outside his rectangle, and the fingerprint counts pixels inside it
against a baseline that was recorded with the fault in place.

This runs each scenario twice, once as it is and once with the camera pinned
where it starts, and compares the two screens byte for byte with the moved
one shifted back by the camera.  They have to be identical: the camera is a
window over the room and nothing else in the game knows it exists.

    camcheck.py <tap>
"""
import json
import os
import sys

import runtap
import zxscreen

HERE = os.path.dirname(os.path.abspath(__file__))

SCENES = [
    # These stay inside the first room on purpose: they are a check on the
    # drawing, and walking out of it would be a check on something else.
    ('walk left',  44, ['left@1-60']),
    ('walk right', 60, ['right@1-60']),
    ('fall+climb', 55, ['left@1-20', 'down@26-34', 'up@46-120']),
    ('jump up',    40, ['up@14-20']),
    ('run jump',   17, ['left@1-14', 'up@8-12']),
]


def run(tap, sym, pin, keys, upto):
    """[(camera at the moment the screen was written, the screen)]"""
    cpu = runtap.boot(tap)
    if pin:
        cpu.mem[sym['camera']] = 0xC9           # ret: the view never moves
    script = runtap.parse(keys)
    out = []
    for n in range(1, upto):
        # show_rect runs at the top of the frame, before the camera decides,
        # so what is on the screen belongs to the camera as it was.
        cam = cpu.mem[sym['cam']]
        runtap.game_frame(cpu, sym['main'], runtap.held(script, n))
        out.append((cam, bytes(cpu.mem[16384:16384 + 6144])))
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    tap = argv[1]
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    total = 0
    for name, upto, keys in SCENES:
        moved = run(tap, sym, False, keys, upto)
        pinned = run(tap, sym, True, keys, upto)
        bad, first = 0, None
        for n, ((cam, a), (_, b)) in enumerate(zip(moved, pinned), 1):
            if n < 6:                           # the first frames are startup
                continue
            d = [(y, c) for y in range(192) for c in range(32 - cam)
                 if a[zxscreen.bitmap_offset(c, y)]
                 != b[zxscreen.bitmap_offset(c + cam, y)]]
            if d:
                bad += 1
                if first is None:
                    first = ' first at frame %d, camera %d, %d bytes, %s' % (
                        n, cam, len(d), d[:3])
        total += bad
        print('%-12s %d differing frames%s' % (name, bad, first or ''))
    print('%d in all' % total)
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
