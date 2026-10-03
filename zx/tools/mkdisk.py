"""
The disk's last steps, from build.sh once the program and its blocks are
made: where everything goes on the disk (maketrd.layout), the loader
assembled knowing it (loader.asm, with ldr.inc and ldrbanks.inc), and the
disk itself, build/pop.trd.
"""
import json
import os
import re
import subprocess
import sys

import maketrd

HERE = os.path.dirname(os.path.abspath(__file__))
ZX = os.path.dirname(HERE)

# The banks in the order the tape had them, which is the order they are
# read off the disk.
BANKS = [(6, 'build/bin/bank_art.bin'), (0, 'build/bin/bank_spr1.bin'),
         (4, 'build/bin/bank_spr2.bin'), (1, 'build/bin/bank_spr3.bin'),
         (3, 'build/bin/bank_bg.bin'), (7, 'build/bin/bank_spare.bin')]


def symbols(path):
    sym = {}
    for line in open(path):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
        if m:
            sym[m.group(1)] = int(m.group(2), 16)
    return sym


def main():
    os.chdir(ZX)
    sym = symbols('build/pop.sym')
    blocks = [t.strip() for t in open('build/bin/tape.lst') if t.strip()]
    size = os.path.getsize
    pos = maketrd.layout(size('build/pop.bin'), [size(p) for _, p in BANKS],
                         [size(b) for b in blocks], size('build/bin/cut6.bin'))
    assert maketrd.LDRPOS == sym['LDRPOS'], 'LDRPOS не тот, что на диске'
    assert maketrd.LDR_BODY == sym['LDRLOAD'], 'LDRLOAD не тот, что на диске'
    assert sym['DPOS'] + 2 <= sym['stubs'], 'DPOS налез на программу'
    inc = [('LDRORG', sym['LDRORG']), ('LDRSTACK', sym['DPOS']),
           ('GDPOS', sym['DPOS']), ('START', sym['start']),
           ('MAINORG', sym['stubs']), ('MAINPOS', maketrd.enc(pos['main'])),
           ('MAINLEN', size('build/pop.bin')),
           ('CUT6POS', maketrd.enc(pos['cut6'])),
           ('CUT6LEN', size('build/bin/cut6.bin')),
           ('BANK_ART', sym['BANK_ART'])]
    with open('src/ldr.inc', 'w', newline='\n') as f:
        f.write('; where things are on the disk: mkdisk.py -- do not edit\n')
        for k, v in inc:
            f.write('%-15s equ     0x%04X\n' % (k, v))
    with open('src/ldrbanks.inc', 'w', newline='\n') as f:
        f.write('; the banks, as the disk has them: mkdisk.py -- do not edit\n')
        for b, p in BANKS:
            f.write('                db      %d\n                dw      %d\n'
                    % (b, size(p)))
    subprocess.check_call([os.path.join(HERE, 'pasmo.exe'), '--bin',
                           'loader.asm', '../build/loader.bin',
                           '../build/loader.sym'], cwd='src')
    lsym = symbols('build/loader.sym')
    n = size('build/loader.bin')
    assert n == lsym['ldrend'] - lsym['LDRORG']
    assert n <= maketrd.LDR_BODY, 'загрузчик длиннее двух секторов: %d' % n
    assert lsym['ldrend'] + 32 <= lsym['LDRSTACK'], 'стек загрузчика налез на него'
    print('загрузчик %04X..%04X, %d байт' % (lsym['LDRORG'], lsym['ldrend'], n))
    json.dump({'loader': 'build/loader.bin', 'ldrorg': sym['LDRORG'],
               'main': 'build/pop.bin', 'org': sym['stubs'], 'banks': BANKS,
               'blocks': blocks, 'cut6': 'build/bin/cut6.bin', 'pos': pos},
              open('build/trd.json', 'w'))
    print('диск: программа с сектора %d, банки с %d, уровни с %d, PlayCut6 '
          'с %d, всего %d' % (pos['main'], pos['banks'][0], pos['blocks'][0],
                              pos['cut6'], pos['end']))
    return maketrd.main(['maketrd.py', 'build/pop.trd', 'build/trd.json'])


if __name__ == '__main__':
    sys.exit(main())
