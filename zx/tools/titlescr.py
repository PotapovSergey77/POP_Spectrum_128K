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
    a single cell down the sides -- and the yellow line inside it in the
    first cells of the picture.  The top band is sixteen lines, two more
    than the Apple's, and the picture loses its first two lines, a black one
    and one of the tapestry.

    The splash.  What stands on the cells is drawn on them: the awning, the
    wall of bricks, the columns with their pattern and the blocks under
    them, the arch in yellow, the tapestry's yellow on blue.  The palace
    keeps every pixel of its outline, and the sky round it is made simple
    enough to leave it standing out.

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

# The Apple's colours by name, as poptitles.PALETTE has them.
A_BLACK, A_CRIMSON, A_BROWN, A_ORANGE, A_DKGREEN, A_GREY1, A_GREEN, \
    A_YELLOW, A_DKBLUE, A_PURPLE, A_GREY2, A_PINK, A_BLUE, A_LTBLUE, \
    A_AQUA, A_WHITE = range(16)


def apple_col(x):
    """The Apple colour under Spectrum pixel x of the picture, and which of
    its two halves -- 0 or 1."""
    k = x - SIDE
    return FIRST_COL + (k >> 1), k & 1


def spectrum_x(col):
    """The Spectrum pixel an Apple colour's left half lands on."""
    return SIDE + (col - FIRST_COL) * 2


def picture(cols):
    """The Apple's colours, two pixels each, inside the border."""
    pix = [[zx(BLACK)] * 256 for _ in range(192)]
    for y in range(TOP, 192):
        line = cols[y]
        row = pix[y]
        for x in range(SIDE, 256 - SIDE):
            row[x] = line[apple_col(x)[0]]
    return pix


def put2(pix, x, y, c):
    """A pixel of the left half and its mirror in the right."""
    pix[y][x] = c
    pix[y][255 - x] = c


def rect2(pix, xa, ya, w, h, c):
    for y in range(ya, ya + h):
        for x in range(xa, xa + w):
            put2(pix, x, y, c)


# The border, drawn.  A tile is rows of pixels, '#' ink and '.' paper.  The
# Apple's: along the top dark blue tiles, a crimson triangle at head and
# foot and an orange cross between, on yellow lines; down the sides crimson
# edges closing in on a white heart; pink corners.  The yellow lines go --
# a cell has no room for them -- but for the one inside the border.

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
             '##....##',
             '###..###',
             '###..###',
             '##....##',
             '#......#',
             '#......#',
             '########',
             '........']

CORNER = ['........',
          '.######.',
          '.#....#.',
          '.#.##.#.',
          '.#.##.#.',
          '.#....#.',
          '.######.',
          '........']

BORDER_INK, BORDER_PAPER = zx(RED), zx(BLUE)
CORNER_INK, CORNER_PAPER = zx(RED, 1), zx(MAGENTA, 1)
FRAME = zx(YELLOW, 1)       # the yellow line inside the border


def lay(pix, x0, y0, tile, ink, paper, width=None, height=None):
    h = height or len(tile)
    w = width or len(tile[0])
    for j in range(h):
        row = tile[j % len(tile)]
        for i in range(w):
            if 0 <= y0 + j < 192 and 0 <= x0 + i < 256:
                pix[y0 + j][x0 + i] = ink if row[i % len(row)] == '#' else paper


def band(pix):
    """The knotwork band at the foot: its yellow on the crimson, the orange
    and pink of it yellow too."""
    for y in range(FOOT, 192):
        for x in range(SIDE, 256 - SIDE):
            v = pix[y][x]
            if v < 16:
                bright = v in (A_YELLOW, A_WHITE, A_ORANGE, A_PINK, A_GREEN)
                pix[y][x] = zx(YELLOW, 1) if bright else zx(RED)


def border(pix, story):
    band(pix)
    for x in range(SIDE, 256 - SIDE, 16):
        lay(pix, x, 0, TOP_TILE, BORDER_INK, BORDER_PAPER)
    for x in (0, 256 - SIDE):
        lay(pix, x, 0, CORNER, CORNER_INK, CORNER_PAPER, height=TOP)
        n = FOOT - TOP
        off = (n % len(SIDE_TILE)) // 2
        for y in range(TOP, FOOT):
            row = SIDE_TILE[(y - TOP - off) % len(SIDE_TILE)]
            for i in range(SIDE):
                pix[y][x + i] = BORDER_INK if row[i] == '#' else BORDER_PAPER
        lay(pix, x, FOOT, CORNER, CORNER_INK, CORNER_PAPER, height=192 - FOOT)
    for x in range(SIDE, 256 - SIDE):
        pix[TOP][x] = pix[TOP + 1][x] = FRAME
    if story:
        for y in range(TOP, FOOT):
            pix[y][SIDE] = pix[y][255 - SIDE] = FRAME


# ---------------------------------------------------------------- the splash

ARCH = {}
RING = (A_YELLOW, A_WHITE, A_GREEN, A_ORANGE)


