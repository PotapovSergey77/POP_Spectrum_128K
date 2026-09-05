"""
Run the demo in the little Z80 core and save what it drew.

Loads the CODE block out of a .tap, starts at the address in its header, runs
a number of game frames and writes the screen as a PNG -- so a build can be
checked before it goes anywhere near a real Spectrum.

Keys are given as name@first-last in game frames, or bare for the whole run:

    runtap.py build/pop.tap out.png 200 left@0-45 up@70-73 down@165-175

Usage: runtap.py <tap> [out.png] [frames] [key ...]
"""
import struct
import sys

import pngwrite
import z80
import zxscreen

# Half rows and bit within them, as the hardware sees them.
KEYS = {
    'left': (0xF7FE, 4),        # key 5
    'right': (0xEFFE, 2),       # key 8
    'up': (0xEFFE, 3),          # key 7
    'down': (0xEFFE, 4),        # key 6
    'space': (0x7FFE, 0),
}


def load_tap(path):
    """The last CODE block, which is the program itself."""
    for addr, payload in code_blocks(path):
        pass
    return addr, payload


def code_blocks(path):
    """Every CODE block in the tape, in order, as (load address, bytes)."""
    data = open(path, 'rb').read()
    blocks, i = [], 0
    while i < len(data):
        n = struct.unpack_from('<H', data, i)[0]
        blocks.append(data[i + 2:i + 2 + n])
        i += 2 + n
    out = []
    for j, b in enumerate(blocks):
        if b[0] == 0 and b[1] == 3:                 # CODE header
            out.append((struct.unpack_from('<H', b, 14)[0],
                        blocks[j + 1][1:-1]))
    if not out:
        raise SystemExit('%s: no CODE block' % path)
    return out


def boot(path):
    """A CPU with the tape's CODE loaded and no key held."""
    cpu = z80.Z80()
    start = None
    for addr, payload in code_blocks(path):
        cpu.mem[addr:addr + len(payload)] = payload
        start = addr
    cpu.pc = start
    release(cpu)
    return cpu


def release(cpu):
    for row in set(r for r, _ in KEYS.values()):
        cpu.ports[row] = 0xFF


def parse(args):
    """[(name, first frame, last frame)] out of the command line."""
    out = []
    for a in args:
        name, _, span = a.partition('@')
        if name not in KEYS:
            raise SystemExit('unknown key %r' % name)
        if not span:
            out.append((name, 0, 1 << 30))
            continue
        first, _, last = span.partition('-')
        out.append((name, int(first), int(last or first)))
    return out


def play(cpu, frames, script, limit=400000):
    """Run `frames` game frames, holding each key over its own span."""
    steps = 0
    for n in range(frames):
        release(cpu)
        for name, a, b in script:
            if a <= n <= b:
                row, bit = KEYS[name]
                cpu.ports[row] &= ~(1 << bit) & 0xFF
        before = cpu.frames
        steps += cpu.run(1, limit=limit)
        if cpu.frames == before:
            break
    return steps


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    out = argv[2] if len(argv) > 2 else pngwrite.build_png('run.png')
    frames = int(argv[3]) if len(argv) > 3 else 4
    held = argv[4:]

    cpu = boot(argv[1])
    steps = play(cpu, frames, parse(held))
    scr = bytes(cpu.mem[16384:16384 + 6912])
    zxscreen.preview(scr, out)
    print('%s: %d frames, %d instructions, PC=%04X -> %s'
          % (argv[1], cpu.frames, steps, cpu.pc, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
