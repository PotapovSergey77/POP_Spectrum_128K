"""
Dump every background tile type as a text grid, for editing by coordinate.

Each type is rendered in a standard context -- floor to its left and right,
floor along the row below -- so its B section (drawn by the block to its
right) and C section (drawn by the block below and left) both appear.  The
grid covers the tile's full block: 28 columns across, and the 63 scanlines
from the top of the block down to its floor line.

Row numbers are screen scanlines, columns are 0..27 within the tile, which is
the coordinate system used to describe edits.

Usage: tilegrid.py [out.txt] [type]
       with a type given, that one grid goes to stdout instead.
"""
import os
import sys

import bgdata as bg
import renderroom

NAMES = [
    'space', 'floor', 'spikes', 'posts', 'gate',
    'dpressplate', 'pressplate', 'panelwif', 'pillarbottom', 'pillartop',
    'flask', 'loose', 'panelwof', 'mirror', 'rubble',
    'upressplate', 'exit', 'exit2', 'slicer', 'torch',
    'block', 'bones', 'sword', 'window', 'window2',
    'archbot', 'archtop1', 'archtop2', 'archtop3', 'archtop4',
]

# Only the floor band is under edit: the twelve scanlines of the vertical
# face plus the three of the surface.  Everything above is left alone.
Y_FROM, Y_TO = 51, 65

TILE = 4                      # the column under test
ROW = 0                       # top band, so the scanlines are the 3..65 we
                              # have been quoting coordinates in all along


class Bench:
    """Stands in for a Level: one tile under test, floor all around it."""

    def __init__(self, tile_type):
        types = bytearray(30)
        for c in range(10):
            types[ROW * 10 + c] = bg.floor
            types[(ROW + 1) * 10 + c] = bg.floor
            types[(ROW + 2) * 10 + c] = bg.floor
        types[ROW * 10 + TILE] = tile_type
        self.types = bytes(types)

    def screen(self, num):
        return self.types, bytes(30)


def grid(tile_type):
    bench = Bench(tile_type)
    room = renderroom.Room('DUN')
    room.build(bench, 1)
    px = renderroom.normalise_hatch(room.to_pixels(), bench, 1)
    px = renderroom.seam_pass(px, bench, 1)

    x0 = TILE * renderroom.BLOCK_PX
    out = ['%2d  %s' % (tile_type, NAMES[tile_type]),
           '      ' + ''.join(str(i % 10) for i in range(28))]
    for y in range(Y_FROM, Y_TO + 1):
        line = ''.join('#' if px[y][x] else '.'
                       for x in range(x0, x0 + renderroom.BLOCK_PX))
        out.append('y=%3d %s' % (y, line))
    return '\n'.join(out)


def compare(a, b):
    """Two tile grids side by side, for reading off differences."""
    left = grid(a).splitlines()
    right = grid(b).splitlines()
    return '\n'.join('%-36s%s' % (l, r) for l, r in zip(left, right))


def main(argv):
    if len(argv) > 3:
        print(compare(int(argv[2]), int(argv[3])))
        return 0
    if len(argv) > 2:
        print(compare(1, int(argv[2])))
        return 0
    out = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'tiles.txt')
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w') as f:
        f.write(__doc__.strip() + '\n\n')
        for t in range(30):
            f.write(grid(t) + '\n\n')
    print('%s (%d types)' % (out, 30))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
