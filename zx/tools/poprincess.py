"""
The princess's room, off the Apple's own disk, for the opening scene.

LoadStage2A in MASTER.S reads side A tracks 29 to 31 whole and track 32's
first nine sectors into auxmem $6000-$9EFF, and chtable7 -- the vizier's
last frames -- from track 28's last five sectors to $9F00.  In there:

    chtable6    $6000   the princess, the vizier, the hourglass, the post,
                        the torch flames and the stars (IMG.CHTAB6.A)
    pacProom    $8400   the room, a single hi-res screen crunched for
                        SNGEXPAND in UNPACK.S

SNGEXPAND ("lifted directly from DRAZ") fills page 1 column by column from
the right, a column's forty bytes taken in an interleaved order of lines;
the data is bytes as they are, or $FE, a count and a byte for a run.  Every
byte gets its top bit, the palette bit, set.

    poprincess.py [dir]    the room as a PNG, to look at
"""
import os
import sys

import pngwrite
import popdisk
import popimg

HERE = os.path.dirname(os.path.abspath(__file__))
DISK = os.path.join(HERE, '..', 'disk', 'Prince of Persia side A.nib')

CHTABLE6, CHTABLE7 = 0x6000, 0x9F00
PACPROOM = 0x84


def memory():
    """64K of auxmem as LoadStage2A leaves it."""
    disk = popdisk.Disk(DISK)
    mem = bytearray(0x10000)
    for i, t in enumerate((29, 30, 31)):
        mem[0x6000 + i * 0x1200:0x6000 + (i + 1) * 0x1200] = disk.track(t)
    mem[0x9600:0x9F00] = disk.track(32)[:9 * 256]
    mem[0x9F00:0xA400] = disk.track(28)[13 * 256:18 * 256]
    return bytes(mem)


def sng_expand(mem, hi=PACPROOM):
    """SNGEXPAND, step for step: hi-res page 1, $2000-$3FFF."""
    out = bytearray(0x10000)
    pac = hi << 8
    v8, va, v9, vb = 0xFE, 0, 0, 0
    y = 0x27
    while y >= 0:
        v3v2 = 0x2078                       # :4
        while True:
            v3v2 = (v3v2 - 0x28) & 0xFFFF   # :0
            v5v4 = (v3v2 + 0x400) & 0xFFFF  # :1
            while True:
                v5v4 = (v5v4 - 0x80) & 0xFFFF       # :2
                v5 = v5v4 >> 8
                pic = ((v5 + 0x20) << 8) | (v5v4 & 0xFF)   # :3
                while True:
                    pic -= 0x400                    # :5
                    if not va & 0x80:               # :6
                        vb = mem[pac]
                        if vb == v8:
                            v9 = mem[pac + 1]
                            vb = mem[pac + 2]
                            pac += 3
                            va = 0x80
                        else:
                            out[pic + y] = vb | 0x80    # :10
                            pac += 1
                            if (pic >> 8) == v5:
                                break
                            continue
                    out[pic + y] = vb | 0x80            # :11
                    v9 = (v9 - 1) & 0xFF
                    if v9 == 0:
                        va = 0
                    if (pic >> 8) == v5:                # :13
                        break
                if (v5v4 & 0xFF) != (v3v2 & 0xFF) or v5 != (v3v2 >> 8):
                    continue
                break
            if v3v2 & 0xFF:
                continue
            break
        y -= 1
    return out


def line_address(y):
    """YLO/YHI in HRTABLES.S."""
    lo = ((y >> 3) & 1) * 0x80 + (y >> 6) * 0x28
    hi = 0x20 + 4 * (y & 7) + ((y >> 4) & 3)
    return hi << 8 | lo


def hires_bits(page):
    """192 lines of 280 dots, and of 40 palette bits a line."""
    dots, pal = [], []
    for y in range(192):
        a = line_address(y)
        row = []
        for b in page[a:a + 40]:
            row.extend((b >> i) & 1 for i in range(7))
        dots.append(row)
        pal.append([(b >> 7) & 1 for b in page[a:a + 40]])
    return dots, pal


def main(argv):
    out = argv[1] if len(argv) > 1 else '.'
    mem = memory()
    page = sng_expand(mem)
    dots, pal = hires_bits(page)
    rows = []
    for y in range(192):
        line = bytearray()
        for x in range(280):
            line += bytes((255, 255, 255) if dots[y][x] else (0, 0, 0)) * 2
        rows.append(bytes(line))
        rows.append(bytes(line))
    path = os.path.join(out, 'proom.png')
    pngwrite.write_rgb(path, 560, 384, rows)
    print(path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
