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
import poplevel
import renderroom
import zxscreen

GOTO, FACE, CHX, SEQID = 0xFF, 0xFE, 0xFD, 0xFC
CHY, SETFALL, ACT, UP, DOWN = 0xFB, 0xFA, 0xF9, 0xF8, 0xF7

# Straight out of SEQTABLE.S.  A plain number is a frame, a tuple is a frame
# with its chx, and the strings are the byte code above.
# The ids the keys read.  Most are a sequence's name, but not all: the
# crouch a soft landing ends in is part of `softland` and still has to be
# told apart from the landing itself, so the list stands on its own.
IDS = ['stand', 'startrun', 'runcyc', 'turn', 'runstop', 'runturn',
       'stepfall', 'freefall', 'softland', 'crouch', 'standup',
       'climbdown', 'hang', 'climbup', 'hangdrop', 'stoop', 'step']
(ID_STAND, ID_STARTRUN, ID_RUNCYC, ID_TURN, ID_RUNSTOP, ID_RUNTURN,
 ID_STEPFALL, ID_FREEFALL, ID_SOFTLAND, ID_CROUCH, ID_STANDUP,
 ID_CLIMBDOWN, ID_HANG, ID_CLIMBUP, ID_HANGDROP,
 ID_STOOP, ID_STEP) = range(len(IDS))

