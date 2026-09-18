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
            (YELLOW, 0),    # yellow, as dark as the rest of it
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
TITLE = HEAVY + 16          # the title's letters, which are bright white


def _cost(i, c, br):
    if i == LETTER:
        return 0 if c == WHITE else 4 * _cost(15, c, br) + 200000
    if i == TITLE:
        return 0 if c == WHITE and br else 100000 + _cost(LETTER, c, br)
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


COLOURS = TITLE + 1
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

# Along the top the Apple's tiles are dark blue squares in a yellow grid, a
# crimson cap at the head and the foot of each and an orange cross between.
# A tile and its line of the grid are two cells here: one the tile's shape
# in red on blue, the other blue with the grid's yellow line down it, so
# neither holds more than its two colours.  The cross has to be the caps'
# red: a cell with the caps and the cross in it has room for one of them.
TOP_TILE = ['########',
            '.######.',
            '.######.',
            '.######.',
            '...##...',
            '...##...',
            '...##...',
            '.######.',
            '.######.',
            '...##...',
            '...##...',
            '...##...',
            '.######.',
            '.######.',
            '.######.',
            '########']
TOP_LINE = ['...##...'] * 16

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

# The corner at the foot on the left is not a pattern on the Apple but two
# letters, brown on its pink: here dark on the magenta, a pixel to each of
# the Apple's colours, on its lines.
MONOGRAM = ['........',
            '........',
            '........',
            '........',
            '...##...',
            '..#.#...',
            '..#.#...',
            '..####..',
            '..#..#..',
            '........',
            '........',
            '..##....',
            '.##.....',
            '..#.....',
            '..#.#...',
            '..#.#...',
            '..###...',
            '..###...',
            '..#.#...',
            '....#...',
            '...##...',
            '...#....',
            '...#....',
            '........']
MONO_INK = zx(BLACK)

