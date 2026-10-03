"""
Build the .trd: the disk version, a TR-DOS disk image.

TR-DOS keeps its catalogue on track 0 and its files after it, each a run of
whole sectors -- sixteen of 256 bytes a track, the tracks of the two sides
taking turns, 160 of them on an 80-track double-sided disk.  The disk here
is laid out in the order the tape was, each block a catalogue file of its
own so that TR-DOS sees a proper disk:

    boot      BASIC, autostart: TR-DOS loads loader into the screen, black,
              and calls it
    loader    a sector that copies the rest of it to the buffers under the
              program, and the loader itself (loader.asm), two sectors
    pop       the program, at 24320
    bank6 ... the banks, each to the window with its bank paged
    ...       the levels after the first, the scenes and character sets
              with them, in the tape's order: the game reads them on from
              where the loader stopped, a block a level
    cut6      PlayCut6, the hour run out, past the rest: read when wanted

Only boot and loader are read by TR-DOS.  Everything after is read by the
loader and the game sector by sector (dload.asm), from positions worked out
here: a position is the sector's number from the start of the disk, as
dload.asm's DPOS holds it -- the cylinder high, side times sixteen and
sector low.

    maketrd.py <out.trd> <layout.json>      (build.sh writes the layout)
"""
import json
import os
import sys

import taputil as t

SECTOR = 256
TRACK_SECTORS = 16
TRACKS = 160                    # 80 cylinders, two sides
FIRST = 16                      # track 1: track 0 is the catalogue
BOOT_SECTORS = 1
LDR_SECTORS = 3                 # the copying sector, and two of loader
LDR_BODY = 2 * SECTOR           # what of it is the loader proper
LDRPOS = FIRST + BOOT_SECTORS + 1       # pop.asm's LDRPOS: the body
MAINPOS = FIRST + BOOT_SECTORS + LDR_SECTORS
SCREEN = 16384


def sectors(n):
    return (n + SECTOR - 1) // SECTOR


