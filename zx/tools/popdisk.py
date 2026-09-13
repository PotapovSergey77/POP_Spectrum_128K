"""
Prince of Persia's own disks, read the way RW18 reads them.

The game disk is not DOS: past its boot track every track holds eighteen
256-byte sectors in six blocks of three, which Roland Gustafsson's RW18 reads
and writes.  Taken apart from the copy of RW18 on track 0 of side A:

    D5 9D  track  block  track^block  AA  FF FF  BbundID
    256 groups of four nibbles, one checksum nibble, D4

Each group is three bytes, one each for the block's three sectors: the first
nibble carries their top two bits, 5-4, 3-2 and 1-0, and the other three
their low six.  The nibbles are DOS 3.3's 6-and-2 set, in the same order,
and the three sectors a block fills are block, block + 6 and block + 12.

A .nib image holds a track as the 6656 nibbles a drive reads off it.
"""

TRACK_NIBS = 6656

NIBBLES = [0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6, 0xA7, 0xAB, 0xAC,
           0xAD, 0xAE, 0xAF, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA,
           0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3, 0xD6,
           0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE5, 0xE6, 0xE7,
           0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5,
           0xF6, 0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF]
VALUE = dict((n, i) for i, n in enumerate(NIBBLES))

BLOCK_NIBS = 9 + 1024 + 1


class Disk:
    def __init__(self, path):
        self.data = open(path, 'rb').read()

    def track(self, t):
        """The track's eighteen sectors as one 4608-byte string."""
        raw = self.data[t * TRACK_NIBS:(t + 1) * TRACK_NIBS]
        raw2 = raw + raw                        # a block can wrap round
        secs = {}
        for i in range(TRACK_NIBS):
            if raw2[i] != 0xD5 or raw2[i + 1] != 0x9D:
                continue
            head = raw2[i:i + BLOCK_NIBS]
            if (head[5] != 0xAA or head[2] not in VALUE
                    or head[3] not in VALUE or head[4] not in VALUE):
                continue
            block = VALUE[head[3]]
            if VALUE[head[4]] != VALUE[head[2]] ^ block or block > 5:
                continue
            nib = [VALUE.get(x, 0) for x in head[9:9 + 1024]]
            out = [bytearray(), bytearray(), bytearray()]
            for g in range(256):
                hi, a, b, c = nib[g * 4:g * 4 + 4]
                out[0].append(((hi >> 4) & 3) << 6 | a)
                out[1].append(((hi >> 2) & 3) << 6 | b)
                out[2].append((hi & 3) << 6 | c)
            for k in range(3):
                secs[block + 6 * k] = bytes(out[k])
        if len(secs) != 18:
            raise SystemExit('track %d: %d of 18 sectors read' % (t, len(secs)))
        return b''.join(secs[k] for k in range(18))
