"""
Drive the prince through a set of situations and print where each one ends.

A quick way to see that the boundaries hold: what he does at a wall, at the
edge of a floor, hanging, and so on.

Usage: scenes.py <tap> [name ...]
"""
import json
import os
import sys

import runtap

SCENES = [
    ('в стену справа',      120, ['right@2-200']),
    ('к обрыву слева',      120, ['left@2-45']),
    ('аккуратный шаг',      160, ['left@2-20', 'shift@40-200',
                                  'left@42-45', 'left@70-73', 'left@98-101']),
    ('шаг с края',          200, ['left@2-20', 'shift@40-120',
                                  'left@42-45', 'left@70-73',
                                  'down@140-150']),
    ('прыжок вверх',        120, ['up@40-50']),
    ('прыжок с места',       90, ['left@40-70', 'up@40-70']),
    ('прыжок с разбега',    120, ['left@2-90', 'up@30-40']),
    ('присесть и встать',   100, ['down@20-40']),
]


def main(argv):
    tap = argv[1]
    want = argv[2:]
    here = os.path.dirname(os.path.abspath(__file__))
    sym = json.load(open(os.path.join(here, '..', 'build', 'sym.json')))
    keys = ('charx', 'chary', 'blocky', 'charact', 'frame', 'facing')
    print('%-20s %s' % ('сцена', ' '.join('%-7s' % k for k in keys)))
    for name, frames, script in SCENES:
        if want and name not in want:
            continue
        cpu = runtap.boot(tap)
        runtap.play(cpu, frames, runtap.parse(script))
        vals = [cpu.mem[sym[k]] for k in keys]
        print('%-20s %s' % (name, ' '.join('%-7d' % v for v in vals)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
