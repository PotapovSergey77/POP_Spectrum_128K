"""
The opening scene in the princess's room, for the Spectrum.

poprincess.py takes the room off the Apple's disk and princess.py runs the
scene as PlayCut0 does; this makes of them what intro.asm plays.

    The size.  The Apple's room is 280 pixels wide and the Spectrum's
    screen 256.  The characters keep the Apple's pixels one for one, as the
    prince does in the game, so the room is not squeezed either: it loses
    the 24 pixels at its right, a piece of the arcade the vizier walks in
    through.  The window, the stars, the bed, both torches, the hourglass
    and the post all stay where they were; he comes into sight a few frames
    later than he did, and the scene is not changed at all.

    The colours.  Apple hi-res makes its colours of the dots themselves, so
    the dots are kept as they are, each cell given the ink of the dots in
    it: blue for the evening behind the arches and the window, the bed's
    own yellow and blue.  Where the princess and the vizier can be, and on
    the whole of the floor, the ink is white -- a character takes the ink
    of the cells it is drawn in, and theirs is white on the Apple.

    The characters.  Drawn as the Apple draws them, masked: MASKTAB clears a
    pixel either side of every lit one before the picture is ORed in, so a
    dark edge a pixel wide keeps them apart from the room.  The Spectrum
    works out that mask as it draws; one facing is kept, the other made
    through the bit reversal table.

    The scene.  princess.py runs ANIMCHAR over SEQTABLE.S exactly as the
    Apple would, and nothing in the scene depends on anything but the
    clock -- so what it gives, frame by frame, is kept as it is: which
    picture each of them shows and where.  The torches, the stars and the
    sand, which go by RND, are run on the Spectrum.

Out, through build(): the bank blob (the room packed, and the pictures and
the script packed to be unpacked where they lie), the fixed pictures for
fixed memory, and the equates intro.asm needs.

    princessscr.py [dir]   the room, and frames of the scene, as PNGs
"""
import os
import sys

import pngwrite
import poprincess
import princess
import titlescr
import zxscreen

BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)

WIDTH = 256                 # of the Apple's 280, from the left
FLOOR_Y = princess.FLOOR_Y

# The band of lines anything moves in: the vizier's raised arms at the top,
# the post's foot at the bottom.  intro.asm composes it in fixed memory and
# copies it to the screen whole.
BAND_TOP, BAND_BOT = 94, 152
BAND_ROWS = BAND_BOT - BAND_TOP + 1

# ---------------------------------------------------------------- the room

# Where the characters can be, in cells: rows 11 to 18, columns 13 on.
ZONE_ROWS, ZONE_COL = (11, 18), 13
FLOOR_ROW = 17              # the floor, down to the bottom
RAIL_ROWS, RAIL_COL = (14, 15), 5   # the balustrade, from the first pillar

# A lit dot is white beside another lit dot; alone, it is the colour its
# column and the byte's palette bit make of it.
DOT_WHITE, DOT_VIOLET, DOT_GREEN, DOT_BLUE, DOT_ORANGE = 1, 2, 3, 4, 5
INK = {DOT_WHITE: WHITE, DOT_VIOLET: MAGENTA, DOT_GREEN: GREEN,
       DOT_BLUE: BLUE, DOT_ORANGE: YELLOW}
BRIGHT = 1


def apple_room():
    page = poprincess.sng_expand(poprincess.memory())
    return poprincess.hires_bits(page)


