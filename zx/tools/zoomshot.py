"""Blow up a rectangle of a saved screen so a few pixels can be looked at."""
import sys
import runtap, z80, zxscreen, pngwrite


def main(argv):
    tap, out, frames = argv[1], argv[2], int(argv[3])
    x0, y0, x1, y1, Z = (int(v) for v in argv[4:9])
    held = argv[9:]
    cpu = runtap.boot(tap, held)
    cpu.run(frames)
    rows = []
    for y in range(y0, y1):
        line = []
        for x in range(x0, x1):
            off = zxscreen.bitmap_offset(x >> 3, y)
            v = 255 if cpu.mem[16384 + off] & (0x80 >> (x & 7)) else 0
            line.extend([v] * Z)
        for _ in range(Z):
            rows.append(bytes(line))
    pngwrite.write_gray(out, (x1 - x0) * Z, len(rows), rows)
    print('%s: %d..%d x %d..%d' % (out, x0, x1, y0, y1))


if __name__ == '__main__':
    main(sys.argv)
