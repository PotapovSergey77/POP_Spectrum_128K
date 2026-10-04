"""
Build the .tap.

The sprites alone outgrow a Spectrum's fixed map twice over, so they live in
RAM banks and the tape has to put them there.  BASIC loads only the tape's own
loader (src/tapeldr.asm) and calls it; the loader loads the rest, as
Spectrum games did: the title first -- the palace with Prince of Persia over
it -- and then the banks and the program, with how much is in, in per cent,
at the bottom left.  The loader pages the banks itself.  The part of the
program it sits in comes last, loaded by a stub low down through the ROM's
LD-BYTES, and the stub goes into the game.

    BASIC:  CLEAR 24319 / LOAD "" CODE / RANDOMIZE USR loader
    then    loader (CODE)  title  banks...  program  program's top  levels...

Load in 128 mode: entering 48 BASIC locks paging until a hard reset.

Writes a manifest beside the tape so the emulator can place the blocks the
same way without pretending to be a tape.

Usage: maketap.py <out.tap> <code.bin> <org> [bank:file ...] [L:level.bin ...]
"""
import json
import os
import subprocess
import sys

import taputil as t

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'src')
PAGE_WINDOW = 0xC000
STUB = 4                        # bytes per paging stub in the program
LDRORG = 0xBD00                 # the loader: a page of its own for its
LDRSTACK = 0xC000               # figures, at the top of the fixed map
STUBAT = 0x5E00                 # the last block's stub, low down


def title_screen():
    """The palace and Prince of Persia over it, as the titles show it."""
    sys.path.insert(0, HERE)
    import titlescr
    return titlescr.screen('title')


def assemble_loader(table, kstep, popb_at, popb_len, entry):
    with open(os.path.join(SRC, 'ldrtab.inc'), 'w') as f:
        f.write('; the tape loader\'s numbers: maketap.py -- do not edit\n')
        for name, value in (('LDRORG', LDRORG), ('LDRSTACK', LDRSTACK),
                            ('STUBAT', STUBAT), ('KSTEP', kstep),
                            ('POPB_AT', popb_at), ('POPB_LEN', popb_len),
                            ('ENTRY', entry)):
            f.write('%-15s equ     0x%04X\n' % (name, value))
    with open(os.path.join(SRC, 'ldrblk.inc'), 'w') as f:
        for bank, addr, length in table:
            f.write('                db      0x%02X\n'
                    '                dw      0x%04X, 0x%04X\n'
                    % (bank, addr, length))
    out = os.path.join(HERE, '..', 'build', 'tapeldr.bin')
    sym = os.path.join(HERE, '..', 'build', 'tapeldr.sym')
    subprocess.run([os.path.join(HERE, 'pasmo.exe'), '--bin', 'tapeldr.asm',
                    out, sym], cwd=SRC, check=True)
    syms = {}
    for line in open(sym):
        p = line.split()
        if len(p) >= 3 and p[1] == 'EQU':
            syms[p[0]] = int(p[2].rstrip('H'), 16)
    code = open(out, 'rb').read()
    assert len(code) == syms['ldrend'] - LDRORG
    assert syms['ldrend'] <= LDRSTACK - 32, 'загрузчик плёнки не влез под стек'
    assert syms['stubend'] - syms['stubsrc'] <= 0x100
    return code, syms['entry']


def main(argv):
    out, binary, org = argv[1], argv[2], int(argv[3])
    banks = [(int(a.split(':')[0]), a.split(':', 1)[1]) for a in argv[4:]
             if not a.startswith('L:')]
    levels = [a[2:] for a in argv[4:] if a.startswith('L:')]

    program = open(binary, 'rb').read()
    split = LDRORG - org            # the loader's part of it comes last
    assert 0 < split < len(program), 'программа не доходит до загрузчика'
    popa, popb = program[:split], program[split:]
    payloads = []
    for bank, path in banks:
        payload = open(path, 'rb').read()
        # The ROM cannot load a block of no length: "R Tape loading error".
        # Nothing here can see it -- runtap puts the banks in from the
        # manifest without the ROM -- so the build has to.
        if not payload:
            raise SystemExit('%s пуст: плёнка с блоком нулевой длины не '
                             'загрузится' % os.path.basename(path))
        payloads.append(payload)
    table = [(bank, PAGE_WINDOW, len(p)) for (bank, _), p
             in zip(banks, payloads)] + [(0xff, org, len(popa))]
    total = sum(len(p) for p in payloads) + len(popa) + len(popb)
    kstep = round(256 * 100 * 65536 / total)
    assert kstep < 65536
    entry = org + len(banks) * STUB
    loader, ldentry = assemble_loader(table, kstep, LDRORG, len(popb), entry)

    lines = [t.line(10, [t.CLEAR] + list(t.number(org - 1))),
             t.line(20, [t.LOAD, ord('"'), ord('"'), t.CODE_T]),
             t.line(30, [t.RANDOMIZE, t.USR] + list(t.number(ldentry)))]
    tap = t.program_file('pop', b''.join(lines), 10)
    tap += t.code_file('loader', loader, LDRORG)
    tap += t.data(title_screen())
    for payload in payloads:
        tap += t.data(payload)
    tap += t.data(popa) + t.data(popb)

    manifest = [{'file': binary, 'addr': org, 'bank': None, 'entry': entry}]
    for bank, path in banks:
        manifest.append({'file': path, 'addr': PAGE_WINDOW, 'bank': bank})

    # The levels after the first: each a bare data block, no header, which
    # the game loads itself with the ROM's LD-BYTES when the one before is
    # left by its stairs -- the tape going on where the loader stopped.
    for path in levels:
        payload = open(path, 'rb').read()
        tap += t.data(payload)
        manifest.append({'file': path, 'addr': None, 'bank': None,
                         'level': True})

    open(out, 'wb').write(tap)
    json.dump(manifest, open(os.path.splitext(out)[0] + '.banks.json', 'w'))
    print('%s: %d байт; загрузчик %04X..%04X, %d байт, шаг процента %d'
          % (out, len(tap), LDRORG, LDRORG + len(loader), len(loader), kstep))
    print('   заставка             -> 4000')
    for m in manifest:
        if m.get('level'):
            print('   %-18s    уровень, грузит игра' % os.path.basename(m['file']))
            continue
        print('   %-18s -> %04X%s' % (os.path.basename(m['file']), m['addr'],
                                      '' if m['bank'] is None
                                      else '  банк %d' % m['bank']))
    print('   (программа двумя блоками: %04X..%04X, затем %04X..%04X)'
          % (org, LDRORG, LDRORG, org + len(program)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
