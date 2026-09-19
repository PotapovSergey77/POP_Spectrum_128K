"""
The title music of Amstrad CPC Prince of Persia, for the Spectrum 128's AY.

The CPC's PRINCE.BIN reads 75 sectors from track 2, sector &47, to &0040 and
jumps to &0049: the titles, the princess's scenes and their music.  The
music is the same kind of data the game's own sounds are (see cpcsound.py:
a run of commands, one AY tick a fiftieth), and the titles' driver at &7AD3
plays tune A from word A of the table at &7AB5 up to word A + 1:

    0  &8692   the titles, from the first screen (7AD3 with A = 0 at &766C)
    1  &8866   the story (A = 1 at &7700)
    2  &892A   the princess's room (PlayCut0's script, at its start)
    3  &896C   the door squeaks
    4  &89BA   the vizier, the spell, the hourglass: to the scene's end
    6  &8C5C   PlayCut1: the princess waiting
    7  &8CF8   PlayCut7        8  &8D66  the end        9  &90AE  PlayCut8

The scenes' scripts start them with opcode &7x, the tune after it.  Every
one of them ends with a wait of nought, which stops the sound.

    cpcmusic.py        say what each tune is, and how long
"""
import os
import struct
import sys

import cpcdisk
import cpcsound

TABLE = 0x7AB5
TITLES = (0, 1, 2, 3, 4)


def boot_image(disk):
    mem = bytearray(0x10000)
    addr, track, sector = 0x0040, 2, 0x47
    for _ in range(75):
        mem[addr:addr + 512] = disk.sector(track, sector)
        addr += 512
        sector += 1
        if sector == 0x4A:
            track, sector = track + 1, 0x41
    return bytes(mem)


def length(mem, start):
    """The bytes of the tune up to and with its stop."""
    hl = start
    while True:
        c = mem[hl]
        if c & 0x80:
            k = c & 0x7F
            if k == 0:
                hl += 2
            elif k == 1:
                hl += 4
            else:
                hl += 2
                if mem[hl - 1] == 0:
                    return hl - start
        elif c == 11:
            hl += 4
        else:
            hl += 2


def ticks(data):
    hl, t, acc = 0, 0, 0
    while hl < len(data):
        c = data[hl]
        if c & 0x80:
            k = c & 0x7F
            if k == 0:
                acc = data[hl + 1]
                hl += 2
            elif k == 1:
                d, e = data[hl + 2], data[hl + 3]
                t += max(1, (e - acc) // d) if d else 1
                acc = e
                hl += 4
            else:
                t += data[hl + 1] + 1
                hl += 2
        else:
            hl += 4 if c == 11 else 2
    return t


def tunes(numbers=TITLES):
    """The tunes, each its periods scaled for the 128's AY clock."""
    mem = boot_image(cpcdisk.Disk(cpcsound.DISK))
    words = [struct.unpack_from('<H', mem, TABLE + 2 * i)[0] for i in range(11)]
    out = []
    for n in numbers:
        start = words[n]
        out.append(cpcsound.convert(mem, start, start + length(mem, start)))
    return out


def main(argv):
    mem = boot_image(cpcdisk.Disk(cpcsound.DISK))
    words = [struct.unpack_from('<H', mem, TABLE + 2 * i)[0] for i in range(11)]
    for n in (0, 1, 2, 3, 4, 6, 7, 8, 9):
        data = mem[words[n]:words[n] + length(mem, words[n])]
        print('tune %d at %04X: %4d bytes, %.1f s' % (n, words[n], len(data), ticks(data) / 50))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
