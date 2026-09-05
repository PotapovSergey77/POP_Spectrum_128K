"""
Build the .tap.

The program does not fit in the fixed half of a Spectrum's map, so its two
big read only lumps go in RAM banks and the loader has to put them there.
48K BASIC on a 128K can still write the paging port, so the loader is three
lines: page a bank in, LOAD "" CODE into the window at 0xC000, repeat, then
load the program itself and run it.

Writes banks.json beside the tap so the emulator can place the blocks the
same way without pretending to be a tape.

Usage: maketap.py <out.tap> <code.bin> <org> [bank:file ...]
"""
import json
import os
import sys

import taputil as t

PAGE_WINDOW = 0xC000
PAGE_PORT = 32765

# The loader runs under 128 BASIC, whose interpreter is executing from ROM 0.
# Bit 4 of the paging port picks the ROM, so the loader must leave it alone --
# setting it would pull the 128 editor out from under the statement doing the
# setting.  The program selects the 48K ROM itself, once it is running its own
# code and no longer cares.
#
# 48 BASIC is not an option: entering it locks paging until a hard reset, and
# these OUTs would do nothing at all.


def main(argv):
    out, binary, org = argv[1], argv[2], int(argv[3])
    banks = [(int(a.split(':')[0]), a.split(':', 1)[1]) for a in argv[4:]]

    lines = [t.line(10, [t.CLEAR] + list(t.number(org - 1)))]
    n = 20
    for bank, _ in banks:
        lines.append(t.line(n, [t.OUT] + list(t.number(PAGE_PORT)) + [ord(',')]
                            + list(t.number(bank))
                            + [ord(':'), t.LOAD, ord('"'), ord('"'), t.CODE_T]))
        n += 10
    lines.append(t.line(n, [t.LOAD, ord('"'), ord('"'), t.CODE_T]))
    lines.append(t.line(n + 10, [t.RANDOMIZE, t.USR] + list(t.number(org))))
    basic = b''.join(lines)

    tap = t.program_file('pop', basic, 10)
    manifest = []
    for bank, path in banks:
        payload = open(path, 'rb').read()
        tap += t.code_file(os.path.basename(path)[:10], payload, PAGE_WINDOW)
        manifest.append({'file': path, 'addr': PAGE_WINDOW, 'bank': bank})
    code = open(binary, 'rb').read()
    tap += t.code_file('pop', code, org)
    manifest.append({'file': binary, 'addr': org, 'bank': None})

    open(out, 'wb').write(tap)
    json.dump(manifest, open(os.path.splitext(out)[0] + '.banks.json', 'w'))
    print('%s: %d байт, %d блоков' % (out, len(tap), len(manifest) + 1))
    for m in manifest:
        print('   %-24s -> %04X%s' % (os.path.basename(m['file']), m['addr'],
                                      '' if m['bank'] is None
                                      else '  банк %d' % m['bank']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
