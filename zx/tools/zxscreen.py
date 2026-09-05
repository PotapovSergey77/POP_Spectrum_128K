"""
ZX Spectrum screen memory: 6912 bytes = 6144 bitmap + 768 attributes.

Bitmap addressing is the usual thirds/interleave:

    offset = ((y & 0xC0) << 5) | ((y & 0x07) << 8) | ((y & 0x38) << 2) | x

with x the byte column 0..31 and y the scanline 0..191.  Within a byte bit 7
is the leftmost pixel -- the opposite of the Apple II, where bit 0 is.
"""

WIDTH, HEIGHT = 256, 192
BITMAP, ATTRS, SIZE = 6144, 768, 6912


def bitmap_offset(x, y):
    return ((y & 0xC0) << 5) | ((y & 0x07) << 8) | ((y & 0x38) << 2) | x


def build(pixels, attr=0x47):
    """
    pixels: 192 sequences of 256 truthy/falsy values, top row first.
    attr:   one attribute byte for the whole screen, or 768 of them.
    """
    scr = bytearray(SIZE)
    for y in range(HEIGHT):
        row = pixels[y]
        for x in range(32):
            b = 0
            for bit in range(8):
                if row[x * 8 + bit]:
                    b |= 0x80 >> bit          # bit 7 is leftmost
            scr[bitmap_offset(x, y)] = b
    if isinstance(attr, int):
        attr = bytes([attr]) * ATTRS
    scr[BITMAP:BITMAP + ATTRS] = attr
    return bytes(scr)


def tint(pixels, solid, detail, threshold=48):
    """
    An attribute per 8x8 cell: cells that came out as a solid fill get the
    `solid` attribute, everything else `detail`.  Dither that the hybrid pass
    flooded would otherwise read as glaring white where the Apple II showed a
    mid tone, and a dimmer ink is the only mid tone a Spectrum has.
    """
    a = bytearray(ATTRS)
    for cy in range(24):
        for cx in range(32):
            n = sum(sum(pixels[cy * 8 + r][cx * 8:cx * 8 + 8]) for r in range(8))
            a[cy * 32 + cx] = solid if n >= threshold else detail
    return bytes(a)


def window(canvas, left):
    """Cut a 256-pixel-wide window out of a wider pixel canvas."""
    return [row[left:left + WIDTH] for row in canvas]


PALETTE = [(0, 0, 0), (0, 0, 192), (192, 0, 0), (192, 0, 192),
           (0, 192, 0), (0, 192, 192), (192, 192, 0), (192, 192, 192)]


def preview(screen, path):
    """Decode a 6912-byte SCREEN$ into an RGB PNG, as a real Spectrum shows it."""
    import pngwrite
    rows = []
    for y in range(HEIGHT):
        out = bytearray()
        for x in range(32):
            b = screen[bitmap_offset(x, y)]
            a = screen[BITMAP + (y >> 3) * 32 + x]
            bright = 8 if a & 0x40 else 0
            ink = PALETTE[a & 7]
            paper = PALETTE[(a >> 3) & 7]
            if bright:
                ink = tuple(255 if c else 0 for c in ink)
                paper = tuple(255 if c else 0 for c in paper)
            for bit in range(8):
                out.extend(ink if (b >> (7 - bit)) & 1 else paper)
        rows.append(bytes(out))
    pngwrite.write_rgb(path, WIDTH, HEIGHT, rows)
