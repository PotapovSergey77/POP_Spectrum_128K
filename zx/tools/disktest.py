"""
The disk version, booted and played on trdemu.py's Spectrum with its Beta
128: the checks build.sh cannot make.

    disktest.py [--pentagon] [--all]

  - TR-DOS boots the disk (RANDOMIZE USR 15616, RUN), the loader reads the
    program and the banks, and start finds them as they are on the disk,
    DPOS at the first level's block;
  - past the titles and the controls, Q to the next level: every block
    levelgo reads is the one the disk has, where the tape put it (--all:
    on through every level to the ending, and from the Epilog back to the
    titles);
  - the hour run out: PlayCut6, its tune, and the titles again.

Pictures of the way into build/png/disk_*.png.

Q is the test key, only in a build made for testing:
    POP_TESTKEY=1 sh build.sh
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ZX = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import maketrd      # noqa: E402
import trdemu       # noqa: E402
import zxscreen     # noqa: E402

TEMIN = 0x5C3B


def shot(m, name):
    zxscreen.preview(m.screen(), os.path.join(ZX, 'build', 'png',
                                              'disk_%s.png' % name))


def check(ok, what):
    print('%s  %s' % ('ok  ' if ok else 'FAIL', what))
    if not ok:
        raise SystemExit(1)


def main(argv):
    os.chdir(ZX)
    os.makedirs('build/png', exist_ok=True)
    sym = json.load(open('build/disk/sym.json'))
    if 'nextlevkey' not in sym:
        raise SystemExit('no test key in this build: POP_TESTKEY=1 sh build.sh')
    lay = json.load(open('build/disk/trd.json'))
    disk = lambda p: p.replace('build/bin', 'build/disk/bin')
    m = trdemu.Machine('build/pop.trd', pentagon='--pentagon' in argv)
    m.boot_trdos()
    why = m.run(frames=3000, until=lambda pc: pc == sym['start'])
    check(why == 'until', 'TR-DOS и загрузчик дошли до start за %d кадров' % m.frames)
    main_bin = open('build/disk/pop.bin', 'rb').read()
    check(bytes(m.mem[0x5F00 + i] for i in range(len(main_bin))) == main_bin,
          'программа на месте')
    for b, p in lay['banks']:
        d = open(disk(p), 'rb').read()
        check(bytes(m.banks[b][:len(d)]) == d, 'банк %d на месте' % b)
    check(m.peekw(sym['DPOS']) == maketrd.enc(lay['pos']['blocks'][0]),
          'DPOS у первого блока уровней')

    m.run(frames=100)
    shot(m, '1_titles')
    m.type_keys(['space'])
    m.run(frames=50)
    m.type_keys(['0'])
    m.run(frames=100)
    shot(m, '2_level1')
    check(m.peek(sym['curlev']) == 0 and m.peek(sym['lvflag']) == 1, 'первый уровень')

    # every block levelgo reads, against the disk's
    blocks = [disk(b) for b in lay['blocks']]
    at = {'n': 0}

    def entry(mm):
        at['hl'] = mm.R[6] << 8 | mm.R[7]
        at['de'] = mm.R[4] << 8 | mm.R[5]

    def done(mm):
        data = open(blocks[at['n']], 'rb').read()
        got = bytes(mm.mem[(at['hl'] + i) & 0xFFFF] for i in range(at['de']))
        check(got == data, 'блок %s в %04X' % (os.path.basename(blocks[at['n']]),
                                              at['hl']))
        at['n'] += 1

    m.traps[sym['tapeblk']] = entry
    m.traps[sym['tapeblk'] + 7] = done          # after call dload
    last = 14 if '--all' in argv else 2
    for lev in range(1, last + 1):
        m.type_keys(['q'])
        for k in range(100):
            m.run(frames=50)
            if lev < 14 and m.peek(sym['curlev']) != lev - 1:
                break
            if lev == 14 and m.peek(sym['curlev']) == 0:
                break                           # the Epilog, and the titles
            if k % 4 == 3:
                m.type_keys(['space'])
        m.run(frames=150)
        if lev < 14:
            check(m.peek(sym['curlev']) == lev, 'уровень %d' % (lev + 1))
            if lev == 1:
                state = m.state()
        else:
            check(m.peek(sym['curlev']) == 0, 'после Эпилога снова заставка')
            shot(m, '4_after_epilog')
    shot(m, '3_level2' if last == 2 else '3_last')
    if last != 2:
        m.restore(state)
    m.traps.clear()

    # the hour run out
    m.banks[5][TEMIN - 0x4000] = 60
    why = m.run(frames=300, until=lambda pc: pc == sym['LDRORG'] + 3)
    check(why == 'until', 'час вышел: загрузчик идёт за PlayCut6')
    m.run(frames=100)
    shot(m, '5_cut6')
    tones = set()
    for _ in range(60):
        m.run(frames=10)
        if m.ay[9]:
            tones.add(m.ay[2] | m.ay[3] << 8)
    check(len(tones) > 3, 'PlayCut6 играет s_Tragic: %d нот' % len(tones))
    why = m.run(frames=3000, until=lambda pc: pc == sym['LDRORG'])
    check(why == 'until', 'после PlayCut6 загрузчик снова')
    why = m.run(frames=1000, until=lambda pc: pc == sym['start'])
    check(why == 'until', 'и игра с начала')
    m.run(frames=150)
    shot(m, '6_titles_again')
    check(m.peek(TEMIN) == 0, 'часы снова на часе')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
