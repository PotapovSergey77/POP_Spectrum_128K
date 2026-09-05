#!/bin/sh
# Build the Spectrum demo: export the assets, assemble, produce a .tap.
set -e
cd "$(dirname "$0")"
python tools/mkassets.py build
cp build/assets.inc build/seqfix.inc build/sprtab.bin build/seqs.bin \
   build/tiles.bin build/floory.bin build/blockof.bin build/shifthi.bin \
   build/shiftlo.bin build/fill.bin build/revtab.bin src/
cd src
../tools/pasmo.exe --bin pop.asm ../build/pop.bin ../build/pop.sym
cd ..
python tools/maketap.py build/pop_game.tap build/pop.bin 24576 \
       6:build/bank_art.bin 0:build/bank_spr.bin
python - <<'PY'
import re, json
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
json.dump(sym, open('build/sym.json', 'w'))
end = sym['dataend'] + 6144
print('фиксированная память: %04X..%04X, до окна банков %d байт'
      % (sym['start'], end, 0xC000 - end))
assert end <= 0xC000, 'рабочий буфер налез на окно банков'
PY