def dot_class(dots, pal, x, y):
    d = dots[y]
    if not d[x]:
        return 0
    if (x > 0 and d[x - 1]) or (x < 279 and d[x + 1]):
        return DOT_WHITE
    p = pal[y][x // 7]
    if x % 2 == 0:
        return DOT_BLUE if p else DOT_VIOLET
    return DOT_ORANGE if p else DOT_GREEN


def room_attrs(dots, pal):
    attrs = bytearray(768)
    for cy in range(24):
        for cx in range(32):
            zone = (ZONE_ROWS[0] <= cy <= ZONE_ROWS[1] and cx >= ZONE_COL)
            count = [0] * 6
            for y in range(cy * 8, cy * 8 + 8):
                for x in range(cx * 8, cx * 8 + 8):
                    count[dot_class(dots, pal, x, y)] += 1
            lit = sum(count[1:])
            k = max(range(1, 6), key=lambda i: count[i])
            ink = INK[k] if lit else WHITE
            # the floor's sparse orange: white, as the rest of the floor
            if cy >= FLOOR_ROW and k == DOT_ORANGE and lit < 20:
                ink = WHITE
            # the balustrade runs through the zone, and is one colour
            if zone or (cy in RAIL_ROWS and cx >= RAIL_COL):
                ink = WHITE
            attrs[cy * 32 + cx] = BRIGHT << 6 | BLACK << 3 | ink
    return bytes(attrs)


# The torches, moved.  A flame is coloured as the game's are, but a cell has
# one ink: where the Apple has them, each flame shares its cells with the
# thin column beside it, which would burn as well.  So each torch -- its
# holder and its flame -- is moved along the balustrade into cells of its
# own: the left one two pixels left, the right one three pixels right.
# The balustrade it leaves is made again from the one six pixels along,
# which repeats every six; the holder is the same shape on both.
HOLDER_TOP = 114
HOLDER = ['#####',
          '.#.#.',
          '.###.',
          '.###.',
          '.###.',
          '.###.',
          '.####',
          '.###.',
          '.###.',
          '.###.',
          '.###.']
# (holder's left on the Apple, how far it moves, where the balustrade that
# fills in behind it is taken from)
TORCH_MOVE = [(93, -2, -6), (183, +3, +6)]


def move_torches(dots):
    src = [row[:] for row in dots]
    out = [row[:] for row in dots]
    for x0, dx, far in TORCH_MOVE:
        w = len(HOLDER[0])
        xs = range(min(x0, x0 + dx), max(x0, x0 + dx) + w)
        for j in range(len(HOLDER)):
            y = HOLDER_TOP + j
            for x in xs:
                out[y][x] = src[y][x + far]
            for i, c in enumerate(HOLDER[j]):
                assert c != '#' or src[y][x0 + i], (x0, y)
                if c == '#':
                    out[y][x0 + dx + i] = 1
    return out


# The flames are red, the game's bright red -- INK_FLAME_MID of mkassets.py
# -- in the two cells that hold nothing but the flame.  Its last two lines
# are in the balustrade's cells and stay white.
INK_FLAME_TIP = INK_FLAME_BODY = 0x42


def flame_cells(dots):
    """{cell: ink} for the flames, and per torch the cells it colours."""
    cells, per = {}, []
    for x, y in TORCHES:
        mine = set()
        for n in range(1, 10):
            im = ch6(n)
            h = im.height
            for j, line in enumerate(im.pixels()):
                for i, v in enumerate(line):
                    if v:
                        mine.add(((x + i) >> 3, (y - h + 1 + j) >> 3))
        own = sorted(c for c in mine
                     if not any(dots[cy][cx]
                                for cy in range(c[1] * 8, c[1] * 8 + 8)
                                for cx in range(c[0] * 8, c[0] * 8 + 8)))
        assert len(own) == 2 and own[0][0] == own[1][0], own
        cells[own[0]] = INK_FLAME_TIP
        cells[own[1]] = INK_FLAME_BODY
        per.append(own)
    return cells, per


def room_dots():
    dots, pal = apple_room()
    return move_torches(dots), pal


def room():
    """The room as a SCREEN$."""
    dots, pal = room_dots()
    rows = [dots[y][:WIDTH] for y in range(192)]
    attrs = bytearray(room_attrs(dots, pal))
    for (cx, cy), ink in flame_cells(dots)[0].items():
        attrs[cy * 32 + cx] = ink
    return zxscreen.build(rows, bytes(attrs))


# ---------------------------------------------------------------- pictures

def pack_rows(rows):
    """Rows of 0/1 into bytes, bit 7 leftmost: (width in bytes, data)."""
    w = (max(len(r) for r in rows) + 7) // 8
    out = bytearray()
    for r in rows:
        for b in range(w):
            v = 0
            for bit in range(8):
                x = b * 8 + bit
                if x < len(r) and r[x]:
                    v |= 0x80 >> bit
            out.append(v)
    return w, bytes(out)


def trimmed(img):
    """A character's picture cut down to its lit bytes: (byte column and
    row the box starts at, width in bytes, height, data)."""
    rows = [list(line) for line in img.pixels()]
    w, data = pack_rows(rows)
    h = len(rows)
    by = [data[r * w:(r + 1) * w] for r in range(h)]
    lit = [r for r in range(h) if any(by[r])]
    cols = [c for c in range(w) if any(row[c] for row in by)]
    c0, c1, r0, r1 = cols[0], cols[-1], lit[0], lit[-1]
    out = b''.join(row[c0:c1 + 1] for row in by[r0:r1 + 1])
    return c0, r0, c1 - c0 + 1, r1 - r0 + 1, out


def aligned(rows, x):
    """A picture placed at pixel x, the bytes it covers: (column, width,
    data, and the bytes of what its box covers, for an opaque one)."""
    sh = x & 7
    shifted = [[0] * sh + list(r) for r in rows]
    w, data = pack_rows(shifted)
    ext = [[0] * sh + [1] * len(rows[0])]
    _, extb = pack_rows([ext[0] + [0] * (w * 8 - len(ext[0]))])
    return x >> 3, w, data, extb


# PMASK in GAMEBG.S: for the princess's frames 1 and 18 (Pslump) the face
# and hair are masked with image $22 of chtable6, ANDed in at her XCO and
# FCharY - 33.  It clears what its unlit pixels are over.
PMASK = {1: -33, 18: -33}
PMASK_IMAGE = 0x22

# The rest of what FrameAdv draws, all at places GAMEBG.S fixes: XCO * 7 +
# OFFSET, and YCO the bottom line.
TORCHES = [(13 * 7 + 0 + TORCH_MOVE[0][1], 113),      # ptorchx/off/y, and
           (25 * 7 + 6 + TORCH_MOVE[1][1], 113)]      # moved as above
TORCH_FLAMES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 3, 5, 7, 1, 4, 9, 2, 8, 6]
GLASS_X, GLASS_Y = 19 * 7, 151
GLASS_IMAGES = [0x15, 0x0d]         # glassimg: states 0 and 1, all cut 0 uses
FLOW_X, FLOW_Y = 20 * 7, 149
FLOW_IMAGES = [0x16, 0x17, 0x18]
POST_X, POST_Y, POST_IMAGE = 31 * 7, 152, 0x0c
STAR_X, STAR_Y, STAR_IMAGE = 2 * 7, [0x62, 0x65, 0x6d, 0x72], \
    [0x2a, 0x2b, 0x2b, 0x2a]