def find_arch(pix):
    """Where the arch's two sides are on each line, from the Apple's own
    picture before anything is drawn over it: from the middle out to the
    first two yellow side by side.  Down to its widest it only widens, for
    all a star says."""
    ARCH.clear()
    for y in range(192):
        row = pix[y]
        l = 127
        while l > SIDE and not row[l] == row[l - 1] == A_YELLOW:
            l -= 1
        r = 128
        while r < 255 - SIDE and not row[r] == row[r + 1] == A_YELLOW:
            r += 1
        ARCH[y] = (l + 1, r)
    for y in range(TOP + 1, 60):        # its widest
        pl, pr = ARCH[y - 1]
        l, r = ARCH[y]
        ARCH[y] = (min(l, pl), max(r, pr))


def ring(pix, y):
    """The arch's outer edges on line y: out from its inside while the
    colours are the arch's."""
    l, r = ARCH[y]
    while l > SIDE and pix[y][l - 1] in RING:
        l -= 1
    while r < 256 - SIDE and pix[y][r] in RING:
        r += 1
    return l, r


# Inside the arch, the palace at dusk, every line of its outline where the
# Apple has it.  The Apple's sky is crimson, brown and grey above and more
# and more orange lower down, dot by dot; here it is red and yellow, the
# share of orange round each pixel laid down as an even dither.  The palace
# -- its pink, white and pale blue -- is a cell's ink, in white or magenta,
# whichever it has more of, and every one of its pixels stays: the paper is
# the red of the sky, or where the cell is more roof and shadow than sky,
# blue or black.
DUSK_TO = 96
GROUND_FROM = 70            # below it the Apple's brown is the dark ground
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
LIGHT = (A_PINK, A_WHITE, A_LTBLUE)
DARK = (A_DKBLUE, A_BLACK, A_BLUE)
SKY = (A_CRIMSON, A_BROWN, A_GREY1, A_GREY2, A_ORANGE, A_DKGREEN, A_YELLOW,
       A_GREEN, A_PURPLE)


EDGE = 4                    # the arch's white and green edge inside it


