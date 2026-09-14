"""
The Apple's title screens as Spectrum screens.

poptitles.py unpacks them: 140 colours across, each two of the Apple's
pixels wide, and 192 lines.  Stretched to fit, the Spectrum's 256 pixels
drop a column here and there, and every pattern and letter comes out
bitten.  So nothing is stretched: an Apple colour is two Spectrum pixels,
exactly, and what does not fit is made to fit by the layout instead.

    The border.  The Apple's is tiles 14 pixels wide and 11 or 12 lines tall
    in four colours, which no 8x8 cell can hold.  It is drawn afresh: the
    same tiles, two colours to a cell -- sixteen pixels a tile along the top,
    a single cell down the sides -- and the aqua line inside it in the first
    cells of the picture.  The top band is sixteen lines, two more than the
    Apple's, and the picture loses its first two lines, a black one and one
    of the tapestry.

    The picture.  Inside the border the Apple has 124 colours, the Spectrum
    room for 120: two go at either side, where the tapestry and the pillars
    run under the border anyway.  The knotwork band at the foot is cut the
    same way.

    The letters.  They are drawn in the Apple's dots, four to a colour, two
    to a Spectrum pixel.  Where a letter starts on an odd dot its pixels
    come out different from the same letter elsewhere; so every letter is
    cut out, the same letters found, and each drawn once, the one way that
    keeps most of it, and put down where it was.

Then every 8x8 cell gets the two Spectrum colours, of one brightness, that
cost least for what is in it, and each pixel the nearer of the two.

    titlescr.py [dir]      the screens as .scr files and PNGs, to look at

Out, through screen(name): 6912 bytes, a SCREEN$.
"""
import os
import sys

import pngwrite
import poptitles
import zxscreen

LEVELS = (0xD7, 0xFF)       # a Spectrum's normal and bright

BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)


def zx_rgb(colour, bright):
    v = LEVELS[bright]
    return ((v if colour & 2 else 0), (v if colour & 4 else 0),
            (v if colour & 1 else 0))


