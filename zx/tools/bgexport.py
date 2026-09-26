"""
The background as data the program can draw from, instead of a baked room.

Up to now a room was composed here and shipped as a bitmap.  That is fine for
one room and impossible for a level: twenty four of them at 6720 bytes would
be 161K.  POP draws a room out of its image tables when you walk into it, and
so must this -- and the same machinery is what a loose floor, a gate or a
pressplate needs, since those redraw a block while the game runs.

So the two dungeon image tables, the piece tables of BGDATA.S and the level's
blueprint all go into a bank of their own, in a shape a Z80 can index:

    tables      the arrays of BGDATA.S, in a fixed order, 30 bytes each
    bgtab1      count, then count 2-byte offsets, then the records
    bgtab2      the same
    level       the 2304-byte blueprint, as it is on disk

An image record is width (in bytes of 7 pixels), height, then width*height
bytes -- BOTTOM row first, which is the order FASTLAY walks them in.  Bit 7
of an image byte is the Apple's palette bit and carries no luminance, so it
is dropped here rather than at draw time.

The seven pixels are also turned round here, leftmost into bit 7, which is
the order the Spectrum reads a byte in.  It costs nothing at export and it
is the one thing about the art that never changes from room to room, so the
repack at the end of a build no longer has to reverse every byte it touches.
Composition does not care either way: it lays whole bytes down with AND, ORA,
STA and XOR, and none of those has an opinion about which end a byte starts.
"""
import os
import struct

import bgdata as bg
import popimg

IMAGES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                      '01 POP Source', 'Images')

# The arrays a block redraw indexes, in the order the Z80 side expects them.
# Thirty entries each, one per piece id, so a single base plus the id reaches
# any of them.
BY_PIECE = ('maska', 'maskb', 'piecea', 'pieceay', 'pieceb', 'pieceby',
            'piecec', 'pieced', 'fronti', 'fronty', 'frontx', 'bstripe',
            'frontmx', 'frontmw', 'halfimg')

# And the shorter ones, each padded to its own fixed length.
FIXED = (('blockb', 2), ('blockc', 2), ('blockd', 2), ('blockfr', 2),
         ('spaceb', 4), ('spaceby', 4), ('floorb', 4), ('floorby', 4),
         ('panelb', 3), ('panelc', 3),
         ('loosea', 11), ('looseby', 11), ('loosed', 11),
         ('spikea', 10), ('spikeb', 10),
         ('slicertop', 5), ('slicerbot', 5), ('slicerfrnt', 5),
         ('slicerbot2', 5), ('slicergap', 5), ('slicerseq', 7),
         ('gate8b', 8), ('gate8c', 8))

# Single values, in one block, in this order.
SINGLES = ('looseb', 'panelb0', 'panelc0', 'archpanel', 'CUmask', 'CUpiece',
           'CUpost', 'gatebotSTA', 'gatebotORA', 'gateB1', 'gatecmask',
           'stairs', 'door', 'doormask', 'toprepair', 'archtop3sp',
           'specialflask', 'numblox', 'numpans', 'numbpans', 'slicerfrh')


def front_body(imgnum, t1, t2, shafts=None):
    """
    How much of a front piece stands in front of him: all of it.

    I tried narrowing this to the columns that are lit in half their rows or
    more, on the theory that a column's rectangle reached past its body.  It
    does not: the seven thin columns to the right of a column are its shaded
    side, and cutting them out let him show through it.  What made the mask
    look too wide was fx0 wrapping at 255, which painted a right hand piece
    on top of a left hand one -- the screen with the exit, which has no piece
    far enough right to wrap, was correct all along.

    Out: (offset, width) in pixels, both zero if there is no piece.
    """
    if not imgnum:
        return 0, 0
    img = (t2 if imgnum & 0x80 else t1).get(imgnum & 0x7f)
    if img is None:
        return 0, 0
    if imgnum in (SHAFTS if shafts is None else shafts):
        # The long pillars are laid masked, not stamped, so only their
        # pixels hide him -- and for all but a few rows at one end those are
        # a narrow shaft in the middle of the picture.  The mask is one
        # rectangle, so it is the shaft's: the columns lit in most rows, and
        # the pixel either side that MASKTAB clears too.  The whole width hid
        # him in the dark to the shaft's left.
        rows = list(img.pixels())
        cols = [x for x in range(img.px_width)
                if sum(r[x] for r in rows) * 2 >= len(rows)]
        lo, hi = max(0, min(cols) - 1), min(img.px_width - 1, max(cols) + 1)
        return lo, hi - lo + 1
    return 0, img.width * 7


