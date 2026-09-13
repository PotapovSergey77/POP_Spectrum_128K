"""
Assemble one Prince of Persia room into a 280x192 image.

Mirrors the background pass of FRAMEADV.S: rows bottom-to-top, columns
left-to-right, each block drawn by RedBlockSure as C, maskB, B, D, A, maskA,
front.  Movable sub-sections (drawmc/drawmb/drawmd/drawma -- spikes, slicers,
gates, flasks, swords) are not drawn here; those need MOVEDATA state and are
animated at runtime.

Geometry (TABLES.S, FRAMEADV.S):
  a block is 4 bytes = 28 hires pixels, a room is 10 blocks = 40 bytes = 280 px
  BlockBot = [2, 65, 128, 191, 254]; row r uses Dy = BlockBot[r+1], Ay = Dy-3
  A/B sections hang from Ay, C/D sections from Dy, both bottom-referenced

Usage: renderroom.py <LEVEL file> [screen] [out.png]
"""
import os
import sys

import bgdata as bg
import pngwrite
import popimg
import poplevel

WIDTH_BYTES, HEIGHT = 40, 192
BLOCK_PX = 28                   # a block is 4 bytes of 7 pixels
BLOCKBOT = [2, 65, 128, 191, 254]

AND, ORA, STA, XOR, MASK = 0, 1, 2, 3, 4

IMAGES = os.path.join(os.path.dirname(__file__), '..', '..',
                      '01 POP Source', 'Images')


