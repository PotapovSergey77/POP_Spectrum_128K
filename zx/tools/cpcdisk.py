"""
Read an Amstrad CPC disk image (the EXTENDED CPC DSK format) -- the CPC
release of Prince of Persia, whose sounds are for the same AY chip the
Spectrum 128 has.

    cpcdisk.py <dsk>                 list the tracks and the catalogue
    cpcdisk.py <dsk> <name> <out>    write one file out

Tracks are kept as they are, sectors in the order their IDs say.  The
catalogue is AMSDOS's: 64 entries of 32 bytes in the first four sectors
after the reserved tracks (two for the system format, none for data).
"""
import struct
import sys


class Disk:
    def __init__(self, path):
        d = open(path, 'rb').read()
        if not d.startswith(b'EXTENDED CPC DSK') and not d.startswith(b'MV - CPC'):
            raise ValueError('not a CPC disk image')
        ext = d.startswith(b'EXTENDED')
        self.ntracks, self.nsides = d[0x30], d[0x31]
        size = struct.unpack_from('<H', d, 0x32)[0]
        self.tracks = {}
        at = 0x100
        for i in range(self.ntracks * self.nsides):
            tsize = d[0x34 + i] * 256 if ext else size
            if not tsize:
                continue
            t = d[at:at + tsize]
            assert t.startswith(b'Track-Info'), (i, t[:12])
            track, side, ssize, nsec = t[0x10], t[0x11], t[0x14], t[0x15]
            secs = {}
            off = 0x100
            for s in range(nsec):
                c, h, r, n, st1, st2, length = struct.unpack_from('<BBBBBBH', t, 0x18 + s * 8)
                if not ext or not length:
                    length = 128 << n
                secs[r] = t[off:off + length]
                off += length
            self.tracks[(track, side)] = secs
            at += tsize

    def sector(self, track, sid, side=0):
        return self.tracks[(track, side)][sid]

    def format(self):
        first = min(self.tracks[(0, 0)])
        return 'system' if first == 0x41 else 'data' if first == 0xC1 else 'ibm'

    def blocks(self):
        """The disk after the reserved tracks, as one run of 512-byte
        sectors, sector IDs in order."""
        fmt = self.format()
        base, reserved = (0x41, 2) if fmt == 'system' else (0xC1, 0) if fmt == 'data' else (1, 1)
        out = bytearray()
        for tr in range(reserved, self.ntracks):
            secs = self.tracks.get((tr, 0), {})
            for i in range(9):
                out += secs.get(base + i, bytes(512))
        return bytes(out)

    def catalogue(self):
        data = self.blocks()
        files = {}
        for i in range(64):
            e = data[i * 32:(i + 1) * 32]
            if e[0] == 0xE5:
                continue
            name = bytes(c & 0x7f for c in e[1:9]).decode('ascii').rstrip()
            ext = bytes(c & 0x7f for c in e[9:12]).decode('ascii').rstrip()
            full = name + ('.' + ext if ext else '')
            f = files.setdefault((e[0], full), {'extents': {}, 'user': e[0]})
            f['extents'][e[12]] = (e[15], [b for b in e[16:32]])
        return files

    def read(self, full, user=0):
        data = self.blocks()
        f = self.catalogue()[(user, full)]
        out = bytearray()
        for ex in sorted(f['extents']):
            recs, blocks = f['extents'][ex]
            chunk = bytearray()
            for b in blocks:
                if b:
                    chunk += data[b * 1024:(b + 1) * 1024]
            out += chunk[:recs * 128]
        return bytes(out)


def main(argv):
    disk = Disk(argv[1])
    if len(argv) >= 4:
        want = argv[2].upper()
        for (user, full) in disk.catalogue():
            if full.upper() == want:
                open(argv[3], 'wb').write(disk.read(full, user))
                print('wrote', argv[3])
                return 0
        print('no such file')
        return 1
    print('tracks', disk.ntracks, 'sides', disk.nsides, 'format', disk.format())
    for (user, full), f in sorted(disk.catalogue().items()):
        size = sum(r for r, _ in f['extents'].values()) * 128
        print('%3d %-12s %6d' % (user, full, size))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
