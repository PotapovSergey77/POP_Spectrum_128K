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
import sys

import bgexport
import popframe
import popseq
import poplevel
import renderroom
import zxscreen

# Which of POP's sequences the prince may be in.  One to fifty is most of his
# movement; the rest of it is scattered further up the table among the guards
# and the princess.  Fighting and dying are left out for now.
KID_SEQS = (list(range(1, 51))
            + [68,      # climbdown
               70,      # climbstairs
               72,      # stepback
               73,      # climbfail
               79,      # crawl
               84])     # running

CHAR_ANCHOR = 21

# A block is drawn at room x = 28*b, so it runs 28*b to 28*b + 27 -- but the
# block a character is ON is not simply the one
# his coordinate lands in.  CharX is BlockEdge[b+5] + angle + 7, which is the
# far edge of his own block, and GETBLOCKXP in CTRLSUBS.S takes `angle` back
# off before the lookup, putting him at the middle of the block instead.  That
# is a whole 14 pixels on screen, and without it he walks half a block past
# the edge of the floor before he notices it has gone.
BLOCK_PX = 28
TILE_FLOOR, TILE_SOLID = 1, 2

ROOM = ('LEVEL1', 1)

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
INK_FLAME = 0x02                # and red where a torch burns
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
START_ROW = int(os.environ.get('POP_START_ROW', 0))
START_COL = int(os.environ.get('POP_START_COL', 5))


def sprite_bytes(img, mirror):
    """One frame as rows of (mask, data) pairs, eight pixels to the byte."""
    rows = [list(line) for line in img.pixels()]
    if mirror:
        rows = [list(reversed(r)) for r in rows]
    width = (len(rows[0]) + 7) // 8
    out = bytearray()
    for row in rows:
        for b in range(width):
            mask = data = 0
            for bit in range(8):
                x = b * 8 + bit
                if x < len(row) and row[x]:
                    data |= 0x80 >> bit
                else:
                    mask |= 0x80 >> bit
            out.append(mask)
            out.append(data)
    return width, len(rows), bytes(out)