SHAFTS = (0x48, 0x49)           # fronti of pillarbottom and pillartop
# In the palace a post and the foot of an arch are a thin column with a
# knob or two, drawn masked (maddfore) and not stamped: only the column hides
# him, as the long pillars' shaft does.  Their whole rectangle hid him as if
# they were solid walls.
PAL_SHAFTS = SHAFTS + (0x45, 0xa8)      # fronti of posts and archbot


def foot_rows(imgnum, t1, t2):
    """How many rows up from the foot of a picture have anything on them.

    For a slicer's front piece with its jaws up that is the plinth it stands
    on, and nothing else: the rest of the rectangle is the empty middle of
    the block.
    """
    img = (t2 if imgnum & 0x80 else t1).get(imgnum & 0x7f)
    n = 0
    for row in reversed(list(img.pixels())):
        if not any(row):
            break
        n += 1
    return n

# The long pillar's shaft is a thin line, a gap and two bands of three: on
# the Apple the line is a colour and the bands white, and on the Spectrum,
# all of it one ink, the line was too thin to read as the pillar's edge.  So
# it is two pixels thick, along the shaft -- on the two pieces behind him
# (pieceb of pillarbottom and pillartop) and the two in front, whose mask
# (front_body) widens with them.
EDGED = (26, 28) + SHAFTS


