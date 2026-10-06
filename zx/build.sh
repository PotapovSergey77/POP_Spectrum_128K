#!/bin/sh
# Build the Spectrum demo: export the assets, assemble, produce a .tap and
# a .trd -- the tape and the disk, each assembled for itself (DISK in
# media.inc), the disk first and the tape last, so that what build/ holds
# besides the two -- the symbols, the binaries -- is the tape's, as the
# tools that test it expect.  The disk's are kept in build/disk/.
#
#   build/          the tape, the disk, the symbols, the include files
#   build/bin/      the binaries the assembler pulls in
#   build/disk/     the disk's symbols and binaries
#   build/png/      whatever the diagnostic tools draw
set -e
cd "$(dirname "$0")"
# The version on the controls screen: 0.2 and the first four of the sources'
# hash -- git's tree of zx/ as the files stand, tracked ones
# only, which is `git rev-parse <commit>:zx` for a build from that commit
# unchanged.
VERINDEX="$(pwd)/build/.verindex"
mkdir -p build
rm -f "$VERINDEX"
SRCHASH=$( (GIT_INDEX_FILE=$VERINDEX git read-tree HEAD &&
            GIT_INDEX_FILE=$VERINDEX git add -u . &&
            GIT_INDEX_FILE=$VERINDEX git write-tree --prefix="$(git rev-parse --show-prefix)") 2>/dev/null || echo '????')
rm -f "$VERINDEX"
VERSION="0.2 $(echo "$SRCHASH" | cut -c1-4)"
echo "                db      \"$VERSION\", 0" > src/ctlver.inc
echo "версия: $VERSION ($SRCHASH)"
python tools/mkassets.py build
# what mkassets made, as it made it: each build changes some of it
rm -rf build/bin.mk
cp -r build/bin build/bin.mk