def ch6(n):
    princess.picture(1)
    return princess.T6.get(n)


def band_row(y):
    assert BAND_TOP <= y <= BAND_BOT, y
    return y - BAND_TOP


# The band goes to the screen from this column on: everything that moves or
# changes is right of it but the stars, which TWINKLE puts on the screens
# themselves.
COL0 = 11

# ---------------------------------------------------------------- the scene

MIRROR = 0x80
NONE = 0xFF


def scene():
    """(sprites, frames): the pictures in the order their ids give, each
    (posn, c0, r0, w, h, data, pmask); and a frame's record per frame."""
    frames = princess.cut0()
    ids, sprites = {}, []
    out = []
    for st in frames:
        rec = []
        for who in ('vizier', 'princess'):
            posn, x, y, face = st[who]
            left, bottom, img, mir = princess.place(posn, x, y, face)
            assert bottom == FLOOR_Y, (who, bottom)
            if posn not in ids:
                ids[posn] = len(sprites)
                sprites.append((posn,) + trimmed(img) + (img,))
            n = ids[posn]
            _, c0, r0, w, h, data, _ = sprites[n]
            if mir:
                bx = left + img.px_width - 8 * c0 - 8 * w
            else:
                bx = left + 8 * c0
            assert bx >= 0, (who, posn, bx)
            if bx >= WIDTH:
                rec.append((NONE, 0))
                continue
            rec.append(((n | MIRROR) if mir else n, bx))
        out.append((st, rec))
    return sprites, out


