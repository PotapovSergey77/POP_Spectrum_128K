"""
The palace's colours, cell by cell.

The dungeon is one ink, and so was the palace until the user asked for it
grey with its windows yellow as before, the frames of its exit doors blue,
the panels over its gates a blue pattern in a grey frame, and the arches'
lattice high up the wall blue, as the Apple has it.  The Spectrum colours a
cell of eight by eight at a time, so each of those is a cell every lit pixel
of which belongs to that one thing: a room is drawn here as renderroom draws
it, remembering which picture lit each pixel, and a cell takes the colour of
what lit it only when nothing else did.  What changes as the game goes --
a gate, the door rising -- is drawn in the state the level begins with, and
anything it lights counts against the cell, so a cell the door slides
through stays grey.

The result is a list of rectangles of cells for each room, which the game
applies over the room's grey whenever the colours are worked out
(set_attrs); see bgovl.asm.

    palcolour.py <level> [room]     the colour map, as text
"""
import os
import sys

import bgdata as bg
import bgexport
import poplevel
import renderroom as R

INK_YELLOW = 0x46               # bright yellow, the palace as it was
INK_BLUE = 0x41                 # bright blue

WINDOWS = {bg.spaceb[3], 0x91, 0x92, 0x93, 0x94}
DOORS = {bg.pieceb[bg.exit_], bg.pieceb[bg.exit2],
         bg.piecec[bg.exit_], bg.piecec[bg.exit2], bg.toprepair}
# Pixels that colour nothing and spoil nothing: the stick of a torch that
# stands against a door's post, and the foot of an arch's pillar head,
# a pixel or two in the arches' last row of cells.
NEUTRAL = {bg.pieceb[bg.torch], bg.pieced[bg.archtop1]}
DOOR_FLOOR = 48                 # the posts' pictures have the floor below
PANEL = 0x80 | bgexport.PANEL_IMG


# The arches: the tops of the three kinds are the curve, its lattice and
# the dotted field under it, all blue on the Apple; the first, which stands
# between them, is the frieze above, the pillar's head, and either side of
# it the lattice where two arches meet -- only that is blue.
ARCHES = {bg.piecea[bg.archtop2], bg.piecea[bg.archtop3], bg.piecea[bg.archtop4]}
ARCH1 = bg.piecea[bg.archtop1]
ARCH1_FROM = 24                 # its rows above are the frieze
ARCH1_PILLAR = (8, 19)          # and these its pillar


# And the ends of a row of arches, which are panels: the first, over a
# wall, is the lattice where the last arch meets it; the arch's own panel
# (archpanel) ends at a gate's post.
ARCH_ENDS = {bg.panelb[0]: 32, bg.archpanel: 21}


def arch_blue(img, x, r):
    if img in ARCHES:
        return True
    if img in ARCH_ENDS:
        return r >= ARCH1_FROM and x < ARCH_ENDS[img]
    return (img == ARCH1 and r >= ARCH1_FROM
            and not ARCH1_PILLAR[0] <= x < ARCH1_PILLAR[1])


# The rail along the wall with its diamonds, blue on the Apple, where he
# never stands by it (the user's choice, room by room): over nothing
# (spaceb) and over spikes (the palace's wall stripe, bstripe).  Where he
# walks it stays grey, or he would be blue going past.
RAILS = {bg.spaceb[1], bg.spaceb[2]}
# The B sections of what he stands on carry the rail on along the wall.
FLOOR_RAILS = {bg.floorb[1], bg.floorb[2], bg.pieceb[bg.floor],
               bg.pieceb[bg.spikes], bg.pieceb[bg.posts], bg.looseb,
               bg.pieceb[bg.rubble], bg.pieceb[bg.bones]}


def panel_rows(r):
    return bgexport.PANEL_PAT[1] <= r < bgexport.PANEL_FIELD[3]


def panel_blue(x, r):
    px, py = bgexport.PANEL_PAT
    return px <= x < px + len(bgexport.DIAMOND[0]) and panel_rows(r)


