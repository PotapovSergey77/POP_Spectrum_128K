"""
Export the assets the Z80 demo needs: one room, the prince's frames, and the
sequences that string them together.

Sprites are stored byte aligned and shifted into place at run time.  Each row
holds `width` pairs of (mask, data): the screen byte becomes

    screen = (screen AND mask) OR data

so mask bits are 1 where the background must show through.

The sequences are transcribed from SEQTABLE.S, which drives POP's animation
with a little byte code of its own.  Ours keeps the same shape:

    0xFF lo hi   jump to another sequence
    0xFE         about face
    0xFD d       move without changing frame
    0xFC n       say which sequence we are in, so the keys know what to do
    0xFB d       drop by d screen lines
    0xFA x y     set the falling velocities
    0xF9 n       CharAction: which of POP's states he is in
    0xF8         step a block row up, 0xF7 down
    f    d       show frame f and move by d

`d` is chx, in the 140-wide logic space, so a screen pixel is half a unit; the
sign is applied by whichever way the prince faces.

Usage: mkassets.py [outdir]
"""
import os
import re
import sys

import bgexport
import popframe
import popimg
import cpcmusic
import cpcsound
import titlescr
import popseq
import princessscr
import poplevel
import renderroom
import zxscreen

# Which of POP's sequences the prince may be in.  One to fifty is most of his
# movement; the rest of it is scattered further up the table among the guards
# and the princess.  Fighting and dying are left out for now.
KID_SEQS = (list(range(1, 51))
            + [51,      # impale, on spikes
               52,      # crush, under a floor that lands on him
               68,      # climbdown
               70,      # climbstairs
               72,      # stepback
               73,      # climbfail
               79,      # crawl
               84]      # running
            # The sword, and the fight it is for.  Both fighters are drawn
            # out of the same pictures -- chtable4 is the fencing set, and
            # guardengarde stands in frames 158, 170 and 171 just as he does
            # -- so the guard costs nothing here beyond his own few.
            + [53,      # deadfall
               54,      # halve
               55, 56, 57, 60,           # engarde, advance, retreat, turn
               58, 75, 67, 76, 69, 66,   # strike, fast, adv, ret, blocked
               61, 62,                   # strikeblock, readyblock
               63, 64, 65,               # landengarde, bumpeng fwd and back
               71, 74, 85,               # dropdead, stabbed, stabkill
               77, 80, 87,               # alertstand, alertturn, goalert
               86,                       # fastadvance
               88, 89,                   # arise, turndraw
               90,                       # guardengarde
               91,                       # pickupsword
               92, 93,                   # resheathe, fastsheathe
               81, 82, 83, 104,          # fightfall, efightfall, patchfall
               78])                      # drinkpotion

CHAR_ANCHOR = 21
ALT_FRAMES = 40                 # ALTSET1: frames 150 to 189

# A block is drawn at room x = 28*b, so it runs 28*b to 28*b + 27 -- but the
# block a character is ON is not simply the one
# his coordinate lands in.  CharX is BlockEdge[b+5] + angle + 7, which is the
# far edge of his own block, and GETBLOCKXP in CTRLSUBS.S takes `angle` back
# off before the lookup, putting him at the middle of the block instead.  That
# is a whole 14 pixels on screen, and without it he walks half a block past
# the edge of the floor before he notices it has gone.
BLOCK_PX = 28
TILE_FLOOR, TILE_SOLID = 1, 2

ROOM = ('LEVEL%s' % os.environ.get('POP_LEVEL', '1'), 1)

# The Apple's room is 280 pixels wide and the Spectrum's screen is 256, so
# the room is carried whole -- 35 bytes to a scanline, laid out plainly -- and
# the view slides over it a byte at a time.  Four positions cover the 24
# pixel difference, so every part of the room can be brought on screen.
ROOM_BYTES = 35

# Torch flames.  MOVER.S gives every torch a state and picks the next one at
# random; FRAMEADV.S draws that frame as the B section of the block to the
# torch's RIGHT -- XCO = blockxco + 1, YCO = Ay - 43 -- which is why a torch
# in the last column has no flame.  GAMEBG.S holds the order.
TORCH = 19
FLAME_FRAMES = [0x52, 0x53, 0x54, 0x55, 0x56, 0x61, 0x62, 0x63, 0x64]
FLAME_TABLE = [0x52, 0x53, 0x54, 0x55, 0x56, 0x61, 0x62, 0x63, 0x64,
               0x52, 0x54, 0x56, 0x63, 0x61, 0x55, 0x53, 0x64, 0x62]
FLAME_UP = 43

INK_ROOM = 0x05                 # cyan on black, the whole room
INK_FLAME_TOP = 0x02            # and where a torch burns: dark red at the
INK_FLAME_MID = 0x42            # tip, bright red in the middle and yellow
INK_FLAME_LOW = 0x06            # where it comes off the torch
ROOM_PX = ROOM_BYTES * 8
CAM_MAX = ROOM_BYTES - 32

# 128K layout.  The fixed half of the map holds the code, the tables the inner
# loops index, and the off screen copy of the screen; the 16K window at 0xC000
# holds the two big read only things.  They are never wanted at the same
# moment -- the sprites are read while the prince is drawn, the room and the
# foreground mask while he is erased and covered up again -- so one page in
# each direction a frame is all it costs.  Which banks they end up in is
# settled at startup, not here: see the tail of pop.asm.
PAGE_WINDOW = 0xC000
BANK_SIZE = 0x4000

# Which RAM banks hold what.  0, 4 and 6 are uncontended; 1 is not, and the
# sprites there are the ones drawn least often.
BANK_SPR = (0, 4, 1)
BANK_ART = 6
BANK_BG = 3                     # the image tables, the piece tables, the level
BANK_CANVAS = 7                 # and the room as it is composed, Apple layout
RBROOM = 3275                   # the room's code at most: pop.asm's RBROOM

# A frame's blob offset carries the bank it lives in: the top two bits index a
# table the program fills in at startup, the low fourteen are the offset
# inside that bank.  Sprites therefore cost no more table than they did with
# one bank, and no frame is ever split across the join.
BANK_SHIFT = 14
SIG_ART, SIG_SPR = bytes([0x5A, 0xA5]), bytes([0xA5, 0x5A])
# Where the kid starts.  POP's own place, unless the environment says
# otherwise: POP_START_ROOM, POP_START_ROW and POP_START_COL build a tape
# that begins somewhere else, which is the only honest way to reach a far
# room in a test -- putting him there by hand skips everything nextroom
# does and the game goes off the rails a frame or two later.
#
# Without them it is POP's start: KidStartBlock, facing KidStartFace, and for
# level one STARTKID's special start -- he drops in and the gate slams.
POP_START = not any(k in os.environ
                    for k in ('POP_START_ROOM', 'POP_START_ROW', 'POP_START_COL'))
_KID = poplevel.Level(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', '..',
    '01 POP Source', 'Levels', ROOM[0])).kid_start