def enc(n):
    """A sector's number as DPOS holds it."""
    return (n % 32) | (n // 32) << 8


def layout(main_len, bank_lens, block_lens, cut6_len):
    """Where each part begins, as sector numbers: the program, the banks,
    the blocks the game reads on from the banks' end, and PlayCut6."""
    at = MAINPOS
    main = at
    at += sectors(main_len)
    banks = []
    for n in bank_lens:
        banks.append(at)
        at += sectors(n)
    blocks = []
    for n in block_lens:
        blocks.append(at)
        at += sectors(n)
    cut6 = at
    at += sectors(cut6_len)
    assert at <= TRACKS * TRACK_SECTORS, 'диск полон: %d секторов' % at
    return {'main': main, 'banks': banks, 'blocks': blocks, 'cut6': cut6,
            'end': at}


def boot_program(ldr_name):
    """10 BORDER 0: PAPER 0: INK 0: CLS: RANDOMIZE USR 15619: REM : LOAD
    "loader" CODE / 20 RANDOMIZE USR 16384 -- the screen black before
    the loader lands in it."""
    q = ord('"')
    return (t.line(10, [t.BORDER] + list(t.number(0)) + [ord(':'), t.PAPER]
                   + list(t.number(0)) + [ord(':'), t.INK]
                   + list(t.number(0)) + [ord(':'), t.CLS, ord(':'),
                                          t.RANDOMIZE, t.USR]
                   + list(t.number(15619)) + [ord(':'), t.REM, ord(':'),
                                              t.LOAD, q]
                   + list(ldr_name.encode('ascii')) + [q, t.CODE_T])
            + t.line(20, [t.RANDOMIZE, t.USR] + list(t.number(SCREEN))))


def loader_file(body, ldrorg):
    """The copying sector, at 16384, and the loader after it."""
    assert len(body) <= LDR_BODY, 'загрузчик длиннее двух секторов'
    pro = bytes([0xF3,                                          # di
                 0x21]) + (SCREEN + SECTOR).to_bytes(2, 'little') + \
        bytes([0x11]) + ldrorg.to_bytes(2, 'little') + \
        bytes([0x01]) + LDR_BODY.to_bytes(2, 'little') + \
        bytes([0xED, 0xB0, 0xC3]) + ldrorg.to_bytes(2, 'little')  # ldir, jp
    return pro.ljust(SECTOR, b'\0') + body.ljust(LDR_BODY, b'\0')


def entry(name, kind, p1, p2, data, at):
    return (name.encode('ascii')[:8].ljust(8, b' ') + kind.encode('ascii')
            + p1.to_bytes(2, 'little') + p2.to_bytes(2, 'little')
            + bytes([sectors(len(data)), at % TRACK_SECTORS,
                     at // TRACK_SECTORS]))


def build(out, files, title):
    """files: (name, kind, param 1, param 2, data, sector), in order on
    the disk, each where the layout put it."""
    disk = bytearray(TRACKS * TRACK_SECTORS * SECTOR)
    cat = bytearray()
    at = FIRST
    for name, kind, p1, p2, data, pos in files:
        assert pos == at, (name, pos, at)
        assert len(data) <= 255 * SECTOR, name
        disk[at * SECTOR:at * SECTOR + len(data)] = data
        cat += entry(name, kind, p1, p2, data, at)
        at += sectors(len(data))
    assert len(files) <= 128
    disk[:len(cat)] = cat
    info = 8 * SECTOR
    free = TRACKS * TRACK_SECTORS - at
    disk[info + 0xE1] = at % TRACK_SECTORS
    disk[info + 0xE2] = at // TRACK_SECTORS
    disk[info + 0xE3] = 0x16                    # 80 tracks, two sides
    disk[info + 0xE4] = len(files)
    disk[info + 0xE5:info + 0xE7] = free.to_bytes(2, 'little')
    disk[info + 0xE7] = 0x10                    # TR-DOS's
    disk[info + 0xEA:info + 0xF3] = b' ' * 9
    disk[info + 0xF5:info + 0xFD] = title.encode('ascii')[:8].ljust(8, b' ')
    open(out, 'wb').write(disk)
    return at


def names(paths):
    """Catalogue names for the blocks: their files' own, a letter on for
    one met again."""
    seen = {}
    out = []
    for p in paths:
        base = os.path.splitext(os.path.basename(p))[0][:7]
        k = seen.get(base, 0)
        seen[base] = k + 1
        out.append(base if not k else base + chr(ord('a') + k))
    return out


def main(argv):
    out, lay = argv[1], json.load(open(argv[2]))
    prog = boot_program('loader')
    # a BASIC file: its length with its variables and without (there are
    # none), and after it TR-DOS's mark and the line it starts at
    boot = prog + bytes([0x80, 0xAA]) + (10).to_bytes(2, 'little')
    ldr = loader_file(open(lay['loader'], 'rb').read(), lay['ldrorg'])
    main_bin = open(lay['main'], 'rb').read()
    files = [('boot', 'B', len(prog), len(prog), boot, FIRST),
             ('loader', 'C', SCREEN, len(ldr), ldr, FIRST + BOOT_SECTORS),
             ('pop', 'C', lay['org'], len(main_bin), main_bin, MAINPOS)]
    pos = layout(len(main_bin), [os.path.getsize(p) for _, p in lay['banks']],
                 [os.path.getsize(p) for p in lay['blocks']],
                 os.path.getsize(lay['cut6']))
    assert pos == lay['pos'], 'раскладка диска не та, что у загрузчика'
    for (bank, p), at in zip(lay['banks'], pos['banks']):
        files.append(('bank%d' % bank, 'C', 0xC000, os.path.getsize(p),
                      open(p, 'rb').read(), at))
    for name, p, at in zip(names(lay['blocks']), lay['blocks'], pos['blocks']):
        files.append((name, 'C', 0xC000, os.path.getsize(p),
                      open(p, 'rb').read(), at))
    files.append(('cut6', 'C', 0xC000, os.path.getsize(lay['cut6']),
                  open(lay['cut6'], 'rb').read(), pos['cut6']))
    end = build(out, files, 'PRINCE')
    print('%s: %d файлов, занято %d секторов из %d'
          % (out, len(files), end, TRACKS * TRACK_SECTORS))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
