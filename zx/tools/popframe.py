"""
Character frames: FRAMEDEF.S gives five bytes per frame and the table the
image comes from is encoded across two of them.

    Fimage, Fsword, Fdx, Fdy, Fcheck

`decodeim` in CTRLSUBS.S splits out the picture:

    table = ((Fimage >> 7) & 1) * 4 + ((Fsword >> 6) & 3)
    image =   Fimage & 0x7f

Checked against three independently documented cases: frame 15 "stand" comes
out as chtable1 image 15, which is the standing prince; altset1 resolves to
chtable4 and altset2 to chtable6, exactly as the comments in FRAMEDEF.S say.

Position, from CTRLSUBS.S:

    screen x = 2 * (CharX + Fdx - ScrnLeft), +1 when the high bits of Fcheck
               and CharFace agree
    screen y = CharY + Fdy - ScrnTop

CharX is in the 140-wide logic space, so a block is 14 units and 28 pixels.
"""
import os
import re

import popimg

TABLES = ['IMG.CHTAB1', 'IMG.CHTAB2', 'IMG.CHTAB3', 'IMG.CHTAB4.GD',
          'IMG.CHTAB5', 'IMG.CHTAB6.A', 'IMG.CHTAB7']
IMAGES = os.path.join(os.path.dirname(__file__), '..', '..',
                      '01 POP Source', 'Images')

SCRN_LEFT, BLOCK_UNITS = 58, 14
SCRN_BOT, BLOCK_HEIGHT, VERT_DIST, ANGLE = 191, 63, 10, 7
BLOCK_PIXELS = 28

# TABLES.S builds FloorY as ScrnBot - Blox(n) - VertDist, indexed by block
# row + 1.  SUBS.S puts the kid on his starting block with
# CharY = FloorY[blockY+1] and CharX = BlockEdge[blockX+5] + angle + 7, so
# both coordinates come straight out of the tables -- nothing to eyeball.
FLOOR_Y = [SCRN_BOT - 3 * BLOCK_HEIGHT - VERT_DIST,
           SCRN_BOT - 2 * BLOCK_HEIGHT - VERT_DIST,
           SCRN_BOT - 1 * BLOCK_HEIGHT - VERT_DIST,
           SCRN_BOT - VERT_DIST,
           SCRN_BOT + BLOCK_HEIGHT - VERT_DIST]

# BlockTop, from the same table: the scanline a block row starts on, indexed
# by block row + 1.  CROPCHAR cuts a character off at his own row's, so the
# floor above covers him rather than the other way round.
BLOCK_TOP = [SCRN_BOT + 1 - 4 * BLOCK_HEIGHT,
             SCRN_BOT + 1 - 3 * BLOCK_HEIGHT,
             SCRN_BOT + 1 - 2 * BLOCK_HEIGHT,
             SCRN_BOT + 1 - 1 * BLOCK_HEIGHT,
             SCRN_BOT + 1]

FLOOR_HEIGHT = 15               # GAMEEQ.S floorheight


def block_edge(block):
    """BlockEdge: the left edge of a block, in the 140-wide logic space."""
    return -12 + BLOCK_UNITS * (block + 5)


def char_x(block):
    """SUBS.S: CharX = BlockEdge[blockX+5] + angle + 7."""
    return block_edge(block) + ANGLE + 7


def char_y(row):
    """SUBS.S: CharY = FloorY[blockY+1] -- the centre plane of the floor,
    VertDist above the bottom of the block, not its lower edge."""
    return FLOOR_Y[row + 1]


def screen_x(charx):
    """CTRLSUBS.S: the drawing coordinate is 2*(CharX - ScrnLeft)."""
    return 2 * (charx - SCRN_LEFT)

_LINE = re.compile(r'^:(\d+)\s+db\s+(.+?)(?:\s*;(.*))?$')


def _num(tok):
    tok = tok.strip()
    total = 0
    for part in re.split(r'(?=[+-])', tok):
        part = part.strip()
        if not part:
            continue
        sign = -1 if part.startswith('-') else 1
        part = part.lstrip('+-').strip()
        total += sign * (int(part[1:], 16) if part.startswith('$')
                         else int(part))
    return total & 0xff if total >= 0 else total & 0xff


class Frame:
    def __init__(self, num, vals, comment):
        self.num = num
        self.image, self.sword, dx, dy, self.check = vals
        self.dx = dx - 256 if dx > 127 else dx
        self.dy = dy - 256 if dy > 127 else dy
        self.name = (comment or '').strip()

    @property
    def table(self):
        return ((self.image >> 7) & 1) * 4 + ((self.sword >> 6) & 3)

    @property
    def index(self):
        return self.image & 0x7f

    def __repr__(self):
        return ('frame %d %s: chtable%d image %d dx=%d dy=%d'
                % (self.num, self.name, self.table + 1, self.index,
                   self.dx, self.dy))


def load(path=None):
    """Parse the main frame-definition list out of FRAMEDEF.S."""
    path = path or os.path.join(os.path.dirname(__file__), '..', '..',
                                '01 POP Source', 'Source', 'FRAMEDEF.S')
    frames = {}
    for line in open(path, encoding='latin-1'):
        m = _LINE.match(line.rstrip('\n'))
        if not m:
            continue
        vals = [_num(t) for t in m.group(2).split(',')]
        if len(vals) != 5:
            continue
        num = int(m.group(1))
        if num in frames:            # the alternate sets restart numbering
            continue
        frames[num] = Frame(num, vals, m.group(3))
    return frames


_tables = {}


def image(frame):
    """The decoded picture for a frame."""
    t = frame.table
    if t not in _tables:
        _tables[t] = popimg.Table(os.path.join(IMAGES, TABLES[t]))
    return _tables[t].get(frame.index)
