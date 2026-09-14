"""
The title screens, off the Apple's own disk, unpacked the way UNPACK.S does.

LoadStage1A in MASTER.S reads side A from track 22, eighteen sectors a track,
into auxmem $4000-$99FF, and tracks 27 and 28 into mainmem $6000-$83FF.  In
there, by MASTER.S's "hi bytes of crunch data":

    pacSplash   $40 aux    the palace, a whole double hi-res screen
    delPresents $70 aux    "Broderbund Software presents", laid over it
    delByline   $72 aux    "A game by Jordan Mechner"
    delTitle    $74 aux    "Prince of Persia"
    pacProlog   $7c aux    the story, part 1, a whole screen
    pacSumup    $60 main   the story, part 2

DBLEXPAND unpacks a whole screen column by column, even lines then odd; a
column is a run of bytes, each either one byte (bit 7 clear) or a byte
(bit 7 set, and taken off) and a count.  DELTAEXPPOP lays changes over the screen there: a byte with bit 7
clear is one byte, a count and a byte a run of it -- a byte with bit 7 set in
a run is a gap -- and a count of nought a new column and line; $FF ends it.
The column runs down to line 191 and then on to the next column.

A double hi-res screen is 80 bytes a line, aux and main by turns, seven bits
each from bit 0: 560 dots, and a colour for every four of them.

    poptitles.py [dir]     the screens as PNGs, to look at
"""
import os
import sys

import pngwrite
import popdisk

HERE = os.path.dirname(os.path.abspath(__file__))
DISK = os.path.join(HERE, '..', 'disk', 'Prince of Persia side A.nib')

SPLASH, PRESENTS, BYLINE, TITLE, PROLOG = 0x40, 0x70, 0x72, 0x74, 0x7c
SUMUP = 0x60


def memory():
    """(aux, main): 64K each, what LoadStage1A leaves in them."""
    disk = popdisk.Disk(DISK)
    aux, main = bytearray(0x10000), bytearray(0x10000)
    for i, t in enumerate(range(22, 27)):
        at = 0x4000 + i * 0x1200
        aux[at:at + 0x1200] = disk.track(t)
    for i, t in enumerate(range(27, 29)):
        at = 0x6000 + i * 0x1200
        main[at:at + 0x1200] = disk.track(t)
    return bytes(aux), bytes(main)


def blank():
    """A screen: 192 lines of 80 bytes."""
    return [bytearray(80) for _ in range(192)]


def dbl_expand(mem, hi):
    """DBLEXPAND: a whole screen, from (hi << 8) + 1."""
    scr = blank()
    p = (hi << 8) + 1
    for x in range(80):
        for y0 in (0, 1):
            y = y0
            while y < 192:
                b = mem[p]
                if b & 0x80:
                    v, n = b & 0x7f, mem[p + 1]
                    p += 2
                else:
                    n, v = 1, b
                    p += 1
                # ExpClmSeq: a count of nought is 256 times round
                for _ in range(n or 256):
                    if y < 192:
                        scr[y][x] = v
                    y += 2
    return scr


def delta_expand(mem, hi, scr):
    """DeltaExp: the changes at (hi << 8), laid over scr."""
    p = hi << 8
    x = y = 0
    while True:
        b = mem[p]
        if b == 0xff:
            return scr
        if b & 0x80:
            n = b & 0x7f
            if n == 0:
                x, y = mem[p + 1], mem[p + 2]
                p += 3
            else:
                v = mem[p + 1]
                p += 2
                x, y = _seq1(scr, x, y, v, n)
        else:
            p += 1
            x, y = _seq1(scr, x, y, b, 1)
        if x == 0x80:
            return scr


def _seq1(scr, x, y, v, n):
    for _ in range(n):
        if not v & 0x80 and x < 80 and y < 192:
            scr[y][x] = v
        y += 1
        if y == 192:
            y = 0
            x += 1
    return x, y


def screen(name):
    """The screen as it is shown: the splash with its credit, or a story."""
    aux, main = memory()
    if name == 'prolog':
        return dbl_expand(aux, PROLOG)
    if name == 'sumup':
        return dbl_expand(main, SUMUP)
    scr = dbl_expand(aux, SPLASH)
    delta = {'splash': None, 'presents': PRESENTS, 'byline': BYLINE,
             'title': TITLE}[name]
    if delta:
        delta_expand(aux, delta, scr)
    return scr


NAMES = ['splash', 'presents', 'byline', 'title', 'prolog', 'sumup']


def dots(scr):
    """192 lines of 560 dots, 0 or 1."""
    out = []
    for line in scr:
        row = []
        for b in line:
            row.extend((b >> i) & 1 for i in range(7))
        out.append(row)
    return out


# The double hi-res colours, by the four dots' value from the first.
PALETTE = [(0, 0, 0), (0x94, 0x0c, 0x40), (0x64, 0x4c, 0x00), (0xe8, 0x70, 0x1c),
           (0x00, 0x70, 0x28), (0x80, 0x80, 0x80), (0x14, 0xd8, 0x28), (0xd0, 0xd0, 0x2c),
           (0x20, 0x1c, 0xb4), (0xd0, 0x3c, 0xe8), (0x80, 0x80, 0x80), (0xfc, 0x8c, 0xb4),
           (0x2c, 0x80, 0xfc), (0x9c, 0xb4, 0xfc), (0x6c, 0xfc, 0xbc), (0xff, 0xff, 0xff)]


def colours(scr):
    """192 lines of 140 colour indices.  The first of a colour's four dots
    is its top bit: taken the other way round every colour comes out as its
    mirror -- the dusk sky blue, the yellow arch aqua."""
    out = []
    for row in dots(scr):
        out.append([row[4 * k] << 3 | row[4 * k + 1] << 2 | row[4 * k + 2] << 1
                    | row[4 * k + 3] for k in range(140)])
    return out


def main(argv):
    out = argv[1] if len(argv) > 1 else '.'
    for name in NAMES:
        cols = colours(screen(name))
        rows = []
        for line in cols:
            px = bytearray()
            for c in line:
                px.extend(bytes(PALETTE[c]) * 4)
            rows.append(bytes(px))
            rows.append(bytes(px))
        path = os.path.join(out, 'title_%s.png' % name)
        pngwrite.write_rgb(path, 560, 384, rows)
        print(path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
