"""
Run the demo in the little Z80 core and save what it drew.

Loads the CODE block out of a .tap, starts at the address in its header, runs
a number of game frames and writes the screen as a PNG -- so a build can be
checked before it goes anywhere near a real Spectrum.

Keys are given as name@first-last in game frames, or bare for the whole run:

    runtap.py build/pop.tap out.png 200 left@0-45 up@70-73 down@165-175

Usage: runtap.py <tap> [out.png] [frames] [key ...]
"""
import json
import os
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
    'shift': (0xFEFE, 0),
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
    """
    A CPU with the tape loaded the way the tape loads it: the program first,
    then a paging stub and a block for each bank, in order.  Doing it any
    other way hides the bugs that only show up in that order -- one of them
    was writing six kilobytes into whichever bank happened to be paged.
    """
    manifest = os.path.splitext(path)[0] + '.banks.json'
    banks = json.load(open(manifest)) if os.path.exists(manifest) else []
    levels = [m['file'] for m in banks if m.get('level')]
    banks = [m for m in banks if not m.get('level')]
    cpu = z80.Z80()
    cpu.mem[0x5B5C] = 0x00          # BANKM, as 128 BASIC leaves it
    # The two bytes of the 48K ROM that the program's IM 2 vector leans on:
    # the run of 0xFF it points I into, and the DI at 0x0000 that the JR at
    # 0xFFFF takes as its displacement.
    cpu.mem[0x3900:0x3C00] = bytes([0xFF]) * 0x300
    cpu.mem[0x0000] = 0xF3
    blocks = code_blocks(path)
    # Somewhere for the stubs to return to, below the program the way CLEAR
    # leaves it: a fixed address of its own would be inside the program as
    # soon as it loads any lower, and the two bytes written there came out
    # as a handful of wrong pixels in every check at once.
    stack = blocks[0][0] - 16
    cpu.sp = stack
    entry = None
    for i, (addr, payload) in enumerate(blocks):
        if i and banks:             # page the bank this block belongs in
            _usr(cpu, banks[0]['entry'] - STUB * (len(banks) - i), stack)
        cpu.mem[addr:addr + len(payload)] = payload
        if not i:
            entry = banks[0]['entry'] if banks else addr
    cpu.pc = entry
    release(cpu)
    skip_intro(cpu, path)
    tape_levels(cpu, path, levels)
    return cpu


def tape_levels(cpu, path, levels):
    """
    The levels after the first are bare blocks on the tape after the banks,
    which the game loads itself through the ROM's LD-BYTES in tapeload --
    and there is no ROM here, so tapeload is done here: the next block of
    the tape, in order, into the background bank at the blueprint.
    """
    for sym in (os.path.splitext(path)[0] + '.sym.json',
                os.path.join(os.path.dirname(path), 'sym.json')):
        if os.path.exists(sym):
            s = json.load(open(sym))
            break
    else:
        return
    if 'tapeload' not in s:
        return
    queue = list(levels)

    def load(cpu):
        data = open(queue.pop(0), 'rb').read()
        at = s['level'] - 0xC000
        bank = s['BANK_BG']
        if cpu.page == bank:
            cpu.mem[0xC000 + at:0xC000 + at + len(data)] = data
        else:
            cpu.banks[bank][at:at + len(data)] = data
        cpu.f |= 1                      # carry: loaded
        cpu.iff1 = cpu.iff2 = 1         # LD-BYTES leaves them on
    cpu.traps[s['tapeload']] = load


def skip_intro(cpu, path):
    """
    The title screens run half a minute of interrupts before the game: every
    check wants the game, so the intro returns at once -- unless POP_INTRO is
    set, to look at the titles themselves.
    """
    if os.environ.get('POP_INTRO'):
        return
    for sym in (os.path.splitext(path)[0] + '.sym.json',
                os.path.join(os.path.dirname(path), 'sym.json')):
        if os.path.exists(sym):
            at = json.load(open(sym)).get('intro')
            if at is not None:
                cpu.mem[at] = 0xC9          # RET
            return


STUB = 4


def _usr(cpu, addr, stack=0x5FF0):
    """RANDOMIZE USR: call it and let it come back."""
    cpu.mem[stack] = 0
    cpu.mem[stack + 1] = 0
    cpu.sp = stack
    cpu.pc = addr
    for _ in range(200):
        if cpu.pc == 0:
            return
        cpu.step()
    raise SystemExit('заглушка страницы по %d не вернулась' % addr)


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


def play(cpu, frames, script, limit=3000000):
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


def game_frame(cpu, main, keys=(), limit=2000000):
    """
    Run one turn of the main loop with `keys` held down.

    play() counts interrupts, and a game frame is several of those -- more
    than FRAME_WAIT of them when the view moves -- so anything sampled per
    interrupt catches the screen halfway through being written, which reads
    as damage that is not there.  This stops at the top of the loop, where a
    frame is whole.
    """
    release(cpu)
    for name in keys:
        row, bit = KEYS[name]
        cpu.ports[row] &= ~(1 << bit) & 0xFF
    cpu.step()
    n = 0
    while cpu.pc != main and n < limit:
        cpu.step()
        n += 1
    return n


def held(script, n):
    """Which keys of a parsed script are down on game frame `n`."""
    return [name for name, a, b in script if a <= n <= b]


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    out = argv[2] if len(argv) > 2 else pngwrite.build_png('run.png')
    frames = int(argv[3]) if len(argv) > 3 else 4
    held = argv[4:]

    cpu = boot(argv[1])
    steps = play(cpu, frames, parse(held))
    scr = cpu.screen()
    zxscreen.preview(scr, out)
    print('%s: %d frames, %d instructions, PC=%04X -> %s'
          % (argv[1], cpu.frames, steps, cpu.pc, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
