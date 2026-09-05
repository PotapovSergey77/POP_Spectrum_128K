"""
Prince of Persia level files ("blueprints"), 2304 bytes each.

Layout is given by `dum blueprnt` in EQ.S and confirmed by the file size:

    BLUETYPE   24*30 = 720    piece id per block, low 5 bits (idmask = $1f)
    BLUESPEC   24*30 = 720    per-block state / modifier
    LINKLOC      256
    LINKMAP      256
    MAP        24*4  =  96
    INFO         256

CALCBLUE in GRAFIX.S reduces a screen number 1..24 to (n-1), then indexes
BLUETYPE/BLUESPEC by Mult30 -- so screen n occupies bytes [(n-1)*30, +30).
Within a screen, block 0 is top-left and block 29 bottom-right (10 per row).
"""
import struct

IDMASK = 0x1f

BLUETYPE, BLUESPEC = 0, 720
LINKLOC, LINKMAP, MAP, INFO = 1440, 1696, 1952, 2048

# Offsets within INFO
KidStartScrn, KidStartBlock, KidStartFace = 64, 65, 66
SwStartScrn, SwStartBlock = 68, 69
GdStartBlock, GdStartFace, GdStartX = 72, 96, 120
GdStartSeqL, GdStartProg, GdStartSeqH = 144, 168, 192


class Level:
    def __init__(self, path):
        self.data = open(path, 'rb').read()
        if len(self.data) != 2304:
            raise ValueError('%s: expected 2304 bytes, got %d'
                             % (path, len(self.data)))

    def _info(self, off):
        return self.data[INFO + off]

    @property
    def kid_start(self):
        """(screen, block, face) for the prince's starting position."""
        return (self._info(KidStartScrn), self._info(KidStartBlock),
                self._info(KidStartFace))

    def screen(self, num):
        """Return (types, specs), 30 bytes each, for screen 1..24."""
        off = (num - 1) * 30
        return (self.data[BLUETYPE + off:BLUETYPE + off + 30],
                self.data[BLUESPEC + off:BLUESPEC + off + 30])

    def objid(self, num, block):
        return self.screen(num)[0][block] & IDMASK

    def links(self, num):
        """Neighbours of screen num: (left, right, above, below)."""
        off = MAP + (num - 1) * 4
        return tuple(self.data[off:off + 4])
