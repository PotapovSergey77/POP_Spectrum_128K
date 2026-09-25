#!/bin/sh
# Build the Spectrum demo: export the assets, assemble, produce a .tap.
#
#   build/          the tape, its symbols, and the two include files
#   build/bin/      the binaries the assembler pulls in
#   build/png/      whatever the diagnostic tools draw
set -e
cd "$(dirname "$0")"
python tools/mkassets.py build
cp build/assets.inc build/bg.inc build/cut1.inc build/bin/*.bin src/
cd src
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
with open('src/popsyms.inc', 'w') as f:
    f.write('; what PlayCut1 uses of the game: build.sh -- do not edit\n')
    for name in sorted((used & set(sym)) - own):
        f.write('%-15s equ     0x%04X\n' % (name, sym[name]))
PY
cd src
../tools/pasmo.exe --bin cut1.asm ../build/cut1code.bin ../build/cut1.sym
cd ..
# The control code is assembled at its place in the canvas bank: cut it out
# of the program and put it after the tables it travels up with.
python - <<'PY'
import re
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
data = open('build/pop.bin', 'rb').read()
base = sym['stubs']
# PlayCut1's tape block: at 0xC000 a few bytes that put its code where it
# runs and jump there, the room, the pictures and the tune, and the code.
csym = {}
for line in open('build/cut1.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        csym[m.group(1)] = int(m.group(2), 16)
code = open('build/cut1code.bin', 'rb').read()
cdata = open('build/bin/cut1data.bin', 'rb').read()
org = csym['cut1go']
assert len(code) == csym['cut1end'] - org
assert csym['CUT1_CODE'] == 0xC000 + 14 + len(cdata)
stub = (bytes([0x21]) + csym['CUT1_CODE'].to_bytes(2, 'little')     # ld hl
        + bytes([0x11]) + org.to_bytes(2, 'little')                 # ld de
        + bytes([0x01]) + len(code).to_bytes(2, 'little')           # ld bc
        + bytes([0xED, 0xB0, 0xC3]) + org.to_bytes(2, 'little'))    # ldir, jp
block = stub + cdata + code
open('build/bin/cut1.bin', 'wb').write(block)
print('принцесса 1: блок %d байт, код %04X..%04X, свободно до постройки '
      'комнаты %d, в банке заставки до распакованного %d'
      % (len(block), org, csym['cut1end'], sym['roomblk'] - csym['cut1end'],
         csym['CUT1_LOW'] - 0xC000 - len(block)))
assert csym['cut1end'] <= sym['roomblk'], 'принцесса 1 налезла на постройку комнаты'
assert 0xC000 + len(block) <= csym['CUT1_LOW'], 'принцесса 1 не влезла в банк'
assert csym['RB1LEN'] <= 3275
assert sym['PORTLEN'] <= sym['RB1LEN'], 'надпись порта длиннее кода постройки комнаты'
at = sym['cut1len'] + 1 - base          # levelgo's LD-BYTES length
data = data[:at] + len(block).to_bytes(2, 'little') + data[at + 2:]
mod = data[sym['MODORG'] - base:sym['modend'] - base]
assert len(mod) == sym['MODLEN'], 'the control code did not come out whole'
# The canvas bank's own code, assembled at CODE1, rides at the end of the
# art bank's block, past the titles' music, for start to put in place.
c1 = data[sym['CODE1'] - base:sym['c1end'] - base]
assert len(c1) == sym['C1LEN'] <= sym['CODE1_MAX'], 'код банка холста не влез'
art = open('build/bin/bank_art.bin', 'rb').read()
assert 0xC000 + len(art) == sym['C1ART'], 'банк заставки не той длины'
assert sym['C1ART'] + len(c1) <= 0x10000 - 12, 'код банка холста не влез в банк заставки'
assert len(c1) <= sym['RB1LEN'], 'код банка холста длиннее кода постройки комнаты'
open('build/bin/bank_art.bin', 'wb').write(art + c1)
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
print('управление %04X..%04X, %d байт в банке 7, свободно там %d'
      % (sym['MODORG'], sym['modend'], len(mod), 0x10000 - sym['modend']))
assert sym['modend'] <= 0x10000, 'the control code does not fit the canvas bank'
assert sym['modend'] <= 0x10000 - 12 and sym['modend'] > sym['MODORG'], 'the control code does not fit under the interrupt stub'
PY
python tools/maketap.py build/pop.tap build/pop.bin 24320       6:build/bin/bank_art.bin 0:build/bin/bank_spr1.bin        4:build/bin/bank_spr2.bin 1:build/bin/bank_spr3.bin 3:build/bin/bank_bg.bin 7:build/bin/bank_spare.bin L:build/bin/cut1.bin $(tr -d '\r' < build/bin/tape.lst | sed 's/^/L:/')
python - <<'PY'
import re, json, os
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
json.dump(sym, open('build/sym.json', 'w'))
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
assert sym['BAND_BYTES'] <= rb, 'полоса принцессы больше кода постройки комнаты'
print('буферы под загрузчиком %04X..%04X, %d байт'
      % (sym['LOWBUF'], sym['LOWTOP'], sym['LOWTOP'] - sym['LOWBUF']))
assert sym['LOWTOP'] <= sym['stubs'], 'буферы под загрузчиком налезли на код'
assert sym['SLEND'] <= sym['CODE1'], 'картинки ножниц налезли на код банка холста'
assert sym["SLCOMMON"] + 4 * sym["SLBAND"] <= 0x10000 - 12, 'ножницы не влезли за код банка холста'
assert sym['LOWSTACK'] >= 23755, 'буферы под загрузчиком залезли в переменные ПЗУ'
assert sym['blockbot'] & 0xff <= 0xff - 7, 'blockbot не на одной странице'
assert sym['SYSVARS'] >= 23675 and sym['SYSVARS'] + sym['SYSVARLEN'] <= sym['LOWVARS'], 'переменные в системных налезли'
assert sym['gdlast'] + 10 <= sym['LOWSTACK'], 'гдласт залез в стек'
assert sym['LOWVARS'] + sym['LOWVARLEN'] <= 23755, 'переменные рисования налезли на стек'
assert work <= sym['HICODE'], 'рабочий буфер налез на код боя'
PY
