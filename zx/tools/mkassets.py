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

# A block is drawn at canvas x = 28*b, so on screen it runs 28*b - CAMERA to
# 28*b + 27 - CAMERA -- but the block a character is ON is not simply the one
# his coordinate lands in.  CharX is BlockEdge[b+5] + angle + 7, which is the
# far edge of his own block, and GETBLOCKXP in CTRLSUBS.S takes `angle` back
# off before the lookup, putting him at the middle of the block instead.  That
# is a whole 14 pixels on screen, and without it he walks half a block past
# the edge of the floor before he notices it has gone.
BLOCK_PX = 28
TILE_FLOOR, TILE_SOLID = 1, 2

ROOM = ('LEVEL1', 1)
CAMERA = 12

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

# A frame's blob offset carries the bank it lives in: the top two bits index a
# table the program fills in at startup, the low fourteen are the offset
# inside that bank.  Sprites therefore cost no more table than they did with
# one bank, and no frame is ever split across the join.
BANK_SHIFT = 14
SIG_ART, SIG_SPR = bytes([0x5A, 0xA5]), bytes([0xA5, 0x5A])
START_ROW, START_COL = 0, 5


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
    screen = zxscreen.build(zxscreen.window(px, CAMERA), 0x05)

    types, _ = level.screen(ROOM[1])
    ids = [b & poplevel.IDMASK for b in types]
    flags = bytearray(30)
    for i, t in enumerate(ids):
        # A tile has a floor when its D section is one of the floor tops --
        # the renderer's own test -- plus the loose floor, whose top is drawn
        # by its movable piece instead.
        if (renderroom.bg.pieced[t] in renderroom.FLOOR_TOPS
                or t == renderroom.bg.loose):
            flags[i] |= TILE_FLOOR      # something to stand on
        if t == renderroom.bg.block:
            flags[i] |= TILE_SOLID      # and nothing to walk through
    open(os.path.join(binout, 'tiles.bin'), 'wb').write(bytes(flags))

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
    rects = bytearray()
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
            x0 = (col * 4 + renderroom.bg.frontx[t]) * 7 - CAMERA
            ybot = ay + renderroom.bg.fronty[t]
            ytop = ybot - img.height + 1
            x1, y1 = x0 + img.width * 7 - 1, ybot
            x0, y0 = max(0, x0), max(0, ytop)
            x1, y1 = min(255, x1), min(191, ybot)
            if x1 < x0 or y1 < y0:
                continue
            rects += bytes([x0, x1 - x0 + 1, y0, y1 - y0 + 1])
    rects = bytes([len(rects) // 4]) + rects
    open(os.path.join(binout, 'frontrect.bin'), 'wb').write(rects)

    # Putting the foreground back is the most expensive thing in a frame, and
    # most of it is spent walking over bytes the mask has nothing in.  This
    # says, per scanline, the first and last byte column it covers, so the
    # walk can be cut to the part that matters -- or skipped.
    span = bytearray(192 * 2)
    for row in range(3):
        pass
    cover = [[] for _ in range(192)]
    for i in range(rects[0]):
        x0, xw, y0, yh = rects[1 + i * 4:5 + i * 4]
        for y in range(y0, y0 + yh):
            cover[y].append((x0 >> 3, (x0 + xw - 1) >> 3))
    for y in range(192):
        if cover[y]:
            span[y * 2] = min(a for a, _ in cover[y])
            span[y * 2 + 1] = max(b for _, b in cover[y])
        else:
            span[y * 2], span[y * 2 + 1] = 31, 0     # first > last: nothing
    open(os.path.join(binout, 'forespan.bin'), 'wb').write(bytes(span))

    # The screen's thirds and interleave cost a dozen instructions a row to
    # work out, and four passes a frame do it.  192 words is cheaper.
    rows = bytearray()
    for y in range(192):
        rows += (0x4000 + zxscreen.bitmap_offset(0, y)).to_bytes(2, 'little')
    open(os.path.join(binout, 'rowaddr.bin'), 'wb').write(bytes(rows))

    # The art bank: the room first, then the foreground mask behind it, and a
    # signature the program checks -- a bank that did not load leaves a black
    # screen and nothing to go on, so it is worth two bytes to say so.
    art = screen
    open(os.path.join(binout, 'bank_art.bin'), 'wb').write(art + SIG_ART)

    blockof = bytearray(256)            # screen pixel -> block column
    # GETBLOCKXP takes `angle` off the base coordinate before the lookup.
    # That is the whole of it: a character stands on the TOP surface of his
    # tile, which the perspective draws half a tile right of its front face,
    # and `angle` is what carries him there.  The figure looking right of the
    # tile it belongs to is the drawing being right, not wrong.
    angle_px = 2 * popframe.ANGLE       # logic units are half pixels
    shift = CAMERA - angle_px
    for x in range(256):
        b = (x + shift) // BLOCK_PX
        blockof[x] = b if 0 <= b <= 9 else 0xFF
    open(os.path.join(binout, 'blockof.bin'), 'wb').write(bytes(blockof))

    # GETDIST in CTRLSUBS.S works in OFFSET, the position within the block in
    # POP's 140-wide space -- 0 to 13, two screen pixels to the unit.  Every
    # judgement about edges is made in those units, so the table comes along.
    distof = bytearray(256)
    for x in range(256):
        distof[x] = ((x + shift) % BLOCK_PX) // 2
    open(os.path.join(binout, 'distof.bin'), 'wb').write(bytes(distof))

    seq, code, entry = build_sequences()
    open(os.path.join(binout, 'seqs.bin'), 'wb').write(code)
    open(os.path.join(binout, 'seqtab.bin'), 'wb').write(entry)

    used = seq.walk(KID_SEQS)
    table, blobs = build_sprites(used)

    # Every judgement about edges is made from GETBASEX, not from CharX: the
    # frame's own Fdx and the footmark in the low bits of Fcheck say where his
    # weight is.  Bit 6 of Fcheck says whether to look for floor under him at
    # all, which is how a step can swing out over a drop without falling.
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
    open(os.path.join(binout, 'fcheck.bin'), 'wb').write(bytes(fcheck))
    open(os.path.join(binout, 'fdx.bin'), 'wb').write(bytes(fdx))
    # SETUPCHAR: FCharY = CharY + Fdy.  Without it every frame of a sequence
    # is drawn at the same height and the climb looks like it teleports.
    open(os.path.join(binout, 'fdy.bin'), 'wb').write(bytes(fdy))
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
        f.write('room        equ %d' % PAGE_WINDOW + chr(10))
        f.write('foremask    equ %d' % (PAGE_WINDOW + len(screen) + 2) + chr(10))
        f.write('SIG_ART_AT  equ %d' % (PAGE_WINDOW + len(art)) + chr(10))
        f.write('SIG_ART     equ %d' % int.from_bytes(SIG_ART, 'little') + chr(10))
        f.write('SIG_SPR     equ %d' % int.from_bytes(SIG_SPR, 'little') + chr(10))
        for i, b in enumerate(blobs):
            f.write('SIG_SPR%d_AT equ %d' % (i + 1, PAGE_WINDOW + len(b))
                    + chr(10))
        f.write('BANK_ART    equ %d' % BANK_ART + chr(10))
        for i, n in enumerate(BANK_SPR):
            f.write('BANK_SPR%d   equ %d' % (i + 1, n) + chr(10))
        f.write('F_CHECK     equ %d' % 0x40 + chr(10))
        f.write('F_FOOTMARK  equ %d' % 0x1f + chr(10))
        f.write('TILE_FLOOR  equ %d' % TILE_FLOOR + chr(10))
        f.write('TILE_SOLID  equ %d' % TILE_SOLID + chr(10))

        # POP's own sequence numbers, so the control code can read the way
        # CTRL.S does: `lda #climbdown / jmp jumpseq`.
        for n, label in sorted(seq.entries.items()):
            if n in KID_SEQS:
                f.write('SQ_%-12s equ %d' % (label.upper(), n) + chr(10))
        f.write('START_X     equ %d\n'
                % (popframe.screen_x(popframe.char_x(START_COL)) - CAMERA))
        f.write('START_Y     equ %d\n' % popframe.char_y(START_ROW))
        f.write('START_ROW   equ %d\n' % START_ROW)

    print('bank_art    %d байт (комната)' % len(art))
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

    print('tiles.bin   %s' % ' '.join('%d' % f for f in flags))
    print('floory.bin  %s' % ' '.join('%d' % f for f in floory))
    print('frontrect   %d прямоугольников переднего плана, %d байт'
          % (rects[0], len(rects)))
    print('START_X=%d START_Y=%d'
          % (popframe.screen_x(popframe.char_x(START_COL)) - CAMERA,
             popframe.char_y(START_ROW)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