SEQUENCES = {
    'stand':    [('id', ID_STAND), ('act', 1), (15, 0), ('goto', 'stand')],
    'startrun': [('id', ID_STARTRUN), ('act', 1),
                 (1, 0), (2, 0), (3, 0), (4, 8), (5, 3), (6, 3),
                 ('goto', 'runcyc')],
    'runcyc':   [('id', ID_RUNCYC), ('act', 1), (7, 5), (8, 1), (9, 2), (10, 4),
                 ('label', 'runcyc5'), ('id', ID_RUNCYC),
                 (11, 5), (12, 2), (13, 3), (14, 4), ('goto', 'runcyc')],
    'turn':     [('id', ID_TURN), ('act', 1), ('face',), ('chx', 6),
                 (45, 1), (46, 2), (47, -1), (48, 1),
                 (49, -2), (50, 0), (51, 0), (52, 0), ('goto', 'stand')],
    'runstop':  [('id', ID_RUNSTOP), ('act', 1), (53, 2), (54, 7), (55, 0), (56, 2),
                 (49, -2), (50, 0), (51, 0), (52, 0), ('goto', 'stand')],
    'runturn':  [('id', ID_RUNTURN), ('act', 1), ('chx', 1),
                 (53, 1), (54, 8), (55, 0), (56, 7), (57, 3),
                 (58, 1), (59, 0), (60, 2), (61, -1), (62, 0), (63, 0),
                 (64, -1), (65, -14), ('face',), ('goto', 'runcyc5')],
    # The floor runs out and he tips over the edge.  The chy beside a frame
    # is the drop out of it, exactly as chx is the step; the setfall at the
    # end hands him to gravity with a Y velocity already wound up.
    'stepfall': [('id', ID_STEPFALL), ('act', 3), ('chx', 1), ('chy', 3),
                 (102, 2, 6), (103, -1, 9), (104, 0, 12), (105, -2),
                 ('setfall', 1, 15), ('goto', 'freefall')],
    'freefall': [('id', ID_FREEFALL), ('act', 4), ('label', 'ff'), (106, 0),
                 ('goto', 'ff')],
    # A one storey drop: he takes it on his hands and stays crouched until
    # he is told to get up.
    'softland': [('id', ID_SOFTLAND), ('act', 5), ('chx', 1), (107, 2), (108, 0),
                 ('label', 'crouch'), ('id', ID_CROUCH), ('act', 1), (109, 0),
                 ('goto', 'crouch')],
    'standup':  [('id', ID_STANDUP), ('act', 5), ('chx', 1),
                 (110, 0), (111, 2), (112, 0), (113, 1), (114, 0), (115, 0),
                 (116, -4), (117, 0), (118, 0), (119, 0), ('goto', 'stand')],
    # Lowering himself over the edge.  The chy of 63 and the `down` go
    # together: one block row is 63 scanlines, so he ends up hanging with his
    # feet where they would be if he were standing on the floor below.
    'climbdown': [('id', ID_CLIMBDOWN), ('act', 1),
                  (148, 0), (145, 0), (144, 0), (143, 0), (142, 0), (141, 0),
                  ('chx', -5), ('chy', 63), ('down',), ('act', 3),
                  (140, 0), (138, 0), (136, 0), (91, 0),
                  ('goto', 'hang')],
    'hang':     [('id', ID_HANG), ('act', 6),
                 (92, 0), (93, 0), (93, 0), (92, 0), (92, 0),
                 ('label', 'hangloop'), (91, 0), ('goto', 'hangloop')],
    # act 3 all the way up: POP gates its floor check on a per frame flag we
    # do not carry, and "in the air" says the same thing -- do not look for
    # ground under him while he is halfway over the edge.
    'climbup':  [('id', ID_CLIMBUP), ('act', 3),
                 (135, 0), (136, 0), (137, 0), (138, 0), (139, 0), (140, 0),
                 ('chx', 5), ('chy', -63), ('up',),
                 (141, 0), (142, 0), (143, 0), (144, 0), (145, 0), (146, 0),
                 (147, 0), (148, 0), ('act', 5), (149, 0), ('act', 1),
                 (118, 0), (119, 0), ('chx', 1), ('goto', 'stand')],
    # Down with floor still ahead of him is just a crouch; it ends in the
    # same loop a soft landing does.
    'stoop':    [('id', ID_STOOP), ('act', 1), ('chx', 1),
                 (107, 2), (108, 0), ('goto', 'crouch')],
    'hangdrop': [('id', ID_HANGDROP), ('act', 0),
                 (81, 0), (82, 0), ('act', 5), (83, 0), ('act', 1),
                 (84, 0), (85, 0), ('chx', 3), ('goto', 'stand')],
}
# POP carries fourteen careful steps, one per distance, so that a step
# always finishes exactly where it should -- against a wall, or with his toes
# on the edge.  They differ in one chx: the frames add up to eleven units and
# the odd one makes up the rest.  SEQTABLE.S writes them all out; we do not
# have to.  The swing carries him eleven units forward and the odd chx pulls
# him back, so the middle of a step can hang well over a drop: it says "in the
# air" until his foot is down, which is what POP's per frame floor check flag
# is saying too.
for _n in range(1, 15):
    SEQUENCES['step%d' % _n] = [
        ('id', ID_STEP), ('act', 3),
        (121, 1), (122, 1), (123, 3), (124, 4), (125, 3), (126, -1),
        ('chx', _n - 11), ('act', 1),
        (127, 0), (128, 0), (129, 0), (130, 0), (131, 0), (132, 0),
        ('goto', 'stand')]

ORDER = ['stand', 'startrun', 'runcyc', 'turn', 'runstop', 'runturn',
         'stepfall', 'freefall', 'softland', 'standup',
         'climbdown', 'hang', 'climbup', 'hangdrop', 'stoop']
ORDER += ['step%d' % n for n in range(1, 15)]

