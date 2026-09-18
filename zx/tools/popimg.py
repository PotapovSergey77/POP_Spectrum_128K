"""
Apple II Prince of Persia image tables (IMG.*).

Table format, from the "Image table format" comment and `setimage` in HIRES.S:

    byte 0      image count
    bytes 1..   little-endian pointers; image N (1-based) lives at offset 2N-1,
                with one extra pointer past the last image marking end-of-data
    records     width byte, height byte, then width*height image bytes

Rows are stored BOTTOM FIRST.  The comment in HIRES.S says "top-bottom", but
FASTLAY is the authority: it loads YCO into X, walks the image forward one
row-width at a time, and does `dex` each pass until it reaches YCO-height --
so the first stored row lands on YCO, the image's bottom line, and the rest
climb upward.  Rows are flipped here so that row 0 is the top.

An image byte holds 7 pixels with bit 0 leftmost; bit 7 is the Apple II
palette-shift bit and carries no luminance, so it is dropped.
"""
import os
import struct
import sys

import pngwrite


class Image:
    def __init__(self, index, width, height, data):
        self.index = index
        self.width = width        # in bytes, 7 px each
        self.height = height      # scanlines
        self.data = data          # width*height bytes, top row first

    @property
    def px_width(self):
        return self.width * 7

    def row(self, y):
        return self.data[y * self.width:(y + 1) * self.width]

    def pixels(self):
        """Yield a bytearray of 0/1 per scanline, leftmost pixel first."""
        for y in range(self.height):
            line = bytearray()
            for b in self.row(y):
                for bit in range(7):
                    line.append((b >> bit) & 1)
            yield line


class Table:
    def __init__(self, path, data=None):
        self.name = os.path.basename(path)
        if data is None:
            data = open(path, 'rb').read()
        self.count = data[0]
        # Records follow the pointer table, so image 1 pins the load address.
        first = struct.unpack_from('<H', data, 1)[0]
        self.base = first - (1 + 2 * (self.count + 1))

        self.images = {}
        for i in range(1, self.count + 1):
            ptr = struct.unpack_from('<H', data, 2 * i - 1)[0]
            off = ptr - self.base
            if off < 0 or off + 2 > len(data):
                continue
            w, h = data[off], data[off + 1]
            if not w or not h or off + 2 + w * h > len(data):
                continue
            body = data[off + 2:off + 2 + w * h]
            rows = [body[y * w:(y + 1) * w] for y in range(h)]
            rows.reverse()                  # stored bottom first
            self.images[i] = Image(i, w, h, b''.join(rows))

    @classmethod
    def from_memory(cls, mem, addr):
        """A table where a loader left it: its pointers say how far it runs."""
        count = mem[addr]
        end = struct.unpack_from('<H', mem, addr + 2 * count + 1)[0]
        return cls('$%04X' % addr, bytes(mem[addr:end]))

    def get(self, index):
        return self.images.get(index)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    outdir = argv[-1] if len(argv) > 2 else 'out'
    for path in argv[1:-1] if len(argv) > 2 else argv[1:]:
        t = Table(path)
        sub = os.path.join(outdir, t.name)
        os.makedirs(sub, exist_ok=True)
        for img in t.images.values():
            pngwrite.write_gray(
                os.path.join(sub, '%03d.png' % img.index),
                img.px_width, img.height,
                [bytes(255 if p else 0 for p in line) for line in img.pixels()])
        w = [i.px_width for i in t.images.values()]
        h = [i.height for i in t.images.values()]
        print('%-20s base=$%04X  images=%-4d decoded=%-4d  w=%d..%d px  h=%d..%d'
              % (t.name, t.base, t.count, len(t.images),
                 min(w), max(w), min(h), max(h)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