def dusk(pix):
    src = [row[:] for row in pix]
    inside = lambda x, y: ARCH[min(y, 119)][0] + EDGE <= x < ARCH[min(y, 119)][1] - EDGE
    for y in range(TOP, DUSK_TO):
        l, r = ARCH[min(y, 119)]
        for x in list(range(l, l + EDGE)) + list(range(r - EDGE, r)):
            v = src[y][x]
            if y < 88:
                pix[y][x] = zx(YELLOW, 1) if v in RING + LIGHT else zx(RED)
        for x in range(l + EDGE, r - EDGE):
            v = src[y][x]
            if v == A_BROWN and y >= GROUND_FROM:
                src[y][x] = v = A_BLACK     # the ground the palace stands on
            if v in SKY:
                n = orange = 0
                for yy in range(max(TOP, y - 3), min(DUSK_TO, y + 4)):
                    for xx in range(x - 5, x + 6):
                        w = src[yy][xx]
                        if w in SKY and inside(xx, yy):
                            n += 1
                            orange += w in (A_ORANGE, A_YELLOW)
                share = orange * 16 // max(n, 1)
                glow = share > 10 or (share > 6 and y & 1)
                pix[y][x] = zx(YELLOW) if glow else zx(RED)
            elif v in DARK:
                pix[y][x] = zx(BLUE) if v != A_BLACK else zx(BLACK)
    for cy in range(TOP // 8, DUSK_TO // 8):
        for cx in range(32):
            cells = [(x, y) for y in range(cy * 8, cy * 8 + 8)
                     for x in range(cx * 8, cx * 8 + 8) if inside(x, y)]
            light = [src[y][x] for x, y in cells if src[y][x] in LIGHT]
            if not light:
                continue
            ink = zx(WHITE, 1) if sum(v != A_PINK for v in light) * 2 > len(light)                 else zx(MAGENTA, 1)
            dark = [src[y][x] for x, y in cells if src[y][x] in DARK]
            sky = [pix[y][x] for x, y in cells if src[y][x] in SKY]
            if len(dark) > 2 * len(sky):
                paper = zx(BLUE) if sum(v != A_BLACK for v in dark) * 2 >= len(dark)                     else zx(BLACK)
            else:
                paper = zx(RED)
            for x, y in cells:
                pix[y][x] = heavy(ink >> 0 and (ink - ZX) >> 1, (ink - ZX) & 1)                     if src[y][x] in LIGHT else heavy((paper - ZX) >> 1, (paper - ZX) & 1)


# The dunes in front, down to the band: dark blue streaks on black, a check
# of them here and there.  Each pixel takes what most of the nine round it
# are, which keeps the streaks and loses the single dots between them.

def dunes(pix):
    src = [row[:] for row in pix]
    blue = lambda v: v in (A_DKBLUE, A_BLUE, A_PURPLE, A_LTBLUE)
    for y in range(DUSK_TO, FOOT):
        l, r = ARCH[min(y, 119)]
        for x in range(max(l, SIDE + 1), min(r, 255 - SIDE)):
            v = src[y][x]
            if not (v == A_BLACK or blue(v)):
                continue
            n = sum(blue(src[yy][xx]) for yy in (y - 1, y, y + 1)
                    for xx in (x - 1, x, x + 1) if yy < 192)
            pix[y][x] = zx(BLUE) if n >= 5 else zx(BLACK)


def arch(pix):
    """The tapestry either side of the arch, its yellow on dark blue, and
    the arch itself yellow."""
    for y in range(TOP + 2, 88):
        l, r = ring(pix, y)
        il, ir = ARCH[y]
        if il >= 128:
            continue
        for x in list(range(SIDE, l)) + list(range(r, 256 - SIDE)):
            v = pix[y][x]
            pix[y][x] = zx(YELLOW) if v in (A_YELLOW, A_WHITE, A_ORANGE, A_GREEN) \
                else zx(BLUE)
        for x in list(range(l, il)) + list(range(ir, r)):
            pix[y][x] = zx(YELLOW, 1)


# The column the arch comes down to, its three Apple colours a line: white
# and yellow, or the orange and blue of the pattern on its upper part, or
# black between.  Drawn a cell wide, the pattern across the whole cell.
COLUMN = 32                 # its Apple colour


def column(pix, cols):
    x = 48
    for y in range(80, 152):
        c = cols[y][COLUMN:COLUMN + 3]
        rect2(pix, x, y, 8, 1, zx(BLACK))
        if all(v in (A_WHITE, A_YELLOW) for v in c):
            rect2(pix, x + 2, y, 6, 1, zx(YELLOW, 1))
        elif any(v in (A_ORANGE, A_BLUE) for v in c):
            for i, v in enumerate((c[0], c[0], c[0], c[1], c[1], c[2], c[2], c[2])):
                put2(pix, x + i, y, zx(YELLOW, 1) if v == A_ORANGE else zx(BLUE, 1))


def sides(pix, cols):
    arch(pix)
    # the awning: stripes of white and crimson, a cell of each by turns
    rect2(pix, SIDE, 88, 40, 16, zx(BLACK))
    for cx in range(5):
        x = SIDE + cx * 8
        if cx % 2 == 0:
            rect2(pix, x, 88, 6, 14, zx(WHITE, 1))
            rect2(pix, x + 6, 88, 2, 14, zx(RED, 1))
        else:
            rect2(pix, x, 88, 8, 14, zx(RED, 1))
    # the wall under it: bricks of two blues by turns, on black
    for cy in range(13, 21):
        for cx in range(5):
            x, y = SIDE + cx * 8, cy * 8
            rect2(pix, x, y, 8, 8, zx(BLACK))
            rect2(pix, x, y, 6, 6, zx(BLUE, (cx + cy) & 1))
    column(pix, cols)
    # the block it stands on, yellow, lit along its top and outer side
    rect2(pix, 40, 152, 24, 16, zx(YELLOW, 1))
    rect2(pix, 40, 152, 24, 2, zx(WHITE, 1))
    rect2(pix, 40, 152, 2, 16, zx(WHITE, 1))


def splash_picture(pix, cols):
    find_arch(pix)
    dusk(pix)
    dunes(pix)
    sides(pix, cols)


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


# The story screens: white letters on a ground of dark blue, a dot in every
# other colour in a check with black, inside the border -- colours 8 to
# 131, lines 14 to 167.  A letter's dot is lit and not the ground's.
STORY = ('prolog', 'sumup')
GROUND = A_DKBLUE


def story(pix, cols, dots):
    for y in range(TOP + 2, FOOT):
        for x in range(SIDE + 1, 255 - SIDE):
            pix[y][x] = zx(BLUE)
    mask = [[bool(dots[y][d]) and cols[y][d >> 2] != GROUND
             for d in range(560)] for y in range(192)]
    letters(pix, mask, TOP + 2, FOOT, 8 * 4, 132 * 4)


def credit(pix, apple, cols, dots, splash):
    """The credits and the title are letters in dots laid over the splash:
    where a credit has changed a byte of the splash, a lit dot beside
    another lit dot, of anything but the ground's colour, is a letter's --
    a lone dot is the band's crimson or the dunes' blue.  They go over the
    Spectrum's splash, each with a black edge a pixel wide round it, as the
    Apple's letters have."""
    mask = [[False] * 560 for _ in range(192)]
    for y in range(TOP, 192):
        for d in range(560):
            if apple[y][d // 7] == splash[y][d // 7]:
                continue
            c = cols[y][d >> 2]
            run = dots[y][d] and ((d and dots[y][d - 1]) or (d < 559 and dots[y][d + 1]))
            if run and c not in (A_BLACK, A_CRIMSON, GROUND):
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
            pix[yy][xx] = zx(RED)
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
    if name not in STORY:
        splash_picture(pix, poptitles.colours(splash))
    border(pix, name in STORY)
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