class Owned(R.Room):
    """A room drawn with, for every lit pixel, what lit it: (picture, its x,
    its row, the tile to the left when it is a B section)."""

    preced = None

    def draw_b(self, st):
        self.preced = st['preced']
        super().draw_b(st)
        self.preced = None

    def __init__(self, bgset='PAL'):
        super().__init__(bgset, edges=False)
        self.owner = [[None] * (R.WIDTH_BYTES * 7) for _ in range(R.HEIGHT)]

    def draw(self, imgnum, xco, yco, op, shift=0):
        super().draw(imgnum, xco, yco, op, shift)
        if not imgnum or op in (R.AND, R.MASK, R.XOR):
            return
        img = (self.tab2 if imgnum & 0x80 else self.tab1).get(imgnum & 0x7f)
        if img is None:
            return
        if shift:
            img = R.shifted(img, shift, False)
        top = yco - img.height + 1
        for r, row in enumerate(img.pixels()):
            y = top + r
            if not 0 <= y < R.HEIGHT:
                continue
            for x, on in enumerate(row):
                sx = xco * 7 + x
                if 0 <= sx < R.WIDTH_BYTES * 7 and (on or op == R.STA):
                    self.owner[y][sx] = ((imgnum, x - shift, r, self.preced)
                                         if on else None)


def kind(own):
    """What colour a lit pixel asks for: 'Y', 'B', or '.' for grey."""
    img, x, r, preced = own
    if img in NEUTRAL:
        return None
    if img in RAILS or (img == bg.bstripe[bg.floor] and preced == bg.spikes):
        return 'R'                      # blue, if all of it can be: rails
    if img in FLOOR_RAILS or img == bg.bstripe[bg.floor]:
        return 'F'                      # the same rail, where he walks
    if img in WINDOWS:
        return 'Y'
    if img in DOORS and r < DOOR_FLOOR:
        return None                     # its own shape: door_cells
    if img == PANEL and panel_blue(x, r):
        return 'B'
    if img == PANEL:
        return 'P'                      # its frame: see cells
    if arch_blue(img, x, r):
        return 'B'
    return '.'


