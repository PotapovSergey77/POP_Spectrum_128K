"""
Render all 30 background tile types in one screen, as a reference sheet.

A room holds exactly 30 blocks and BGDATA.S defines exactly 30 piece ids, so
the whole vocabulary fits on a single screen: type 0..9 across the top row,
10..19 in the middle, 20..29 along the bottom.

Neighbours still matter -- a piece's B section is drawn by the block to its
right and its C section by the block below and left -- so a tile here is not
identical to the same tile in a real room.  It is a catalogue, not a mockup.

Usage: tileatlas.py [out.png]
"""
import os
import sys

import poplevel
import renderroom
import zxscreen

NAMES = [
    'space', 'floor', 'spikes', 'posts', 'gate',
    'dpressplate', 'pressplate', 'panelwif', 'pillarbottom', 'pillartop',
    'flask', 'loose', 'panelwof', 'mirror', 'rubble',
    'upressplate', 'exit', 'exit2', 'slicer', 'torch',
    'block', 'bones', 'sword', 'window', 'window2',
    'archbot', 'archtop1', 'archtop2', 'archtop3', 'archtop4',
]


class Atlas:
    """Stands in for a Level: one screen holding every piece id in order."""

    def screen(self, num):
        return bytes(range(30)), bytes(30)


def main(argv):
    out = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'atlas.png')
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)

    room = renderroom.Room('DUN')
    room.build(Atlas(), 1)
    px = room.to_pixels()

    screen = zxscreen.build(zxscreen.window(px, 12), 0x05)
    zxscreen.preview(screen, out)

    for row in range(3):
        print('row %d: %s' % (row, ', '.join(
            '%d=%s' % (row * 10 + c, NAMES[row * 10 + c]) for c in range(10))))
    print('-> %s' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
