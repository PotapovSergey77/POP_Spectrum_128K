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
            'piecec', 'pieced', 'fronti', 'fronty', 'frontx', 'bstripe')

# And the shorter ones, each padded to its own fixed length.
FIXED = (('blockb', 2), ('blockc', 2), ('blockd', 2), ('blockfr', 2),
         ('spaceb', 4), ('spaceby', 4), ('floorb', 4), ('floorby', 4),
         ('panelb', 3), ('panelc', 3),
         ('loosea', 11), ('looseby', 11), ('loosed', 11),
         ('spikea', 10), ('spikeb', 10),
         ('slicertop', 5), ('slicerbot', 5), ('slicerfrnt', 5),
         ('gate8b', 8), ('gate8c', 8))

# Single values, in one block, in this order.
SINGLES = ('looseb', 'panelb0', 'panelc0', 'archpanel', 'CUmask', 'CUpiece',
           'CUpost', 'gatebotSTA', 'gatebotORA', 'gateB1', 'gatecmask',
           'stairs', 'door', 'doormask', 'toprepair', 'archtop3sp',
           'specialflask', 'numblox', 'numpans', 'numbpans')


def piece_tables():
    out = bytearray()
    for name in BY_PIECE:
        a = list(getattr(bg, name))
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


def image_table(path):
    """count, count 2-byte offsets, then the records -- bottom row first."""
    t = popimg.Table(path)
    top = max(t.images) if t.images else 0
    body = bytearray()
    where = [0] * (top + 1)
    for i in range(1, top + 1):
        img = t.images.get(i)
        if img is None:
            continue
        where[i] = len(body)
        body += bytes([img.width, img.height])
        rows = [img.data[y * img.width:(y + 1) * img.width]
                for y in range(img.height)]
        rows.reverse()                          # back to POP's own order
        for r in rows:
            body += bytes(b & 0x7f for b in r)
    head = bytearray([top])
    base = 1 + 2 * top
    for i in range(1, top + 1):
        head += struct.pack('<H', (base + where[i]) if where[i] or i == 1 else 0)
    return bytes(head) + bytes(body)


def build(level_path):
    """(blob, {name: offset}) -- everything the background bank carries."""
    tables = piece_tables()
    t1 = image_table(os.path.join(IMAGES, 'IMG.BGTAB1.DUN'))
    t2 = image_table(os.path.join(IMAGES, 'IMG.BGTAB2.DUN'))
    level = open(level_path, 'rb').read()

    blob = bytearray()
    at = {}
    for name, part in (('bgtables', tables), ('bgtab1', t1),
                       ('bgtab2', t2), ('level', level)):
        at[name] = len(blob)
        blob += part
    return bytes(blob), at, offsets(BY_PIECE)