def scene_boxes(sprites, frames):
    for st, rec in frames:
        for n, x in rec:
            if n != NONE:
                yield n, (x, 0)


def sprite_top(img, r0):
    return FLOOR_Y - img.height + 1 + r0


def build_blobs():
    """(bank blob pieces, fixed blob, equates)."""
    sprites, frames = scene()
    eq = {}

    # the characters' pictures and their table: per id the address of its
    # rows, width, height, top band row, and the pmask's place or NONE
    table, pics = bytearray(), bytearray()
    for posn, c0, r0, w, h, data, img in sprites:
        top = band_row(sprite_top(img, r0))
        band_row(sprite_top(img, r0) + h - 1)
        pm = NONE
        if posn in PMASK:
            # at the picture's left edge, which is 8 * c0 left of the box
            assert c0 == 0
            pm = band_row(FLOOR_Y + PMASK[posn])
        table += bytes([0, 0, w, h, top, pm])
        pics += data
    # the pmask: its unlit pixels, the ones it clears, as a picture
    img = ch6(PMASK_IMAGE)
    row = [1 - v for v in next(img.pixels())]
    pmw, pmdata = pack_rows([row])

    # The fixed pictures, laid at their own places once and for all: each
    # the bytes it covers from its column, and for the opaque ones the box.
    fixed = bytearray()
    at = {}

    def put(name, b):
        at[name] = len(fixed)
        fixed.extend(b)

    for t, (x, y) in enumerate(TORCHES):
        imgs = [ch6(n) for n in range(1, 10)]
        col, w, _, ext = aligned([list(l) for l in imgs[0].pixels()], x)
        h = imgs[0].height
        eq['CUT_FL%d_AT' % t] = band_row(y - h + 1) * 32 + col
        eq['CUT_FL_W'], eq['CUT_FL_H'] = w, h
        put('CUT_FL%d_EXT' % t, ext)
        data = bytearray()
        for im in imgs:
            c, ww, d, _ = aligned([list(l) for l in im.pixels()], x)
            assert (c, ww) == (col, w) and im.height == h
            data += d
        put('CUT_FL%d' % t, data)
    eq['CUT_FLTAB'] = None
    put('CUT_FLTAB', bytes(n - 1 for n in TORCH_FLAMES))

    for s, n in enumerate(GLASS_IMAGES):
        im = ch6(n)
        col, w, d, ext = aligned([list(l) for l in im.pixels()], GLASS_X)
        eq['CUT_GL_AT'] = band_row(GLASS_Y - im.height + 1) * 32 + col
        eq['CUT_GL_W'], eq['CUT_GL_H'] = w, im.height
        put('CUT_GL_EXT', ext) if s == 0 else None
        put('CUT_GL%d' % s, d)

    data = bytearray()
    for n in FLOW_IMAGES:
        im = ch6(n)
        col, w, d, ext = aligned([list(l) for l in im.pixels()], FLOW_X)
        eq['CUT_FW_AT'] = band_row(FLOW_Y - im.height + 1) * 32 + col
        eq['CUT_FW_W'], eq['CUT_FW_H'] = w, im.height
        data += d
    put('CUT_FW_EXT', ext)
    put('CUT_FW', data)

    im = ch6(POST_IMAGE)
    col, w, d, _ = aligned([list(l) for l in im.pixels()], POST_X)
    eq['CUT_PO_AT'] = band_row(POST_Y - im.height + 1) * 32 + col
    eq['CUT_PO_W'], eq['CUT_PO_H'] = w, im.height
    put('CUT_PO', d)

    stars = bytearray()
    for y, n in zip(STAR_Y, STAR_IMAGE):
        im = ch6(n)
        (px,) = [i for i, v in enumerate(next(im.pixels())) if v]
        x = STAR_X + px
        # TWINKLE puts a star straight on both screens, outside the band's
        # columns: where on a screen it is
        assert x >> 3 < COL0
        stars += zxscreen.bitmap_offset(x >> 3, y).to_bytes(2, 'little')
        stars.append(0x80 >> (x & 7))
    put('CUT_STARS', stars)
    put('CUT_PMASK', bytes([pmw]) + pmdata)

    # The right torch's flame is where the vizier walks, and a cell has one
    # ink: while the box he is drawn in covers one of its cells, that cell
    # is white, as he is.  Nobody comes near the left one.
    _, (left_cells, right_cells) = flame_cells(room_dots()[0])
    tip, body = right_cells
    eq['CUT_T1_TIP'], eq['CUT_T1_BODY'] = (tip[1] * 32 + tip[0],
                                           body[1] * 32 + body[0])
    eq['CUT_INK_TIP'], eq['CUT_INK_BODY'] = INK_FLAME_TIP, INK_FLAME_BODY
    eq['CUT_INK_WHITE'] = BRIGHT << 6 | WHITE

    def covered(rec, cell):
        cx, cy = cell
        for n, x in rec:
            if n == NONE:
                continue
            posn, c0, r0, w, h, data, img = sprites[n & 0x7F]
            col = x >> 3
            last = col + min(w + 1, 32 - col) - 1
            top = sprite_top(img, r0)
            if col <= cx <= last and top <= cy * 8 + 7 and top + h - 1 >= cy * 8:
                return True
        return False

    # The script: a record a frame -- what happens, and each of them.
    script = bytearray()
    last_glass, sand = None, False
    for st, rec in frames:
        f = 0
        if st['speed'] == 12:
            f |= 1
        if st['flash']:
            f |= 2
        if st['glass'] != last_glass:
            f |= 4 | (8 if st['glass'] else 0)
            last_glass = st['glass']
        if st['sand'] and not sand:
            f |= 16
            sand = True
        assert not any(covered(rec, c) for c in left_cells)
        if covered(rec, tip):
            f |= 32
        if covered(rec, body):
            f |= 64
        if st.get('tune'):
            f |= 128
        script.append(f)
        for n, x in rec:
            script += bytes([n, x])
    eq['CUT_FRAMES'] = len(frames)
    eq['CUT_COL0'] = COL0
    for n, (x, _) in scene_boxes(sprites, frames):
        assert x >> 3 >= COL0, x
    for name in ('CUT_FL0_AT', 'CUT_FL1_AT', 'CUT_GL_AT', 'CUT_FW_AT',
                 'CUT_PO_AT'):
        assert eq[name] % 32 >= COL0, name
    del eq['CUT_FLTAB']
    return table, pics, bytes(script), fixed, at, eq, len(sprites)


