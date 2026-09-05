"""
Build the .tap.

The sprites alone outgrow a Spectrum's fixed map several times over, so they
live in RAM banks and the loader has to put them there.  48K BASIC cannot:
entering it locks paging until a hard reset.  Under 128 BASIC it can, as long
as it leaves bit 4 of the paging port alone -- that bit picks the ROM, and
setting it pulls the 128 editor out from under the statement doing the
setting.  So the loader is one line per bank, and each writes the bank number
and nothing else.

Writes a manifest beside the tape so the emulator can place the blocks the
same way without pretending to be a tape.

Usage: maketap.py <out.tap> <code.bin> <org> [bank:file ...]
"""
import json
import os
import sys

import taputil as t

PAGE_WINDOW = 0xC000
PAGE_PORT = 32765


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

    tap = t.program_file('pop', b''.join(lines), 10)
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
        print('   %-18s -> %04X%s' % (os.path.basename(m['file']), m['addr'],
                                      '' if m['bank'] is None
                                      else '  банк %d' % m['bank']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