START_ROW = int(os.environ.get('POP_START_ROW', _KID[1] // 10 if POP_START else 0))
START_COL = int(os.environ.get('POP_START_COL', _KID[1] % 10 if POP_START else 5))
START_FACE = 1 if POP_START and _KID[2] == 0xff else 0    # ~KidStartFace
# The levels the tape carries: the first in the background bank, the rest
# after the banks, each loaded over it when the one before is left by its
# stairs -- LoadNextLevel, with the tape for the disk.
LEVELS = 3

# chset in MISC.S: the level's own opponent, the fourth character table --
# LOADLEVEL reads it off the disk with the blueprint when it is not the one
# in memory already.  Level three's is the skeleton's; one and two have the
# guard the tape starts with.
CHSET = {3: 'IMG.CHTAB4.SKEL'}


def level_path(n):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                        '01 POP Source', 'Levels', 'LEVEL%d' % n)


def kid_place(block, face):
    """STARTKID's start on a block: CharX, CharY and the block row, and
    CharFace the other way from KidStartFace -- the turn he starts with
    brings him round to it."""
    x = popframe.screen_x(popframe.char_x(block % 10)) & 0xffff
    return bytes([x & 0xff, x >> 8, popframe.char_y(block // 10),
                  block // 10, 1 if face == 0xff else 0])


def level_head(n, chset_len=0):
    """
    STARTKID's normal start worked out here, where the tables are, whether
    another level follows this one on the tape, and how long the block of
    its character set is that follows it there, nought for none.
    """
    scrn, block, face = poplevel.Level(level_path(n)).kid_start
    return (kid_place(block, face) + bytes([1 if n < LEVELS else 0])
            + chset_len.to_bytes(2, 'little'))


LEVEL_HEAD = 8

# STARTKID's :special3 and milestone3 in AUTO.S: level three's milestone is
# passed when he goes left out of the room right of the first gate, and from
# then on he begins again just inside it -- room 2, block 6, facing left --
# with the loose floor of room 7 already gone.
MILESTONE3 = kid_place(6, 0xff)
MS3_SCRN, MS3_ROOM, MS3_LOOSE, MS3_LOOSESCRN = 7, 2, 4, 7

# Level one's drop lands him with his face in the first torch's colours; two
# POP units back, and he stands in the cell before them.
START_NUDGE = 4 if POP_START and ROOM[0] == 'LEVEL1' else 0


def sprite_bytes(img, mirror, pad=0):
    """
    One frame as rows of bytes, eight pixels to the byte, the figure's ink
    set and the room showing through the rest.

    No mask is stored.  A pixel is either ink or it is not, so the mask a
    blitter wants is the data's own complement, which a CPL makes for
    nothing -- and the mask the shift needs at the edges is the complement
    of the shifted data as well, ones shifting in exactly where the data
    shifted zeroes out.  The Apple stored its pictures the same way, which
    is how the whole of Prince of Persia fitted in the same 128K.
    """
    rows = [[0] * pad + list(line) for line in img.pixels()]
    if mirror:
        rows = [list(reversed(r)) for r in rows]
    width = (len(rows[0]) + 7) // 8
    out = bytearray()
    for row in rows:
        for b in range(width):
            data = 0
            for bit in range(8):
                x = b * 8 + bit
                if x < len(row) and row[x]:
                    data |= 0x80 >> bit
            out.append(data)
    return width, len(rows), bytes(out)


def trim_frame(width, height, data):
    """
    The frame's own box: the (mask, data) pairs that are wholly transparent
    make a border round every picture -- a standing figure in a box wide
    enough for a sword -- and two fifths of the bytes are in it.  Cutting the
    box down to what is drawn saves the space and the blitter's time both,
    and costs nothing at all in the drawing: every row is still the same
    length and the same stride, so dfsetup goes on working out the row once
    for the whole frame.  Only whole byte columns go, so nothing has to shift.

    Out: (left, bottom, width, height, data) -- left in byte columns and
    bottom in rows, for the anchors to be moved by.
    """
    rows = [[data[r * width + b] for b in range(width)] for r in range(height)]
    left, right = 0, width - 1
    while left < width and all(r[left] == 0 for r in rows):
        left += 1
    while right >= left and all(r[right] == 0 for r in rows):
        right -= 1
    top, bottom = 0, height - 1
    while top < height and all(b == 0 for b in rows[top]):
        top += 1
    while bottom >= top and all(b == 0 for b in rows[bottom]):
        bottom -= 1
    if right < left or bottom < top:
        return 0, 0, 0, 0, b''           # nothing to draw at all
    out = bytearray()
    for r in rows[top:bottom + 1]:
        out += bytes(r[left:right + 1])
    return (left, height - 1 - bottom,
            right - left + 1, bottom - top + 1, bytes(out))


def build_sprites(frames_used):
    """
    Table of (width, height, xoff left, xoff right, blob offset), indexed by
    POP's own frame number so the byte code needs no translating, and the
    pixels behind it cut into bank sized pieces.  Only one facing is stored --
    mirroring at draw time through a bit reversal table costs a lookup per
    byte and saves ten kilobytes.

    Also out: the rows cut off the bottom of each frame, which Fdy carries.
    """
    frames = popframe.load()
    top = max(frames_used) + 1
    table, banks, trims = bytearray(top * 6), [bytearray()], {}
    for n in frames_used:
        if n in frames:             # frame 0 is "nothing to draw"
            lay_frame(table, banks, trims, n, frames[n])
    return table, banks, trims



def lay_frame(table, banks, trims, n, frame):
    """One frame's record at index n of the table, its pixels in the banks."""
    img = popframe.image(frame)
    width, height, data = sprite_bytes(img, 0)
    cut, below, width, height, data = trim_frame(width, height, data)
    trims[n] = below
    if len(banks[-1]) + len(data) > BANK_SIZE - 2:
        banks.append(bytearray())   # this one will not fit: start the next
    e = n * 6
    # The foot has to land where the logic says it does.  GETBASEX puts
    # it at CharX + Fdx - footmark, applied the way he faces, and the
    # footmark counts in from the LEFT edge of the image -- so facing
    # left the image's left edge goes at CharX - Fdx, and facing right,
    # where it is mirrored inside its buffer, at CharX + Fdx less the
    # buffer's width.  Both then have the foot in the same place, which
    # one constant for the two of them could never manage.
    #
    # The box cut off the left moves both of them along by what it took:
    # facing left the stored edge now stands `cut` bytes further in, and
    # facing right, where the row is reversed inside a buffer that is
    # narrower by as much, the far edge is `cut + width` from the anchor.
    dx = 2 * frame.dx
    table[e:e + 4] = bytes([width, height, (-dx + cut * 8) & 0xff,
                            (dx - (cut + width) * 8) & 0xff])
    table[e + 4:e + 6] = (((len(banks) - 1) << BANK_SHIFT)
                          | len(banks[-1])).to_bytes(2, 'little')
    banks[-1] += data

# SOUNDNAMES.S's sounds, by number, and after them the moments the CPC
# release has a sound for that the Apple's has not.  Each is played as the
# CPC effect of the same moment -- see cpcsound.py -- or not at all.
SOUNDS = ['PlateDown', 'PlateUp', 'GateDown', 'SpecialKey1', 'SpecialKey2',
          'Splat', 'MirrorCrack', 'LooseCrash', 'GotKey', 'Footstep',
          'RaisingExit', 'RaisingGate', 'LoweringGate', 'SmackWall',
          'Impaled', 'GateSlam', 'FlashMsg', 'SwordClash1', 'SwordClash2',
          'JawsClash',
          'GateTop', 'Spikes', 'Stabbed', 'DoorShut', 'Drink', 'Slicer']
NONE = 0xff
CPC_FOR_SOUND = {'PlateDown': 2, 'LooseCrash': 1,
                 'Footstep': 11, 'RaisingExit': 17, 'RaisingGate': 13,
                 'LoweringGate': 13, 'GateSlam': 0, 'SwordClash1': 7,
                 'SwordClash2': 7, 'GateTop': 14, 'Spikes': 6, 'Stabbed': 8,
                 'DoorShut': 3, 'Drink': 15, 'Slicer': 5,
                 # the CPC has none of its own for these: the blow's, as the
                 # user asked
                 'SmackWall': 8, 'Splat': 8, 'Impaled': 8}
# SOUNDNAMES.S's game music, by number, to the CPC's tunes.
CPC_FOR_SONG = {1: 10, 2: 10, 3: 4, 4: 9, 7: 9, 9: 19, 11: 16, 12: 16}
SONGS = 13


def sword_table():
    """SWORDTAB in FRAMEDEF.S: (image in chtable3, dx, dy) for swords 1 on."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                        '01 POP Source', 'Source', 'FRAMEDEF.S')
    src = open(path).read()
    src = src[src.index('SWORDTAB'):]
    out = []
    for m in re.finditer(r'^:\d+\s+db\s+(\$?[0-9a-fA-F]+),(-?\d+),(-?\d+)',
                         src, re.M):
        v = m.group(1)
        out.append((int(v[1:], 16) if v.startswith('$') else int(v),
                    int(m.group(2)), int(m.group(3))))
    return out


# The one picture whose mask is real: it is composed of two renderings and
# the pixels where they disagree are the room's, not the piece's, so the mask
# is not the data's complement and the blitter above cannot draw it.  Its
# drawing is not in the build -- it waits in a stash -- and when it comes
# back it needs a path of its own, with the mask stored as it is here.
#
# DrawFF in FRAMEADV.S: a floor on its way down is the loose floor's own art
# at the mob's foot -- maska[floor] masked in at y - 3, loosea over it,
# loosed stamped at y, and looseb a block to the right at y - 4.  It is laid
# over the room rather than into it, so it is composed here once and drawn
# the way a sprite is: rendered over a clear background and over a solid one,
# the pixels where the two agree are the piece's own, and the rest is where
# the room shows through -- which is exactly the mask the blitter wants.

FF_ROWS = 16                    # the foot's row and fifteen above it


def chset_block(tabname, alt, alt_base, spans, tables, fdy_at):
    """
    rdch4 in MASTER.S, for the tape: another fourth character table in place
    of the guard's -- the skeleton's, for level three.  The opponent is
    drawn out of ALTSET1's frames 150 to 189, and those name the table's
    pictures by number, so the one set of frames serves every table; what
    changes is the pictures, and with them each frame's record and its Fdy,
    which the rows cut off a picture's foot move.

    The pictures go where the guard's lay, in the banks the tape filled, and
    the records and Fdy over his in the canvas bank.  The block says where:
    a count of pieces, each one's bank, address and length, then the bytes
    of them all, one after another -- for levelgo to put where they go.
    """
    t = popimg.Table(os.path.join(popframe.IMAGES, tabname))
    room = [[b, lo, hi, bytearray()] for b, lo, hi in spans]
    at = {}                     # a picture laid once, however many use it
    recs = bytearray(6 * ALT_FRAMES)
    fdy = bytearray(ALT_FRAMES)
    for i in range(ALT_FRAMES):
        f = alt.get(150 + i)
        if f is None:
            continue
        below = 0
        if f.index:
            w, h, data = sprite_bytes(t.get(f.index), 0)
            cut, below, w, h, data = trim_frame(w, h, data)
            if f.index not in at:
                for r in room:
                    if r[1] + len(r[3]) + len(data) <= r[2]:
                        at[f.index] = (r[0] << BANK_SHIFT) | (r[1] + len(r[3]))
                        r[3] += data
                        break
                else:
                    raise SystemExit('%s: no room where the guard was' % tabname)
            dx = 2 * f.dx
            recs[6 * i:6 * i + 6] = (bytes([w, h, (-dx + cut * 8) & 0xff,
                                            (dx - (cut + w) * 8) & 0xff])
                                     + at[f.index].to_bytes(2, 'little'))
        fdy[i] = (f.dy - below) & 0xff
    parts = [(BANK_SPR[b], PAGE_WINDOW + lo, bytes(data))
             for b, lo, hi, data in room if data]
    parts += [(BANK_CANVAS, tables + 6 * alt_base, bytes(recs)),
              (BANK_CANVAS, fdy_at + alt_base, bytes(fdy))]
    head = bytearray([len(parts)])
    for bank, addr, data in parts:
        head += (bytes([bank]) + addr.to_bytes(2, 'little')
                 + len(data).to_bytes(2, 'little'))
    return bytes(head) + b''.join(p[2] for p in parts)


def falling_floor(shift=0):
    """(width in bytes, the rows as (mask, data) pairs), laid shift pixels
    into its first byte: 28 pixels a block leaves a block's left edge on a
    byte or four pixels into one."""
    bgd, x, y = renderroom.bg, 8, 100
    f = bgd.Ffalling

    def render(fill):
        r = renderroom.Room('DUN')
        if fill:
            for line in r.canvas:
                for i in range(len(line)):
                    line[i] = 0x7f
        if bgd.maska[bgd.floor]:
            r.draw(bgd.maska[bgd.floor], x, y - 3, renderroom.AND)
        r.draw(bgd.loosea[f], x, y - 3, renderroom.ORA)
        r.draw(bgd.loosed[f], x, y, renderroom.STA)
        r.draw(bgd.looseb, x + 4, y - 4, renderroom.ORA)
        return r.to_pixels()

    clear, solid = render(False), render(True)
    left, rows = x * 7, range(y - FF_ROWS + 1, y + 1)
    own = [c for c in range(left, min(len(clear[0]), left + 8 * 8))
           if any(clear[r][c] == solid[r][c] for r in rows)]
    width = (own[-1] - left + shift + 8) // 8
    out = bytearray()
    for r in rows:
        for b in range(width):
            mask = data = 0
            for bit in range(8):
                c = left + b * 8 + bit - shift
                if (c < left or c >= len(clear[r])
                        or clear[r][c] != solid[r][c]):
                    mask |= 0x80 >> bit         # the room shows through here
                elif clear[r][c]:
                    data |= 0x80 >> bit
            out.append(mask)
            out.append(data)
    return width, bytes(out)


def build_sequences():
    """
    SEQTABLE.S as it stands, with the goto addresses turned into offsets from
    the start of the code.  The program adds its own base, which saves both a
    relocation pass at startup and any chance of getting one wrong.
    """
    t = popseq.load()
    code = bytearray(t.code)
    for at, label in t.fixups:
        code[at:at + 2] = t.at[label].to_bytes(2, 'little')
    top = max(t.entries) + 1
    entry = bytearray(top * 2)
    for n, label in t.entries.items():
        entry[n * 2:n * 2 + 2] = t.at[label].to_bytes(2, 'little')
    return t, bytes(code), bytes(entry)


def pack_row(px):
    """One scanline of 0/1 pixels into ROOM_BYTES bytes, bit 7 leftmost."""
    out = bytearray(ROOM_BYTES)
    for x in range(min(len(px), ROOM_PX)):
        if px[x]:
            out[x >> 3] |= 0x80 >> (x & 7)
    return bytes(out)


def pack(rows):
    """The room, plainly: 192 scanlines of ROOM_BYTES, top row first."""
    return b''.join(pack_row(r) for r in rows)


def band_mask(px):
    """(index, mask): the rows with anything in them, and only those rows."""
    rows = [y for y in range(192) if any(px[y])]
    index = bytearray([0xff]) * 192
    mask = bytearray()
    for i, y in enumerate(rows):
        index[y] = i
        mask += pack_row(px[y])
    return bytes(index), bytes(mask)


def main(argv):
    out = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'build')
    # What the assembler eats goes in one place, the pictures the diagnostic
    # tools draw in another, and the tape and its symbols stay at the top.
    binout = os.path.join(out, 'bin')
    os.makedirs(binout, exist_ok=True)
    os.makedirs(os.path.join(out, 'png'), exist_ok=True)

    level = poplevel.Level(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', '..',
        '01 POP Source', 'Levels', ROOM[0]))
    room = renderroom.Room('DUN')
    room.build(level, ROOM[1])
    px = renderroom.normalise_hatch(room.to_pixels(), level, ROOM[1])
    # The seam pass -- the light edge and its shadow along the join between
    # floor tiles -- is not wanted after all.  It stays in renderroom.py, but
    # the floor goes out as the original draws it.
    # px = renderroom.seam_pass(px, level, ROOM[1])
    screen = pack(px)

    types, _ = level.screen(ROOM[1])
    ids = [b & poplevel.IDMASK for b in types]
    # The block types themselves, as BLUETYPE has them.  Two flags of my own
    # were standing in for these and every rule I had to invent came out of
    # that; POP asks the type and so do we now.
    open(os.path.join(binout, 'tiles.bin'), 'wb').write(bytes(ids))

    # CMPSPACE and CMPBARR out of CTRLSUBS.S, as lookups.  cmpspace: is the
    # block clear -- and note that a solid block counts as clear here, which
    # is why onground has a case of its own for it.  cmpbarr: 0 clear, else
    # the barrier's code.
    bg = renderroom.bg
    space = bytearray(32)
    barr = bytearray(32)
    for t in range(32):
        clear = t in (bg.space, bg.pillartop, bg.panelwof, bg.block)             or t >= bg.archtop1
        space[t] = 0 if clear else 1
        if t in (bg.panelwif, bg.panelwof, bg.gate):
            barr[t] = 1
        elif t in (bg.mirror, bg.slicer):
            barr[t] = 3
        elif t == bg.block:
            barr[t] = 4
    open(os.path.join(binout, 'cmpspace.bin'), 'wb').write(bytes(space))
    open(os.path.join(binout, 'cmpbarr.bin'), 'wb').write(bytes(barr))

    # POP draws the foreground pieces after the characters, which is what
    # lets a wall or a post stand in front of the prince.  Those pieces are
    # listed in `fronti`, positioned by `frontx` (in bytes) and `fronty`, and
    # the room never changes -- so the area they cover goes back over him
    # after he is drawn.  The whole rectangle is covered, not just the lit
    # pixels, or he would show through the gaps in the dither.
    #
    # It is a bitmask at run time, a bit a pixel, but it does not travel as
    # one: six kilobytes of tape and of staging room for a handful of
    # rectangles.  The rectangles travel instead and the program paints them.
    fore = [bytearray(ROOM_PX) for _ in range(192)]
    for row in range(3):
        ay = renderroom.BLOCKBOT[row + 1] - 3
        for col in range(10):
            t = ids[row * 10 + col]
            n = renderroom.bg.fronti[t]
            if not n:
                continue
            img = (room.tab2 if n & 0x80 else room.tab1).get(n & 0x7f)
            if img is None:
                continue
            mx, mw = bgexport.front_body(n, room.tab1, room.tab2)
            if not mw:
                continue
            x0 = (col * 4 + renderroom.bg.frontx[t]) * 7 + mx
            ybot = ay + renderroom.bg.fronty[t]
            for y in range(max(0, ybot - img.height + 1), min(192, ybot + 1)):
                for x in range(max(0, x0), min(ROOM_PX, x0 + mw)):
                    fore[y][x] = 1

    # Putting the foreground back was the most expensive thing in a frame,
    # and most of it went on rows the mask has nothing in.  So the mask
    # carries only the rows a front piece reaches, and an index says which
    # row of it a scanline is, or -1 for the rest of the screen.
    foreband, foremask = band_mask(fore)


    # The art bank: the room first, then the foreground mask behind it, and a
    # signature the program checks -- a bank that did not load leaves a black
    # screen and nothing to go on, so it is worth two bytes to say so.
    floorpx, halfpx = renderroom.floor_covers(level, ROOM[1])
    band = []
    for r in range(3):
        dy = renderroom.BLOCKBOT[r + 1]
        band += [y for y in range(dy - 14, dy + 1) if 0 <= y < 192]
    floorband = bytearray([0xff]) * 192
    fmask, hmask = bytearray(), bytearray()
    for i, y in enumerate(band):
        floorband[y] = i
        fmask += pack_row(floorpx[y])
        hmask += pack_row(halfpx[y])

    # The room is composed when it is walked into and the foreground mask
    # is painted from the pieces as they go down, so neither travels: only
    # the two floorpiece masks do, and they go first so the tape block is
    # just them.  The room and the mask have their room behind.
    # Nothing in the art bank travels at all now: the room, its foreground
    # mask and both floorpiece masks are all made when a room is entered.
    # Only the signature goes, so a bank that did not arrive still says so.
    art = b''
    # The art bank is empty until the first room is built, and the title
    # screens are shown before that: they travel in it, packed, after the
    # signature, and are gone once the room goes over them.
    intro_at, intro = titlescr.build(binout)
    # And the CPC's music for them, after the screens: see cpcmusic.py.
    tunes = cpcmusic.tunes()
    tunes_off = len(SIG_ART) + len(intro)
    intro = intro + b''.join(tunes)
    assert len(SIG_ART) + len(intro) <= BANK_SIZE - 12, 'the title screens do not fit the art bank'
    open(os.path.join(binout, 'bank_art.bin'), 'wb').write(SIG_ART + intro)
    print('заставка   %d байт, музыка %d, в банке свободно %d'
          % (len(intro) - sum(map(len, tunes)), sum(map(len, tunes)),
             BANK_SIZE - 12 - len(SIG_ART) - len(intro)))
    open(os.path.join(binout, 'floorband.bin'), 'wb').write(bytes(floorband))

    # RDBLOCK's handler wants a column for coordinates outside the room too,
    # so the table is biased: index x + BLOCKOF_BIAS, value column + 2, over
    # -64 to 319 and columns -2 to 11.
    BLOCKOF_BIAS, BLOCKOF_LEN = 64, 384
    blockof = bytearray(BLOCKOF_LEN)
    # GETBLOCKXP takes `angle` off the base coordinate before the lookup.
    # That is the whole of it: a character stands on the TOP surface of his
    # tile, which the perspective draws half a tile right of its front face,
    # and `angle` is what carries him there.  The figure looking right of the
    # tile it belongs to is the drawing being right, not wrong.
    angle_px = 2 * popframe.ANGLE       # logic units are half pixels
    for i in range(BLOCKOF_LEN):
        b = (i - BLOCKOF_BIAS - angle_px) // BLOCK_PX
        blockof[i] = max(-2, min(11, b)) + 2
    open(os.path.join(binout, 'blockof.bin'), 'wb').write(bytes(blockof))

    # GETDIST in CTRLSUBS.S works in OFFSET, the position within the block in
    # POP's 140-wide space -- 0 to 13, two screen pixels to the unit.  It used
    # to be a table of 288; the game works it out from the block column now,
    # which is three subtractions and 288 bytes we did not have.

    # The flame itself, with nothing behind it, and a mask saying which
    # pixels are its own.  A torch's flame sits at room pixel 28*col + 35, so
    # it falls on one of two byte boundaries and no more -- three off an even
    # column, seven off an odd one -- and the nine frames are shifted for
    # both.  None of this is about a particular room, so it is the same for
    # the whole level; where a room's torches are is worked out when it is
    # entered.
    FLAME_W, FLAME_H = 3, 16
    flames, flamemask = bytearray(), bytearray()
    for align in (3, 7):
        for img in [room.tab1.get(n) for n in FLAME_FRAMES]:
            pix = list(img.pixels())
            for r in range(FLAME_H):
                line = bytearray(FLAME_W)
                for b8 in range(FLAME_W):
                    for bit in range(8):
                        x = b8 * 8 + bit - align
                        y = r - (FLAME_H - img.height)
                        if 0 <= x < img.px_width and 0 <= y < img.height:
                            if pix[y][x]:
                                line[b8] |= 0x80 >> bit
                flames += line
    for align in (3, 7):
        line = bytearray(FLAME_W)
        for b8 in range(FLAME_W):
            for bit in range(8):
                x = b8 * 8 + bit - align
                if 0 <= x < 14:
                    line[b8] |= 0x80 >> bit
        flamemask += line
    # Where a flame is coloured: the cells its pixels actually reach, over
    # all nine frames, for each of the two shifts and each of the three
    # heights a torch can burn at -- the flame's sixteen rows start four,
    # three and two lines into a cell on the three block rows.  An odd
    # column's flame comes out a cross, an even one's two cells by three;
    # the three by three box it is drawn in turned the wall the flame's
    # colour.  Bit 0 is the top left cell, then along and down.
    flcells = []
    for ai in range(2):
        for br in range(3):
            top = renderroom.BLOCKBOT[br + 1] - 3 - 43 - 15
            cells = 0
            for f in range(len(FLAME_FRAMES)):
                base = (ai * len(FLAME_FRAMES) + f) * FLAME_W * FLAME_H
                for r in range(FLAME_H):
                    for c in range(FLAME_W):
                        if flames[base + r * FLAME_W + c]:
                            cr = (top + r) // 8 - top // 8
                            cells |= 1 << (cr * 3 + c)
            flcells.append(cells)

    open(os.path.join(binout, 'flamemask.bin'), 'wb').write(bytes(flamemask))
    open(os.path.join(binout, 'flametab.bin'), 'wb').write(
        bytes(FLAME_FRAMES.index(n) for n in FLAME_TABLE))


    seq, code, entry = build_sequences()
    used = seq.walk(KID_SEQS)
    # And the frames the code puts him in that no sequence names: 161, the
    # block that worked, which CHECKSTRIKE sets over 150.
    used += [f for f in (161,) if f not in used]
    table, blobs, trims = build_sprites(used)
    # A falling floor is nobody's frame, so it goes one past his own, in the
    # bank the last of the sprites leave half empty.
    ff_w, ff_data = falling_floor()
    ff_frame = len(table) // 6
    ff_at = ((len(blobs) - 1) << BANK_SHIFT) | len(blobs[-1])
    table += bytes([ff_w, FF_ROWS, 0, 0]) + ff_at.to_bytes(2, 'little')
    blobs[-1] += ff_data
    ff_w4, ff_data4 = falling_floor(4)
    ff_at4 = len(blobs[-1])
    blobs[-1] += ff_data4
    ff_at0 = ff_at & ((1 << BANK_SHIFT) - 1)
    ff_blob = len(blobs) - 1
    assert len(blobs[-1]) <= BANK_SIZE - 2, 'the falling floor does not fit'

    # The guard's own frames, after it: USEALTSETS in CTRLSUBS.S draws a
    # guard's 150 to 189 out of ALTSET1 -- chtable4, himself with the sword
    # in the other hand -- and his falling 102 to 106 as 172 to 176.  The
    # rest of what he does he does in the kid's frames.  Index ALT_BASE + n
    # - 150 is ALTSET1's frame n, in every table indexed by frame.
    alt_base = len(table) // 6
    alt = popframe.load_altset1()
    table += bytes(6 * ALT_FRAMES)
    alt_spans = []              # where they went, for another set to go
    for i in range(ALT_FRAMES):
        f = alt.get(150 + i)
        if f is not None and f.index:
            lay_frame(table, blobs, trims, alt_base + i, f)
            e = (alt_base + i) * 6
            b, end = len(blobs) - 1, len(blobs[-1])
            start = end - table[e] * table[e + 1]
            if alt_spans and alt_spans[-1][0] == b and alt_spans[-1][2] == start:
                alt_spans[-1][2] = end
            else:
                alt_spans.append([b, start, end])

    # SETUPSWORD in CTRLSUBS.S: the sword in his hand is not in his picture
    # but a picture of its own out of chtable3, laid over him at SWORDTAB's
    # offset from his anchor -- dx the way he faces, dy down from FCharY.
    # Both offsets are folded here into one record per frame, shaped like a
    # frame's own (width, height, anchor facing left, anchor facing right,
    # blob) and the sword's Fdy after it, so the engine lays it down exactly
    # as it lays him down.  fswd says which record a frame has, 0 for none.
    swtab = sword_table()
    t3 = popimg.Table(os.path.join(popframe.IMAGES, popframe.TABLES[2]))
    frl = popframe.load()
    logic = dict((n, frl[n]) for n in used if n in frl)
    logic.update((alt_base + i, alt[150 + i]) for i in range(ALT_FRAMES)
                 if 150 + i in alt)
    fswd = bytearray(len(table) // 6)
    poses = bytearray()
    sword_at = {}
    for n in sorted(logic):
        f = logic[n]
        if not f.sword & 0x3f:
            continue
        im, sdx, sdy = swtab[(f.sword & 0x3f) - 1]
        if not im:
            continue                    # image 0: SETUPSWORD draws nothing
        # SETUPCHAR doubles his Fdx into FCharX, which is in pixels already,
        # and ADDFCHARX then adds the sword's dx to that as it stands: the
        # sword's is in pixels, his in 140 wide units.
        total = 2 * f.dx + sdx
        # An odd one would want the blitter's odd shifts, and those tables
        # are two kilobytes of the fixed map for nothing else: the picture is
        # stored a pixel along instead, and lands on exactly the same pixels.
        pad = total & 1
        total += pad
        w, h, data = sprite_bytes(t3.get(im), 0, pad)
        cut, below, w, h, data = trim_frame(w, h, data)
        if not h:
            continue
        if (im, pad) not in sword_at:   # one copy of a picture, however
            if len(blobs[-1]) + len(data) > BANK_SIZE - 2:  # many hold it
                blobs.append(b'')
            sword_at[im, pad] = (((len(blobs) - 1) << BANK_SHIFT)
                                 | len(blobs[-1]))
            blobs[-1] += data
        at = sword_at[im, pad]
        left, right = -total + cut * 8, total - (cut + w) * 8
        dy = f.dy + sdy - below
        assert all(-128 <= v < 128 for v in (left, right, dy)), n
        poses += bytes([w, h, left & 0xff, right & 0xff]) \
            + at.to_bytes(2, 'little') + bytes([dy & 0xff])
        fswd[n] = len(poses) // 7
    assert len(blobs) <= 3, 'the swords do not fit'
    # The frame table and the sequences share the canvas bank.  Both are
    # read at points in a frame where nothing wants the room, so they are
    # paged in for those, and the canvas starts after them.
    # Every judgement about edges is made from GETBASEX, not from CharX: the
    # frame's own Fdx and the footmark in the low bits of Fcheck say where his
    # weight is.  Bit 6 of Fcheck says whether to look for floor under him at
    # all, which is how a step can swing out over a drop without falling.
    # SETUPCHAR: FCharY = CharY + Fdy.  Without it every frame of a sequence
    # is drawn at the same height and the climb looks like it teleports.
    # All three are indexed by frame like the frame table, so they ride in
    # the canvas bank with it: 687 bytes the fixed half of the map needs for
    # code.
    fr = logic
    top = len(table) // 6
    fcheck = bytearray(top)
    fdx = bytearray(top)
    fdy = bytearray(top)
    # Fdy is where the drawing hangs the picture, so the rows cut off the
    # bottom of a frame come off it: the top row then lands where it did.
    # Fdx and Fcheck are the logic's own -- GETBASEX asks them where his
    # weight is, not where his pixels are -- and the box never touches them.
    for n in range(top):
        if n in fr:
            fcheck[n] = fr[n].check
            fdx[n] = fr[n].dx & 0xff
            fdy[n] = (fr[n].dy - trims.get(n, 0)) & 0xff
    spare = table + code + entry + fcheck + fdx + fdy + fswd + poses
    open(os.path.join(binout, 'bank_spare.bin'), 'wb').write(spare)

    # The background bank: the two dungeon image tables, the piece tables of
    # BGDATA.S and the level's blueprint, in a shape a Z80 can index.  A room
    # is composed out of these when it is walked into, the way POP does it.
    bgblob, bgat, bgoffs = bgexport.build(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', '..',
        '01 POP Source', 'Levels', ROOM[0]))
    # After the blueprint, what the Z80 needs to start a level: see
    # level_head.  Level one's is only there to keep the shape; the next
    # levels come off the tape as blueprint and head together, over it.
    assert bgat['level'] + 2304 == len(bgblob)
    bgblob = bytes(bgblob) + level_head(1)
    # The torch flames go in after the level.  They are read a frame at a
    # time, into a buffer, before they are laid over the room -- which is
    # in the art bank, so they could not be read from here directly -- and
    # the fixed half of the map has code to hold instead.
    flames_at = len(bgblob)
    bgblob = bytes(bgblob) + bytes(flames)
    assert len(bgblob) <= BANK_SIZE, 'the background bank is full'
    open(os.path.join(binout, 'bank_bg.bin'), 'wb').write(bgblob)
    # The canvas bank is bank 7, whose first 6912 bytes are the 128K's
    # second screen.  The tape still drops the frame table and the sequences
    # at the window -- above it, the 128 editor keeps its workspace while
    # BASIC runs -- and the program moves them up past the screen once BASIC
    # is gone.  The two floorpiece masks follow them.  The canvas itself, the
    # room as it is composed, would not fit as well, and goes to the bank the
    # last of the sprites leave half empty.
    tables = PAGE_WINDOW + 6912
    assert tables + len(spare) <= 0x10000, 'the canvas bank is full'
    # The levels after the first, each with the character set it wants
    # after it on the tape if it is not the one the tape started with: the
    # tape's blocks in order, for build.sh.
    fdy_at = tables + len(table) + len(code) + len(entry) + 2 * top
    tape = []
    for n in range(2, LEVELS + 1):
        chset = (chset_block(CHSET[n], alt, alt_base, alt_spans,
                             tables, fdy_at) if n in CHSET else b'')
        blob = bgexport.level_blob(level_path(n)) + level_head(n, len(chset))
        open(os.path.join(binout, 'level%d.bin' % n), 'wb').write(blob)
        tape.append('build/bin/level%d.bin' % n)
        if chset:
            open(os.path.join(binout, 'chset%d.bin' % n), 'wb').write(chset)
            tape.append('build/bin/chset%d.bin' % n)
            print('chset%d.bin  %d байт: %s' % (n, len(chset), CHSET[n]))
    open(os.path.join(binout, 'tape.lst'), 'w', newline='').write('\n'.join(tape) + '\n')
    # The sounds go after the last of the sprites, in the canvas's bank:
    # which CPC effect each of POP's sounds and tunes is, the effects' table
    # and their data, read with that bank paged in for a moment.
    while len(blobs) < 3:
        blobs.append(b'')
    sfxtab, sfxdata = cpcsound.build(binout)
    sfxmap = bytes(CPC_FOR_SOUND.get(n, NONE) for n in SOUNDS)
    sfxmap += bytes(CPC_FOR_SONG.get(n, NONE) for n in range(SONGS))
    sfxmap_at = PAGE_WINDOW + len(blobs[2])
    sfxtab_at = sfxmap_at + len(sfxmap)
    sfxdata_at = sfxtab_at + len(sfxtab)
    blobs[2] = bytes(blobs[2]) + sfxmap + sfxtab + sfxdata
    spr3 = blobs[2]
    canvas = PAGE_WINDOW + len(spr3) + len(SIG_SPR) + 3
    # The two floorpiece masks follow the canvas's pixels in their bank, and
    # the room-build code follows them; the canvas bank keeps the tables.
    # Past the canvas, and never written by building a room: the code that
    # works on the canvas bank with it paged in (CODE1, see pop.asm) and at
    # the top the two floorpiece masks.  While the titles run, the room's
    # code is kept where CODE1's tail and the masks will go (RBINTRO).
    code1 = canvas + 40 * 192
    maskcan = 0x10000 - 12 - 2 * 40 * 45
    rbintro = 0x10000 - 12 - RBROOM         # the princess's room had 715 spare
    code1_max = maskcan - code1
    assert code1_max >= 256, 'no room for the canvas bank code'
    # The princess's room rides in the canvas's place, empty until the
    # first room is built: the room packed, the pictures and the script
    # packed, unpacked there for the scene -- see princessscr.py.  The clean
    # copy of the band it composes goes past the title screens.
    cut_room = rbintro - canvas
    cut, cutfixed, cutinc, cutstats = princessscr.build(canvas, cut_room)
    open(os.path.join(binout, 'cutfixed.bin'), 'wb').write(cutfixed)
    # And PlayCut1, the princess waiting before level two: a tape block of
    # its own, cut1.asm and what it plays -- see princessscr.build1.  Its
    # code is put to it by build.sh.
    cut1, cut1fixed, cut1inc, cut1low = princessscr.build1(
        cpcmusic.tunes((6,))[0], RBROOM)
    open(os.path.join(binout, 'cut1data.bin'), 'wb').write(cut1)
    open(os.path.join(binout, 'cutfixed1.bin'), 'wb').write(cut1fixed)
    with open(os.path.join(out, 'cut1.inc'), 'w') as f:
        f.write('; generated by mkassets.py -- do not edit\n')
        f.write('\n'.join(cut1inc) + '\n')
        f.write('CUT1_LOW    equ %d\n' % cut1low)
    print('принцесса 1 комната, картинки и мелодия %d байт на плёнке, код '
          'отдельно' % len(cut1))
    # The clean copy of the princess's band goes over the splash, which is
    # unpacked once, at the start, and never again; and the canvas bank's
    # own code (CODE1) travels past the music, for start to put in place.
    clean_off = len(SIG_ART) + dict(intro_at)['splash']
    splash_len = dict(intro_at)['presents'] - dict(intro_at)['splash']
    assert princessscr.BAND_ROWS * 32 <= splash_len,         'the princess band is longer than the splash it goes over'
    c1art = PAGE_WINDOW + len(SIG_ART) + len(intro)
    print('принцесса  комната %d, картинки %d (%d), в памяти %d; в банке 1 '
          'свободно %d' % (cutstats + (cut_room - cutstats[0] - cutstats[1],)))
    inc = ['; generated by mkassets.py -- do not edit',
           'BANK_BG     equ %d' % BANK_BG,
           'BANK_CANVAS equ %d' % BANK_CANVAS,
           'BANK_CVS    equ %d' % BANK_SPR[2],
           'SPARE_LEN   equ %d' % len(spare),
           'sprites     equ %d' % tables,
           'seqs        equ %d' % (tables + len(table)),
           'seqtab      equ %d' % (tables + len(table) + len(code)),
           'fcheck      equ %d' % (tables + len(table) + len(code)
                                   + len(entry)),
           'fdx         equ %d' % (tables + len(table) + len(code)
                                   + len(entry) + top),
           'fdy         equ %d' % (tables + len(table) + len(code)
                                   + len(entry) + 2 * top),
           'fswd        equ %d' % (tables + len(table) + len(code)
                                   + len(entry) + 3 * top),
           'swposes     equ %d' % (tables + len(table) + len(code)
                                   + len(entry) + 4 * top),
           'MASKCAN     equ %d' % maskcan,
           'CODE1       equ %d' % code1,
           'CODE1_MAX   equ %d' % code1_max,
           'RBINTRO     equ %d' % rbintro,
           'CANVAS      equ %d' % canvas,
           'sfxmap      equ %d' % sfxmap_at,
           'sfxtab      equ %d' % sfxtab_at,
           'sfxdata     equ %d' % sfxdata_at]
    for name, off in intro_at:
        inc.append('T_%-9s equ %d' % (name.upper(), PAGE_WINDOW + len(SIG_ART) + off))
    inc += cutinc
    inc.append('CUT_CLEAN_OFF equ %d' % clean_off)
    inc.append('C1ART       equ %d' % c1art)
    at = tunes_off
    for i, t in enumerate(tunes):                   # where each begins,
        inc.append('TUNE%d       equ %d' % (i, PAGE_WINDOW + at))     # and
        at += len(t)                                # the last its end
    inc.append('TUNE%d       equ %d' % (len(tunes), PAGE_WINDOW + at))
    for k, v in bgat.items():
        inc.append('%-11s equ %d' % (k, PAGE_WINDOW + v))
    inc.append('flames      equ %d' % (PAGE_WINDOW + flames_at))
    inc.append('FLAME_BYTES equ %d' % (FLAME_W * FLAME_H))
    for i, cells in enumerate(flcells):
        inc.append('FLCELLS%d    equ %d' % (i, cells))
    for n, o in bgoffs:
        inc.append('T_%-9s equ %d' % (n.upper(), o))
    inc.append('BUBBLES     equ %d' % (0x80 | bgexport.BUBBLES))
    inc.append('BUBMASK     equ %d' % (0x80 | bgexport.BUBMASK))
    for n in ('space', 'floor', 'posts', 'gate', 'panelwif', 'pillartop',
              'loose', 'panelwof', 'block', 'spikes', 'archtop1', 'archtop2',
              'torch', 'dpressplate', 'pressplate', 'upressplate',
              'rubble', 'sword', 'flask', 'slicer', 'mirror', 'bones'):
        inc.append('BG_%-8s equ %d' % (n.upper(), getattr(renderroom.bg, n)))
    inc.append('BG_EXIT     equ %d' % renderroom.bg.exit_)
    inc.append('BG_NUMBLOX  equ %d' % renderroom.bg.numblox)
    inc.append('BG_FFALLING equ %d' % renderroom.bg.Ffalling)
    open(os.path.join(out, 'bg.inc'), 'w').write(chr(10).join(inc) + chr(10))




    # The index stays in fixed memory -- it is walked every frame -- and only
    # the pixels go in banks.  The first rides at 0xC000 in the tape image and
    # so needs no copying, only a signature to say which bank it landed in.
    open(os.path.join(binout, 'sprtab.bin'), 'wb').write(table)
    if len(blobs) > 3:
        raise SystemExit('спрайты переросли три банка: %d' % sum(map(len, blobs)))
    while len(blobs) < 3:
        blobs.append(b'')          # without the mask two banks hold them all
    # The signature goes in even when the bank holds no frames at all: the
    # loader LOADs every one of them by line number and a block of no length
    # is "R Tape loading error", while check_banks looks for the signature in
    # all three whatever they hold.
    for i in (0, 1, 2):
        open(os.path.join(binout, 'bank_spr%d.bin' % (i + 1)), 'wb').write(
            blobs[i] + SIG_SPR + (bytes(3) + cut if i == 2 else b''))

    # Shifting a row bit by bit was costing more than the whole rest of the
    # frame, so it goes through tables instead: for a shift of s, hi[s][b] is
    # what stays in this byte and lo[s][b] what spills into the next.  The
    # mask wants ones shifted in at both ends and gets them for nothing: it
    # is the data's complement, so the zeroes the shift brings in complement
    # to exactly the ones it needs, and there are no fill tables any more.
    #
    # Every coordinate a picture is placed at is even -- CharX moves two
    # pixels to POP's unit and the swords are stored to match -- so only the
    # shifts of two, four and six need tables, and the shift of none needs
    # none at all: its loops simply lay the bytes down.
    hi = bytearray(3 * 256)
    lo = bytearray(3 * 256)
    for i, sh in enumerate((2, 4, 6)):
        for b in range(256):
            hi[i * 256 + b] = b >> sh
            lo[i * 256 + b] = (b << (8 - sh)) & 0xff
    open(os.path.join(binout, 'shifthi.bin'), 'wb').write(bytes(hi))
    open(os.path.join(binout, 'shiftlo.bin'), 'wb').write(bytes(lo))

    rev = bytearray(256)
    for b in range(256):
        r = 0
        for i in range(8):
            if b & (1 << i):
                r |= 0x80 >> i
        rev[b] = r
    open(os.path.join(binout, 'revtab.bin'), 'wb').write(bytes(rev))

    # The strength meters' bullet, image $88 of the second dungeon table as
    # GAMEBG.S names it: four rows of one byte, and the same turned about for
    # the opponent's, which DRAWOPPMETER draws mirrored.
    t2 = popimg.Table(os.path.join(popframe.IMAGES, 'IMG.BGTAB2.DUN'))
    w, h, bullet = sprite_bytes(t2.get(0x88 & 0x7f), 0)
    assert (w, h) == (1, 4), (w, h)
    # The Apple draws it in every other pixel, which its colour fills in; in
    # one colour here those are stripes.  So the bullet is drawn solid, and
    # taller with sharper corners, as the user asked: seven rows, pointing the
    # same way from the same column, down to the foot of the screen.
    bullet = bytes([0x40, 0x60, 0x70, 0x78, 0x70, 0x60, 0x40])
    # The bubbles as bits, for changing them in place: for each of the three
    # pictures, its six rows that have anything, pixels one to five of the
    # seven as bits 4 to 0 -- after six rows of none, for the blank one.
    bits = bytearray(6)
    for n in bgexport.BUBBLE_IMAGES:
        lines = list(t2.get(n).pixels())
        for r in range(1, 7):
            bits.append(sum(lines[r][p] << (5 - p) for p in range(1, 6)))
    open(os.path.join(binout, 'bubblebits.bin'), 'wb').write(bytes(bits))
    open(os.path.join(binout, 'bullet.bin'), 'wb').write(
        bullet + bytes(rev[b] for b in bullet))

    with open(os.path.join(out, 'assets.inc'), 'w') as f:
        f.write('; generated by mkassets.py -- do not edit\n')
        f.write('sprblob     equ %d' % PAGE_WINDOW + chr(10))
        f.write('room        equ %d'
                % (PAGE_WINDOW + 2 + len(fmask) + len(hmask)) + chr(10))
        f.write('floormask   equ %d' % (PAGE_WINDOW + 2) + chr(10))
        f.write('halfmask    equ %d'
                % (PAGE_WINDOW + 2 + len(fmask)) + chr(10))
        # foreband is read only with the art bank in, so it lives there,
        # between the room and the mask: a mask that ever ran past the end
        # of the bank would wrap into the ROM, not into it.
        fb_at = PAGE_WINDOW + 2 + len(fmask) + len(hmask) + len(screen)
        assert fb_at + 192 + len(foremask) <= 0x10000, 'the art bank is full'
        f.write('foreband    equ %d' % fb_at + chr(10))
        f.write('foremask    equ %d' % (fb_at + 192) + chr(10))
        # as many of its rows as fit under the interrupt's way in: a room
        # that wants more goes without cover on its lowest
        fore_rows = (0x10000 - 12 - fb_at - 192) // ROOM_BYTES
        f.write('FORE_ROWS   equ %d' % min(fore_rows, 192) + chr(10))
        f.write('ROOM_BYTES  equ %d' % ROOM_BYTES + chr(10))
        f.write('CAM_MAX     equ %d' % CAM_MAX + chr(10))
        f.write('SIG_ART_AT  equ %d' % PAGE_WINDOW + chr(10))
        f.write('SIG_ART     equ %d' % int.from_bytes(SIG_ART, 'little') + chr(10))
        f.write('SIG_SPR     equ %d' % int.from_bytes(SIG_SPR, 'little') + chr(10))
        for i, b in enumerate(blobs):
            f.write('SIG_SPR%d_AT equ %d' % (i + 1, PAGE_WINDOW + len(b))
                    + chr(10))
        f.write('BANK_ART    equ %d' % BANK_ART + chr(10))
        for i, n in enumerate(BANK_SPR):
            f.write('BANK_SPR%d   equ %d' % (i + 1, n) + chr(10))
        f.write('INK_ROOM    equ %d' % INK_ROOM + chr(10))
        f.write('INK_FLAME_TOP equ %d' % INK_FLAME_TOP + chr(10))
        f.write('INK_FLAME_MID equ %d' % INK_FLAME_MID + chr(10))
        f.write('INK_FLAME_LOW equ %d' % INK_FLAME_LOW + chr(10))
        f.write('BLK_BLOCK   equ %d' % renderroom.bg.block + chr(10))
        f.write('F_CHECK     equ %d' % 0x40 + chr(10))
        f.write('F_FOOTMARK  equ %d' % 0x1f + chr(10))
        f.write('FF_FRAME    equ %d' % ff_frame + chr(10))
        f.write('ALT_BASE    equ %d' % alt_base + chr(10))
        f.write('FF_W        equ %d' % ff_w + chr(10))
        f.write('FF_W4       equ %d' % ff_w4 + chr(10))
        f.write('FF_BLOB     equ %d' % ff_blob + chr(10))
        f.write('FF_AT0      equ %d' % (PAGE_WINDOW + ff_at0) + chr(10))
        f.write('FF_AT4      equ %d' % (PAGE_WINDOW + ff_at4) + chr(10))
        f.write('FF_H        equ %d' % FF_ROWS + chr(10))

        # POP's own sequence numbers, so the control code can read the way
        # CTRL.S does: `lda #climbdown / jmp jumpseq`.
        for n, label in sorted(seq.entries.items()):
            if n in KID_SEQS:
                f.write('SQ_%-12s equ %d' % (label.upper(), n) + chr(10))
        f.write('START_X     equ %d\n'
                % (popframe.screen_x(popframe.char_x(START_COL)) - START_NUDGE))
        f.write('START_Y    equ %d\n' % popframe.char_y(START_ROW))
        f.write('START_ROW   equ %d\n' % START_ROW)
        f.write('START_FACE  equ %d\n' % START_FACE)
        f.write('POP_START   equ %d\n' % (1 if POP_START else 0))
        f.write('BLOCKOF_BIAS equ %d\n' % BLOCKOF_BIAS)
        f.write('BLOCKOF_LEN equ %d\n' % BLOCKOF_LEN)
        f.write('ANGLE_PX    equ %d\n' % angle_px)
        # The room the tape starts him in, and the level's own start
        # room -- KidStartScrn -- where the exit tile is the way in and
        # gets no stairs, wherever a test tape starts.
        f.write('START_ROOM  equ %d\n' % int(os.environ.get('POP_START_ROOM', level.kid_start[0])))
        f.write('KIDSTART_SCRN equ %d\n' % level.kid_start[0])
        f.write('LEVEL_LEN   equ %d\n' % (2304 + LEVEL_HEAD))
        f.write('LEVELS      equ %d\n' % LEVELS)
        f.write('LV_ARMED1   equ %d\n' % (1 if LEVELS > 1 else 0))
        f.write('LV_KIDSCRN  equ %d\n' % (poplevel.INFO + poplevel.KidStartScrn))
        f.write('LV_HEAD     equ 2304\n')
        f.write('MS3_X       equ %d\n' % (MILESTONE3[0] | MILESTONE3[1] << 8))
        f.write('MS3_Y       equ %d\n' % MILESTONE3[2])
        f.write('MS3_ROW     equ %d\n' % MILESTONE3[3])
        f.write('MS3_FACE    equ %d\n' % MILESTONE3[4])
        f.write('MS3_SCRN    equ %d\n' % MS3_SCRN)
        f.write('MS3_ROOM    equ %d\n' % MS3_ROOM)
        f.write('MS3_LOOSE   equ %d\n' % MS3_LOOSE)
        f.write('MS3_LOOSESCRN equ %d\n' % MS3_LOOSESCRN)
        # And a tape for the fight can start him with the sword already his.
        f.write('START_SWORD equ %d\n' % int(os.environ.get('POP_GOTSWORD', 0)))
        for n, name in enumerate(SOUNDS):
            f.write('SND_%-12s equ %d\n' % (name.upper(), n))
        f.write('SOUNDS      equ %d\n' % len(SOUNDS))
        f.write('SONGS       equ %d\n' % SONGS)
        f.write('SFXCOUNT    equ %d\n' % cpcsound.COUNT)

    print('bank_art    %d байт' % len(art))
    for i, b in enumerate(blobs):
        print('bank_spr%-3d %d байт  (свободно в банке %d)'
              % (i + 1, len(b), BANK_SIZE - len(b) - (2 if not i else 0)))
    print('спрайтов    %d кадров, %d байт' % (len(used), sum(map(len, blobs))))
    print('sprtab.bin  %d байт' % len(table))
    print('seqs.bin    %d байт, %d последовательностей из SEQTABLE.S'
          % (len(code), len(seq.entries)))
    print('sprtab.bin  %d байт, кадры 0..%d' % (len(table), len(table) // 6 - 1))
    # FloorY, indexed by block row + 1: the plane his feet rest on.
    floory = bytes(v & 0xff for v in popframe.FLOOR_Y)
    open(os.path.join(binout, 'floory.bin'), 'wb').write(floory)
    blocktop = bytes(v & 0xff for v in popframe.BLOCK_TOP)
    open(os.path.join(binout, 'blocktop.bin'), 'wb').write(blocktop)


    print('tiles.bin   типы блоков: %s' % ' '.join('%d' % t for t in ids[:10]))
    print('floory.bin  %s' % ' '.join('%d' % f for f in floory))
    print('blocktop.bin %s' % ' '.join('%d' % f for f in blocktop))
    print('foremask    %d rows painted in the game' % (len(foremask) // ROOM_BYTES))
    print('floor masks %d rows, %d bytes each' % (len(band), len(fmask)))
    print('art bank    %d of %d bytes' % (len(art) + 2, BANK_SIZE))
    print('bg bank     %d of %d bytes' % (len(bgblob), BANK_SIZE))
    print('flames      %d bytes over two alignments' % len(flames))
    print('START_X=%d START_Y=%d'
          % (popframe.screen_x(popframe.char_x(START_COL)),
             popframe.char_y(START_ROW)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
