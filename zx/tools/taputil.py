"""
.tap file construction.

A .tap is a bare sequence of blocks, each stored as a little-endian 16-bit
length followed by that many bytes.  A block is a flag byte (0x00 for a
17-byte header, 0xFF for data), the payload, and an XOR checksum of
everything before it.

Header payload:
    0       type: 0 = BASIC program, 3 = CODE
    1..10   file name, space padded
    11..12  length of the data block that follows
    13..14  param 1: autostart line for a program, load address for CODE
    15..16  param 2: offset to variables for a program, 32768 for CODE
"""
import struct

PROGRAM, NUMBER_ARRAY, CHAR_ARRAY, CODE = 0, 1, 2, 3


def _block(flag, payload):
    body = bytes([flag]) + bytes(payload)
    check = 0
    for b in body:
        check ^= b
    body += bytes([check])
    return struct.pack('<H', len(body)) + body


def header(ftype, name, length, param1, param2):
    payload = (bytes([ftype]) + name.encode('ascii')[:10].ljust(10, b' ') +
               struct.pack('<HHH', length, param1, param2))
    return _block(0x00, payload)


def data(payload):
    return _block(0xFF, payload)


def code_file(name, payload, address):
    return (header(CODE, name, len(payload), address, 32768) + data(payload))


def program_file(name, payload, autostart):
    # No variables area, so the variables offset is the program length.
    return (header(PROGRAM, name, len(payload), autostart, len(payload)) +
            data(payload))


# -- BASIC tokenisation ---------------------------------------------------

BORDER, PAPER, INK, CLS, LOAD, SCREEN_D, PAUSE, GOTO = (
    0xE7, 0xDA, 0xD9, 0xFB, 0xEF, 0xAA, 0xF2, 0xEC)
CLEAR, OUT, RANDOMIZE, USR, CODE_T, REM = 0xFD, 0xDF, 0xF9, 0xC0, 0xAF, 0xEA


def number(n):
    """A BASIC numeric literal: the digits, then the hidden 5-byte form."""
    return (str(n).encode('ascii') + bytes([0x0E, 0x00, 0x00,
                                            n & 0xFF, (n >> 8) & 0xFF, 0x00]))


def line(num, tokens):
    body = bytes(tokens) + b'\x0d'
    return struct.pack('>H', num) + struct.pack('<H', len(body)) + body