# ---------------------------------------------------------------- the blob

def unpack(data, n):
    """titlescr's tokens, unpacked from nothing into n bytes."""
    out = bytearray(n)
    p = d = 0
    while data[p] != 0xFF:
        t = data[p]
        if t < 0x80:
            out[d:d + t + 1] = data[p + 1:p + t + 2]
            p += t + 2
            d += t + 1
        else:
            assert t < 0xC0
            src = d - (data[p + 1] | data[p + 2] << 8)
            for _ in range((t & 0x3F) + 3):
                out[d] = out[src]
                d += 1
                src += 1
            p += 3
    return bytes(out)


def in_place(data, at):
    """Whether the tokens at offset `at` can be unpacked to offset 0 of
    the same memory: after every token, what is written stays below what
    is still to be read."""
    p = d = 0
    while data[p] != 0xFF:
        t = data[p]
        if t < 0x80:
            p += t + 2
            d += t + 1
        else:
            p += 3
            d += (t & 0x3F) + 3
        if d > at + p:
            return False
    return True


def build(bank_base, bank_room):
    """The bank blob, to go at bank_base, with bank_room bytes free there;
    the fixed blob; and the lines of the include file."""
    table, pics, script, fixed, at, eq, count = build_blobs()
    scr = room()
    room_packed = titlescr.pack(scr)
    assert titlescr.unpack(room_packed) == scr
    # The pictures are unpacked where they lie: packed at the top of the
    # room, unpacked from its bottom up -- the room's own packing, which
    # the pictures overwrite, has been used by then.
    tab_at = 0
    pics_at = len(table)
    for i in range(count):
        a = bank_base + pics_at + sum(table[j * 6 + 2] * table[j * 6 + 3]
                                      for j in range(i))
        table[i * 6:i * 6 + 2] = a.to_bytes(2, 'little')
    plain = bytes(table) + bytes(pics) + script
    script_at = len(table) + len(pics)
    packed = titlescr.pack(plain)
    assert unpack(packed, len(plain)) == plain
    pk_at = bank_room - len(packed)
    assert len(room_packed) <= pk_at, 'the room and the pictures do not fit'
    assert len(plain) <= bank_room
    # unpacked in place: the writing must never catch up with the reading
    assert in_place(packed, pk_at), 'unpacking would overrun'
    blob = bytearray(bank_room)
    blob[0:len(room_packed)] = room_packed
    blob[pk_at:] = packed
    blob = bytes(blob[:pk_at + len(packed)])
    inc = ['CUT_ROOM    equ %d' % bank_base,
           'CUT_PACKED  equ %d' % (bank_base + pk_at),
           'CUT_SPRTAB  equ %d' % (bank_base + tab_at),
           'CUT_SCRIPT  equ %d' % (bank_base + script_at),
           'CUT_END     equ %d' % (bank_base + len(plain)),
           'CUT_BAND_TOP equ %d' % BAND_TOP,
           'CUT_BAND_ROWS equ %d' % BAND_ROWS]
    for k, v in eq.items():
        inc.append('%-11s equ %d' % (k, v))
    for k, v in at.items():
        inc.append('%-11s equ cutfixed + %d' % (k, v))
    stats = (len(room_packed), len(packed), len(plain), len(fixed))
    return blob, bytes(fixed), inc, stats