def edge_shafts(table):
    """The dungeon's first image table, the long pillars' edge thickened:
    wherever a row has the shaft -- line, gap, band -- the pixel left of
    the line is lit too."""
    for n in EDGED:
        img = table.images[n]
        rows = [list(r) for r in img.pixels()]
        # the line: the column lit in most rows with a gap after it
        x = min(i for i in range(1, img.px_width - 4)
                if sum(r[i] and not r[i + 1] and r[i + 2] for r in rows) * 2
                >= len(rows))
        data = bytearray(img.data)
        for y, r in enumerate(rows):
            if not r[x - 1] and r[x] and not r[x + 1] and all(r[x + 2:x + 5]):
                data[y * img.width + (x - 1) // 7] |= 1 << ((x - 1) % 7)
        table.images[n] = popimg.Image(img.index, img.width, img.height,
                                       bytes(data))
    return table


# The two background sets, BGset1 in MISC.S: the dungeon, and the palace
# that levels four to six, ten, eleven and fourteen are built of.
BGSETS = ('DUN', 'PAL')
BGSET_OF_LEVEL = [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 1, 1, 2, 2, 1]   # bgset1


def level_bgset(n):
    """'DUN' or 'PAL' for level n -- bgset1's 2 is the dungeon's too."""
    return 'PAL' if BGSET_OF_LEVEL[n] == 1 else 'DUN'


def set_table(n, bgset='DUN'):
    """IMG.BGTAB1 or 2 of a set, as this port draws them: the palace's
    long pillars are the dungeon's, and thickened the same."""
    t = popimg.Table(os.path.join(IMAGES, 'IMG.BGTAB%d.%s' % (n, bgset)))
    return edge_shafts(t) if n == 1 else t


def dungeon_table(n):
    return set_table(n, 'DUN')


# DRAWHALF in FRAMEADV.S: climbing up, the tiles with a half piece have
# CUmask and CUpiece laid instead of their whole floorpiece -- and in the
# palace a post and the foot of an arch have CUpost.  The port asks a table
# rather than the tile and the set.
HALFPIECE = ('floor', 'torch', 'dpressplate', 'exit_')


def half_images(bgset):
    half = [0] * 30
    for n in HALFPIECE:
        half[getattr(bg, n)] = bg.CUpiece
    if bgset == 'PAL':
        half[bg.posts] = half[bg.archbot] = bg.CUpost
    return half


def piece_tables(bgset='DUN'):
    t1 = set_table(1, bgset)
    t2 = set_table(2, bgset)
    bg.halfimg = half_images(bgset)
    shafts = PAL_SHAFTS if bgset == 'PAL' else SHAFTS
    body = [front_body(n, t1, t2, shafts) for n in bg.fronti]
    # The mirror's front piece is the foot of its frame, a few thin slanting
    # lines: laid masked, it stood in front of the reflection's legs as a
    # solid rectangle and cut them off.  It hides nobody now.
    body[bg.mirror] = (0, 0)
    # drawfrnt puts a slicer's front piece down itself, one of slicerfrnt
    # by its state, and fronti has none for it: all five are the one size,
    # and it stands in front of him like any other.  But only the foot of it
    # is solid once the jaws are up -- the rest of the rectangle is the empty
    # middle of the block -- and standing all sixty rows of it in front of
    # him rubbed a slab out of him as he walked through an open slicer.  So
    # the mask is the picture at rest, and only the rows of it that have
    # anything on them: slicerfrh, which drawfrnt gives frontrec.
    rest = bg.slicerfrnt[bg.slicerseq[bg.slicerRet] - 1]
    body[bg.slicer] = front_body(rest, t1, t2)
    bg.slicerfrh = foot_rows(rest, t1, t2)
    bg.frontmx = [b[0] for b in body]
    bg.frontmw = [b[1] for b in body]
    out = bytearray()
    for name in BY_PIECE:
        a = list(getattr(bg, name))
        if name == 'bstripe' and bgset != 'PAL':
            a = [0] * 30                # the stripe is the palace's alone
        a += [0] * (30 - len(a))
        out += bytes(v & 0xff for v in a[:30])
    for name, n in FIXED:
        a = list(getattr(bg, name))
        a += [0] * (n - len(a))
        out += bytes(v & 0xff for v in a[:n])
    out += bytes(getattr(bg, name) & 0xff for name in SINGLES)
    return bytes(out)


def offsets(names):
    """Where each array starts, so the assembler can be told."""
    out, at = [], 0
    for name in BY_PIECE:
        out.append((name, at))
        at += 30
    for name, n in FIXED:
        out.append((name, at))
        at += n
    for name in SINGLES:
        out.append((name, at))
        at += 1
    return out


REV = [int('{:08b}'.format(b)[::-1], 2) for b in range(256)]


# SETUPFLASK in GAMEBG.S lays the bubbles with an OFFSET of two pixels, or
# three for a mystery potion, and stamps them: the seven pixels from there on
# are the bubble's, the rest of the two bytes stay as they were.  bgdraw has
# no offsets, so each bubble goes in shifted already, with a mask that clears
# its seven pixels, at the end of the second table: BUBBLES and BUBMASK.
BUBBLE_IMAGES = (0x2f, 0x30, 0x31)      # $af, $b0, $b1; $b2 is blank
# In slots neither set lays a picture of its own from (8 to 13, 28 and 29),
# so the second table's count stops at its last real picture.
BUBBLES, BUBMASK = 8, 28                # off 2 first, then off 3


def flask_images(t):
    out = {}
    for k, off in enumerate((2, 3)):
        for j, n in enumerate(BUBBLE_IMAGES):
            img = t.get(n)
            data = bytearray()
            for line in img.pixels():
                px = [0] * off + list(line[:7])
                px += [0] * (14 - len(px))
                data += bytes(sum(px[b * 7 + i] << i for i in range(7))
                              for b in (0, 1))
            out[BUBBLES + 3 * k + j] = popimg.Image(0, 2, img.height,
                                                    bytes(data))
        px = [0 if off <= i < off + 7 else 1 for i in range(14)]
        row = bytes(sum(px[b * 7 + i] << i for i in range(7)) for b in (0, 1))
        out[BUBMASK + k] = popimg.Image(0, 2, 8, row * 8)
    return out


# The pictures the game ever lays: every one BGDATA.S's arrays and single
# pieces name, the sword's gleam, and the bubbles made at the end of the
# second table.  The rest of a table -- the torch flames, which go over the
# room from a table of their own, and the letters and boxes of the messages,
# which this port does not show -- stays off the tape: bgdraw lays nothing
# for a picture whose offset is nought.
IMAGE_ARRAYS = ('maska', 'maskb', 'piecea', 'pieceb', 'piecec', 'pieced',
                'fronti', 'bstripe', 'halfimg', 'blockb', 'blockc', 'blockd',
                'blockfr', 'spaceb', 'floorb', 'panelb', 'panelc', 'loosea',
                'loosed', 'spikea', 'spikeb', 'slicertop', 'slicerbot',
                'slicerfrnt', 'slicerbot2', 'gate8b', 'gate8c')
IMAGE_SINGLES = ('looseb', 'panelb0', 'panelc0', 'archpanel', 'CUmask',
                 'CUpiece', 'CUpost', 'gatebotSTA', 'gatebotORA', 'gateB1',
                 'gatecmask', 'stairs', 'door', 'doormask', 'toprepair',
                 'archtop3sp', 'specialflask', 'swordgleam0', 'swordgleam1')


def used_images():
    """The image numbers the game lays, bit 7 the second table."""
    keep = bg.halfimg if hasattr(bg, 'halfimg') else None
    bg.halfimg = half_images('PAL')
    used = set()
    for name in IMAGE_ARRAYS:
        used |= {v & 0xff for v in getattr(bg, name)}
    for name in IMAGE_SINGLES:
        used.add(getattr(bg, name) & 0xff)
    used |= {0x80 | n for n in list(range(BUBBLES, BUBBLES + 6))
             + [BUBMASK, BUBMASK + 1]}
    used.discard(0)
    if keep is not None:
        bg.halfimg = keep
    return used


def table_records(t, keep):
    """(top, offsets into the records or None, the records) -- bottom row
    first, and only the pictures in keep -- the count only as far as the
    last of them."""
    top = max(i for i in t.images if i in keep)
    body = bytearray()
    where = [None] * (top + 1)
    for i in range(1, top + 1):
        img = t.images.get(i)
        if img is None or i not in keep:
            continue
        where[i] = len(body)
        body += bytes([img.width, img.height])
        rows = [img.data[y * img.width:(y + 1) * img.width]
                for y in range(img.height)]
        rows.reverse()                          # back to POP's own order
        for r in rows:
            body += bytes(REV[b & 0x7f] for b in r)
    return top, where, bytes(body)


GDINFO = 2048 + 71              # GdStartBlock in INFO, EQ.S


def guards_fixed(level):
    """
    INITIALGUARDS in SUBS.S, once for the level: every guard stands on his
    block the way the kid is put on his -- GdStartX getblockej + angle + 7 --
    and starts fresh, SeqH 0 being ADDGUARD's own code for that.  What the
    blueprints have there is whatever the editor left: mostly 255, which
    puts him off the right of the screen, and level four's first guard 0,
    off the left.
    """
    level = bytearray(level)
    for s in range(24):
        block = level[GDINFO + s]
        if block < 30:
            level[GDINFO + 48 + s] = 14 * (block % 10) + 72
            level[GDINFO + 120 + s] = 0
    return bytes(level)


def flasks_set(level):
    """
    GETINITOBJ in FRAMEADV.S, as the level is loaded: a flask's spec is its
    potion number, and the game keeps that in the top three bits so the low
    five can count the bubbles.
    """
    level = bytearray(level)
    for i in range(720):
        if level[i] & 0x1f == 10:               # flask
            level[720 + i] = (level[720 + i] << 5) & 0xff
    return bytes(level)


def gates_set(level):
    """
    GETINITOBJ's gates: a gate's spec in the blueprint is 1 for up and 2 for
    down, which initsettings turns into the state -- gmaxval or gminval.  A
    gate left at its raw 1 was all but shut.
    """
    level = bytearray(level)
    for i in range(720):
        if level[i] & 0x1f == 4 and level[720 + i] in (1, 2):
            level[720 + i] = (GMAXVAL, 0)[level[720 + i] - 1]
    return bytes(level)


GMAXVAL = 47 * 4


# Where this port changes a level, as the user asked: torches whose flame
# burned over a slicer's blade.  Level four's room with the tall flask has
# its torch two blocks left, on the floor there; and the room right of the
# exit's plate (11) has its torch -- in its first column, the flame in the
# second over the slicer -- in the last column of the room to its left (4),
# whose flame burns in this one's first (maketorches).  (level, room, block,
# room, block): the two swapped, type and spec.
MOVES = [(4, 23, 6, 23, 4), (4, 11, 10, 4, 19)]


def level_moved(n, level):
    level = bytearray(level)
    for lv, ra, a, rb, b in MOVES:
        if lv == n:
            for base in (0, 720):
                i, j = base + (ra - 1) * 30 + a, base + (rb - 1) * 30 + b
                level[i], level[j] = level[j], level[i]
    return bytes(level)


def level_blob(level_path):
    """A level's blueprint as the game keeps it."""
    n = int(os.path.basename(level_path)[5:])
    return gates_set(flasks_set(guards_fixed(
        level_moved(n, open(level_path, 'rb').read()))))


# The background bank is laid out once for both sets: the piece tables, the
# set's own code (BGOVL_LEN bytes: see bgovl.asm), the two image tables'
# offsets, then their pictures, and the blueprint where the bigger set's
# pictures end.  So a level of the other set brings everything up to its
# blueprint off the tape in one block, and a level of the same set only its
# blueprint.  An offset is from its table's own count byte, round 65536, and
# may reach any picture in the bank.
BGOVL_LEN = 429


def set_parts(bgset):
    """(piece tables, (top, where, records) for each image table)."""
    keep = used_images()
    tables = piece_tables(bgset)
    t1 = set_table(1, bgset)
    t2 = set_table(2, bgset)
    t2.images.update(flask_images(t2))
    k1 = {n for n in keep if n < 0x80}
    k2 = {n & 0x7f for n in keep if n >= 0x80}
    return tables, table_records(t1, k1), table_records(t2, k2)


def layout():
    """({name: offset}, the parts of each set): where each thing is in the
    bank, the same for both sets."""
    parts = {s: set_parts(s) for s in BGSETS}
    tlen = len(parts['DUN'][0])
    top1 = max(parts[s][1][0] for s in BGSETS)
    top2 = max(parts[s][2][0] for s in BGSETS)
    at = {'bgtables': 0, 'bgovl': tlen}
    at['bgtab1'] = at['bgovl'] + BGOVL_LEN
    at['bgtab2'] = at['bgtab1'] + 1 + 2 * top1
    at['bgpics'] = at['bgtab2'] + 1 + 2 * top2
    at['level'] = at['bgpics'] + max(len(parts[s][1][2]) + len(parts[s][2][2])
                                     for s in BGSETS)
    return at, parts


def set_blob(bgset, ovl=b''):
    """The bank up to the blueprint, for a set: its tables, its code, its
    pictures."""
    at, parts = layout()
    tables, (top1, w1, r1), (top2, w2, r2) = parts[bgset]
    assert len(ovl) <= BGOVL_LEN, "the set's code is over BGOVL_LEN"
    blob = bytearray(at['level'])
    blob[0:len(tables)] = tables
    blob[at['bgovl']:at['bgovl'] + len(ovl)] = ovl
    pics = at['bgpics']
    for base, top, where, rec in ((at['bgtab1'], top1, w1, 0),
                                  (at['bgtab2'], top2, w2, len(r1))):
        blob[base] = top
        for i in range(1, top + 1):
            off = 0 if where[i] is None else (pics + rec + where[i] - base) & 0xffff
            blob[base + 1 + 2 * (i - 1):base + 3 + 2 * (i - 1)] = struct.pack('<H', off)
    blob[pics:pics + len(r1)] = r1
    blob[pics + len(r1):pics + len(r1) + len(r2)] = r2
    return bytes(blob)


def build(level_path, bgset='DUN'):
    """(blob, {name: offset}, the piece tables' offsets) -- everything the
    background bank carries up to and with the blueprint."""
    at, _ = layout()
    blob = set_blob(bgset) + level_blob(level_path)
    return blob, at, offsets(BY_PIECE)