def _dist(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


# The Spectrum colour each Apple colour is drawn in, (colour, bright), by
# hue first: the Apple's pale mint is the Spectrum's cyan, not its grey.
SPECTRUM = [(BLACK, 0),     # black
            (RED, 0),       # deep red
            (RED, 0),       # brown
            (YELLOW, 0),    # orange
            (GREEN, 0),     # dark green
            (WHITE, 0),     # grey
            (GREEN, 1),     # green
            (YELLOW, 1),    # yellow
            (BLUE, 0),      # dark blue
            (MAGENTA, 1),   # purple
            (WHITE, 0),     # grey
            (MAGENTA, 1),   # pink
            (BLUE, 1),      # medium blue
            (CYAN, 0),      # light blue
            (CYAN, 1),      # aqua
            (WHITE, 1)]     # white

# Past the Apple's sixteen, what the layout draws: letters, which a cell
# must keep above all, and Spectrum colours by number.
LETTER = 16
ZX = 17                     # ZX + colour * 2 + bright
HEAVY = ZX + 16             # the same, but a cell must keep them


def _cost(i, c, br):
    if i == LETTER:
        return 0 if c == WHITE else 4 * _cost(15, c, br) + 200000
    if i >= HEAVY:
        return 8 * _cost(i - 16, c, br)
    if i >= ZX:
        want = ((i - ZX) >> 1, (i - ZX) & 1)
    else:
        want = SPECTRUM[i]
    if c == want[0] and (br == want[1] or c == BLACK):
        return 0
    if c == want[0]:
        return 1000
    return _dist(zx_rgb(*want), zx_rgb(c, br))


COLOURS = HEAVY + 16
DIST = [[[_cost(i, c, br) for c in range(8)] for i in range(COLOURS)]
        for br in (0, 1)]


def zx(colour, bright=0):
    return ZX + colour * 2 + bright


def heavy(colour, bright=0):
    return HEAVY + colour * 2 + bright


# ---------------------------------------------------------------- layout

TOP = 16                    # lines of the top band
FOOT = 168                  # where the knotwork band starts, as on the Apple
SIDE = 8                    # pixels of each side border
FIRST_COL = 10              # the Apple colour at the picture's left pixel
INNER = 120                 # Apple colours across the picture


def apple_col(x):
    """The Apple colour under Spectrum pixel x of the picture, and which of
    its two halves -- 0 or 1."""
    k = x - SIDE
    return FIRST_COL + (k >> 1), k & 1


def picture(cols):
    """The Apple's colours, two pixels each, inside the border."""
    pix = [[zx(BLACK)] * 256 for _ in range(192)]
    for y in range(TOP, 192):
        line = cols[y]
        row = pix[y]
        for x in range(SIDE, 256 - SIDE):
            row[x] = line[apple_col(x)[0]]
    return pix


# The border, drawn.  A tile is rows of pixels, '#' ink and '.' paper, and
# the cell colours it is laid in.

TOP_TILE = ['..##########....',
            '....######......',
            '....######......',
            '......##........',
            '......##........',
            '....######......',
            '....######......',
            '....######......',
            '....######......',
            '......##........',
            '......##........',
            '....######......',
            '....######......',
            '..##########....',
            '................',
            '................']

SIDE_TILE = ['#......#',
             '#......#',
             '#..##..#',
             '#.####.#',
             '#.####.#',
             '#.####.#',
             '#..##..#',
             '#......#',
             '#......#',
             '########']

CORNER = ['########',
          '#......#',
          '#.####.#',
          '#.#..#.#',
          '#.#..#.#',
          '#.####.#',
          '#......#',
          '########']

BORDER_INK, BORDER_PAPER = zx(BLUE), zx(RED)
FRAME = zx(CYAN, 1)         # the aqua line inside the border


def lay(pix, x0, y0, tile, ink, paper, width=None, height=None):
    h = height or len(tile)
    w = width or len(tile[0])
    for j in range(h):
        row = tile[j % len(tile)]
        for i in range(w):
            if 0 <= y0 + j < 192 and 0 <= x0 + i < 256:
                pix[y0 + j][x0 + i] = ink if row[i % len(row)] == '#' else paper


def band(pix):
    """The knotwork band at the foot: its aqua on the blue, the dark green
    shading and the blues given up to the blue."""
    for y in range(FOOT, 192):
        for x in range(SIDE, 256 - SIDE):
            v = pix[y][x]
            if v < 16:
                pix[y][x] = zx(CYAN, 1) if v in (13, 14, 15, 6, 7) else zx(BLUE, 1)


def border(pix):
    band(pix)
    for x in range(SIDE, 256 - SIDE, 16):
        lay(pix, x, 0, TOP_TILE, BORDER_INK, BORDER_PAPER)
    for x in (0, 256 - SIDE):
        lay(pix, x, 0, CORNER, BORDER_INK, zx(CYAN), height=TOP)
        # the side tiles, centred on the picture's lines
        n = FOOT - TOP
        off = (n % len(SIDE_TILE)) // 2
        for y in range(TOP, FOOT):
            k = (y - TOP - off) % len(SIDE_TILE)
            row = SIDE_TILE[k]
            for i in range(SIDE):
                c = row[i if x == 0 else SIDE - 1 - i]
                pix[y][x + i] = BORDER_INK if c == '#' else BORDER_PAPER
        lay(pix, x, FOOT, CORNER, BORDER_INK, zx(CYAN), height=192 - FOOT)
    for x in range(SIDE, 256 - SIDE):       # the aqua line inside
        pix[TOP][x] = pix[TOP + 1][x] = FRAME
    for y in range(TOP, FOOT):
        pix[y][SIDE] = pix[y][255 - SIDE] = FRAME


# ---------------------------------------------------------------- the palace

ARCH = {}


def find_arch(pix):
    """Where the arch's two sides are on each line, from the Apple's own
    picture before anything is drawn over it: from the middle out to the
    first two aqua side by side -- a star or a minaret has none."""
    ARCH.clear()
    for y in range(192):
        row = pix[y]
        l = 127
        while l > SIDE and not row[l] == row[l - 1] == 14:
            l -= 1
        r = 128
        while r < 255 - SIDE and not row[r] == row[r + 1] == 14:
            r += 1
        ARCH[y] = (l + 1, r)
    # it only ever widens going down, whatever a star says
    for y in range(TOP + 1, 120):
        pl, pr = ARCH[y - 1]
        l, r = ARCH[y]
        ARCH[y] = (min(l, pl), max(r, pr))


def inside_arch(pix, y):
    """The pixels of line y between the arch's two sides."""
    return ARCH[y]


# The sky over the palace, as simple as a Spectrum can say it: the Apple's
# night of blues, greens and greys is blue, the lower part of it bright; the
# white of the minarets and the stars stays, the pale blue of the domes is
# cyan, the roofs red, the trees black.
SKY_TO = 76
SKY = {8: zx(BLUE), 4: zx(BLUE), 10: zx(BLUE), 5: zx(BLUE), 2: zx(BLUE),
       12: zx(BLUE, 1), 15: heavy(WHITE, 1), 13: zx(CYAN, 1), 1: heavy(RED),
       0: zx(BLACK), 3: zx(BLUE), 9: zx(BLUE), 11: zx(BLUE), 7: zx(BLUE)}


def palace(pix):
    for y in range(TOP, SKY_TO):
        l, r = inside_arch(pix, y)
        for x in range(l, r):
            v = pix[y][x]
            if v in SKY:
                pix[y][x] = SKY[v]
    castle(pix)
    water(pix)
    dunes(pix)
    sides(pix)


# The palace itself, drawn again where the Apple has it, in shapes a cell of
# two colours can carry: minarets and a dome in white against the sky, the
# hall below them pale with its roof red, the gatehouse in front, the trees
# to the right black, and the green of the hills under it all.  Cell rows
# 3 to 10, columns 9 to 24.

def castle(pix):
    x0, x1, y0, y1 = 64, 208, 24, 88
    sky_dark, sky = zx(BLUE), zx(BLUE, 1)
    white, pale, red, black = zx(WHITE, 1), zx(CYAN, 1), zx(RED, 1), zx(BLACK)
    green, water = zx(GREEN), zx(CYAN)

    def put(x, y, c):
        if x0 <= x < x1 and y0 <= y < y1:
            l, r = inside_arch(pix, y) if y < SKY_TO else (0, 256)
            if l <= x < r:
                pix[y][x] = c

    def rect(xa, ya, w, h, c):
        for y in range(ya, ya + h):
            for x in range(xa, xa + w):
                put(x, y, c)

    # the sky: dark above, bright from the minarets' feet down
    for y in range(y0, y1):
        for x in range(x0, x1):
            put(x, y, sky_dark if y < 48 else sky)
    for x, y in ((90, 34), (178, 38), (150, 30), (100, 28), (170, 52),
                 (76, 44), (196, 46), (138, 26)):
        put(x, y, white)

    def minaret(x, top, foot, balcony):
        put(x, top, white)
        rect(x, top + 1, 2, 1, white)
        rect(x - 1, top + 2, 4, 2, white)          # the cap
        rect(x, top + 4, 2, foot - top - 4, white)
        rect(x - 1, balcony, 4, 1, white)          # the gallery

    minaret(114, 26, 64, 40)
    minaret(124, 32, 64, 44)
    minaret(136, 42, 64, 52)
    minaret(90, 48, 64, 56)
    minaret(160, 50, 64, 58)

    # the dome, an onion on a drum
    for i, half in enumerate((0, 1, 1, 2, 3, 4, 5, 6, 6, 6, 6, 5, 4)):
        if half:
            rect(104 - half, 46 + i, 2 * half, 1, white)
        else:
            rect(103, 46 + i, 2, 1, white)
    rect(99, 59, 10, 5, white)

    # the hall: roof red, walls pale, windows dark and arched
    rect(96, 64, 72, 2, red)
    rect(96, 66, 72, 14, pale)
    for x in range(99, 166, 8):
        if 118 <= x < 138:
            continue
        rect(x + 1, 72, 2, 1, black)
        rect(x, 73, 4, 5, black)
    # the gatehouse in front of it
    rect(118, 66, 20, 2, red)
    rect(120, 68, 16, 12, white)
    rect(126, 72, 4, 8, black)
    rect(127, 71, 2, 1, black)

    # the trees on the right
    for x, top in ((174, 62), (182, 58), (190, 63), (198, 60)):
        for y in range(top, 76):
            w = (1, 2, 3, 3, 4, 4, 4, 3, 3, 4, 4, 3, 2, 2, 2, 2, 2, 2)[min(17, y - top)]
            rect(x - w, y, 2 * w, 1, black)
    rect(168, 76, 40, 4, black)

    # the hills
    rect(64, 80, 144, 8, green)
    rect(64, 72, 32, 8, green)
    for x in range(64, 96):
        for y in range(72, 72 + max(0, 6 - (x - 64) // 5)):
            put(x, y, sky)


# The dunes in front of the palace, below the water: the Apple's are deep
# red streaks on black, a check of them here and there.  Each pixel takes
# what most of the nine round it are, which keeps the streaks and loses the
# single dots between them.

def dunes(pix):
    src = [row[:] for row in pix]
    red = lambda v: v in (1, zx(RED), 2, 9, 11, 3)
    for y in range(88, FOOT):
        l, r = ARCH.get(min(y, 119), (SIDE, 256 - SIDE))
        for x in range(max(l, SIDE + 1), min(r, 255 - SIDE)):
            v = src[y][x]
            if not (v == 0 or red(v)):
                continue
            n = sum(red(src[yy][xx]) for yy in (y - 1, y, y + 1)
                    for xx in (x - 1, x, x + 1) if yy < 192)
            pix[y][x] = zx(RED) if n >= 5 else zx(BLACK)


# Either side of the arch, drawn on the cells: the tapestry, its aqua
# pattern on the red, the awning's stripes, white and blue, the wall of
# bricks under it, orange and red by turns on black, the arch's column
# and the block it stands on.  The left side, and the right as its mirror.

RING = (14, 15, 6, 12, 8, 13, 2)


def tapestry(pix):
    for y in range(TOP + 2, 88):
        l, r = inside_arch(pix, y)
        while l > SIDE and pix[y][l - 1] in RING:
            l -= 1
        while r < 256 - SIDE and pix[y][r] in RING:
            r += 1
        if l >= 128:            # no arch on this line: all of it is picture
            continue
        for x in list(range(SIDE, l)) + list(range(r, 256 - SIDE)):
            v = pix[y][x]
            pix[y][x] = zx(CYAN) if v in (13, 14, 15, 6) else zx(RED)
        # the arch itself, aqua, its blue shadow on the sky's side
        il, ir = inside_arch(pix, y)
        for x in list(range(l, il)) + list(range(ir, r)):
            v = pix[y][x]
            pix[y][x] = zx(BLUE) if v in (12, 8, 2) else zx(CYAN, 1)


def sides(pix):
    tapestry(pix)
    white, blue, black = zx(WHITE, 1), zx(BLUE, 1), zx(BLACK)
    cyan = zx(CYAN, 1)

    def put(x, y, c):
        pix[y][x] = c
        pix[y][255 - x] = c

    def rect(xa, ya, w, h, c):
        for y in range(ya, ya + h):
            for x in range(xa, xa + w):
                put(x, y, c)

    # the awning: a cell of white, then one of blue, over two cell rows
    rect(SIDE, 88, 40, 16, black)
    for cx in range(5):
        x = SIDE + cx * 8
        if cx % 2 == 0:
            rect(x, 88, 6, 14, white)
            rect(x + 6, 88, 2, 14, blue)
        else:
            rect(x, 88, 8, 14, blue)
    # the bricks
    for cy in range(13, 21):
        for cx in range(5):
            x, y = SIDE + cx * 8, cy * 8
            colour = zx(YELLOW) if (cx + cy) % 2 == 0 else zx(RED)
            rect(x, y, 8, 8, black)
            rect(x, y, 6, 6, colour)
    # the column, white down its outer edge, and the block under it
    rect(48, 80, 8, 72, black)
    rect(48, 80, 2, 72, white)
    rect(50, 80, 6, 72, cyan)
    rect(40, 152, 24, 16, cyan)
    rect(40, 152, 24, 2, white)
    rect(40, 152, 2, 16, white)


# The water under the hills, down to the dunes: blue, a gleam of cyan.
WATER_TO = 104
WATER = {4: zx(BLUE, 1), 12: zx(BLUE, 1), 8: zx(BLUE, 1), 13: zx(CYAN, 1),
         10: zx(BLUE, 1), 5: zx(BLUE, 1), 6: zx(BLUE, 1), 14: zx(CYAN, 1),
         15: zx(CYAN, 1)}


def water(pix):
    for y in range(88, WATER_TO):
        for x in range(64, 208):
            v = pix[y][x]
            if v in WATER:
                pix[y][x] = WATER[v]


# ---------------------------------------------------------------- letters

def components(mask, y0, y1, x0, x1):
    """The letters in a mask of dots: (left, top, rows of '#'/'.')."""
    seen = set()
    out = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            if not mask[y][x] or (y, x) in seen:
                continue
            stack = [(y, x)]
            seen.add((y, x))
            pts = []
            while stack:
                cy, cx = stack.pop()
                pts.append((cy, cx))
                for dy in (-1, 0, 1):
                    for dx in (-2, -1, 0, 1, 2):
                        ny, nx = cy + dy, cx + dx
                        if y0 <= ny < y1 and x0 <= nx < x1 and mask[ny][nx] \
                                and (ny, nx) not in seen:
                            seen.add((ny, nx))
                            stack.append((ny, nx))
            top = min(p[0] for p in pts)
            left = min(p[1] for p in pts)
            h = max(p[0] for p in pts) - top + 1
            w = max(p[1] for p in pts) - left + 1
            bits = [['.'] * w for _ in range(h)]
            for py, px in pts:
                bits[py - top][px - left] = '#'
            out.append((left, top, tuple(''.join(r) for r in bits)))
    return out


def halve(bits):
    """A letter's dots two to a pixel, starting on whichever dot leaves the
    fewest pixels half lit: (phase, rows of 0/1)."""
    best = None
    for p in (0, 1):
        rows, half = [], 0
        for r in bits:
            padded = '.' * p + r + '..'
            px = []
            for k in range(0, len(r) + p, 2):
                a, b = padded[k] == '#', padded[k + 1] == '#'
                half += a != b
                px.append(1 if a or b else 0)
            rows.append(px)
        if best is None or half < best[0]:
            best = (half, p, rows)
    return best[1], best[2]


def letters(pix, mask, y0, y1, x0, x1, ground=None):
    """The letters of a dot mask onto the picture: each shape drawn one way
    wherever it comes.  Dots count from the Apple's dot 0; the picture's
    left pixel is dot FIRST_COL * 4."""
    drawn = {}
    for left, top, bits in components(mask, y0, y1, x0, x1):
        if bits not in drawn:
            drawn[bits] = halve(bits)
        p, rows = drawn[bits]
        sx = SIDE + (left - p - FIRST_COL * 4) // 2
        for j, r in enumerate(rows):
            for i, v in enumerate(r):
                if v and 0 <= sx + i < 256:
                    pix[top + j][sx + i] = LETTER


# The story screens: white letters on a ground of deep red, a dot in every
# other colour in a check with black, inside the border -- colours 8 to
# 131, lines 14 to 167.  A letter's dot is lit and not the ground's.
STORY = ('prolog', 'sumup')
GROUND = 1


def story(pix, cols, dots):
    for y in range(TOP + 2, FOOT):
        for x in range(SIDE + 1, 255 - SIDE):
            pix[y][x] = zx(RED)
    mask = [[bool(dots[y][d]) and cols[y][d >> 2] != GROUND
             for d in range(560)] for y in range(192)]
    letters(pix, mask, TOP + 2, FOOT, 8 * 4, 132 * 4)


def credit(pix, apple, cols, dots, splash):
    """The credits and the title are letters in dots laid over the splash:
    where a credit has changed a byte of the splash, a lit dot beside
    another lit dot, of anything but the ground's colour, is a letter's --
    a lone dot is the band's blue or the ground's red.  They go over the
    Spectrum's splash, each with a black edge a pixel wide round it, as the
    Apple's letters have."""
    mask = [[False] * 560 for _ in range(192)]
    for y in range(TOP, 192):
        for d in range(560):
            if apple[y][d // 7] == splash[y][d // 7]:
                continue
            c = cols[y][d >> 2]
            run = dots[y][d] and ((d and dots[y][d - 1]) or (d < 559 and dots[y][d + 1]))
            if run and c not in (0, GROUND):
                mask[y][d] = True
    letters(pix, mask, TOP, FOOT, 0, 560)
    edge = heavy(BLACK)
    for y in range(TOP, FOOT):
        for x in range(SIDE, 256 - SIDE):
            if pix[y][x] == LETTER:
                continue
            if any(0 <= y + dy < 192 and pix[y + dy][x + dx] == LETTER
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                pix[y][x] = edge


# The copyright line on the knotwork band: the Apple's letters there are
# seven dots high and three wide a stroke, which two to a pixel leave as
# smudges.  It is set again in letters of the Spectrum's own size.
FONT = {
    ' ': ['...'],
    '©': ['..###..', '.#...#.', '#..##.#', '#.#...#', '#..##.#',
               '.#...#.', '..###..'],
    'C': ['.###.', '#...#', '#....', '#....', '#...#', '.###.'],
    'J': ['..###', '...#.', '...#.', '...#.', '#..#.', '.##..'],
    'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#'],
    '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '.###.'],
    '8': ['.###.', '#...#', '.###.', '#...#', '#...#', '.###.'],
    '9': ['.###.', '#...#', '.####', '....#', '...#.', '.##..'],
    'a': ['.....', '.###.', '....#', '.####', '#...#', '.####'],
    'c': ['.....', '.###.', '#....', '#....', '#....', '.###.'],
    'd': ['....#', '.####', '#...#', '#...#', '#...#', '.####'],
    'e': ['.....', '.###.', '#...#', '#####', '#....', '.###.'],
    'g': ['.....', '.####', '#...#', '#...#', '.####', '....#', '.###.'],
    'h': ['#....', '####.', '#...#', '#...#', '#...#', '#...#'],
    'i': ['..#..', '.....', '.##..', '..#..', '..#..', '.###.'],
    'n': ['.....', '####.', '#...#', '#...#', '#...#', '#...#'],
    'o': ['.....', '.###.', '#...#', '#...#', '#...#', '.###.'],
    'p': ['.....', '####.', '#...#', '#...#', '####.', '#....', '#....'],
    'r': ['.....', '#.##.', '##..#', '#....', '#....', '#....'],
    't': ['.#...', '####.', '.#...', '.#...', '.#..#', '..##.'],
    'y': ['.....', '#...#', '#...#', '#...#', '.####', '....#', '.###.'],
}
COPYRIGHT = '© Copyright 1989 Jordan Mechner'


def copyright(pix):
    width = sum(len(FONT[ch][0]) + 1 for ch in COPYRIGHT) - 1
    x = (256 - width) // 2
    for yy in range(176, 184):
        for xx in range(x - 4, x + width + 4):
            pix[yy][xx] = zx(BLUE)
    for ch in COPYRIGHT:
        glyph = FONT[ch]
        for j, row in enumerate(glyph):
            for i, c in enumerate(row):
                if c == '#':
                    pix[176 + j][x + i] = LETTER
        x += len(glyph[0]) + 1


def cell(pix, cx, cy):
    """(ink, paper, bright, [64 bits]) for the cell."""
    count = [0] * COLOURS
    for y in range(cy * 8, cy * 8 + 8):
        for x in range(cx * 8, cx * 8 + 8):
            count[pix[y][x]] += 1
    used = [i for i in range(COLOURS) if count[i]]
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
    splash = poptitles.screen('splash') if name not in STORY else apple
    pix = picture(poptitles.colours(splash))
    find_arch(pix)
    if name not in STORY:
        palace(pix)
    border(pix)
    if name in STORY:
        story(pix, cols, dots)
    elif name != 'splash':
        credit(pix, apple, cols, dots, splash)
        if name == 'title':
            copyright(pix)
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


def preview(scr, path, zoom=2):
    rows = []
    for y in range(192):
        line = bytearray()
        for x in range(256):
            a = scr[6144 + (y >> 3) * 32 + (x >> 3)]
            on = scr[zxscreen.bitmap_offset(x >> 3, y)] & (0x80 >> (x & 7))
            c = zx_rgb(a & 7 if on else (a >> 3) & 7, (a >> 6) & 1)
            line.extend(bytes(c) * zoom)
        for _ in range(zoom):
            rows.append(bytes(line))
    pngwrite.write_rgb(path, 256 * zoom, 192 * zoom, rows)


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