def build_sprites(frames_used):
    """
    Table of (width, height, xoff left, xoff right, blob offset), indexed by
    POP's own frame number so the byte code needs no translating, and the
    pixels behind it cut into bank sized pieces.  Only one facing is stored --
    mirroring at draw time through a bit reversal table costs a lookup per
    byte and saves ten kilobytes.
    """
    frames = popframe.load()
    top = max(frames_used) + 1
    table, banks = bytearray(top * 6), [bytearray()]
    for n in frames_used:
        if n not in frames:
            continue            # frame 0 is "nothing to draw"
        img = popframe.image(frames[n])
        apple_bytes = (img.px_width + 6) // 7
        width, height, data = sprite_bytes(img, 0)
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
        dx = 2 * frames[n].dx
        table[e:e + 4] = bytes([width, height, (-dx) & 0xff,
                                (dx - width * 8) & 0xff])
        table[e + 4:e + 6] = (((len(banks) - 1) << BANK_SHIFT)
                              | len(banks[-1])).to_bytes(2, 'little')
        banks[-1] += data
    return bytes(table), [bytes(b) for b in banks]


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

    # The screen's thirds and interleave cost a dozen instructions a row to
    # work out, and four passes a frame do it.  192 words is cheaper.
    rows = bytearray()
    for y in range(192):
        rows += (0x4000 + zxscreen.bitmap_offset(0, y)).to_bytes(2, 'little')
    open(os.path.join(binout, 'rowaddr.bin'), 'wb').write(bytes(rows))

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
    open(os.path.join(binout, 'bank_art.bin'), 'wb').write(SIG_ART)
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
    open(os.path.join(binout, 'flamemask.bin'), 'wb').write(bytes(flamemask))
    open(os.path.join(binout, 'flametab.bin'), 'wb').write(
        bytes(FLAME_FRAMES.index(n) for n in FLAME_TABLE))


    seq, code, entry = build_sequences()
    used = seq.walk(KID_SEQS)
    table, blobs = build_sprites(used)
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
    fr = popframe.load()
    top = len(table) // 6
    fcheck = bytearray(top)
    fdx = bytearray(top)
    fdy = bytearray(top)
    for n in range(top):
        if n in fr:
            fcheck[n] = fr[n].check
            fdx[n] = fr[n].dx & 0xff
            fdy[n] = fr[n].dy & 0xff
    spare = table + code + entry + fcheck + fdx + fdy
    open(os.path.join(binout, 'bank_spare.bin'), 'wb').write(spare)

    # The background bank: the two dungeon image tables, the piece tables of
    # BGDATA.S and the level's blueprint, in a shape a Z80 can index.  A room
    # is composed out of these when it is walked into, the way POP does it.
    bgblob, bgat, bgoffs = bgexport.build(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', '..',
        '01 POP Source', 'Levels', ROOM[0]))
    # The torch flames go in after the level.  They are read a frame at a
    # time, into a buffer, before they are laid over the room -- which is
    # in the art bank, so they could not be read from here directly -- and
    # the fixed half of the map has code to hold instead.
    flames_at = len(bgblob)
    bgblob = bytes(bgblob) + bytes(flames)
    assert len(bgblob) <= BANK_SIZE, 'the background bank is full'
    open(os.path.join(binout, 'bank_bg.bin'), 'wb').write(bgblob)
    inc = ['; generated by mkassets.py -- do not edit',
           'BANK_BG     equ %d' % BANK_BG,
           'BANK_CANVAS equ %d' % BANK_CANVAS,
           # The frame table shares the canvas bank: it is read once at the
           # top of a draw, before anything wants the room, so the two never
           # collide.  It goes first so the tape can drop it at the window.
           'sprites     equ %d' % PAGE_WINDOW,
           'seqs        equ %d' % (PAGE_WINDOW + len(table)),
           'seqtab      equ %d' % (PAGE_WINDOW + len(table) + len(code)),
           'fcheck      equ %d' % (PAGE_WINDOW + len(table) + len(code)
                                   + len(entry)),
           'fdx         equ %d' % (PAGE_WINDOW + len(table) + len(code)
                                   + len(entry) + top),
           'fdy         equ %d' % (PAGE_WINDOW + len(table) + len(code)
                                   + len(entry) + 2 * top),
           'CANVAS      equ %d' % (PAGE_WINDOW + len(spare) + 3)]
    for k, v in bgat.items():
        inc.append('%-11s equ %d' % (k, PAGE_WINDOW + v))
    inc.append('flames      equ %d' % (PAGE_WINDOW + flames_at))
    inc.append('FLAME_BYTES equ %d' % (FLAME_W * FLAME_H))
    for n, o in bgoffs:
        inc.append('T_%-9s equ %d' % (n.upper(), o))
    for n in ('space', 'floor', 'posts', 'gate', 'panelwif', 'pillartop',
              'loose', 'panelwof', 'block', 'archtop1', 'archtop2',
              'torch', 'dpressplate', 'pressplate', 'upressplate',
              'rubble', 'sword', 'flask'):
        inc.append('BG_%-8s equ %d' % (n.upper(), getattr(renderroom.bg, n)))
    inc.append('BG_EXIT     equ %d' % renderroom.bg.exit_)
    inc.append('BG_NUMBLOX  equ %d' % renderroom.bg.numblox)
    inc.append('BG_FFALLING equ %d' % renderroom.bg.Ffalling)
    open(os.path.join(out, 'bg.inc'), 'w').write(chr(10).join(inc) + chr(10))




    # The index stays in fixed memory -- it is walked every frame -- and only
    # the pixels go in banks.  The first rides at 0xC000 in the tape image and
    # so needs no copying, only a signature to say which bank it landed in.
    open(os.path.join(binout, 'sprtab.bin'), 'wb').write(table)
    open(os.path.join(binout, 'bank_spr1.bin'), 'wb').write(blobs[0] + SIG_SPR)
    for i in (1, 2):
        open(os.path.join(binout, 'bank_spr%d.bin' % (i + 1)), 'wb').write(
            blobs[i] + (SIG_SPR if blobs[i] else b''))
    if len(blobs) > 3:
        raise SystemExit('спрайты переросли три банка: %d' % sum(map(len, blobs)))
    while len(blobs) < 3:
        blobs.append(b'')

    # Shifting a row bit by bit was costing more than the whole rest of the
    # frame, so it goes through tables instead: for a shift of s, hi[s][b] is
    # what stays in this byte and lo[s][b] what spills into the next.  The
    # mask needs ones shifted in at both ends, hence the two fill tables.
    hi = bytearray(8 * 256)
    lo = bytearray(8 * 256)
    for sh in range(8):
        for b in range(256):
            hi[sh * 256 + b] = b >> sh
            lo[sh * 256 + b] = (b << (8 - sh)) & 0xff if sh else 0
    open(os.path.join(binout, 'shifthi.bin'), 'wb').write(bytes(hi))
    open(os.path.join(binout, 'shiftlo.bin'), 'wb').write(bytes(lo))
    fill = bytes([(0xff << (8 - sh)) & 0xff for sh in range(8)] +
                 [0xff >> sh for sh in range(8)])
    open(os.path.join(binout, 'fill.bin'), 'wb').write(fill)

    rev = bytearray(256)
    for b in range(256):
        r = 0
        for i in range(8):
            if b & (1 << i):
                r |= 0x80 >> i
        rev[b] = r
    open(os.path.join(binout, 'revtab.bin'), 'wb').write(bytes(rev))

    with open(os.path.join(out, 'assets.inc'), 'w') as f:
        f.write('; generated by mkassets.py -- do not edit\n')
        f.write('sprblob     equ %d' % PAGE_WINDOW + chr(10))
        f.write('room        equ %d'
                % (PAGE_WINDOW + 2 + len(fmask) + len(hmask)) + chr(10))
        f.write('floormask   equ %d' % (PAGE_WINDOW + 2) + chr(10))
        f.write('halfmask    equ %d'
                % (PAGE_WINDOW + 2 + len(fmask)) + chr(10))
        f.write('foremask    equ %d'
                % (PAGE_WINDOW + 2 + len(fmask) + len(hmask) + len(screen))
                + chr(10))
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
        f.write('INK_FLAME   equ %d' % INK_FLAME + chr(10))
        f.write('BLK_BLOCK   equ %d' % renderroom.bg.block + chr(10))
        f.write('F_CHECK     equ %d' % 0x40 + chr(10))
        f.write('F_FOOTMARK  equ %d' % 0x1f + chr(10))

        # POP's own sequence numbers, so the control code can read the way
        # CTRL.S does: `lda #climbdown / jmp jumpseq`.
        for n, label in sorted(seq.entries.items()):
            if n in KID_SEQS:
                f.write('SQ_%-12s equ %d' % (label.upper(), n) + chr(10))
        f.write('START_X     equ %d\n'
                % popframe.screen_x(popframe.char_x(START_COL)))
        f.write('START_Y     equ %d\n' % popframe.char_y(START_ROW))
        f.write('START_ROW   equ %d\n' % START_ROW)
        f.write('BLOCKOF_BIAS equ %d\n' % BLOCKOF_BIAS)
        f.write('BLOCKOF_LEN equ %d\n' % BLOCKOF_LEN)
        f.write('ANGLE_PX    equ %d\n' % angle_px)
        # The room he starts in is the way into the level, so the
        # same tile there is an entrance and gets no stairs.
        f.write('START_ROOM  equ %d\n' % int(os.environ.get('POP_START_ROOM', level.kid_start[0])))

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