media() {
MEDIA=$1
export MEDIA
rm -rf build/bin
cp -r build/bin.mk build/bin
if [ "$MEDIA" = disk ]; then DISK=1; CUTS="1 2 3 4 5 6"; else DISK=0; CUTS="1 2 3 4 5"; fi
echo "DISK            equ     $DISK" > src/media.inc
# Q, on to the next level, only in a build for testing: POP_TESTKEY=1
echo "TESTKEY         equ     ${POP_TESTKEY:-0}" >> src/media.inc
cp build/cut6.inc src/
cp build/assets.inc build/bg.inc build/cut1.inc build/cut2.inc build/cut3.inc build/cut4.inc build/cut5.inc build/bin/*.bin src/
cp build/cut1.inc src/cutsel.inc
cd src
# The controls screen's words first (ctldata.asm): the game takes their
# addresses from them.
../tools/pasmo.exe --bin ctldata.asm ../build/ctldata.bin ../build/ctldata.sym
python - <<'PY'
import re
with open('ctldata.inc', 'w') as f:
    f.write('; the controls screen words (ctldata.asm): build.sh -- do not edit' + chr(10))
    for line in open('../build/ctldata.sym'):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
        if m:
            f.write('%-15s equ     0x%04X' % (m.group(1), int(m.group(2), 16)) + chr(10))
PY
../tools/pasmo.exe --bin pop.asm ../build/pop.bin ../build/pop.sym
cd ..
# PlayCut1 is a program of its own, loaded off the tape before level two
# (see cut1.asm): what it uses of the game's comes from the game's symbols.
python - <<'PY'
import re
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
def words(path):
    text = ''.join(l.split(';')[0] + ' ' for l in open(path))
    return set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text))
def defined(path):
    return {m.group(1) for l in open(path)
            for m in [re.match(r'([A-Za-z_][A-Za-z0-9_]*)(:|\s+equ\s)', l, re.I)] if m}
used = words('src/cut1.asm') | words('src/cutplay.asm')
own = defined('src/cut1.asm') | defined('src/cutplay.asm') | defined('src/cut1.inc')
own |= (defined('src/dload.asm') | defined('src/dgate.asm') | defined('src/dout.asm')
        | defined('src/media.inc'))
with open('src/popsyms.inc', 'w') as f:
    f.write('; what PlayCut1 uses of the game: build.sh -- do not edit\n')
    for name in sorted((used & set(sym)) - own):
        f.write('%-15s equ     0x%04X\n' % (name, sym[name]))
PY
cd src
for k in $CUTS; do
    cp cut$k.inc cutsel.inc
    cp cutfixed$k.bin cutsel.bin
    ../tools/pasmo.exe --bin cut1.asm ../build/cut${k}code.bin ../build/cut$k.sym
done
cd ..
# Each background set's own code (bgovl.asm), in the background bank with
# its pictures: the same way, the game's symbols for what it uses.
python - <<'PY'
import re
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
text = ''.join(l.split(';')[0] + ' ' for l in open('src/bgovl.asm'))
used = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text))
own = {m.group(1) for l in open('src/bgovl.asm')
       for m in [re.match(r'([A-Za-z_][A-Za-z0-9_]*)(:|\s+equ\s)', l, re.I)] if m}
with open('src/bgsyms.inc', 'w') as f:
    f.write('; what bgovl.asm uses of the game: build.sh -- do not edit\n')
    for name in sorted((used & set(sym)) - own):
        f.write('%-15s equ     0x%04X\n' % (name, sym[name]))
PY
cd src
for s in 0 1; do
    echo "OVLSET          equ     $s" > ovlset.inc
    ../tools/pasmo.exe --bin bgovl.asm ../build/bgovl$s.bin ../build/bgovl$s.sym
done
cd ..
# And each level's own code (lvcode.asm), which rides with its blueprint:
# what it uses of the game's and of the palace's code, their symbols.
python - <<'PY2'
import re
sym = {}
for path in ('build/pop.sym', 'build/bgovl1.sym'):
    for line in open(path):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
        if m:
            sym.setdefault(m.group(1), int(m.group(2), 16))
text = ''.join(l.split(';')[0] + ' ' for l in open('src/lvcode.asm'))
used = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text))
own = {m.group(1) for l in open('src/lvcode.asm')
       for m in [re.match(r'([A-Za-z_][A-Za-z0-9_]*)(:|\s+equ\s)', l, re.I)] if m}
with open('src/lvsyms.inc', 'w') as f:
    f.write('; what lvcode.asm uses of the game: build.sh -- do not edit\n')
    for name in sorted((used & set(sym)) - own):
        f.write('%-15s equ     0x%04X\n' % (name, sym[name]))
PY2
cd src
for n in $(tr -d '\r' < ../build/bin/lvc.lst | awk '{print $3}'); do
    echo "LVNUM           equ     $n" > lvnum.inc
    ../tools/pasmo.exe --bin lvcode.asm ../build/lvcode$n.bin ../build/lvcode$n.sym
done
cd ..
# The control code is assembled at its place in the canvas bank: cut it out
# of the program and put it after the tables it travels up with.
python - <<'PY'
import os, re
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
data = open('build/pop.bin', 'rb').read()
base = sym['stubs']
# The princess's scenes' tape blocks: at 0xC000 a few bytes that put the
# code where it runs and jump there, the room, the pictures and the tune,
# and the code.  The fifth is the ending's, which composes its band past
# its code (CUT_BUFOFF) and never gives the room's code back.
lens = {}
disk = os.environ['MEDIA'] == 'disk'
for k in (1, 2, 3, 4, 5, 6) if disk else (1, 2, 3, 4, 5):
    csym = {}
    for line in open('build/cut%d.sym' % k):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
        if m:
            csym[m.group(1)] = int(m.group(2), 16)
    code = open('build/cut%dcode.bin' % k, 'rb').read()
    cdata = open('build/bin/cut%ddata.bin' % k, 'rb').read()
    org = csym['cut1go']
    assert len(code) == csym['cut1end'] - org
    assert csym['CUT1_CODE'] == 0xC000 + 14 + len(cdata)
    stub = (bytes([0x21]) + csym['CUT1_CODE'].to_bytes(2, 'little')     # ld hl
            + bytes([0x11]) + org.to_bytes(2, 'little')                 # ld de
            + bytes([0x01]) + len(code).to_bytes(2, 'little')           # ld bc
            + bytes([0xED, 0xB0, 0xC3]) + org.to_bytes(2, 'little'))    # ldir, jp
    block = stub + cdata + code
    lens[k] = len(block)
    open('build/bin/cut%d.bin' % k, 'wb').write(block)
    band = sym['roomblk'] + csym['CUT_BUFOFF']
    print('принцесса %d: блок %d байт, код %04X..%04X, свободно до полосы '
          '%d, в банке заставки до распакованного %d'
          % (k, len(block), org, csym['cut1end'], band - csym['cut1end'],
             csym['CUT1_LOW'] - csym['CUT1_CODE']))
    assert csym['cut1end'] <= band, 'принцесса %d налезла на свою полосу' % k
    assert band + csym['BAND_BYTES'] <= sym['HICODE'], 'полоса принцессы %d налезла на код боя' % k
    # the code goes to where it runs before anything is unpacked: only what
    # is read after that -- the room, the pictures, the tune -- must stay
    # below what the unpacking writes
    assert csym['CUT1_CODE'] <= csym['CUT1_LOW'], 'принцесса %d не влезла в банк' % k
    assert csym['RB1LEN'] <= 3275
assert sym['TAILLEN'] <= sym['RB1LEN'], 'надписи заставки длиннее кода постройки комнаты'
# and each scene's length into the head of the level before it, which
# levelgo reads it from (LH_CUT)
for line in open('build/bin/cuts.lst'):
    if not line.strip():
        continue
    path, off, k = line.split()
    b = bytearray(open(path, 'rb').read())
    b[int(off):int(off) + 2] = lens[int(k)].to_bytes(2, 'little')
    open(path, 'wb').write(b)
# levelgo loads a level's character set into the art bank past the scene
# that came before it on the tape, and puts it away before the scene plays
tape = [t.strip() for t in open('build/bin/tape.lst') if t.strip()]
for i, t in enumerate(tape):
    m = re.match(r'build/bin/cut(\d+)\.bin$', t)
    if m and i + 2 < len(tape) and 'chset' in tape[i + 2]:
        assert 0xC000 + lens[int(m.group(1))] + os.path.getsize(tape[i + 2]) \
            <= 0x10000 - 12, 'a scene and the character set after it are over the art bank'
mod = data[sym['MODORG'] - base:sym['modend'] - base]
assert len(mod) == sym['MODLEN'], 'the control code did not come out whole'
# The canvas bank's own code, assembled at CODE1, rides at the end of the
# art bank's block, past the titles' music, for start to put in place.
c1 = data[sym['CODE1'] - base:sym['c1end'] - base]
# The disk's code (dload.asm), assembled where it runs, past the room's code,
# rides in the canvas bank's: in DRVIMG, kept for it.
if disk:
    drv = data[sym['drvorg'] - base:sym['drvend'] - base]
    assert sym['drvorg'] == sym['roomend'] and sym['drvend'] <= sym['HICODE']
    assert len(drv) <= sym['DRVMAX'], 'код диска длиннее DRVMAX: %d' % len(drv)
    off = sym['DRVIMG'] - sym['CODE1']
    assert not any(c1[off:off + sym['DRVMAX']])
    c1 = c1[:off] + drv + c1[off + len(drv):]
    print('код диска %d байт из %d' % (len(drv), sym['DRVMAX']))
assert len(c1) == sym['C1LEN'] <= sym['CODE1_MAX'], 'код банка холста не влез'
art = open('build/bin/bank_art.bin', 'rb').read()
assert 0xC000 + len(art) == sym['C1ART'], 'банк заставки не той длины'
assert sym['C1ART'] + len(c1) <= 0x10000 - 12, 'код банка холста не влез в банк заставки'
assert len(c1) <= sym['RB1LEN'], 'код банка холста длиннее кода постройки комнаты'
assert sym['c1end'] <= sym['MODORG'], 'код банка холста налез на управление в образе программы'
# and past it, at the top of the bank, the controls screen's words
cm = open('build/ctldata.bin', 'rb').read()
assert sym['C1ART'] + len(c1) <= sym['CMDATA'], 'код банка холста налез на слова экрана управления'
assert sym['CMDATA'] + len(cm) <= 0x10000 - 12, 'слова экрана управления не влезли в банк заставки'
open('build/bin/bank_art.bin', 'wb').write(art + c1 + bytes(sym['CMDATA'] - sym['C1ART'] - len(c1)) + cm)
print('слова экрана управления %04X..%04X' % (sym['CMDATA'], sym['CMDATA'] + len(cm)))
print('код банка холста %04X..%04X, %d байт, свободно там %d'
      % (sym['CODE1'], sym['c1end'], len(c1), sym['CODE1_MAX'] - len(c1)))
# The fight sits past the working copy, and the tape carries a gap to it.
open('build/pop.bin', 'wb').write(data[:sym['roomend'] - base]
                                  + bytes(sym['HICODE'] - sym['roomend'])
                                  + data[sym['HICODE'] - base:sym['hiend'] - base])
print('бой %04X..%04X, %d байт, свободно там %d'
      % (sym['HICODE'], sym['hiend'], sym['hiend'] - sym['HICODE'],
         0xC000 - sym['hiend']))
assert sym['hiend'] <= 0xC000, 'the fight does not fit under the window'
spare = open('build/bin/bank_spare.bin', 'rb').read()
assert len(spare) == sym['SPARE_LEN'], 'the tables are not where MODORG says'
open('build/bin/bank_spare.bin', 'wb').write(spare + mod)
# The sets' code into the bank's image and the blocks that bring a set.
ovl = [open('build/bgovl%d.bin' % s, 'rb').read() for s in (0, 1)]
for s, o in enumerate(ovl):
    assert len(o) <= sym['BGOVL_LEN'], 'код набора %d длиннее BGOVL_LEN' % s
print('код наборов: подземелье %d, дворец %d байт из %d'
      % (len(ovl[0]), len(ovl[1]), sym['BGOVL_LEN']))
for line in open('build/bin/ovl.lst'):
    if not line.strip():
        continue
    path, off, s = line.split()
    off, s = int(off), int(s)
    b = bytearray(open(path, 'rb').read())
    assert not any(b[off:off + sym['BGOVL_LEN']]), path
    b[off:off + len(ovl[s])] = ovl[s]
    open(path, 'wb').write(b)
# Each level's own code into its block.
for line in open('build/bin/lvc.lst'):
    if not line.strip():
        continue
    path, off, n = line.split()
    off = int(off)
    code = open('build/lvcode%s.bin' % n, 'rb').read()
    lsym = {}
    for l in open('build/lvcode%s.sym' % n):
        m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', l.strip())
        if m:
            lsym[m.group(1)] = int(m.group(2), 16)
    assert lsym['post'] == lsym['lvcode'], 'уровень %s: вход не в начале' % n
    b = bytearray(open(path, 'rb').read())
    # a dungeon level may have most of its code where the dungeon's pictures
    # leave room before the blueprint (lvlow at dunfree, up to lvlowend),
    # in its block when the level brings the set with it
    low = 0
    if 'lvlow' in lsym:
        assert lsym['lvlow'] == sym['dunfree'] and lsym['lvlowend'] <= sym['level'], n
        low = lsym['lvlowend'] - lsym['lvlow']
        at = off - (lsym['lvcode'] - lsym['lvlow'])
        assert at >= 0, 'уровень %s: набора нет в блоке' % n
        assert not any(b[at:at + low]), path
        assert not any(code[low:lsym['lvcode'] - lsym['lvlow']])
        b[at:at + low] = code[:low]
        code = code[lsym['lvcode'] - lsym['lvlow']:]
    # the last byte of the room is the level's basicstrength (LVSTR)
    assert len(code) <= sym['LVCODE_LEN'] - 1, 'код уровня %s длиннее LVCODE_LEN' % n
    assert not any(b[off:off + sym['LVCODE_LEN'] - 1]), path
    assert 3 <= b[off + sym['LVCODE_LEN'] - 1] <= 6, path
    b[off:off + len(code)] = code
    open(path, 'wb').write(b)
    print('код уровня %s: %d байт из %d%s' % (n, len(code), sym['LVCODE_LEN'] - 1,
          ', и %d за картинками подземелья из %d' % (low, sym['level'] - sym['dunfree'])
          if low else ''))
print('управление %04X..%04X, %d байт в банке 7, свободно там %d'
      % (sym['MODORG'], sym['modend'], len(mod), 0x10000 - sym['modend']))
assert sym['modend'] <= 0x10000, 'the control code does not fit the canvas bank'
assert sym['modend'] <= 0x10000 - 12 and sym['modend'] > sym['MODORG'], 'the control code does not fit under the interrupt stub'
PY
if [ "$MEDIA" = tape ]; then
python tools/maketap.py build/pop.tap build/pop.bin 24320       6:build/bin/bank_art.bin 0:build/bin/bank_spr1.bin        4:build/bin/bank_spr2.bin 1:build/bin/bank_spr3.bin 3:build/bin/bank_bg.bin 7:build/bin/bank_spare.bin $(tr -d '\r' < build/bin/tape.lst | sed 's/^/L:/')
else
python tools/mkdisk.py
fi
python - <<'PY'
import re, json, os
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
json.dump(sym, open('build/sym.json', 'w'))
json.dump(sym, open('build/pop.sym.json', 'w'))    # the tape's own, which runtap and fuselike read first
work = sym['work'] + 6144
print('код %04X..%04X, рабочий буфер %04X..%04X, до него свободно %d байт,'
      ' и %d перед таблицами сдвигов'
      % (sym['stubs'], sym['codeend'], sym['work'], work,
         sym['work'] - sym['codeend'], sym['shifthi'] - sym['flamemask'] - 6))
print('пуск %04X..%04X, в рабочем буфере' % (sym['start'], sym['initend']))
assert sym['initend'] <= 0xC000, 'пуск не влез'
rb = sym['roomend'] - sym['roomblk']
room = min(0x10000 - 12 - sym['RBINTRO'], sym['CODE1'] - sym['RBAT1'])
print('постройка комнаты %04X..%04X, %d байт, в банках места %d'
      % (sym['roomblk'], sym['roomend'], rb, room))
assert rb <= room, 'код постройки комнаты не влез в банки'
assert sym['roomend'] <= sym['HICODE'], 'код постройки комнаты налез на код боя'
assert sym['work'] % 0x800 == 0, 'рабочий буфер не на границе 2K'
assert sym['BAND_BYTES'] + sym['CUT_BUFOFF'] <= rb, 'полоса принцессы больше кода постройки комнаты'
print('буферы под загрузчиком %04X..%04X, %d байт'
      % (sym['LOWBUF'], sym['LOWTOP'], sym['LOWTOP'] - sym['LOWBUF']))
assert sym['LOWTOP'] <= sym['stubs'], 'буферы под загрузчиком налезли на код'
d6 = sym['dfl6cut'] - sym['dflcut']
assert all(sym[a + '6'] - sym[a] == d6 for a in ('dfleft', 'dfmirror')) and sym['dfm6cut'] - sym['dfmcut'] == d6, 'двойники сдвига на шесть не на месте'
assert sym['SLEND'] <= sym['CODE1'], 'картинки ножниц налезли на код банка холста'
assert sym["SLCOMMON"] + 4 * sym["SLBAND"] <= 0x10000 - 12, 'ножницы не влезли за код банка холста'
assert sym['LOWSTACK'] >= 23755, 'буферы под загрузчиком залезли в переменные ПЗУ'
assert sym['blockbot'] & 0xff <= 0xff - 7, 'blockbot не на одной странице'
assert sym['SYSVARS'] >= 23675 and sym['SYSVARS'] + sym['SYSVARLEN'] <= sym['LOWVARS'], 'переменные в системных налезли'
assert sym['gdlast'] + 10 <= sym['LOWSTACK'], 'гдласт залез в стек'
assert sym['LOWVARS'] + sym['LOWVARLEN'] <= 23755, 'переменные рисования налезли на стек'
assert work <= sym['HICODE'], 'рабочий буфер налез на код боя'
PY
# the disk's own symbols and binaries, kept from the tape's that follow
if [ "$MEDIA" = disk ]; then
    rm -rf build/disk
    mkdir -p build/disk
    cp -r build/bin build/disk/bin
    cp build/pop.bin build/pop.sym build/sym.json build/loader.bin build/loader.sym \
       build/cut6.sym build/cut5.sym build/cut1.sym build/trd.json build/disk/
fi
}

media disk
media tape