BORDER_INK, BORDER_PAPER = zx(RED), zx(BLUE)
CORNER_INK, CORNER_PAPER = zx(RED, 1), zx(MAGENTA, 1)
FRAME = zx(YELLOW)          # the yellow line inside the border


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
    and pink of it yellow too -- both of one brightness, or each cell would
    pick its own."""
    for y in range(FOOT, 192):
        for x in range(SIDE, 256 - SIDE):
            v = pix[y][x]
            if v < 16:
                bright = v in (A_YELLOW, A_WHITE, A_ORANGE, A_PINK, A_GREEN)
                pix[y][x] = heavy(YELLOW) if bright or y < FOOT + 2 else heavy(RED)


def border(pix, story):
    band(pix)
    # a line of the grid, then tile and line by turns all the way along: the
    # same steps everywhere, which the eye goes by, and not the same at the
    # two ends
    for col in range(1, 31):
        if col % 2:
            lay(pix, col * 8, 0, TOP_LINE, FRAME, BORDER_PAPER)
        else:
            lay(pix, col * 8, 0, TOP_TILE, BORDER_INK, BORDER_PAPER)
    for x in (0, 256 - SIDE):
        lay(pix, x, 0, CORNER, CORNER_INK, CORNER_PAPER, height=TOP)
        n = FOOT - TOP
        off = (n % len(SIDE_TILE)) // 2
        for y in range(TOP, FOOT):
            row = SIDE_TILE[(y - TOP - off) % len(SIDE_TILE)]
            for i in range(SIDE):
                pix[y][x + i] = BORDER_INK if row[i] == '#' else BORDER_PAPER
        if x:
            lay(pix, x, FOOT, CORNER, CORNER_INK, CORNER_PAPER, height=192 - FOOT)
        else:
            lay(pix, x, FOOT, MONOGRAM, MONO_INK, CORNER_PAPER)
    for x in range(SIDE, 256 - SIDE):
        pix[TOP][x] = pix[TOP + 1][x] = FRAME
    if story:
        for y in range(TOP, FOOT):
            pix[y][SIDE] = pix[y][255 - SIDE] = FRAME


# ---------------------------------------------------------------- the splash

# The arch's point.  On the Apple its two sides meet above the picture, in
# the border, and cut through the tiles and the yellow line; the top band
# here is drawn afresh, so the point is drawn over it: the sides as they
# close in over the picture's first lines, carried on up until they meet.

def apex(pix):
    # a tile of the top band the point cuts into goes whole: blue, as the
    # tile is round its shape, rather than a shape with a bite out of it
    for col in range(1, 31):
        cells = [(x, y) for y in range(TOP) for x in range(col * 8, col * 8 + 8)]
        if any(onion_at(x, y) for x, y in cells):
            for x, y in cells:
                if pix[y][x] == BORDER_INK:
                    pix[y][x] = BORDER_PAPER
    # and the yellow line under the band stops at the arch, as the Apple's
    for y in range(0, TOP + 2):
        for x in range(SIDE, 256 - SIDE):
            k = onion_at(x, y)
            if k == 1:
                pix[y][x] = zx(RED)
            elif k == 2:
                pix[y][x] = heavy(YELLOW)
    ring_cells(pix, 0, TOP + 2)


# The arch is drawn smooth.  The Apple's sides come in steps two pixels wide,
# and a cell holds two colours of the three that meet along it -- the
# tapestry's blue outside, the yellow, the sky's red inside -- so it came
# out in steps of a cell.  Its inside edge is taken off the Apple's, both
# sides together and evened out over a few lines, and carried up to a point
# in the border; the yellow is as thick all the way round.  A cell the
# yellow runs through keeps it pixel for pixel, and what else it holds is
# the one colour most of the rest of the cell is.
ARCH_TIP = 6                # the line the inside of the point closes on
ARCH_TO = 96                # below here the column is the arch's side
ARCH_FOOT = 72              # the half width it comes down to, the column's
RING_T = 6.5                # the yellow, across
HALF_IN, HALF_OUT = {}, {}  # line -> half widths, from the middle


def smooth_arch():
    raw = {}
    for y in range(TOP, ARCH_TO + 3):
        l, r = ARCH[y]
        raw[y] = (r - l) / 2 if y < 88 else ARCH_FOOT
    sm = {}
    for y in raw:
        near = [raw[yy] for yy in range(y - 3, y + 4) if yy in raw]
        sm[y] = sum(near) / len(near)
    # the point: from the first line of the picture up to the tip, the
    # half width falling as a power, its slope at the join the curve's own
    h0, h1 = sm[TOP], sm[TOP + 2]
    slope = (h1 - h0) / 2
    p = max(1.0, slope * (TOP - ARCH_TIP) / h0)
    pts = []
    y = ARCH_TIP
    while y < TOP:
        pts.append((y, h0 * ((y - ARCH_TIP) / (TOP - ARCH_TIP)) ** p))
        y += 0.05
    for yy in range(TOP, ARCH_TO + 2):
        for k in range(20):
            f = k / 20
            pts.append((yy + f, sm[yy] * (1 - f) + sm[yy + 1] * f))
    # the outside: the inside moved out square to it
    out = []
    for i, (y, h) in enumerate(pts):
        a, b = pts[max(0, i - 3)], pts[min(len(pts) - 1, i + 3)]
        dh, dy = b[1] - a[1], b[0] - a[0]
        n = (dh * dh + dy * dy) ** 0.5
        out.append((y - RING_T * dh / n, h + RING_T * dy / n))
    out.insert(0, (ARCH_TIP - RING_T, 0.0))

    def at(curve, yc):
        best = None
        for (ya, ha), (yb, hb) in zip(curve, curve[1:]):
            if min(ya, yb) <= yc <= max(ya, yb) and ya != yb:
                h = ha + (hb - ha) * (yc - ya) / (yb - ya)
                best = h if best is None else max(best, h)
        return best
    HALF_IN.clear()
    HALF_OUT.clear()
    for y in range(0, ARCH_TO):
        yc = y + 0.5
        hi = at(pts, yc) if yc >= ARCH_TIP else None
        ho = at(out, yc)
        if ho is None and hi is None:
            continue
        HALF_IN[y] = hi if hi is not None else 0
        HALF_OUT[y] = max(ho or 0, HALF_IN[y])
        if y >= TOP:
            h = int(HALF_IN[y] + 0.5)
            ARCH[y] = (128 - h, 128 + h)


def onion_at(x, y):
    """0 outside the arch, 1 inside it, 2 on its yellow."""
    if y not in HALF_OUT:
        return 0
    d = abs(x + 0.5 - 128)
    if d < HALF_IN[y]:
        return 1
    if d < HALF_OUT[y]:
        return 2
    return 0


def ring_cells(pix, y0, y1):
    yellow = (zx(YELLOW), heavy(YELLOW))
    for cy in range(y0 // 8, (y1 + 7) // 8):
        for cx in range(32):
            cell = [(x, y) for y in range(cy * 8, cy * 8 + 8)
                    for x in range(cx * 8, cx * 8 + 8)]
            if not any(onion_at(x, y) == 2 for x, y in cell):
                continue
            rest = {}
            for x, y in cell:
                v = pix[y][x]
                if v not in yellow:
                    key = v - 16 if HEAVY <= v < TITLE else v
                    rest[key] = rest.get(key, 0) + 1
            if not rest:
                continue
            paper = max(rest, key=rest.get)
            # a few pixels of the other side are the yellow's, a speck of the
            # wrong colour by it being worse than the yellow a pixel wider
            few = sum(rest.values()) - rest[paper] <= 6
            for x, y in cell:
                v = pix[y][x]
                if v in yellow:
                    continue
                key = v - 16 if HEAVY <= v < TITLE else v
                if key != paper and few:
                    pix[y][x] = heavy(YELLOW)
                else:
                    pix[y][x] = paper + 16 if ZX <= paper < HEAVY else paper



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
# share of orange round each pixel laid down as a dither in the Bayer
# order, so the orange reads as a shade and not as bars.  The palace -- its
# pink, white and pale blue -- is a cell's ink, in white or magenta,
# whichever it has more of, and every one of its pixels stays: the paper is
# the red of the sky, or where the cell is more roof and shadow than sky,
# blue or black.  A dot of it on its own below the stars is the sky's, and
# a gap of a pixel in a wall is wall, so its shapes hold together.
DUSK_TO = 96
GROUND_FROM = 70            # below it the Apple's brown is the dark ground
HORIZON = 76                # the ground by the arch's foot
STAR_TO = 48                # a lone dot above here is a star
# what the palace's own colours want to be, and how much that counts
WANT = {A_PINK: ({MAGENTA: 1}, 4), A_PURPLE: ({MAGENTA: 1}, 2),
        A_WHITE: ({WHITE: 1}, 4), A_LTBLUE: ({WHITE: 1}, 3),
        A_DKBLUE: ({BLUE: 1}, 3), A_BLUE: ({BLUE: 1}, 3),
        A_BLACK: ({BLACK: 1}, 2)}
WALL_FROM = 50              # the buildings' tops, below the minarets'
GLOW_NEAR, GLOW_FADE = 3, 12    # no glow this close to the palace, full this
                                # much further out
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
LIGHT = (A_PINK, A_WHITE, A_LTBLUE)
DARK = (A_DKBLUE, A_BLACK, A_BLUE)
SKY = (A_CRIMSON, A_BROWN, A_GREY1, A_GREY2, A_ORANGE, A_DKGREEN, A_YELLOW,
       A_GREEN, A_PURPLE)


EDGE = 4                    # the arch's white and green edge inside it


def dusk(pix):
    src = [row[:] for row in pix]
    inside = lambda x, y: ARCH[min(y, 119)][0] + EDGE <= x < ARCH[min(y, 119)][1] - EDGE
    lit = lambda x, y: src[y][x] in LIGHT and inside(x, y)
    for y in range(STAR_TO, DUSK_TO):
        for x in range(SIDE, 256 - SIDE):
            if lit(x, y) and not any(lit(x + dx, y + dy)
                                     for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                                     if (dx or dy) and y + dy < 192):
                src[y][x] = A_ORANGE
    for y in range(TOP, DUSK_TO):
        for x in range(SIDE + 1, 255 - SIDE):
            if not lit(x, y) and lit(x - 1, y) and lit(x + 1, y):
                src[y][x] = src[y][x - 1]
    # the Apple's black line inside its arch, which is not where this one
    # is, is sky too
    for y in range(TOP, min(HORIZON, ARCH_TO)):
        for x in range(SIDE, 256 - SIDE):
            if src[y][x] in DARK + LIGHT and                     HALF_IN[y] - 8 < abs(x + 0.5 - 128) < HALF_IN[y]:
                src[y][x] = A_CRIMSON
    # and a dark dot on its own in the sky is sky
    dark = lambda x, y: src[y][x] in DARK and inside(x, y)
    for y in range(TOP, HORIZON):
        for x in range(SIDE, 256 - SIDE):
            if dark(x, y) and not any(dark(x + dx, y + dy)
                                      for dy in (-1, 0, 1) for dx in (-2, -1, 1, 2)
                                      if dx or dy):
                src[y][x] = A_CRIMSON
    # how far each pixel is from the palace: the glow thins out towards it,
    # so the red a cell of the palace has round it is the sky's own there
    # and not a box cut out of the orange
    far = [[99] * 256 for _ in range(192)]
    for y in range(TOP, DUSK_TO):
        for x in range(SIDE, 256 - SIDE):
            if src[y][x] in LIGHT and inside(x, y):
                far[y][x] = 0
    for y in range(TOP, DUSK_TO):
        for x in range(1, 255):
            far[y][x] = min(far[y][x], far[y - 1][x] + 1, far[y][x - 1] + 1,
                            far[y - 1][x - 1] + 1, far[y - 1][x + 1] + 1)
    for y in range(DUSK_TO - 1, TOP - 1, -1):
        for x in range(254, 0, -1):
            far[y][x] = min(far[y][x], far[y + 1][x] + 1, far[y][x + 1] + 1,
                            far[y + 1][x + 1] + 1, far[y + 1][x - 1] + 1)
    want = {}
    for y in range(TOP, DUSK_TO):
        l, r = ARCH[min(y, 119)]
        for x in list(range(l, l + EDGE)) + list(range(r - EDGE, r)):
            if y < 88:
                pix[y][x] = zx(RED) if y < HORIZON else zx(BLACK)
        for x in range(l + EDGE, r - EDGE):
            v = src[y][x]
            if v in SKY and (y >= HORIZON or (v == A_BROWN and y >= GROUND_FROM)):
                src[y][x] = v = A_BLACK     # the ground the palace stands on
            if v in SKY:
                n = orange = 0
                for yy in range(max(TOP, y - 3), min(DUSK_TO, y + 4)):
                    for xx in range(x - 5, x + 6):
                        w = src[yy][xx]
                        if w in SKY and inside(xx, yy):
                            n += 1
                            orange += w in (A_ORANGE, A_YELLOW)
                share = orange * 16 / max(n, 1)
                fade = min(1.0, max(0.0, (far[y][x] - GLOW_NEAR) / GLOW_FADE))
                g = min(1.0, max(0.0, (share - 5) / 7 * fade))
                want[x, y] = ({RED: 1 - g, YELLOW: g}, 1)
            else:
                want[x, y] = WANT.get(v, ({BLACK: 1}, 1))
    # each cell the two colours that give most of what its pixels want --
    # the palace's count four times the sky's -- and each pixel the one of
    # them it wants, or its mix of the two in the Bayer order, or the
    # nearer of them
    pairs = [(a, b) for a in range(8) for b in range(a + 1, 8)]
    for cy in range(TOP // 8, DUSK_TO // 8):
        for cx in range(32):
            cells = [(x, y) for y in range(cy * 8, cy * 8 + 8)
                     for x in range(cx * 8, cx * 8 + 8) if (x, y) in want]
            if not cells:
                continue
            best = max(pairs, key=lambda ab: sum(
                w * (d.get(ab[0], 0) + d.get(ab[1], 0))
                for d, w in (want[p] for p in cells)))
            a, b = best
            for x, y in cells:
                d, _ = want[x, y]
                wa, wb = d.get(a, 0), d.get(b, 0)
                if wa or wb:
                    c = b if BAYER[y & 3][x & 3] < wb / (wa + wb) * 16 - 0.5 \
                        else a
                else:
                    main = max(d, key=d.get)
                    c = min((a, b), key=lambda k: _dist(zx_rgb(k, 0),
                                                         zx_rgb(main, 0)))
                pix[y][x] = heavy(c)


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
                if v < 16 and y < 112:
                    pix[y][x] = zx(BLACK)       # the Apple's lit hill
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
            pix[y][x] = zx(YELLOW)
    # and the smooth arch over it: the Apple's yellow past its outside is
    # the tapestry's blue, and the sky is red to its inside
    for y in range(TOP, ARCH_TO):
        for x in range(SIDE, 256 - SIDE):
            k = onion_at(x, y)
            d = abs(x + 0.5 - 128)
            if k == 2:
                pix[y][x] = heavy(YELLOW)
            elif k == 0 and pix[y][x] == zx(YELLOW) and d < HALF_OUT[y] + 6:
                pix[y][x] = zx(BLUE)
            elif k == 0 and pix[y][x] < 16:     # the Apple's, left over
                pix[y][x] = zx(BLUE)
            elif k == 1 and d > HALF_IN[y] - 3:
                pix[y][x] = zx(RED) if y < HORIZON else zx(BLACK)
    ring_cells(pix, TOP, ARCH_TO)


# The column the arch comes down to, its three Apple colours a line: white
# and yellow, or the orange and blue of the pattern on its upper part, or
# black between.  Six pixels wide in its cell, the pattern as wide as it.
COLUMN = 32                 # its Apple colour


def column(pix, cols):
    x = 48
    rect2(pix, 46, ARCH_TO, 18, 152 - ARCH_TO, zx(BLACK))  # and nothing of
    for y in range(ARCH_TO, 152):                           # the Apple's by it
        c = cols[y][COLUMN:COLUMN + 3]
        rect2(pix, x, y, 8, 1, zx(BLACK))
        if all(v in (A_WHITE, A_YELLOW) for v in c):
            rect2(pix, x + 2, y, 6, 1, zx(YELLOW))
        elif any(v in (A_ORANGE, A_BLUE) for v in c):
            for i, v in enumerate((c[0], c[0], c[1], c[1], c[2], c[2])):
                put2(pix, x + 2 + i, y, zx(YELLOW) if v == A_ORANGE else zx(BLUE))


def sides(pix, cols):
    arch(pix)
    # the awning: stripes of white and crimson, a cell of each by turns --
    # a whole cell each, so the black under them is the only other colour
    # either has; the white is the grey the Apple's white cloth reads as
    rect2(pix, SIDE, 88, 40, 16, zx(BLACK))
    for cx in range(5):
        x = SIDE + cx * 8
        rect2(pix, x, 88, 8, 14, zx(WHITE) if cx % 2 == 0 else zx(RED, 1))
    # the wall under it: bricks of two blues by turns, on black
    for cy in range(13, 21):
        for cx in range(5):
            x, y = SIDE + cx * 8, cy * 8
            rect2(pix, x, y, 8, 8, zx(BLACK))
            rect2(pix, x, y, 6, 6, zx(BLUE, (cx + cy) & 1))
    column(pix, cols)
    # the block it stands on, yellow, lit along its top and outer side
    rect2(pix, 40, 152, 28, 16, zx(BLACK))
    rect2(pix, 40, 152, 24, 16, zx(YELLOW))
    rect2(pix, 40, 152, 24, 2, zx(WHITE))
    rect2(pix, 40, 152, 2, 16, zx(WHITE))


def splash_picture(pix, cols):
    find_arch(pix)
    smooth_arch()
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


def letters(pix, mask, y0, y1, x0, x1, ground=None, ink=LETTER):
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
                # inside the border: the title's tips reach two pixels
                # past the picture, and a letter in the border's cells
                # would take their colours from its tiles
                if v and SIDE <= sx + i < 256 - SIDE:
                    pix[top + j][sx + i] = ink


# The story screens: white letters on a ground of dark blue, a dot in every
# other colour in a check with black, inside the border -- colours 8 to
# 131, lines 14 to 167.  A letter's dot is lit and not the ground's.
STORY = ('prolog', 'sumup')
GROUND = A_DKBLUE


# The story's text: the Apple sets it in dots, four to a colour, and two of
# them to a Spectrum pixel left its letters ragged whichever way they were
# halved.  So it is set again in the face "presents" has, a pixel wider
# apart so the lines run as far as the Apple's, each line where the Apple's
# starts and on its line; the great initial letter of each page stays the
# Apple's.
STORY_TEXT = {
    'prolog': [(51, 44, "n the Sultan's absence"),
               (51, 60, 'the Grand Vizier JAFFAR'),
               (26, 76, 'rules with the iron fist of'),
               (26, 92, 'tyranny.  Only one obstacle'),
               (26, 109, 'remains between Jaffar and'),
               (26, 125, "the throne: the Sultan's"),
               (26, 142, 'beautiful young daughter. . . .')],
    'sumup': [(80, 45, 'arry Jaffar . . . or die'),
              (80, 62, 'within the hour.  All'),
              (32, 78, "the Princess's hopes now"),
              (32, 94, 'rest on the brave youth she'),
              (32, 111, 'loves.  Little does she know'),
              (32, 127, 'that he is already a prisoner'),
              (32, 144, "in Jaffar's dungeons. . . .")],
}
INITIAL = 16                # taller than this, a letter is the initial
STORY_GAP = 2               # between letters: the lines as long as the Apple's


def story(pix, cols, dots, name):
    for y in range(TOP + 2, FOOT):
        for x in range(SIDE + 1, 255 - SIDE):
            pix[y][x] = zx(BLUE)
    mask = [[bool(dots[y][d]) and cols[y][d >> 2] != GROUND
             for d in range(560)] for y in range(192)]
    initial = [[False] * 560 for _ in range(192)]
    for left, top, bits in components(mask, TOP + 2, FOOT, 8 * 4, 132 * 4):
        if len(bits) > INITIAL:
            for j, row in enumerate(bits):
                for i, c in enumerate(row):
                    if c == '#':
                        initial[top + j][left + i] = True
    letters(pix, initial, TOP + 2, FOOT, 8 * 4, 132 * 4)
    for x, baseline, text in STORY_TEXT[name]:
        assert x + big_width(text, STORY_GAP) <= 255 - SIDE - 1, text
        big_text(pix, text, None, baseline, left=x, gap=STORY_GAP)


def credit(pix, apple, cols, dots, splash, upto=FOOT, ink=LETTER):
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
    letters(pix, mask, TOP, upto, 0, 560, ink=ink)


def edges(pix):
    """A black edge a pixel wide round every letter."""
    edge = heavy(BLACK)
    for y in range(TOP, FOOT):
        for x in range(SIDE, 256 - SIDE):
            if pix[y][x] in (LETTER, TITLE):
                continue
            if any(0 <= y + dy < 192 and pix[y + dy][x + dx] in (LETTER, TITLE)
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                pix[y][x] = edge


# "Broderbund Software presents": the Apple sets it in a narrow face whose
# strokes run into each other two dots to a pixel.  It is set again, where
# the Apple has it, in a face of the same height with room between the
# strokes; the Broderbund sign above it stays the Apple's.
PRESENTS_AT = 118           # the first line under the sign
BIG = {
    ' ': ['...'] * 10,
    'B': ['#####.', '##..##', '##..##', '##..##', '#####.', '##..##', '##..##',
          '##..##', '##..##', '#####.'],
    'S': ['.####.', '##..##', '##....', '##....', '.####.', '....##', '....##',
          '....##', '##..##', '.####.'],
    'a': ['.####.', '....##', '.#####', '##..##', '##..##', '##..##', '.#####'],
    'b': ['##....', '##....', '##....', '#####.', '##..##', '##..##', '##..##',
          '##..##', '##..##', '#####.'],
    'd': ['....##', '....##', '....##', '.#####', '##..##', '##..##', '##..##',
          '##..##', '##..##', '.#####'],
    'e': ['.####.', '##..##', '##..##', '######', '##....', '##..##', '.####.'],
    'f': ['..###.', '.##..#', '.##...', '#####.', '.##...', '.##...', '.##...',
          '.##...', '.##...', '.##...'],
    'n': ['#####.', '##..##', '##..##', '##..##', '##..##', '##..##', '##..##'],
    'o': ['.####.', '##..##', '##..##', '##..##', '##..##', '##..##', '.####.'],
    'p': ['#####.', '##..##', '##..##', '##..##', '##..##', '##..##', '#####.',
          '##....', '##....', '##....'],
    'r': ['##.###', '###...', '##....', '##....', '##....', '##....', '##....'],
    's': ['.####.', '##..##', '##....', '.####.', '....##', '##..##', '.####.'],
    't': ['.##...', '.##...', '#####.', '.##...', '.##...', '.##...', '.##...',
          '.##..#', '..###.'],
    'u': ['##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '.#####'],
    'w': ['##...##', '##...##', '##...##', '##.#.##', '#######', '###.###',
          '.#...#.'],
    'J': ['..####', '....##', '....##', '....##', '....##', '....##', '....##',
          '##..##', '##..##', '.####.'],
    'M': ['##....##', '###..###', '########', '##.##.##', '##....##',
          '##....##', '##....##', '##....##', '##....##', '##....##'],
    'c': ['.####.', '##..##', '##....', '##....', '##....', '##..##', '.####.'],
    'g': ['.#####', '##..##', '##..##', '##..##', '##..##', '##..##', '.#####',
          '....##', '##..##', '.####.'],
    'h': ['##....', '##....', '##....', '#####.', '##..##', '##..##', '##..##',
          '##..##', '##..##', '##..##'],
    'm': ['#########.', '##..##..##', '##..##..##', '##..##..##', '##..##..##',
          '##..##..##', '##..##..##'],
    'y': ['##..##', '##..##', '##..##', '##..##', '##..##', '##..##', '.#####',
          '....##', '##..##', '.####.'],
}
BIG.update({
    'A': ['.####.', '##..##', '##..##', '##..##', '######', '##..##', '##..##',
          '##..##', '##..##', '##..##'],
    'F': ['######', '##....', '##....', '##....', '#####.', '##....', '##....',
          '##....', '##....', '##....'],
    'G': ['.####.', '##..##', '##....', '##....', '##.###', '##..##', '##..##',
          '##..##', '##..##', '.#####'],
    'L': ['##....'] * 9 + ['######'],
    'O': ['.####.'] + ['##..##'] * 8 + ['.####.'],
    'P': ['#####.', '##..##', '##..##', '##..##', '#####.', '##....', '##....',
          '##....', '##....', '##....'],
    'R': ['#####.', '##..##', '##..##', '##..##', '#####.', '####..', '##.##.',
          '##..##', '##..##', '##..##'],
    'T': ['######'] + ['..##..'] * 9,
    'V': ['##..##'] * 6 + ['.####.', '.####.', '..##..', '..##..'],
    'i': ['##', '##', '..', '##', '##', '##', '##', '##', '##', '##'],
    'k': ['##....', '##....', '##....', '##..##', '##.##.', '####..', '###...',
          '####..', '##.##.', '##..##'],
    'l': ['##'] * 10,
    'v': ['##..##', '##..##', '##..##', '##..##', '.####.', '.####.', '..##..'],
    'z': ['######', '....##', '...##.', '..##..', '.##...', '##....', '######'],
    '.': ['##', '##'],
    ':': ['##', '##', '..', '..', '..', '##', '##'],
    "'": ['##', '##', '.#', '#.', '..', '..', '..', '..', '..', '..'],
})
DESCENDS = ('p', 'g', 'y')


def big_width(text, gap=1):
    return sum(len(BIG[ch][0]) + gap for ch in text) - gap


def big_text(pix, text, centre, baseline, left=None, gap=1):
    """A line of BIG, centred on a pixel or from a left edge, its letters
    sitting on a line, gap pixels apart."""
    x = left if left is not None else centre - big_width(text, gap) // 2
    for ch in text:
        glyph = BIG[ch]
        top = baseline - len(glyph) + (3 if ch in DESCENDS else 0)
        for j, row in enumerate(glyph):
            for i, c in enumerate(row):
                if c == '#':
                    pix[top + j][x + i] = LETTER
        x += len(glyph[0]) + gap


def byline(pix):
    """"a game by Jordan Mechner": the Apple sets it in a serif face whose
    strokes, two dots to a pixel, come out ragged; it is set again in the
    face "presents" has, on the Apple's lines and across its middle."""
    big_text(pix, 'a game by', 131, 126)
    big_text(pix, 'Jordan Mechner', 128, 140)


def presents(pix):
    # the Apple's lines: its letters' feet on 129 and 143; across, the
    # middle of the screen
    big_text(pix, 'Broderbund Software', 128, 130)
    big_text(pix, 'presents', 128, 144)


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
    if name not in STORY:
        apex(pix)
    if name in STORY:
        story(pix, cols, dots, name)
    elif name != 'splash':
        if name == 'presents':
            credit(pix, apple, cols, dots, splash, upto=PRESENTS_AT)
            presents(pix)
        elif name == 'byline':
            byline(pix)
        else:
            credit(pix, apple, cols, dots, splash, ink=TITLE)
        edges(pix)
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