# ---------------------------------------------------------------- to look at

def preview_frames(path, every=12):
    """Frames of the scene over the Spectrum's room, the way intro.asm
    draws them, a strip of them."""
    scr = bytearray(room())
    sprites, frames = scene()
    strips = []
    for st, rec in frames[::every]:
        s = bytearray(scr)
        for n, x in rec:
            if n == NONE:
                continue
            posn, c0, r0, w, h, data, img = sprites[n & 0x7F]
            top = sprite_top(img, r0)
            for j in range(h):
                row = data[j * w:(j + 1) * w]
                bits = [(row[k >> 3] >> (7 - (k & 7))) & 1 for k in range(8 * w)]
                if n & MIRROR:
                    bits = bits[::-1]
                dil = [any(bits[k + d] for d in (-1, 0, 1) if 0 <= k + d < len(bits))
                       for k in range(len(bits))]
                for k in range(-1, len(bits) + 1):
                    xx = x + k
                    if not 0 <= xx < 256:
                        continue
                    m = dil[k] if 0 <= k < len(bits) else \
                        (bits[0] if k == -1 else bits[-1])
                    v = bits[k] if 0 <= k < len(bits) else 0
                    if m or v:
                        a = zxscreen.bitmap_offset(xx >> 3, top + j)
                        bit = 0x80 >> (xx & 7)
                        s[a] = (s[a] | bit) if v else (s[a] & ~bit)
        strips.append(bytes(s))
    rows = []
    for s in strips:
        for y in range(80, 192):
            line = bytearray()
            for x in range(256):
                a = s[6144 + (y >> 3) * 32 + (x >> 3)]
                on = s[zxscreen.bitmap_offset(x >> 3, y)] & (0x80 >> (x & 7))
                line += bytes(titlescr.zx_rgb(a & 7 if on else (a >> 3) & 7,
                                              (a >> 6) & 1))
            rows.append(bytes(line))
    pngwrite.write_rgb(path, 256, len(rows), rows)


def main(argv):
    out = argv[1] if len(argv) > 1 else '.'
    scr = room()
    titlescr.preview(scr, os.path.join(out, 'zx_proom.png'), zoom=3)
    preview_frames(os.path.join(out, 'zx_cut0.png'))
    blob, fixed, inc, stats = build(0xC9A9, 11280)
    print('комната %d, картинки %d (%d распакованные), в памяти %d'
          % stats)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
