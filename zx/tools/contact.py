"""
Contact sheet of a level: all 24 screens on one image, numbered.

Rooms that no link leads to are left blank -- a level rarely uses all 24.

Usage: contact.py <LEVEL file> [out.png]
"""
import os
import sys

import gridmap
import poplevel
import pngwrite
import renderroom
import zxscreen

COLS, GAP = 4, 6
INK, PAPER, LABEL, EDGE = (0, 255, 255), (0, 0, 0), (255, 220, 0), (60, 60, 60)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    level = poplevel.Level(argv[1])
    out = argv[2] if len(argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'contact.png')

    W, H = zxscreen.WIDTH, zxscreen.HEIGHT
    rows_n = (24 + COLS - 1) // COLS
    CW, CH = W + GAP, H + GAP
    canvas = [[PAPER] * (COLS * CW) for _ in range(rows_n * CH)]

    used = set()
    for s in range(1, 25):
        types, _ = level.screen(s)
        if any(b & poplevel.IDMASK for b in types):
            used.add(s)

    for s in range(1, 25):
        cx, cy = ((s - 1) % COLS) * CW, ((s - 1) // COLS) * CH
        for x in range(W):
            canvas[cy][cx + x] = EDGE
        if s in used:
            room = renderroom.Room('DUN')
            room.build(level, s)
            px = renderroom.normalise_hatch(room.to_pixels(), level, s)
            px = renderroom.seam_pass(px, level, s)
            view = zxscreen.window(px, 12)
            for y in range(H):
                for x in range(W):
                    if view[y][x]:
                        canvas[cy + y][cx + x] = INK
        for i, d in enumerate('%02d' % s):
            for gy, line in enumerate(gridmap.DIGITS[int(d)]):
                for gx, ch in enumerate(line):
                    if ch == '#':
                        canvas[cy + 2 + gy][cx + 2 + i * 4 + gx] = LABEL

    rows = []
    for line in canvas:
        row = bytearray()
        for rgb in line:
            row.extend(bytes(rgb))
        rows.append(bytes(row))
    pngwrite.write_rgb(out, COLS * CW, rows_n * CH, rows)
    print('%s: занятых экранов %d из 24 -> %s'
          % (os.path.basename(argv[1]), len(used), out))
    print('старт принца: экран %d, блок %d' % level.kid_start[:2])
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