class Room:
    def __init__(self, bgset='DUN', edges=True):
        self.tab1 = popimg.Table(os.path.join(IMAGES, 'IMG.BGTAB1.' + bgset))
        self.tab2 = popimg.Table(os.path.join(IMAGES, 'IMG.BGTAB2.' + bgset))
        self.palace = (bgset == 'PAL')
        self.canvas = [bytearray(WIDTH_BYTES) for _ in range(HEIGHT)]
        self.missing = set()
        self.filtered = {} if edges else None

    def draw(self, imgnum, xco, yco, op):
        """setbgimg: bit 7 of the image number picks BGTAB2, index is bits 0-6."""
        if not imgnum:
            return
        table = self.tab2 if imgnum & 0x80 else self.tab1
        img = table.get(imgnum & 0x7f)
        if img is None:
            self.missing.add(imgnum)
            return
        # Masks must keep their exact bits, so only painted pieces get a
        # replacement fill.
        if self.filtered is not None and op in (ORA, STA):
            fn = piece_filter(imgnum)
            if fn is not None:
                if imgnum not in self.filtered:
                    self.filtered[imgnum] = fn(img)
                img = self.filtered[imgnum]
        top = yco - img.height + 1          # images are bottom-referenced
        for r in range(img.height):
            y = top + r
            if not 0 <= y < HEIGHT:
                continue
            row, line = img.row(r), self.canvas[y]
            for c in range(img.width):
                x = xco + c
                if not 0 <= x < WIDTH_BYTES:
                    continue
                b = row[c] & 0x7f           # drop the palette bit
                if op in (AND, MASK):
                    line[x] &= b
                elif op == ORA:
                    line[x] |= b
                elif op == STA:
                    line[x] = b
                elif op == XOR:
                    line[x] ^= b

    # -- the section passes of RedBlockSure -------------------------------

    def draw_c(self, st):
        if not self._checkc(st):
            return
        self._dodrawc(st)
        self.mask_b(st)

    @staticmethod
    def _checkc(st):
        """checkc: is the C section of the piece below and left visible?"""
        objid = st['objid']
        return (objid == bg.space or objid == bg.pillartop or
                objid == bg.panelwof or objid >= bg.archtop1)

    def _dodrawc(self, st):
        x = st['below']
        if x == bg.block:
            y = st['sbelow'] if st['sbelow'] < bg.numblox else 0
            img = bg.blockc[y]
        else:
            img = bg.piecec[x]
            if img == bg.panelc0:
                if st['sbelow'] >= bg.numpans:
                    return
                img = bg.panelc[st['sbelow']]
        if img:
            self.draw(img, st['xco'], st['Dy'], ORA)

    def draw_mc(self, st):
        """
        Movable C sections (drawmc).  Only a gate has one: the top of its
        bars pokes up into the block above and to the right, and how far up
        depends on how open it is.
        """
        if st['objid'] not in (bg.space, bg.panelwof, bg.pillartop):
            return                          # an A section would cover it
        if st['below'] != bg.gate:
            return
        self._drawgatec(st)

    def _drawgatec(self, st):
        self.draw(bg.gatecmask, st['xco'], st['Dy'], AND)
        state = min(st['sbelow'], bg.gmaxval)
        self.draw(bg.gate8c[(state >> 2) % 8], st['xco'], st['Dy'], ORA)

    def mask_b(self, st):
        img = bg.maskb[st['preced']]
        if img:
            self.draw(img, st['xco'], st['Dy'], AND)

    def draw_b(self, st):
        if st['objid'] == bg.block:
            return                          # hidden by a solid block
        x, sp = st['preced'], st['spreced']
        if x == bg.space:
            if sp >= bg.numbpans + 1:
                return
            img, dy = bg.spaceb[sp], bg.spaceby[sp]
        elif x == bg.floor:
            y = sp if sp < bg.numbpans + 1 else 0
            img, dy = bg.floorb[y], bg.floorby[y]
        elif x == bg.block:
            y = sp if sp < bg.numblox else 0
            img, dy = bg.blockb[y], bg.pieceby[x]
        else:
            img = bg.pieceb[x]
            if img == bg.panelb0:
                if sp >= bg.numpans:
                    return
                img, dy = bg.panelb[sp], bg.pieceby[x]
            elif img:
                self.draw(img, st['xco'], bg.pieceby[x] + st['Ay'], ORA)
                # the palace background set adds a wall stripe
                if self.palace and bg.bstripe[x]:
                    self.draw(bg.bstripe[x], st['xco'], st['Ay'] - 32, ORA)
                return
            else:
                return
        if img:
            self.draw(img, st['xco'], dy + st['Ay'], ORA)

    def draw_d(self, st):
        x = st['objid']
        op = STA
        if x == bg.block:
            y = st['state'] if st['state'] < bg.numblox else 0
            img = bg.blockd[y]
        else:
            if x == bg.panelwof:
                op = ORA
            img = bg.pieced[x]
        if img:
            self.draw(img, st['xco'], st['Dy'], op)

    def draw_a(self, st):
        preced, objid = st['preced'], st['objid']
        if preced == bg.archtop1:
            if objid == bg.panelwof:
                self.draw(bg.archpanel, st['xco'],
                          st['Ay'] + bg.pieceay[objid], ORA)
                return
        elif preced in (bg.panelwif, bg.panelwof, bg.pillartop, bg.block):
            if bg.maska[objid]:
                self.draw(bg.maska[objid], st['xco'], st['Ay'], AND)
        if objid == bg.loose:
            y = st['state'] & 0x7f if st['state'] & 0x80 else 0
            img = bg.loosea[min(y, len(bg.loosea) - 1)]
        elif objid == bg.sword:
            # drawsworda: piecea has no picture for the sword, it has one of
            # its own, and it gleams -- state 1 is the bright one.
            img = bg.swordgleam1 if st['state'] == 1 else bg.swordgleam0
        else:
            img = bg.piecea[objid]
        if img:
            self.draw(img, st['xco'], st['Ay'] + bg.pieceay[objid], ORA)

    def draw_mb(self, st):
        """
        Movable B sections (drawmb).  A loose floor has no pieceb at all --
        its B section comes from `looseb`, so without this the floor tile to
        its right loses its left half.  Gates, spikes, torches and exits also
        dispatch here and still need doing.
        """
        if st['preced'] == bg.gate:
            self._drawgateb(st)
            return
        if st['preced'] == bg.exit_:
            self._drawexitb(st)
            return
        if st['preced'] != bg.loose:
            return
        y = self._loose_state(st['spreced'])
        self.draw(bg.looseb, st['xco'], st['Ay'] + bg.looseby[y], ORA)

    def _drawexitb(self, st):
        """
        The exit: stairs, and a door that rises four pixels to the step.

        Both stand in the block to the right of the exit tile, the way a
        gate's bars do.  In the room the prince starts in the same tile is
        the way he came in, so it gets no stairs.
        """
        if st['xco'] >= 36:
            return                              # it would run off the right
        xco = st['xco'] + 1                     # all of it stands one byte in
        if st['scrnum'] != st['startscrn']:
            self.draw(bg.stairs, xco, st['Ay'] - 12, STA)

        blockthr = st['Dy'] - 67                # topmost usable line
        if not 0 <= blockthr < 192:
            return
        yco = st['Ay'] - 14 - (st['spreced'] >> 2)
        while True:
            self.draw(bg.doormask, xco, yco, AND)
            self.draw(bg.door, xco, yco, ORA)
            if yco - 4 < blockthr:
                break
            yco -= 4

        top = st['Ay'] - 64                     # part of the C section really
        if 0 <= top < 192:
            self.draw(bg.toprepair, xco, top, STA)

    # -- the gate ---------------------------------------------------------
    #
    # A gate's bars hang in the block to its right, so they are drawn as that
    # block's movable B section.  The state is how far the gate has risen,
    # four pixels to the step; the bottom piece is laid at that height and
    # eight-line middle pieces are stacked above it up to the top of the B
    # section, with one of eight part-height shapes to finish.

    @staticmethod
    def _setupdgb(st):
        """setupdgb: the topmost line of the B section, and the gate's foot."""
        blockthr = st['Dy'] - 62
        gateposn = (min(st['spreced'], bg.gmaxval) >> 2) + 1
        return blockthr, st['Ay'] - gateposn

    def _restorebot(self, st):
        """
        The foot of the gate crosses the floor line, where a stamp would cut
        into the floor below it.  Put the background back and OR the foot on
        top of it instead.
        """
        self.draw(bg.pieceb[bg.gate], st['xco'],
                  bg.pieceby[bg.gate] + st['Ay'], STA)
        if self._checkc(st):
            self._dodrawc(st)
        self.draw_a(st)

    def _drawgateb(self, st):
        blockthr, gatebot = self._setupdgb(st)
        if gatebot + 12 >= st['Ay']:
            self._restorebot(st)
            self.draw(bg.gatebotORA, st['xco'], gatebot - 2, ORA)
        else:
            self.draw(bg.gatebotSTA, st['xco'], gatebot, STA)

        yco = gatebot - 12
        while True:
            if yco >= 192:
                return
            top = yco - 7                   # a middle piece is eight high
            if top < 0 or top < blockthr:
                break
            self.draw(bg.gateB1, st['xco'], yco, STA)
            yco -= 8
            if yco == 0:
                break
        height = yco - blockthr + 1         # what is left at the top
        if 0 < height < 9:
            self.draw(bg.gate8b[height - 1], st['xco'], yco, STA)

    def draw_md(self, st):
        """Movable D sections (drawmd): a loose floor's own top surface."""
        if st['objid'] != bg.loose:
            return
        y = self._loose_state(st['state'])
        self.draw(bg.loosed[y], st['xco'], st['Dy'], STA)

    @staticmethod
    def _loose_state(state):
        """
        getloosey.  A floor on its way down counts 1..Ffalling and the state
        is the frame; one that is only wiggling has bit 7 set and counts in
        the low bits, and anything past the last frame draws as the first.
        """
        if not state & 0x80:
            return min(state, bg.Ffalling)
        y = state & 0x7f
        return y if y <= bg.Ffalling else 1

    def draw_front(self, st):
        x = st['objid']
        img = bg.fronti[x]
        # drawfrnt: potions two to four stand in the taller bottle.
        if x == bg.flask and 0x40 <= st['state'] & 0xe0 != 0xa0:
            img = bg.specialflask
        if not img:
            return
        # The balusters are ORed on in the original, so whatever the tile to
        # the left painted here shows through the gaps between them.  Beside
        # rubble that is the debris pile, and the lower half of the column
        # fills in solid.  `fronti[posts]` is piecea's own columns 7..27 to
        # the pixel, so stamping it instead puts the tile's art back exactly
        # as drawn and takes the neighbour's B section out of the balusters.
        op = STA if (x >= bg.archtop2 or x == bg.posts) else ORA
        self.draw(img, st['xco'] + bg.frontx[x], st['Ay'] + bg.fronty[x], op)

    # -- room assembly ----------------------------------------------------

    def build(self, level, scrnum):
        types, specs = level.screen(scrnum)
        got = [self._subplate(level, b & poplevel.IDMASK, sp)
               for b, sp in zip(types, specs)]
        ids = [g[0] for g in got]
        specs = [g[1] for g in got]
        # GETINITOBJ: a flask carries its potion in the top three bits.  Its
        # bubbles count in the low five from nought, and bubble nought is the
        # blank one, so a room as it is first built shows none.
        specs = [(sp << 5) & 0xff if i == bg.flask else sp
                 for i, sp in zip(ids, specs)]
        prev, sprev = self._prev_screen(level, scrnum)

        for row in (2, 1, 0):
            Dy = BLOCKBOT[row + 1]
            Ay = Dy - 3
            # BELOW[col] is the block below and to the LEFT: getbelow stores
            # the row below starting at BELOW+1, so it is shifted by one, and
            # BELOW[0] comes from the screen to the left.
            if row < 2:
                below = [prev[row + 1]] + ids[(row + 1) * 10:(row + 1) * 10 + 9]
                sbelow = ([sprev[row + 1]]
                          + list(specs[(row + 1) * 10:(row + 1) * 10 + 9]))
            else:
                below, sbelow = self._below_screen(level, scrnum)

            preced, spreced = prev[row], sprev[row]
            for col in range(10):
                i = row * 10 + col
                st = {'objid': ids[i], 'state': specs[i],
                      'preced': preced, 'spreced': spreced,
                      'below': below[col], 'sbelow': sbelow[col],
                      'xco': col * 4, 'Dy': Dy, 'Ay': Ay,
                      'scrnum': scrnum, 'startscrn': level.kid_start[0]}
                self.draw_c(st)
                self.draw_mc(st)
                self.draw_b(st)
                self.draw_mb(st)
                self.draw_d(st)
                self.draw_md(st)
                self.draw_a(st)
                self.draw_front(st)
                preced, spreced = ids[i], specs[i]

        # SURE's last pass: the bottom row of the screen above, D-sections
        # only, at Dy = 2 and Ay = -1.  What shows along the top of the
        # screen is the underside of its floor -- the ceiling.  With no
        # screen above, a row of floorpieces.  PRECED starts empty; spreced
        # POP leaves as the row just drawn left it.
        above = level.links(scrnum)[2]
        if above:
            atypes, aspecs = level.screen(above)
            agot = [self._subplate(level, atypes[i] & poplevel.IDMASK,
                                   aspecs[i]) for i in range(20, 30)]
            aids = [g[0] for g in agot]
            aspecs = [g[1] for g in agot]
        else:
            aids, aspecs = [bg.floor] * 10, [0] * 10
        below = [prev[0]] + list(ids[0:9])
        sbelow = [sprev[0]] + list(specs[0:9])
        preced = 0
        for col in range(10):
            st = {'objid': aids[col], 'state': aspecs[col],
                  'preced': preced, 'spreced': spreced,
                  'below': below[col], 'sbelow': sbelow[col],
                  'xco': col * 4, 'Dy': 2, 'Ay': -1,
                  'scrnum': scrnum, 'startscrn': level.kid_start[0]}
            self.draw_c(st)
            self.draw_mc(st)
            self.draw_b(st)
            self.draw_d(st)
            self.draw_md(st)
            self.draw_front(st)
            preced, spreced = aids[col], aspecs[col]

        self.hatch_walls(ids)

    @staticmethod
    def _subplate(level, objid, state):
        """
        getobjid1: a plate that is down is not drawn as the piece the
        blueprint names.  Whether it is down is the count in LINKMAP, indexed
        by the plate's own state, so every read of a block goes through here.
        """
        if objid not in (bg.pressplate, bg.upressplate):
            return objid, state
        down = (level.data[poplevel.LINKMAP + state] & 0x1f) >= 2
        if objid == bg.pressplate:
            return (bg.dpressplate if down else bg.pressplate), state
        return (bg.floor, 0) if down else (bg.upressplate, state)

    @staticmethod
    def _prev_screen(level, scrnum):
        """
        getprev: the three rightmost blocks of the screen to the left.

        They seed PRECED for column 0, so whatever hangs off the right hand
        side of the room next door -- a wall face, or the bars of a gate in
        its last column -- lands here rather than being lost.  With no screen
        to the left POP puts a solid block there.
        """
        left = level.links(scrnum)[0]
        if not left:
            return [bg.block] * 3, [0] * 3
        types, specs = level.screen(left)
        got = [Room._subplate(level, types[i] & poplevel.IDMASK, specs[i])
               for i in (9, 19, 29)]
        return [g[0] for g in got], [g[1] for g in got]

    @staticmethod
    def _below_screen(level, scrnum):
        """
        getbelow for the bottom row: the top row of the screen underneath.

        Nothing to fall through means floor, and the corner block comes from
        the screen below and to the left -- a solid block if there is none.
        """
        below_num = level.links(scrnum)[3]
        if below_num:
            types, specs = level.screen(below_num)
            got = [Room._subplate(level, types[i] & poplevel.IDMASK, specs[i])
                   for i in range(9)]
            below = [0] + [g[0] for g in got]
            sbelow = [0] + [g[1] for g in got]
            corner = level.links(below_num)[0]
        else:
            below = [0] + [bg.floor] * 9
            sbelow = [0] * 10
            corner = 0
        if corner:
            types, specs = level.screen(corner)
            below[0], sbelow[0] = Room._subplate(
                level, types[9] & poplevel.IDMASK, specs[9])
        else:
            below[0] = bg.block
        return below, sbelow

    # Hatching laid over the finished room.
    #
    # The wall face $83 carries three courses of brick.  The top one is a
    # brick per tile, its joint falling on the tile boundary; the middle one
    # is offset by half a brick, its joint sitting at columns 14..17, so a
    # brick there straddles two tiles.  A course is given here as the rows it
    # occupies in the face and the columns of the tile a brick fills.
    #
    # The two are done differently, because they want different things.  The
    # half brick beside the rubble is struck again from nothing: it had to go
    # as dark as the rubble, so it is redrawn in the rubble's dither with its
    # own column of shadow.  The pair in the top course only wants taking
    # down a little, so the original stands and one dot in sixteen is knocked
    # out of it -- 76 per cent of the brick lit against 69, which is about
    # the least that reads as darker at all.  Nothing is ever
    # lit that was not, so the shadow the original throws comes through
    # untouched.  The middle course is
    # rows 22..41, columns 16..27 -- the joint to the tile edge -- and the
    # last of those is blacked out, since the half brick beside the rubble
    # has no neighbour to cast the shadow it needs.
    #
    # The hatch itself is the rubble's own diagonal, but two dots in four
    # rather than the rubble's one, which leaves it darker than the brick
    # beside it and lighter than the shadow it stands against.  Its phase
    # comes from the screen row, which is the only way the diagonals line up
    # with the rubble's -- so this works on the assembled canvas, and every
    # wall it does not name keeps the brick it was drawn with.

    FACE_HEIGHT = 60
    BRICK_DENSITY = 2                   # dots per four, against the brick's 3

    TOPCOURSE = (1, 21, 0, 28, 16)
    MIDCOURSE = (22, 42, 16, 28, 1, 0)

    # The middle floor: the second and fourth brick of its top course,
    # counted from the right hand end of the wall.
    FLOOR_HATCH = (1, TOPCOURSE, (2, 4))

    def hatch_walls(self, ids):
        """Beside the rubble, and wherever FLOOR_HATCH names a brick."""
        for row in range(3):
            for col in range(9):
                if (ids[row * 10 + col] == bg.block and
                        ids[row * 10 + col + 1] == bg.rubble):
                    self.hatch(row, col, self.MIDCOURSE)

        row, course, bricks = self.FLOOR_HATCH
        run = self.wall_run(ids, row)
        if run:
            lo, hi = run
            for n in bricks:
                if hi - n + 1 >= lo:
                    self.thin(row, hi - n + 1, course)

    @staticmethod
    def wall_run(ids, row):
        """The rightmost run of two or more wall blocks in a block row."""
        col = 9
        while col >= 0:
            if ids[row * 10 + col] != bg.block:
                col -= 1
                continue
            hi = col
            while col >= 0 and ids[row * 10 + col] == bg.block:
                col -= 1
            if hi - col >= 2:
                return col + 1, hi
        return None

    def thin(self, row, col, course):
        """Knock one dot in `every` out of the brick as it was drawn."""
        r0, r1, x0, x1, every = course
        top = BLOCKBOT[row + 1] - 3 - self.FACE_HEIGHT + 1
        for r in range(r0, r1):
            y = top + r
            if not 0 <= y < HEIGHT:
                continue
            line = self.canvas[y]
            for c in range(x0, x1):
                x = col * BLOCK_PX + c
                if not 0 <= x < WIDTH_BYTES * 7:
                    continue
                if (x - 2 * y) % every == 0:
                    line[x // 7] &= ~(1 << (x % 7)) & 0xff

    def hatch(self, row, col, course):
        r0, r1, x0, x1, shadow, thin = course
        top = BLOCKBOT[row + 1] - 3 - self.FACE_HEIGHT + 1
        for r in range(r0, r1):
            y = top + r
            if not 0 <= y < HEIGHT:
                continue
            line = self.canvas[y]
            for c in range(x0, x1):
                x = col * BLOCK_PX + c
                if not 0 <= x < WIDTH_BYTES * 7:
                    continue
                if c >= x1 - shadow:
                    lit = False                 # the shadow itself
                elif c >= x1 - shadow - thin:
                    lit = (x - 2 * y) % 8 < 2   # a dot every fourth row
                else:
                    lit = (x - 2 * y) % 4 < self.BRICK_DENSITY
                if lit:
                    line[x // 7] |= 1 << (x % 7)
                else:
                    line[x // 7] &= ~(1 << (x % 7)) & 0xff

    def to_pixels(self):
        """The assembled room as 192 rows of 280 zero/one values."""
        rows = []
        for line in self.canvas:
            out = bytearray()
            for b in line:
                for bit in range(7):
                    out.append((b >> bit) & 1)
            rows.append(out)
        return rows

    def to_png(self, path, pixels=None):
        rows = pixels if pixels is not None else self.to_pixels()
        pngwrite.write_gray(path, len(rows[0]), len(rows),
                            [bytes(255 if p else 0 for p in r) for r in rows])


# -- what the floorpieces put back over a character -------------------------
#
# DRAWFLOOR and DRAWHALF in FRAMEADV.S.  A character who is falling, hanging
# or climbing reaches up into the floor above him, and QUICKFLOOR marks those
# floorpieces so that they are laid down again after he has been drawn.  What
# they cover is not a rectangle: the floor's near edge is drawn in
# perspective, so the piece is a wedge, and without it he shows through the
# triangle at the end of the tile.
#
# DRAWHALF is climbup's own version, a shorter wedge, which leaves the hands
# he has on the ledge showing.  In the dungeon set only floor, torch, the
# down pressplate and the exit have a half piece; anything else falls back to
# the whole floorpiece, exactly as FRAMEADV.S does.

HALFPIECE = (1, 19, 5, 16)              # floor, torch, dpressplate, exit


class Cover(Room):
    """A room drawn only for what it would cover, a bit per pixel."""

    def __init__(self, bgset='DUN'):
        Room.__init__(self, bgset)
        self.mask = [bytearray(WIDTH_BYTES) for _ in range(HEIGHT)]
        self.recording = False

    def draw(self, imgnum, xco, yco, op):
        if self.recording and imgnum:
            table = self.tab2 if imgnum & 0x80 else self.tab1
            img = table.get(imgnum & 0x7f)
            if img is not None:
                top = yco - img.height + 1
                for r in range(img.height):
                    y = top + r
                    if not 0 <= y < HEIGHT:
                        continue
                    row, out = img.row(r), self.mask[y]
                    for c in range(img.width):
                        x = xco + c
                        if not 0 <= x < WIDTH_BYTES:
                            continue
                        b = row[c] & 0x7f
                        # an AND hides whatever it clears, an ORA whatever it
                        # sets, and an STA the whole of its rectangle
                        out[x] |= 0x7f if op == STA else (
                            ~b & 0x7f if op in (AND, MASK) else b)
        return Room.draw(self, imgnum, xco, yco, op)

    def floorpiece(self, st, half):
        """
        drawfloor, or drawhalf when there is a half piece for the tile.

        Both begin by asking whether the tile to the LEFT is empty space, and
        do nothing at all if it is not: the wedge is the near edge of a floor,
        and a floor that runs on into this one has no near edge here.  Without
        that test a tile whose neighbour is solid still laid its whole A
        section back over him, which is most of a figure climbing on to it.
        """
        if st['preced'] != bg.space:
            return
        objid = st['objid']
        if half and objid in HALFPIECE:
            yco = st['Ay'] + (1 if objid == bg.dpressplate else 0)
            self.draw(bg.CUmask, st['xco'], yco, AND)
            self.draw(bg.CUpiece, st['xco'], st['Ay'], ORA)
        else:
            if bg.maska[objid]:                     # addamask
                self.draw(bg.maska[objid], st['xco'], st['Ay'], AND)
            if objid == bg.loose:                   # adda
                y = st['state'] & 0x7f if st['state'] & 0x80 else 0
                img = bg.loosea[min(y, len(bg.loosea) - 1)]
            elif objid == bg.sword:                 # drawsworda
                img = bg.swordgleam1 if st['state'] == 1 else bg.swordgleam0
            else:
                img = bg.piecea[objid]
            if img:
                self.draw(img, st['xco'], st['Ay'] + bg.pieceay[objid], ORA)
        self.draw_d(st)


def floor_covers(level, scrnum, bgset='DUN'):
    """(floor, half): 192 rows of 280 pixels, set where the floor covers."""
    types, specs = level.screen(scrnum)
    ids = [b & poplevel.IDMASK for b in types]
    out = []
    prev = Room._prev_screen(level, scrnum)
    for half in (False, True):
        cov = Cover(bgset)
        cov.recording = True
        for row in range(3):
            Dy = BLOCKBOT[row + 1]
            preced, spreced = prev[0][row], prev[1][row]
            for col in range(10):
                i = row * 10 + col
                cov.floorpiece({'objid': ids[i], 'state': specs[i],
                                'preced': preced, 'spreced': spreced,
                                'xco': col * 4, 'Dy': Dy, 'Ay': Dy - 3}, half)
                preced, spreced = ids[i], specs[i]
        rows = []
        for line in cov.mask:
            px = bytearray()
            for b in line:
                for bit in range(7):
                    px.append((b >> bit) & 1)
            rows.append(px)
        out.append(rows)
    return out


# -- hybrid dither pass ---------------------------------------------------

DITHER_DX, DITHER_DY = 1, 1


def _dilate(px, dx, dy):
    h, w = len(px), len(px[0])
    out = [bytearray(w) for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if px[y][x]:
                for yy in range(max(0, y - dy), min(h, y + dy + 1)):
                    row = out[yy]
                    for xx in range(max(0, x - dx), min(w, x + dx + 1)):
                        row[xx] = 1
    return out


def _erode(px, dx, dy):
    h, w = len(px), len(px[0])
    out = [bytearray(w) for _ in range(h)]
    for y in range(h):
        for x in range(w):
            keep = 1
            for yy in range(y - dy, y + dy + 1):
                if not 0 <= yy < h:
                    continue            # off-image counts as set, so edges hold
                row = px[yy]
                for xx in range(x - dx, x + dx + 1):
                    if 0 <= xx < w and not row[xx]:
                        keep = 0
                        break
                if not keep:
                    break
            out[y][x] = keep
    return out


def solidify(pixels, dx=DITHER_DX, dy=DITHER_DY):
    """
    Hybrid dither pass: a morphological closing that floods dense dither to
    solid ink and leaves sparse hatching alone.

    Apple II background art is dithered for NTSC composite artifacting, which
    a Spectrum does not do -- rendered literally it turns into moire.  A
    closing with a 3x3 element fills gaps of one or two pixels, so the 50%
    and 75% patterns used for floors and wall faces go solid, while the 25%
    diagonal hatching that shades large blocks keeps its 3-pixel gaps and
    still reads as texture.  Closing never shrinks or grows a silhouette, so
    outlines and single-pixel details come through untouched.
    """
    closed = _erode(_dilate(pixels, dx, dy), dx, dy)
    for y in range(len(pixels)):                # closing contains the original
        row, out = pixels[y], closed[y]
        for x in range(len(row)):
            if row[x]:
                out[x] = 1
    return closed


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    level = poplevel.Level(argv[1])
    scrnum = int(argv[2]) if len(argv) > 2 else level.kid_start[0]
    out = argv[3] if len(argv) > 3 else pngwrite.build_png('room.png')
    room = Room('DUN')
    room.build(level, scrnum)
    room.to_png(out)
    print('screen %d -> %s' % (scrnum, out))
    if room.missing:
        print('missing image numbers:',
              ' '.join('$%02x' % m for m in sorted(room.missing)))
    return 0



def despeckle(pixels):
    """
    The gentlest possible clean-up: fill only holes whose eight neighbours are
    all set.  A 75% dither has isolated single-pixel holes and loses them; a
    50% checkerboard has empty diagonals around every hole and survives whole,
    so the tonal gradation that gives the walls their depth is left alone.
    """
    h, w = len(pixels), len(pixels[0])
    out = [bytearray(r) for r in pixels]
    for y in range(1, h - 1):
        row, above, below = pixels[y], pixels[y - 1], pixels[y + 1]
        o = out[y]
        for x in range(1, w - 1):
            if row[x]:
                continue
            if (above[x - 1] and above[x] and above[x + 1] and
                    row[x - 1] and row[x + 1] and
                    below[x - 1] and below[x] and below[x + 1]):
                o[x] = 1
    return out


# Block rows occupy roughly BlockBot[r+1]-62 .. BlockBot[r+1] on screen.
ROW_SPLITS = (66, 129)


def tile_attrs(level, scrnum, camera, wall, detail, wall_ids=(bg.block,)):
    """
    An attribute per 8x8 cell, chosen by the BLUETYPE tile the cell sits over
    rather than by how many pixels happen to be lit there.  With black paper
    an attribute only colours the ink, so cells over empty parts of a tile
    cost nothing -- which makes the tile map the honest source for this.
    """
    types, _ = level.screen(scrnum)
    ids = [b & poplevel.IDMASK for b in types]
    attrs = bytearray(768)
    for cy in range(24):
        y = cy * 8 + 4
        row = 0 if y < ROW_SPLITS[0] else (1 if y < ROW_SPLITS[1] else 2)
        for cx in range(32):
            col = min(9, max(0, (camera + cx * 8 + 4) // 28))
            attrs[cy * 32 + cx] = (wall if ids[row * 10 + col] in wall_ids
                                   else detail)
    return bytes(attrs)


# -- per-piece filters ----------------------------------------------------
#
# A floor slab is drawn as two interlocking triangles: piecea covers the block
# itself and pieceb (or one of its floorb decorations) covers the block to the
# right.  On an Apple II those two planes came out in different artifact
# colours, which is what drew the edge between neighbouring tiles and made the
# end of a floor visible.  In mono they carry the same hatch and merge into
# one continuous band.
#
# Filling the two triangles at different densities puts the edge back but
# splits every tile in half, which is worse.  So the fill is left alone and
# only the seam itself is drawn: a line down the leading edge of piecea.
#
# Only piecea is touched.  Every floorb decoration must keep the art it was
# drawn with, or neighbouring floor tiles -- which alternate decorations via
# BLUESPEC -- stop matching each other.

# How the seam is drawn.  The floor hatch carries a dot every four pixels, so
# clearing one leaves a seven-pixel shadow -- wider than the seam wants to be.
# Narrowing it means moving a dot rather than removing it, and the moved dot
# lands three pixels from its neighbour instead of four, which reads as a
# brighter line beside the shadow.  So a narrow seam and an even floor cannot
# both be had:
#
# A block is 28 px and the hatch repeats every 4, so seven whole periods fit
# and the hatch already tiles seamlessly -- which is why the seam is invisible
# left alone.  Re-phasing a tile to expose it does not help either: stepping
# the phase by 1 per tile gives an even 4 px seam until the phase wraps, and
# at the wrap two dots land side by side; steps of 2 and 3 give gaps of 1 and
# 2.  The dot count over a block is fixed, so opening a four-pixel shadow has
# to take that pixel from another gap somewhere:
#
#   groove  gaps 3,3,3,7,3        wide shadow, nothing else disturbed
#   thin    gaps 3,3,4,2,3        narrow shadow, tight pair right beside it
#   shift   gaps 3,3,4,3,3,2      narrow shadow, tight pair moved to the far
#                                 edge of the block, clear of the seam
#   dashed  as groove, but only on every other row
EDGE_ROWS = 2            # dashed: clear the seam dot once every N rows
EDGE_COL = 26            # right: which column of the 28 the extra line sits in
EDGE_MODE = 'none'       # none | even-left | shift | right | groove | thin | dashed | bevel


def _repack(img, rows):
    width = (len(rows[0]) + 6) // 7
    data = bytearray(width * img.height)
    for y in range(img.height):
        for c in range(width):
            b = 0
            for bit in range(7):
                x = c * 7 + bit
                if x < len(rows[y]) and rows[y][x]:
                    b |= 1 << bit
            data[y * width + c] = b
    return popimg.Image(img.index, width, img.height, bytes(data))


def _shifted(px, k=1):
    """Move a piece k pixels right, widening it so nothing falls off."""
    return [bytearray([0] * k + list(row) + [0] * (7 - k)) for row in px]


def shift_one(img):
    """The whole piece one pixel right: a phase change, nothing more."""
    return _repack(img, _shifted(list(img.pixels())))


def floor_a_even_left(img):
    """
    Shift the A section with everything else, then pull its leading diagonal
    row of dots back one pixel.  The floor stays on a single even grid and the
    seam is one row of dots out of step: a tight pair on its left, a four
    pixel gap on its right.
    """
    rows = _shifted(list(img.pixels()))
    for row in rows:
        x0 = next((i for i, v in enumerate(row) if v), None)
        if x0 is None or x0 == 0:
            continue
        row[x0] = 0
        row[x0 - 1] = 1
    return _repack(img, rows)


def edge_line(img):
    """Draw the piece's leading edge, following its first ink on each row."""
    px = list(img.pixels())
    out = [bytearray(row) for row in px]
    w = len(px[0])

    def put(x, v):
        if 0 <= x < w:
            out[y][x] = v

    for y, row in enumerate(px):
        x0 = next((i for i, v in enumerate(row) if v), None)
        if x0 is None:
            continue
        if EDGE_MODE == 'bevel':
            put(x0, 1)
            put(x0 + 1, 1)
        elif EDGE_MODE == 'groove':
            put(x0, 0)
        elif EDGE_MODE == 'thin':
            put(x0, 0)
            put(x0 + 1, 1)      # bright edge on the far side of the shadow
        elif EDGE_MODE == 'thin-left':
            put(x0, 0)
            put(x0 - 1, 1)
        elif EDGE_MODE == 'right':
            put(EDGE_COL, 1)    # an extra line of ink down the tile's right edge
        elif EDGE_MODE == 'shift':
            pass                # handled below, as a whole-image shift
        elif EDGE_MODE == 'dashed':
            if y % EDGE_ROWS == 0:
                put(x0, 0)
    if EDGE_MODE == 'shift':
        # Move the whole A section one pixel right.  The join then opens to a
        # four-pixel shadow, and every dot inside the section keeps its even
        # four-pixel spacing -- no tight pair, so no bright line.
        out = [bytearray([0] + list(row[:-1])) for row in px]
    return _repack(img, out)


FLOOR_A = 0x01                  # piecea of `floor`, shared by every tile
FLOOR_B = (0x02, 0xa2, 0xa4)    # pieceb and its floorb decorations


def piece_filter(imgnum):
    """The filter, if any, that a background piece goes through."""
    if EDGE_MODE == 'none':
        return None
    if EDGE_MODE == 'even-left':
        if imgnum == FLOOR_A:
            return floor_a_even_left
        if imgnum in FLOOR_B:
            return shift_one
        return None
    return edge_line if imgnum == FLOOR_A else None


# -- seam pass ------------------------------------------------------------
#
# With every filter off the floor is one even grid, which is why the join
# between tiles is invisible.  This pass puts it back by hand: along a
# diagonal, one dot per row is moved a single column to the left, leaving a
# tight pair on its left and a four-pixel gap on its right.  The diagonal
# starts at SEAM_COL on the top row of a floor band and steps SEAM_STEP
# columns per row, matching the slope the hatch itself runs at.
#
# Working on the assembled canvas rather than on the pieces is deliberate:
# the diagonal crosses from one piece into the next, so no per-piece filter
# can draw it.

SEAM_TOP = 23            # column the moved dot lands in, on the band's top row
SEAM_STEP = -2           # columns per row, going down
BAND_ROWS = 12           # height of the vertical face of a floor

# Every tile whose D section is a floor top stands on a floor, so its face
# carries the seam too -- posts and pillars as much as bare floor.  A solid
# block and the arch tops have a D section that is not a floor, and space and
# pillartop have none at all.
FLOOR_TOPS = frozenset([0x15,        # plain floor
                        0x16, 0x17,  # panels with and without floor
                        0x18, 0x19,  # pressed and raised pressure plates
                        0x2e,        # rubble
                        0x4c])       # up pressure plate
# Left exactly as drawn.  `posts` has balusters standing across the floor
# face.  `upressplate` is a raised surface with its own hatch phase, and
# `rubble`, `panelwif` and `bones` have A sections of 13, 29 and 18 rows
# rather than twelve, so they land on the opposite parity -- pulling their
# hatch onto the common grid fights the way the piece was drawn instead of
# tidying it.
SEAM_EXCLUDE = frozenset([bg.posts, bg.upressplate, bg.rubble,
                          bg.panelwif, bg.bones])

SEAM_TYPES = frozenset(
    [i for i, v in enumerate(bg.pieced) if v in FLOOR_TOPS]
    + [bg.loose]) - SEAM_EXCLUDE

# A post or pillar stands in front of the floor, so the seam has to stop
# where it runs into one.  The floor hatch is exactly one lit pixel in every
# four, so a window of four that holds more than one is not floor any more.
SEAM_DENSE = 1

# `posts` is kept out of the hatch pass because of its own art, the balusters
# standing across the floor face.  What it draws into the tile to its RIGHT is
# a different thing: pieceb is plain floor hatch on the common grid, so a tile
# next to a colonnade may still have its seam drawn.
SEAM_LEFT_OK = frozenset([bg.posts, bg.rubble])

# ...but the seam itself is another matter.  These types are left out of the
# hatch pass because of their own art, yet the join at their left edge still
# belongs on them.
SEAM_EXTRA = frozenset([bg.posts])

# On a colonnade the balusters stand across the floor face, so the diagonal
# goes BEHIND them: it disappears at the top of the tile and picks up again in
# the three rows below, instead of stopping dead where it meets the first one.
SEAM_BEHIND = frozenset([bg.posts])

# Where the floor ends over a drop the light edge has nothing to its right to
# move, so it is drawn in rather than shifted.  Only onto a tile with no floor
# of its own, and only where the pixels say the floor really has run out.
SEAM_DRAW = frozenset([bg.space])


def _editable(ids, row, tile, prev, seam=False):
    """
    A tile may be worked on only if its left neighbour is an ordinary floor
    too.  The neighbour's B section is drawn into this tile's columns, so a
    wall next door puts brickwork here, and an excluded type puts art we have
    agreed not to touch -- in both cases the passes must keep away.

    `seam` widens both lists: the tile itself may be one of SEAM_EXTRA, and
    the neighbour one of SEAM_LEFT_OK, whose B section is ordinary hatch.  The
    hatch pass, which rewrites dots across the whole tile, keeps the stricter
    rule.

    Tile zero's neighbour is the last tile of the room next door -- getprev
    draws its B section in here just the same -- so `prev` carries the three
    blocks that room hands over.
    """
    if tile < 0 or tile > 9:
        return False
    own = SEAM_TYPES | SEAM_EXTRA if seam else SEAM_TYPES
    if ids[row * 10 + tile] not in own:
        return False
    left = prev[row] if tile == 0 else ids[row * 10 + tile - 1]
    return left in (SEAM_TYPES | SEAM_LEFT_OK if seam else SEAM_TYPES)


def _is_floor(row, x, width):
    lit = sum(row[i] for i in range(max(0, x - 1), min(width, x + 3)))
    return lit <= SEAM_DENSE


def _floor_ended(row, x, width):
    """
    True where the diagonal has run off the end of the floor: the pair's left
    hand dot is there, its own place is clear, and so are the four pixels of
    shadow that would follow it.
    """
    if not 0 <= x - 3 or x + 3 >= width:
        return False
    return row[x - 3] and not any(row[x + i] for i in range(0, 4))


def seam_pass(pixels, level, scrnum):
    """
    Draw the join between floor tiles: down a diagonal, one dot per row moves
    a single column left, leaving a tight pair on its left and a four pixel
    gap on its right.  The diagonal starts at the tile's top right corner and
    steps SEAM_STEP columns per row.

    It stops as soon as it meets something denser than floor hatch -- a pillar
    standing in front of the floor, say -- except on the types in SEAM_BEHIND,
    whose own art it passes behind and comes out below.
    """
    types, _ = level.screen(scrnum)
    ids = [b & poplevel.IDMASK for b in types]
    prev = Room._prev_screen(level, scrnum)[0]
    out = [bytearray(row) for row in pixels]
    width = len(pixels[0])

    for row in range(3):
        Ay = BLOCKBOT[row + 1] - 3
        for tile in range(10):
            t = ids[row * 10 + tile]
            drawing = t in SEAM_DRAW
            if not drawing and not _editable(ids, row, tile, prev, seam=True):
                continue
            behind = t in SEAM_BEHIND
            for k in range(BAND_ROWS):
                y = Ay - (BAND_ROWS - 1) + k
                if not 0 <= y < len(pixels):
                    break
                dest = tile * BLOCK_PX + SEAM_TOP + SEAM_STEP * k
                src = dest + 1
                if dest < 0 or src >= width:
                    break
                if drawing:
                    # Not on the band's first row: the far corner of the floor
                    # is already drawn there, and a light edge on top of it is
                    # one dot too many.
                    if k and _floor_ended(pixels[y], dest, width):
                        out[y][dest] = 1
                    continue
                if not _is_floor(pixels[y], dest, width):
                    if behind:
                        continue           # behind a baluster
                    break                  # ran into a post or pillar
                if not pixels[y][src] or pixels[y][dest]:
                    continue
                out[y][src] = 0
                out[y][dest] = 1
    return out


# -- hatch normalisation --------------------------------------------------
#
# The floor hatch is one dot in every four, and its phase alternates by row:
# on an odd scanline the dots sit at x % 4 == 0, on an even one at x % 4 == 2.
# Most floor art follows that, but not all of it -- piecea of `posts`, for
# one, carries its hatch two pixels across for part of its height, so the
# floor beside a post does not line up with the floor next to it.
#
# This pass pulls every stray hatch dot onto the common grid.  Only isolated
# dots move: anything denser is real art (the post itself, brickwork) and is
# left exactly as drawn.


def hatch_phase(k):
    """
    Phase of the floor hatch on row k of a floor band.  It has to be taken
    from the row within the band, not from the scanline: the three bands end
    at 62, 125 and 188, so the middle one sits at the opposite parity, and a
    rule based on the scanline would declare its whole hatch off grid and
    shift it two pixels.
    """
    return (2 * k) % 4


def normalise_hatch(pixels, level, scrnum):
    types, _ = level.screen(scrnum)
    ids = [b & poplevel.IDMASK for b in types]
    prev = Room._prev_screen(level, scrnum)[0]
    out = [bytearray(row) for row in pixels]
    width = len(pixels[0])

    for row in range(3):
        Ay = BLOCKBOT[row + 1] - 3
        for k in range(BAND_ROWS):
            y = Ay - (BAND_ROWS - 1) + k
            if not 0 <= y < len(pixels):
                continue
            want = hatch_phase(k)
            src = pixels[y]
            for x in range(width):
                if not src[x] or x % 4 == want:
                    continue
                if ids[row * 10 + x // BLOCK_PX] not in SEAM_TYPES:
                    continue
                if not _editable(ids, row, x // BLOCK_PX, prev):
                    continue
                # Hatch dots stand four apart, so a real one is alone within
                # two pixels either side.  A narrower test mistakes the first
                # pixel of a dense run -- the left edge of a raised pressure
                # plate, say -- for a stray dot and throws it away.
                if sum(src[max(0, x - 2):x + 3]) > 1:
                    continue
                for dx in (2, -2):
                    t = x + dx
                    if not 0 <= t < width or src[t] or out[y][t]:
                        continue
                    if ids[row * 10 + t // BLOCK_PX] not in SEAM_TYPES:
                        continue            # never push a dot into a tile
                                            # that has no floor of its own
                    out[y][x] = 0
                    out[y][t] = 1
                    break                   # no room on the grid: leave the
                                            # dot where it is rather than
                                            # punching a hole in the art
    return out

if __name__ == '__main__':
    sys.exit(main(sys.argv))