def door_cells(room, grid, entrance):
    """An exit door's frame, blue as a whole, the shape the user asked for
    -- cell by cell it came out ragged where the frame and the door in it
    share a cell: the lintel the cells along its top from one post to the
    other, and each post a column of cells down to the one above the
    threshold.  The way out's posts have every cell they reach, the way
    in's only the one with most of each; the lintel is two cells deep."""
    px = []
    for y in range(R.HEIGHT):
        for x in range(R.WIDTH_BYTES * 7):
            own = room.owner[y][x]
            if (own and own[0] in DOORS and own[2] < DOOR_FLOOR
                    and room.canvas[y][x // 7] >> (x % 7) & 1):
                px.append((x, y))
    doors = []                          # a room's doors, apart by x
    for x, y in sorted(px):
        if doors and x - doors[-1][-1][0] < 40:
            doors[-1].append((x, y))
        else:
            doors.append([(x, y)])
    for d in doors:
        top = min(y for x, y in d) // 8
        bot = max(y for x, y in d) // 8 - 1
        mid = (d[0][0] + d[-1][0]) // 2
        posts = set()
        for side in (lambda x: x < mid, lambda x: x > mid):
            cols = [x // 8 for x, y in d
                    if side(x) and top + 2 < y // 8 <= bot]
            main = max(set(cols), key=cols.count)
            if entrance:
                posts.add(main)
            else:
                span = set(range(min(cols), max(cols) + 1))
                # but not a column on the door's inside with less than
                # half the post in it: only its thin edge (the user, level
                # five's exit)
                inner = max(span) if side(0) else min(span)
                if (len(span) > 1 and inner != main
                        and cols.count(inner) * 2 < cols.count(main)):
                    span.discard(inner)
                posts |= span
        deep = 2
        for cy in range(top, top + deep):
            for cx in range(min(posts), max(posts) + 1):
                grid[cy][cx] = 'B'
        for cy in range(top + deep, bot + 1):
            for cx in posts:
                grid[cy][cx] = 'B'


# A rail is blue only where the whole of it can be: along its row of cells,
# a run of it -- windows standing in front of it are no break -- all of
# whose cells are rail and nothing else, but for the two at its ends, where
# it meets a wall, with none of it going on over a floor ('f'), and long
# enough to be the rail along a wall and not the end of one poking out past
# a post.  Coloured in part it looked unfinished (the user asked for it
# this way).
RAIL_RUN = 8


def rails(line):
    out = list(line)
    x = 0
    while x < len(out):
        if out[x] not in 'Rrf':
            x += 1
            continue
        e = x
        while e < len(out) and out[e] in 'RrfY':
            e += 1
        while out[e - 1] == 'Y':
            e -= 1
        run = out[x:e]
        whole = ('r' not in run[1:-1] and 'f' not in run
                 and run.count('R') >= RAIL_RUN)
        for i in range(x, e):
            if out[i] in 'Rrf':
                out[i] = 'B' if whole and out[i] == 'R' else ' '
        x = e
    return ''.join(out)


def cells(level, n):
    """The room's 24 rows of 35 cells: 'Y', 'B', or ' ' for the room's own."""
    room = Owned('PAL')
    room.build(level, n)
    out, raw = [], []
    for cy in range(24):
        line = ''
        for cx in range(35):
            ks = set()
            for y in range(cy * 8, cy * 8 + 8):
                for x in range(cx * 8, cx * 8 + 8):
                    if y < R.HEIGHT and room.canvas[y][x // 7] >> (x % 7) & 1:
                        own = room.owner[y][x]
                        ks.add(kind(own) if own else '.')
            ks.discard(None)
            # A cell with some of the panel's chain is blue whatever of the
            # panel's own frame shares it -- its last link with the frame's
            # foot, or four pixels along the cells its side -- or the chain
            # stops short, or is not blue at all (the user).  Something
            # else in it still keeps it grey.
            if 'P' in ks:
                ks.discard('P')
                if ks != {'B'}:
                    ks.add('.')
            line += ('f' if 'F' in ks else 'r' if 'R' in ks and ks != {'R'}
                     else ks.pop() if len(ks) == 1 and ks != {'.'} else ' ')
        raw.append(line)
        out.append(list(rails(line)))
    # and the tips of its diamonds, in the cells above and below a rail
    # that is blue
    for cy in range(24):
        for cx in range(35):
            if raw[cy][cx] == 'R' and any(
                    0 <= cy + d < 24 and raw[cy + d][cx] in 'Rr'
                    and out[cy + d][cx] == 'B' for d in (-1, 1)):
                out[cy][cx] = 'B'
    door_cells(room, out, n == level.kid_start[0])
    return [''.join(line) for line in out]


def rects(grid):
    """The coloured cells as rectangles: (ink, x, y, w, h), rows of a run
    merged downward while they match.  The blue are laid first and the
    yellow over them, so a blue one may run under a window."""
    out = []
    for c, wild in (('B', 'Y'), ('Y', None)):
        done = set()

        def fits(x, y):
            return (grid[y][x] == c and (x, y) not in done) or grid[y][x] == wild
        for y in range(len(grid)):
            x = 0
            while x < 35:
                if grid[y][x] != c or (x, y) in done:
                    x += 1
                    continue
                w = 1
                while x + w < 35 and fits(x + w, y):
                    w += 1
                while grid[y][x + w - 1] == wild:
                    w -= 1
                h = 1
                while (y + h < len(grid) and h < 8
                       and all(fits(x + i, y + h) for i in range(w))
                       and any(grid[y + h][x + i] == c for i in range(w))):
                    h += 1
                for j in range(h):
                    for i in range(w):
                        if grid[y + j][x + i] == c:
                            done.add((x + i, y + j))
                out.append((INK_YELLOW if c == 'Y' else INK_BLUE, x, y, w, h))
                x += w
    return out


# The most rectangles a room may have: the game copies that many for every
# room into imgbuf, with the code that lays them (bgovl.asm).
MAXRECTS = 16
LISTMAX = 2 + 3 * MAXRECTS


def level_colours(level_path):
    """The bytes the game keeps for a palace level: for each room in turn,
    how many rectangles are blue and then each of them as left cell, top
    row * 8 + rows - 1, width; and the same for the yellow."""
    level = poplevel.Level(level_path)
    level.data = bgexport.level_blob(level_path)
    blob = bytearray()
    for n in range(1, 25):
        rs = rects(cells(level, n))
        assert len(rs) <= MAXRECTS, 'room %d has %d colours' % (n, len(rs))
        ys = [r for r in rs if r[0] == INK_YELLOW]
        bs = [r for r in rs if r[0] == INK_BLUE]
        for group in (bs, ys):
            blob.append(len(group))
            for ink, x, y, w, h in group:
                blob += bytes([x, y * 8 + h - 1, w])
    return bytes(blob)


if __name__ == '__main__':
    lv = int(sys.argv[1])
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                        '01 POP Source', 'Levels', 'LEVEL%d' % lv)
    level = poplevel.Level(path)
    level.data = bgexport.level_blob(path)
    for n in ([int(sys.argv[2])] if len(sys.argv) > 2 else range(1, 25)):
        g = cells(level, n)
        print('room %d: %d rectangles' % (n, len(rects(g))))
        for line in g:
            print('  |' + line + '|')
