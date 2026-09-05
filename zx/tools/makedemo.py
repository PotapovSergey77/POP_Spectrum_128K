"""
Build a .tap that shows Prince of Persia rooms on a ZX Spectrum.

A room is assembled at the Apple II's 280x192 and a 256-pixel window is cut
out of it -- the same window the camera will pan across at run time, since a
room is 280 px wide and the Spectrum screen is 256, leaving 24 px of travel.

The look is settled: the original Apple art is drawn exactly as authored, in
normal cyan on black.  Reworking the dither was tried and dropped -- the clear
column at each block boundary is the brick joint, and neighbouring floor tiles
carry different decorations, so anything that repaints pieces one at a time
pulls the wall apart.

An autostarting BASIC loader shows each room and waits for a key, so no Z80
code is needed yet -- this is here to look at, not to run.

Usage: makedemo.py <LEVEL file> [screen] [camera] [out.tap]
"""
import os
import sys

import bgdata as bg
import popframe
import poplevel
import renderroom
import taputil
import zxscreen

CAMERA_MAX = renderroom.WIDTH_BYTES * 7 - zxscreen.WIDTH   # 280 - 256 = 24

STONE = 0x05            # normal cyan ink on black: closest to the original

# Further rooms on the same tape.
TOUR = [('LEVEL8', 5), ('LEVEL2', 5), ('LEVEL3', 1)]

# Tile types to show on a synthetic screen: the type alternating with plain
# floor along the top row, so the two can be compared directly.
BENCH = [bg.spikes, bg.pressplate, bg.dpressplate]


class Bench:
    """Stands in for a Level: one tile type set against plain floor."""

    def __init__(self, tile_type):
        types = bytearray(30)
        for c in range(10):
            types[c] = tile_type if c % 2 else bg.floor
            types[10 + c] = bg.floor
            types[20 + c] = bg.floor
        self.types = bytes(types)

    def screen(self, num):
        return self.types, bytes(30)


def loader(name):
    """
    10 BORDER 0: PAPER 0: INK 7: CLS
    20 LOAD ""SCREEN$: PAUSE 0: GO TO 20
    """
    t = taputil
    l10 = (bytes([t.BORDER]) + t.number(0) + b':' +
           bytes([t.PAPER]) + t.number(0) + b':' +
           bytes([t.INK]) + t.number(7) + b':' +
           bytes([t.CLS]))
    l20 = (bytes([t.LOAD]) + b'""' + bytes([t.SCREEN_D]) + b':' +
           bytes([t.PAUSE]) + t.number(0) + b':' +
           bytes([t.GOTO]) + t.number(20))
    return t.program_file(name, t.line(10, l10) + t.line(20, l20), autostart=10)


# Where the prince is put on the demo screen: block row, block column, and
# the frame to draw him in (15 is "stand").
PRINCE = (0, 5, 15)


def place_prince(px, row, col, frame_num):
    """
    Composite a character frame into the room.

    Both coordinates come from the tables: CharY is FloorY for the row, which
    puts the feet on the floor's centre plane rather than on its lower edge,
    and CharX is BlockEdge + angle + 7.
    """
    frame = popframe.load()[frame_num]
    img = popframe.image(frame)
    sprite = [list(line) for line in img.pixels()]
    h, w = len(sprite), len(sprite[0])
    x0 = popframe.screen_x(popframe.char_x(col)) - popframe.BLOCK_PIXELS // 2 - w // 2
    ybot = popframe.char_y(row)
    for j, line in enumerate(sprite):
        y = ybot - h + 1 + j
        if not 0 <= y < len(px):
            continue
        for i, v in enumerate(line):
            if v and 0 <= x0 + i < len(px[0]):
                px[y][x0 + i] = 1
    return px


def render(level, scrnum, camera, edge='none', col=27, prince=None):
    renderroom.EDGE_MODE = edge
    renderroom.EDGE_COL = col
    room = renderroom.Room('DUN')
    room.build(level, scrnum)
    px = renderroom.normalise_hatch(room.to_pixels(), level, scrnum)
    px = renderroom.seam_pass(px, level, scrnum)
    if prince:
        px = place_prince(px, *prince)
    return zxscreen.build(zxscreen.window(px, camera), STONE)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    level = poplevel.Level(argv[1])
    scrnum = int(argv[2]) if len(argv) > 2 else level.kid_start[0]
    camera = int(argv[3]) if len(argv) > 3 else CAMERA_MAX // 2
    out = argv[4] if len(argv) > 4 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'pop.tap')
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    camera = max(0, min(CAMERA_MAX, camera))

    base = os.path.basename(argv[1])
    screens = [('%s-s%d' % (base, scrnum), render(level, scrnum, camera))]

    levels = os.path.dirname(os.path.abspath(argv[1]))
    for fname, num in TOUR:
        path = os.path.join(levels, fname)
        if not os.path.exists(path):
            continue
        screens.append(('%s-s%d' % (fname, num),
                        render(poplevel.Level(path), num, camera)))

    screens.insert(1, ('prince', render(level, scrnum, camera, prince=PRINCE)))

    for t in BENCH:
        screens.append(('bench-%02d' % t, render(Bench(t), 1, camera)))

    name = os.path.splitext(os.path.basename(out))[0][:10]
    stem = os.path.splitext(out)[0]
    blocks = [loader(name)]
    for label, screen in screens:
        blocks.append(taputil.code_file(name, screen, 16384))
        zxscreen.preview(screen, '%s_%s.png' % (stem, label))
    with open(out, 'wb') as f:
        f.write(b''.join(blocks))

    print('%s (%d bytes, %d screens, camera %d px, ink $%02x)'
          % (out, os.path.getsize(out), len(screens), camera, STONE))
    for i, (label, _) in enumerate(screens, 1):
        print('  %d. %s' % (i, label))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