# POP anchors a character by his leading edge: facing left that is the left
# edge of the image, facing right it is the leftmost pixel of the RIGHTMOST
# Apple byte (see the note above GETEDGES in CTRLSUBS.S).  That is why the
# turn sequences carry a chx of +-14 next to their about face -- it cancels
# the anchor swapping ends.  Centring the sprite instead makes that chx show
# up as a 28 pixel jump, so the offset from CharX to the sprite's left edge is
# worked out here, per frame and per facing, and stored with the sprite.
#
# CharX lands on the middle of a block: a character on block b has
# charx = 28b + 16 and the block runs 28b+2 .. 28b+29.  The anchor is half the
# standing frame, which puts him squarely on his own block; wider running
# frames then reach out behind him, which is what a leading edge anchor
# should do.
CHAR_ANCHOR = 7

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
    Table of (width, height, xoff left, xoff right, blob offset) and the
    pixels, the latter cut into bank sized pieces.  Only one facing is stored
    -- mirroring at draw time through a bit reversal table costs a lookup per
    byte and saves ten kilobytes.
    """
    frames = popframe.load()
    index, table, banks = {}, bytearray(), [bytearray()]
    for n in frames_used:
        index[n] = len(index)
        img = popframe.image(frames[n])
        apple_bytes = (img.px_width + 6) // 7
        width, height, data = sprite_bytes(img, 0)
        if len(banks[-1]) + len(data) > BANK_SIZE - 2:
            banks.append(bytearray())   # this one will not fit: start the next
        table += bytes([width, height, (-CHAR_ANCHOR) & 0xff,
                        (-CHAR_ANCHOR - (apple_bytes - 1) * 7) & 0xff])
        table += (((len(banks) - 1) << BANK_SHIFT)
                  | len(banks[-1])).to_bytes(2, 'little')
        banks[-1] += data
    return index, bytes(table), [bytes(b) for b in banks]


def build_sequences(index):
    """Assemble the byte code, resolving jumps in a second pass."""
    labels, code, fixups = {}, bytearray(), []
    for name in ORDER:
        labels[name] = len(code)
        for step in SEQUENCES[name]:
            if step[0] == 'label':
                labels[step[1]] = len(code)
            elif step[0] == 'goto':
                code.append(GOTO)
                fixups.append((len(code), step[1]))
                code += b'\0\0'
            elif step[0] == 'face':
                code.append(FACE)
            elif step[0] == 'chx':
                code += bytes([CHX, step[1] & 0xff])
            elif step[0] == 'chy':
                code += bytes([CHY, step[1] & 0xff])
            elif step[0] == 'act':
                code += bytes([ACT, step[1]])
            elif step[0] == 'up':
                code.append(UP)
            elif step[0] == 'down':
                code.append(DOWN)
            elif step[0] == 'setfall':
                code += bytes([SETFALL, step[1] & 0xff, step[2] & 0xff])
            elif step[0] == 'id':
                code += bytes([SEQID, step[1]])
            else:
                code += bytes([index[step[0]], step[1] & 0xff])
                if len(step) > 2:       # a drop belongs to the step out of
                    code += bytes([CHY, step[2] & 0xff])    # the frame too
    return labels, code, fixups


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
    px = renderroom.seam_pass(px, level, ROOM[1])
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

    # The art bank: the room first, then the foreground mask behind it, and a
    # signature the program checks -- a bank that did not load leaves a black
    # screen and nothing to go on, so it is worth two bytes to say so.
    art = screen
    open(os.path.join(binout, 'bank_art.bin'), 'wb').write(art + SIG_ART)

    blockof = bytearray(256)            # screen pixel -> block column
    angle_px = 2 * popframe.ANGLE       # logic units are half pixels
    for x in range(256):
        b = (x + CAMERA - angle_px) // BLOCK_PX
        blockof[x] = b if 0 <= b <= 9 else 0xFF
    open(os.path.join(binout, 'blockof.bin'), 'wb').write(bytes(blockof))

    # GETDIST in CTRLSUBS.S works in OFFSET, the position within the block in
    # POP's 140-wide space -- 0 to 13, two screen pixels to the unit.  Every
    # judgement about edges is made in those units, so the table comes along.
    distof = bytearray(256)
    for x in range(256):
        distof[x] = ((x + CAMERA - angle_px) % BLOCK_PX) // 2
    open(os.path.join(binout, 'distof.bin'), 'wb').write(bytes(distof))

    used = []
    for name in ORDER:
        for step in SEQUENCES[name]:
            if isinstance(step[0], int) and step[0] not in used:
                used.append(step[0])
    index, table, blobs = build_sprites(used)
    # The index stays in fixed memory -- it is walked every frame -- and only
    # the pixels go in banks.  The first rides at 0xC000 in the tape image and
    # so needs no copying, only a signature to say which bank it landed in.
    open(os.path.join(binout, 'sprtab.bin'), 'wb').write(table)
    open(os.path.join(binout, 'bank_spr.bin'), 'wb').write(blobs[0] + SIG_SPR)
    rest = b''.join(blobs[1:])
    open(os.path.join(binout, 'bank_spr2.bin'), 'wb').write(rest)
    if len(blobs) > 2:
        raise SystemExit('спрайты переросли два банка: %d' % sum(map(len, blobs)))

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

    labels, code, fixups = build_sequences(index)
    code = bytearray(code)
    open(os.path.join(binout, 'seqs.bin'), 'wb').write(bytes(code))

    with open(os.path.join(out, 'assets.inc'), 'w') as f:
        f.write('; generated by mkassets.py -- do not edit\n')
        f.write('sprblob     equ %d' % PAGE_WINDOW + chr(10))
        f.write('room        equ %d' % PAGE_WINDOW + chr(10))
        f.write('foremask    equ %d' % (PAGE_WINDOW + len(screen) + 2) + chr(10))
        f.write('SIG_ART_AT  equ %d' % (PAGE_WINDOW + len(art)) + chr(10))
        f.write('SIG_ART     equ %d' % int.from_bytes(SIG_ART, 'little') + chr(10))
        f.write('SIG_SPR     equ %d' % int.from_bytes(SIG_SPR, 'little') + chr(10))
        f.write('SEQ_GOTO    equ %d\n' % GOTO)
        f.write('SEQ_FACE    equ %d\n' % FACE)
        f.write('SEQ_CHX     equ %d\n' % CHX)
        f.write('SEQ_ID      equ %d' % SEQID + chr(10))
        f.write('SEQ_CHY     equ %d' % CHY + chr(10))
        f.write('SEQ_SETFALL equ %d' % SETFALL + chr(10))
        f.write('SEQ_ACT     equ %d' % ACT + chr(10))
        f.write('SEQ_UP      equ %d' % UP + chr(10))
        f.write('SEQ_DOWN    equ %d' % DOWN + chr(10))
        f.write('TILE_FLOOR  equ %d' % TILE_FLOOR + chr(10))
        f.write('TILE_SOLID  equ %d' % TILE_SOLID + chr(10))

        for n, nm in enumerate(IDS):
            f.write('ID_%-9s equ %d' % (nm.upper(), n) + chr(10))
        for name in ORDER:
            f.write('SQ_%-8s equ %d\n' % (name.upper(), labels[name]))
        f.write('START_X     equ %d\n'
                % (popframe.screen_x(popframe.char_x(START_COL)) - CAMERA))
        f.write('START_Y     equ %d\n' % popframe.char_y(START_ROW))
        f.write('START_ROW   equ %d\n' % START_ROW)

    with open(os.path.join(out, 'seqfix.inc'), 'w') as f:
        f.write('; jump targets are patched in once the sequences are placed\n')
        for at, name in fixups:
            f.write('                ld      hl, seqs + %-3d  ; %s' % (labels[name], name) + chr(10))
            f.write('                ld      (seqs + %d), hl\n' % at)

    print('bank_art    %d байт (комната)' % len(art))
    for i, b in enumerate(blobs):
        print('bank_spr%-3d %d байт  (свободно в банке %d)'
              % (i + 1, len(b), BANK_SIZE - len(b) - (2 if not i else 0)))
    print('спрайтов    %d кадров, %d байт' % (len(used), sum(map(len, blobs))))
    print('sprtab.bin  %d байт' % len(table))
    print('seqs.bin    %d bytes, %d sequences' % (len(code), len(ORDER)))
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
