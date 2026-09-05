"""
Build the .tap.

The sprites alone outgrow a Spectrum's fixed map twice over, so they live in
RAM banks and the loader has to put them there.  The loader is BASIC, and the
one statement that would do it directly -- OUT to the paging port -- is also
the one thing this build cannot try out before it ships, so it does not use
it.  The program is loaded first and paged the banks itself, four bytes of it
per bank, called through RANDOMIZE USR.  CLEAR, LOAD and RANDOMIZE USR are all
that is left, and those are proven.

Load in 128 mode: entering 48 BASIC locks paging until a hard reset.

Writes a manifest beside the tape so the emulator can place the blocks the
same way without pretending to be a tape.

Usage: maketap.py <out.tap> <code.bin> <org> [bank:file ...]
"""
import json
import os
import sys

import taputil as t

PAGE_WINDOW = 0xC000
STUB = 4                        # bytes per paging stub in the program


def main(argv):
    out, binary, org = argv[1], argv[2], int(argv[3])
    banks = [(int(a.split(':')[0]), a.split(':', 1)[1]) for a in argv[4:]]

    lines = [t.line(10, [t.CLEAR] + list(t.number(org - 1))),
             t.line(20, [t.LOAD, ord('"'), ord('"'), t.CODE_T])]
    n = 30
    for i, _ in enumerate(banks):
        lines.append(t.line(n, [t.RANDOMIZE, t.USR]
                            + list(t.number(org + i * STUB))))
        lines.append(t.line(n + 10, [t.LOAD, ord('"'), ord('"'), t.CODE_T]))
        n += 20
    lines.append(t.line(n, [t.RANDOMIZE, t.USR]
                        + list(t.number(org + len(banks) * STUB))))

    tap = t.program_file('pop', b''.join(lines), 10)
    tap += t.code_file('pop', open(binary, 'rb').read(), org)
    manifest = [{'file': binary, 'addr': org, 'bank': None,
                 'entry': org + len(banks) * STUB}]
    for bank, path in banks:
        payload = open(path, 'rb').read()
        tap += t.code_file(os.path.basename(path)[:10], payload, PAGE_WINDOW)
        manifest.append({'file': path, 'addr': PAGE_WINDOW, 'bank': bank})

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
