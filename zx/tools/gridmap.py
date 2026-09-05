"""
Render a room with its block grid drawn over it and every cell numbered, so a
position can be pointed at without ambiguity.

Cells are labelled "<row><col>" -- row 0 at the top, column 0 at the left --
which is the same numbering the level data uses.

Usage: gridmap.py <LEVEL file> [screen] [camera] [out.png]
"""
import os
import sys

import poplevel
import pngwrite
import renderroom
import zxscreen

# 3x5 digits, one string per row of the glyph.
DIGITS = [
    ['###', '#.#', '#.#', '#.#', '###'], ['..#', '..#', '..#', '..#', '..#'],
    ['###', '..#', '###', '#..', '###'], ['###', '..#', '###', '..#', '###'],
    ['#.#', '#.#', '###', '..#', '..#'], ['###', '#..', '###', '..#', '###'],
    ['###', '#..', '###', '#.#', '###'], ['###', '..#', '..#', '..#', '..#'],
    ['###', '#.#', '###', '#.#', '###'], ['###', '#.#', '###', '..#', '###'],
]

SCALE = 3
GRID = (110, 0, 0)
LABEL = (255, 220, 0)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    level = poplevel.Level(argv[1])
    scrnum = int(argv[2]) if len(argv) > 2 else level.kid_start[0]
    camera = int(argv[3]) if len(argv) > 3 else 12
    out = argv[4] if len(argv) > 4 else pngwrite.build_png('gridmap.png')

    room = renderroom.Room('DUN')
    room.build(level, scrnum)
    px = renderroom.normalise_hatch(room.to_pixels(), level, scrnum)
    px = renderroom.seam_pass(px, level, scrnum)
    view = zxscreen.window(px, camera)

    W, H = zxscreen.WIDTH, zxscreen.HEIGHT
    canvas = [[(0, 255, 255) if view[y][x] else (0, 0, 0) for x in range(W)]
              for y in range(H)]

    for x in range(W):
        if (x + camera) % renderroom.BLOCK_PX == 0:
            for y in range(H):
                if not view[y][x]:
                    canvas[y][x] = GRID
    for y in (2, 65, 128, 191):
        for x in range(W):
            if not view[y][x]:
                canvas[y][x] = GRID

    for row in range(3):
        for col in range(10):
            ox = col * renderroom.BLOCK_PX - camera + 2
            oy = renderroom.BLOCKBOT[row] + 3
            for i, d in enumerate((row, col)):
                for gy, line in enumerate(DIGITS[d]):
                    for gx, ch in enumerate(line):
                        x, y = ox + i * 4 + gx, oy + gy
                        if ch == '#' and 0 <= x < W and 0 <= y < H:
                            canvas[y][x] = LABEL

    rows = []
    for line in canvas:
        out_row = bytearray()
        for rgb in line:
            out_row.extend(bytes(rgb) * SCALE)
        for _ in range(SCALE):
            rows.append(bytes(out_row))
    pngwrite.write_rgb(out, W * SCALE, H * SCALE, rows)

    types, _ = level.screen(scrnum)
    ids = [b & poplevel.IDMASK for b in types]
    for row in range(3):
        print('ряд %d: %s' % (row, ' '.join('%d%d=%-2d' % (row, c, ids[row * 10 + c])
                                            for c in range(10))))
    print('-> %s' % out)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
