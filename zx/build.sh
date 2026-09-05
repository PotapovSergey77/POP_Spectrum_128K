#!/bin/sh
# Build the Spectrum demo: export the assets, assemble, produce a .tap.
set -e
cd "$(dirname "$0")"
python tools/mkassets.py build
cp build/assets.inc build/seqfix.inc build/room.bin build/sprites.bin build/seqs.bin build/tiles.bin build/floory.bin build/blockof.bin build/foremask.bin build/shifthi.bin build/shiftlo.bin build/fill.bin build/revtab.bin src/
cd src
../tools/pasmo.exe --tapbas pop.asm ../build/pop_game.tap ../build/pop.sym
cd ..
python - <<'PY'
import re, json
sym = {}
for line in open('build/pop.sym'):
    m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
json.dump(sym, open('build/sym.json', 'w'))
PY
ls -l build/pop_game.tap
