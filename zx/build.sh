#!/bin/sh
# Build the Spectrum demo: export the assets, assemble, produce a .tap.
set -e
cd "$(dirname "$0")"
python tools/mkassets.py build
cp build/assets.inc build/seqfix.inc build/sprtab.bin build/seqs.bin \
   build/tiles.bin build/floory.bin build/blockof.bin build/shifthi.bin \
   build/shiftlo.bin build/fill.bin build/revtab.bin \
   build/bank_art.bin build/bank_spr.bin src/
cd src
../tools/pasmo.exe --tapbas pop.asm ../build/pop_game.tap ../build/pop.sym
cd ..
python - <<'PY'
import re, json, os
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
json.dump(sym, open('build/sym.json', 'w'))
work = sym['work'] + 6144
print('код %04X..%04X, рабочий буфер до %04X, комната %04X..%04X'
      % (sym['start'], sym['codeend'], work, sym['stage_art'], sym['stage_end']))
print('спрайты %04X..%04X, тап %d байт'
      % (sym['stage_spr'], sym['spr_end'], os.path.getsize('build/pop_game.tap')))
assert sym['stage_spr'] == 0xC000, 'спрайты должны начинаться ровно на границе банка'
assert sym['stage_end'] <= 0xC000, 'комната налезла на окно банков'
assert work <= sym['stage_end'], 'рабочий буфер вылез за образ комнаты'
PY
