"""
The Apple's title screens as Spectrum screens.

poptitles.py unpacks them: 140 colours across and 192 lines.  The lines stay
as they are; across, the 140 are spread over 256 pixels, each pixel taking
the colour under its middle.  Then every 8x8 cell gets the two Spectrum
colours, of one brightness, that stand closest to what is in it, and each
pixel the nearer of the two.

    titlescr.py [dir]      the screens as .scr files and PNGs, to look at

Out, through screen(name): 6912 bytes, a SCREEN$.
"""
import os
import sys

import pngwrite
import poptitles
import zxscreen

LEVELS = (0xD7, 0xFF)       # a Spectrum's normal and bright


def zx_rgb(colour, bright):
    v = LEVELS[bright]
    return ((v if colour & 2 else 0), (v if colour & 4 else 0),
            (v if colour & 1 else 0))


def _dist(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


# The Spectrum colour each Apple colour is drawn in, (colour, bright), by
# hue first: the Apple's pale mint is the Spectrum's cyan, not its grey.
SPECTRUM = [(0, 0),     # black
            (2, 0),     # deep red
            (2, 0),     # brown
            (6, 0),     # orange
            (4, 0),     # dark green
            (7, 0),     # grey
            (4, 1),     # green
            (6, 1),     # yellow
            (1, 0),     # dark blue
            (3, 1),     # purple
            (7, 0),     # grey
            (3, 1),     # pink
            (1, 1),     # medium blue
            (5, 0),     # light blue
            (5, 1),     # aqua
            (7, 1)]     # white

# DIST[bright][apple][zx]: what it costs to draw an Apple colour in a
# Spectrum one -- nothing in its own, a little in its own at the other
# brightness, and otherwise how far apart the two Spectrum colours are.
DIST = [[[0 if c == SPECTRUM[i][0] and (br == SPECTRUM[i][1] or not c) else
          1000 if c == SPECTRUM[i][0] else
          _dist(zx_rgb(*SPECTRUM[i]), zx_rgb(c, br))
          for c in range(8)] for i in range(16)] for br in (0, 1)]
# And CHECK, the black of a check with a colour: black too, but it can give
# way to the colour at a quarter of the cost, where a cell has letters or
# lines over the check and no room for three colours.
CHECK = 16
for _d in DIST:
    _d.append(list(_d[0]))


def spread(cols, dots):
    """192 lines of 140 Apple colours to 192 lines of 256: each pixel the
    colour under its middle dot.  Where that colour is the white of drawn
    lines and letters, whose dots are finer than the colours, the dot
    itself says: lit, white; dark, the ground either side of the white.
    The Apple's check of a colour and black is drawn as a Spectrum check,
    pixel by pixel, not as whatever the stretch makes of it."""
    chk = checks(cols)
    pick = [(2 * x + 1) * 560 // 512 for x in range(256)]
    out = []
    for y, (line, lit) in enumerate(zip(cols, dots)):
        row = []
        for x, d in enumerate(pick):
            k = d >> 2
            c = line[k]
            if chk[y][k]:
                c = chk[y][k] if (x + y) & 1 else CHECK
            elif c == 15 and not lit[d]:
                c = 0
                for j in (1, -1, 2, -2, 3, -3):
                    if 0 <= k + j < 140 and line[k + j] != 15:
                        c = line[k + j]
                        break
            row.append(c)
        out.append(row)
    return out


def checks(cols):
    """For each colour, the colour of the check with black it is part of,
    or nought: a colour with black all round it and itself across the
    corners, or a black the other way about -- three of the four will do,
    the fourth may be the edge of what lies over it."""
    h, w = len(cols), len(cols[0])
    out = [[0] * w for _ in range(h)]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            v = cols[y][x]
            n = (cols[y - 1][x], cols[y + 1][x], cols[y][x - 1], cols[y][x + 1])
            d = (cols[y - 1][x - 1], cols[y - 1][x + 1], cols[y + 1][x - 1], cols[y + 1][x + 1])
            if v == 0:
                for c in set(n):
                    if c and n.count(c) >= 3 and d.count(0) >= 3:
                        out[y][x] = c
            elif n.count(0) >= 3 and d.count(v) >= 3:
                out[y][x] = v
    return out


# Half-lit colours: two or three of their four dots on.
PART = [i for i in range(16) if bin(i).count('1') in (2, 3)]


def unfringe(cols):
    """White drawn in dots finer than the colours leaves a colour at either
    side of it -- the letters most of all.  Those are white: a lone colour
    by a white, not a run of it, which is a colour drawn for its own sake."""
    out = [list(line) for line in cols]
    for y, line in enumerate(cols):
        for x in range(1, len(line) - 1):
            v = line[x]
            if v in PART and 15 in (line[x - 1], line[x + 1]) and                     v not in (line[x - 1], line[x + 1]):
                out[y][x] = 15
    return out


# The story screens: white letters, drawn in dots, on a ground that is a dot
# in every other colour, colour 1 -- deep red -- in a check with black; in a
# panel inside the border, colours 8 to 131 and lines 14 to 167.  In there a
# pixel is a letter's where its middle dot is lit and is not the ground's.
STORY = ('prolog', 'sumup')
PANEL = (8, 14, 132, 168)
GROUND = 1


def story(pix, cols, dots):
    pick = [(2 * x + 1) * 560 // 512 for x in range(256)]
    for y in range(PANEL[1], PANEL[3]):
        for x, d in enumerate(pick):
            k = d >> 2
            if PANEL[0] <= k < PANEL[2]:
                lit = dots[y][d] and cols[y][k] != GROUND
                pix[y][x] = 15 if lit else GROUND


def credit(pix, apple, cols, dots, splash):
    """The credits and the title are white letters in dots, laid over the
    splash on a ground of deep red and black.  Where a credit has changed a
    byte of the splash, a pixel of anything but that ground is a letter's:
    white where its dot is lit, the ground's check where not."""
    pick = [(2 * x + 1) * 560 // 512 for x in range(256)]
    for y in range(192):
        for x, d in enumerate(pick):
            if apple[y][d // 7] == splash[y][d // 7]:
                continue
            if cols[y][d >> 2] in (0, GROUND):
                continue
            if dots[y][d]:
                pix[y][x] = 15
            else:
                pix[y][x] = GROUND if (x + y) & 1 else CHECK


def cell(pix, cx, cy):
    """(ink, paper, bright, [64 bits]) for the cell."""
    count = [0] * 17
    for y in range(cy * 8, cy * 8 + 8):
        for x in range(cx * 8, cx * 8 + 8):
            count[pix[y][x]] += 1
    used = [i for i in range(17) if count[i]]
    best = None
    for br in (0, 1):
        d = DIST[br]
        for a in range(8):
            for b in range(a, 8):
                cost = sum(count[i] * min(d[i][a], d[i][b]) for i in used)
                if best is None or cost < best[0]:
                    best = (cost, a, b, br)
    _, a, b, br = best
    d = DIST[br]
    bits = [1 if d[pix[y][x]][b] < d[pix[y][x]][a] else 0
            for y in range(cy * 8, cy * 8 + 8)
            for x in range(cx * 8, cx * 8 + 8)]
    if sum(bits) > 32:       # the paper covers more of the cell
        a, b = b, a
        bits = [1 - v for v in bits]
    return b, a, br, bits


def screen(name):
    apple = poptitles.screen(name)
    cols, dots = poptitles.colours(apple), poptitles.dots(apple)
    pix = spread(unfringe(cols), dots)
    if name in STORY:
        story(pix, cols, dots)
    elif name != 'splash':
        credit(pix, apple, cols, dots, poptitles.screen('splash'))
    rows = [[0] * 256 for _ in range(192)]
    attrs = bytearray(768)
    for cy in range(24):
        for cx in range(32):
            ink, paper, br, bits = cell(pix, cx, cy)
            if ink == paper:
                bits = [0] * 64
            for k, v in enumerate(bits):
                rows[cy * 8 + k // 8][cx * 8 + k % 8] = v
            attrs[cy * 32 + cx] = br << 6 | paper << 3 | ink
    return zxscreen.build(rows, bytes(attrs))


def preview(scr, path):
    rows = []
    for y in range(192):
        line = bytearray()
        for x in range(256):
            a = scr[6144 + (y >> 3) * 32 + (x >> 3)]
            on = scr[zxscreen.bitmap_offset(x >> 3, y)] & (0x80 >> (x & 7))
            c = zx_rgb(a & 7 if on else (a >> 3) & 7, (a >> 6) & 1)
            line.extend(bytes(c) * 2)
        rows.append(bytes(line))
        rows.append(bytes(line))
    pngwrite.write_rgb(path, 512, 384, rows)


# ---------------------------------------------------------------- packing
#
# What intro.asm unpacks, onto a screen, a token at a time:
#
#   0nnnnnnn             n + 1 bytes as they come
#   10nnnnnn lo hi       n + 3 bytes copied from lo hi bytes back
#   11nnnnnn lo          (nnnnnn << 8 | lo) + 1 bytes left as they are
#   11111111             the end
#
# A whole screen starts from nothing; a credit from the splash under it,
# and leaves the bytes that do not change.

def pack(target, base=None):
    out = bytearray()
    lit = bytearray()
    heads = {}
    n = len(target)

    def flush():
        while lit:
            chunk = lit[:128]
            out.append(len(chunk) - 1)
            out.extend(chunk)
            del lit[:128]

    def remember(i):
        if i + 3 <= n:
            heads.setdefault(bytes(target[i:i + 3]), []).append(i)

    i = 0
    while i < n:
        if base is not None and target[i] == base[i]:
            j = i
            while j < n and target[j] == base[j] and j - i < 0x3F00:
                j += 1
            if j - i >= 3 or j == n:
                flush()
                run = j - i
                out += bytes([0xC0 | (run - 1) >> 8, (run - 1) & 0xFF])
                for k in range(i, j):
                    remember(k)
                i = j
                continue
        best, at = 0, 0
        for c in reversed(heads.get(bytes(target[i:i + 3]), [])[-48:]):
            m = 0
            while i + m < n and m < 66 and target[c + m] == target[i + m]:
                m += 1
            if m > best:
                best, at = m, c
                if m == 66:
                    break
        if best >= 3:
            flush()
            d = i - at
            out += bytes([0x80 | (best - 3), d & 0xFF, d >> 8])
            for k in range(i, i + best):
                remember(k)
            i += best
        else:
            lit.append(target[i])
            remember(i)
            i += 1
    flush()
    out.append(0xFF)
    return bytes(out)


def unpack(data, base=None):
    """What intro.asm makes of it -- to check the packing against."""
    scr = bytearray(base if base is not None else bytes(6912))
    p = d = 0
    while True:
        t = data[p]
        p += 1
        if t == 0xFF:
            return bytes(scr)
        if t < 0x80:
            scr[d:d + t + 1] = data[p:p + t + 1]
            p += t + 1
            d += t + 1
        elif t < 0xC0:
            src = d - (data[p] | data[p + 1] << 8)
            p += 2
            for _ in range((t & 0x3F) + 3):
                scr[d] = scr[src]
                d += 1
                src += 1
        else:
            d += ((t & 0x3F) << 8 | data[p]) + 1
            p += 1


# The screens intro.asm shows, in the order they are packed.
INTRO = [('splash', None), ('presents', 'splash'), ('byline', 'splash'),
         ('title', 'splash'), ('prolog', None), ('sumup', None)]


def intro_blob():
    """[(name, offset)], and the packed screens one after another."""
    blob = bytearray()
    at = []
    screens = {}
    for name, base in INTRO:
        screens[name] = screen(name)
        b = screens[base] if base else None
        data = pack(screens[name], b)
        assert unpack(data, b) == screens[name], name
        at.append((name, len(blob)))
        blob += data
    return at, bytes(blob)


def build(cache_dir):
    """intro_blob(), worked out once for this disk and these files."""
    import hashlib
    import json
    h = hashlib.sha1()
    h.update(open(poptitles.DISK, 'rb').read())
    for f in (__file__, poptitles.__file__):
        h.update(open(f, 'rb').read())
    key = h.hexdigest()[:16]
    bpath = os.path.join(cache_dir, 'intro.%s.bin' % key)
    jpath = os.path.join(cache_dir, 'intro.%s.json' % key)
    if os.path.exists(bpath) and os.path.exists(jpath):
        return [tuple(x) for x in json.load(open(jpath))], open(bpath, 'rb').read()
    at, blob = intro_blob()
    for old in os.listdir(cache_dir):
        if old.startswith('intro.'):
            os.remove(os.path.join(cache_dir, old))
    open(bpath, 'wb').write(blob)
    json.dump(at, open(jpath, 'w'))
    return at, blob


def main(argv):
    out = argv[1] if len(argv) > 1 else '.'
    for name in poptitles.NAMES:
        scr = screen(name)
        open(os.path.join(out, 'zx_%s.scr' % name), 'wb').write(scr)
        preview(scr, os.path.join(out, 'zx_%s.png' % name))
        print(name)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
