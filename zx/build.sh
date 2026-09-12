#!/bin/sh
# Build the Spectrum demo: export the assets, assemble, produce a .tap.
#
#   build/          the tape, its symbols, and the two include files
#   build/bin/      the binaries the assembler pulls in
#   build/png/      whatever the diagnostic tools draw
set -e
cd "$(dirname "$0")"
python tools/mkassets.py build
cp build/assets.inc build/bg.inc build/bin/*.bin src/
cd src
../tools/pasmo.exe --bin pop.asm ../build/pop.bin ../build/pop.sym
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
mod = data[sym['MODORG'] - base:sym['modend'] - base]
assert len(mod) == sym['MODLEN'], 'the control code did not come out whole'
open('build/pop.bin', 'wb').write(data[:sym['roomend'] - base])
spare = open('build/bin/bank_spare.bin', 'rb').read()
assert len(spare) == sym['SPARE_LEN'], 'the tables are not where MODORG says'
open('build/bin/bank_spare.bin', 'wb').write(spare + mod)
print('управление %04X..%04X, %d байт в банке 7, свободно там %d'
      % (sym['MODORG'], sym['modend'], len(mod), 0x10000 - sym['modend']))
assert sym['modend'] <= 0x10000, 'the control code does not fit the canvas bank'
PY
python tools/maketap.py build/pop.tap build/pop.bin 24320       6:build/bin/bank_art.bin 0:build/bin/bank_spr1.bin        4:build/bin/bank_spr2.bin 1:build/bin/bank_spr3.bin 3:build/bin/bank_bg.bin 7:build/bin/bank_spare.bin
python - <<'PY'
import re, json, os
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
json.dump(sym, open('build/sym.json', 'w'))
work = sym['work'] + 6144
print('код %04X..%04X, рабочий буфер %04X..%04X, до него свободно %d байт'
      % (sym['stubs'], sym['codeend'], sym['work'], work,
         sym['work'] - sym['codeend']))
print('пуск %04X..%04X, в рабочем буфере' % (sym['start'], sym['initend']))
assert sym['initend'] <= 0xC000, 'пуск не влез'
rb = sym['roomend'] - sym['roomblk']
room = 0x10000 - sym['RBAT1']
print('постройка комнаты %04X..%04X, %d байт, в банках места %d'
      % (sym['roomblk'], sym['roomend'], rb, room))
assert rb <= room, 'код постройки комнаты не влез в банки'
assert sym['roomblk'] + room <= 0xC000, 'код постройки комнаты вылез из буфера'
assert sym['work'] % 0x800 == 0, 'рабочий буфер не на границе 2K'
print('буферы под загрузчиком %04X..%04X, %d байт'
      % (sym['LOWBUF'], sym['LOWTOP'], sym['LOWTOP'] - sym['LOWBUF']))
assert sym['LOWTOP'] <= sym['stubs'], 'буферы под загрузчиком налезли на код'
assert sym['LOWBUF'] >= 23755, 'буферы под загрузчиком залезли в переменные ПЗУ'
assert work <= 0xC000, 'рабочий буфер налез на окно банков'
PY
