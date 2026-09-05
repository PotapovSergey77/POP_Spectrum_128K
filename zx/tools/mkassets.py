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
CHY, SETFALL = 0xFB, 0xFA

# Straight out of SEQTABLE.S.  A plain number is a frame, a tuple is a frame
# with its chx, and the strings are the byte code above.
# The ids the keys read.  Most are a sequence's name, but not all: the
# crouch a soft landing ends in is part of `softland` and still has to be
# told apart from the landing itself, so the list stands on its own.
IDS = ['stand', 'startrun', 'runcyc', 'turn', 'runstop', 'runturn',
       'stepfall', 'freefall', 'softland', 'crouch', 'standup']
(ID_STAND, ID_STARTRUN, ID_RUNCYC, ID_TURN, ID_RUNSTOP, ID_RUNTURN,
 ID_STEPFALL, ID_FREEFALL, ID_SOFTLAND, ID_CROUCH,
 ID_STANDUP) = range(len(IDS))

SEQUENCES = {
    'stand':    [('id', ID_STAND), (15, 0), ('goto', 'stand')],
    'startrun': [('id', ID_STARTRUN),
                 (1, 0), (2, 0), (3, 0), (4, 8), (5, 3), (6, 3),
                 ('goto', 'runcyc')],
    'runcyc':   [('id', ID_RUNCYC), (7, 5), (8, 1), (9, 2), (10, 4),
                 ('label', 'runcyc5'), ('id', ID_RUNCYC),
                 (11, 5), (12, 2), (13, 3), (14, 4), ('goto', 'runcyc')],
    'turn':     [('id', ID_TURN), ('face',), ('chx', 6),
                 (45, 1), (46, 2), (47, -1), (48, 1),
                 (49, -2), (50, 0), (51, 0), (52, 0), ('goto', 'stand')],
    'runstop':  [('id', ID_RUNSTOP), (53, 2), (54, 7), (55, 0), (56, 2),
                 (49, -2), (50, 0), (51, 0), (52, 0), ('goto', 'stand')],
    'runturn':  [('id', ID_RUNTURN), ('chx', 1),
                 (53, 1), (54, 8), (55, 0), (56, 7), (57, 3),
                 (58, 1), (59, 0), (60, 2), (61, -1), (62, 0), (63, 0),
                 (64, -1), (65, -14), ('face',), ('goto', 'runcyc5')],
    # The floor runs out and he tips over the edge.  The chy beside a frame
    # is the drop out of it, exactly as chx is the step; the setfall at the
    # end hands him to gravity with a Y velocity already wound up.
    'stepfall': [('id', ID_STEPFALL), ('chx', 1), ('chy', 3),
                 (102, 2, 6), (103, -1, 9), (104, 0, 12), (105, -2),
                 ('setfall', 1, 15), ('goto', 'freefall')],
    'freefall': [('id', ID_FREEFALL), ('label', 'ff'), (106, 0),
                 ('goto', 'ff')],
    # A one storey drop: he takes it on his hands and stays crouched until
    # he is told to get up.
    'softland': [('id', ID_SOFTLAND), ('chx', 1), (107, 2), (108, 0),
                 ('label', 'crouch'), ('id', ID_CROUCH), (109, 0),
                 ('goto', 'crouch')],
    'standup':  [('id', ID_STANDUP), ('chx', 1),
                 (110, 0), (111, 2), (112, 0), (113, 1), (114, 0), (115, 0),
                 (116, -4), (117, 0), (118, 0), (119, 0), ('goto', 'stand')],
}
ORDER = ['stand', 'startrun', 'runcyc', 'turn', 'runstop', 'runturn',
         'stepfall', 'freefall', 'softland', 'standup']

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
    pixels.  Only one facing is stored -- mirroring at draw time through a
    bit reversal table costs a lookup per byte and saves ten kilobytes.
    """
    frames = popframe.load()
    index, table, blob = {}, bytearray(), bytearray()
    for n in frames_used:
        index[n] = len(index)
        img = popframe.image(frames[n])
        apple_bytes = (img.px_width + 6) // 7
        width, height, data = sprite_bytes(img, 0)
        table += bytes([width, height, (-CHAR_ANCHOR) & 0xff,
                        (-CHAR_ANCHOR - (apple_bytes - 1) * 7) & 0xff])
        table += len(blob).to_bytes(2, 'little')
        blob += data
    return index, bytes(table), bytes(blob)


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
    # the room never changes -- so the area they cover is worked out here as a
    # bitmask, one bit a pixel, and simply put back from the room after he is
    # drawn.  The whole rectangle is masked, not just the lit pixels, or he
    # would show through the gaps in the dither.
    fore = bytearray(6144)
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
            for y in range(ybot - img.height + 1, ybot + 1):
                if not 0 <= y < 192:
                    continue
                for x in range(x0, x0 + img.width * 7):
                    if not 0 <= x < 256:
                        continue
                    off = zxscreen.bitmap_offset(x >> 3, y)
                    fore[off] |= 0x80 >> (x & 7)
    # The art bank: the room first, then the foreground mask behind it, and a
    # signature the program checks -- a bank that did not load leaves a black
    # screen and nothing to go on, so it is worth two bytes to say so.
    art = screen + bytes(fore)
    open(os.path.join(binout, 'bank_art.bin'), 'wb').write(art + SIG_ART)

    blockof = bytearray(256)            # screen pixel -> block column
    angle_px = 2 * popframe.ANGLE       # logic units are half pixels
    for x in range(256):
        b = (x + CAMERA - angle_px) // BLOCK_PX
        blockof[x] = b if 0 <= b <= 9 else 0xFF
    open(os.path.join(binout, 'blockof.bin'), 'wb').write(bytes(blockof))

    used = []
    for name in ORDER:
        for step in SEQUENCES[name]:
            if isinstance(step[0], int) and step[0] not in used:
                used.append(step[0])
    index, table, blob = build_sprites(used)
    # The index stays in fixed memory -- it is walked every frame -- and only
    # the pixels go in a bank.
    open(os.path.join(binout, 'sprtab.bin'), 'wb').write(table)
    open(os.path.join(binout, 'bank_spr.bin'), 'wb').write(blob + SIG_SPR)

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
        f.write('foremask    equ %d' % (PAGE_WINDOW + len(screen)) + chr(10))
        f.write('SIG_ART_AT  equ %d' % (PAGE_WINDOW + len(art)) + chr(10))
        f.write('SIG_ART     equ %d' % int.from_bytes(SIG_ART, 'little') + chr(10))
        f.write('SIG_SPR     equ %d' % int.from_bytes(SIG_SPR, 'little') + chr(10))
        f.write('SEQ_GOTO    equ %d\n' % GOTO)
        f.write('SEQ_FACE    equ %d\n' % FACE)
        f.write('SEQ_CHX     equ %d\n' % CHX)
        f.write('SEQ_ID      equ %d' % SEQID + chr(10))
        f.write('SEQ_CHY     equ %d' % CHY + chr(10))
        f.write('SEQ_SETFALL equ %d' % SETFALL + chr(10))
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

    print('bank_art    %d байт (комната %d + маска %d)'
          % (len(screen) + len(fore), len(screen), len(fore)))
    print('bank_spr    %d байт, %d кадров  (свободно в банке %d)'
          % (len(blob), len(used), 0x4000 - len(blob) - 2))
    print('sprtab.bin  %d байт' % len(table))
    print('seqs.bin    %d bytes, %d sequences' % (len(code), len(ORDER)))
    # FloorY, indexed by block row + 1: the plane his feet rest on.
    floory = bytes(v & 0xff for v in popframe.FLOOR_Y)
    open(os.path.join(binout, 'floory.bin'), 'wb').write(floory)

    print('tiles.bin   %s' % ' '.join('%d' % f for f in flags))
    print('floory.bin  %s' % ' '.join('%d' % f for f in floory))
    print('foremask    %d байт, закрыто %d пикселей'
          % (len(fore), sum(bin(b).count('1') for b in fore)))
    print('START_X=%d START_Y=%d'
          % (popframe.screen_x(popframe.char_x(START_COL)) - CAMERA,
             popframe.char_y(START_ROW)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
