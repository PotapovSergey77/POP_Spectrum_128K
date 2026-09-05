"""Minimal 1-bit-expanded-to-grey PNG writer (stdlib only)."""
import struct
import zlib


def _chunk(tag, data):
    body = tag + data
    return (struct.pack('>I', len(data)) + body +
            struct.pack('>I', zlib.crc32(body) & 0xffffffff))


def write_gray(path, width, height, rows):
    """rows: iterable of bytes-like, one byte (0..255) per pixel."""
    raw = bytearray()
    for row in rows:
        raw.append(0)          # filter type 0
        raw.extend(row)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(_chunk(b'IHDR',
                       struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0)))
        f.write(_chunk(b'IDAT', zlib.compress(bytes(raw), 9)))
        f.write(_chunk(b'IEND', b''))


def write_rgb(path, width, height, rows):
    """rows: iterable of bytes-like, three bytes (R,G,B) per pixel."""
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(_chunk(b'IHDR',
                       struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)))
        f.write(_chunk(b'IDAT', zlib.compress(bytes(raw), 9)))
        f.write(_chunk(b'IEND', b''))
