"""
The sound effects of Amstrad CPC Prince of Persia, for the Spectrum 128's AY.

The CPC game proper is 27 sectors from track 11, sector &41, copied to &8000.
Its sound driver keeps a table at &B25A: for each of twenty effects the
address of its data and a priority, the next entry's address marking the
end.  The data is a run of commands, one AY tick (a fiftieth) at a time:

    r v            register r = v; register 11 takes four bytes, 11 lo 12 hi,
                   a 16-bit envelope period that the driver halves
    80 v           the accumulator = v
    81 r d t       accumulator += d into register r, one tick each, until t
    8x n           wait n + 1 ticks (x >= 2); n = 0 stops, volumes to nought

A new effect replaces the one playing unless its priority is lower.

The CPC's AY runs from a 1 MHz clock and the 128's from 1.75 MHz, so every
tone, noise and envelope period is scaled by 1.75 here, in place; the
commands and their lengths stay as they are.

    cpcsound.py            say how big the table and the data come out

Out, through build(cache_dir): (table, data) -- the table as twenty one
entries of (offset into data, little-endian, priority), the data as above.
"""
import hashlib
import os
import sys

import cpcdisk

HERE = os.path.dirname(os.path.abspath(__file__))
DISK = os.path.join(HERE, '..', 'disk', 'Prince of Persia.dsk')
TABLE = 0xB25A
COUNT = 20
SCALE = 1.75


def game_image(disk):
    mem = bytearray(0x10000)
    blob = bytearray()
    track, sector = 11, 0x41
    for _ in range(27):
        blob += disk.sector(track, sector)
        sector += 1
        if sector == 0x4A:
            track, sector = track + 1, 0x41
    mem[0x8000:0x8000 + 0x3600] = blob[:0x3600]
    return bytes(mem)


def effects(mem):
    ents = [(mem[TABLE + 3 * i] | mem[TABLE + 3 * i + 1] << 8, mem[TABLE + 3 * i + 2])
            for i in range(COUNT + 1)]
    return ents


def scale_period(p, top):
    return max(1, min(top, int(round(p * SCALE))))


def convert(mem, start, end):
    """The effect's bytes, its periods scaled for the 128's clock."""
    out = bytearray(mem[start:end])
    hl = 0
    lo_at = [None, None, None]
    acc = 0
    n = len(out)
    while hl < n:
        c = out[hl]
        if c & 0x80:
            k = c & 0x7f
            if k == 0:
                acc = out[hl + 1]
                hl += 2
            elif k == 1:
                reg, d, t = out[hl + 1], out[hl + 2], out[hl + 3]
                if reg == 6:
                    # a noise sweep: the same number of steps to a scaled end
                    steps = max(1, (t - acc) // d) if d else 1
                    t2 = scale_period(t, 31)
                    d2 = max(1, (t2 - scale_period(acc, 31)) // steps)
                    a2 = t2 - steps * d2
                    out[hl + 2], out[hl + 3] = d2, t2
                    fix = hl - 1
                    while fix >= 0 and not (out[fix] == 0x80 and out[fix + 1] == acc):
                        fix -= 1
                    assert fix >= 0, 'no accumulator for the sweep'
                    out[fix + 1] = a2
                    acc = t2
                else:
                    acc = t
                hl += 4
            else:
                hl += 2
        elif c == 11:
            v = (out[hl + 1] | out[hl + 3] << 8) >> 1
            v = scale_period(v, 0xffff // 2) * 2
            out[hl + 1], out[hl + 3] = v & 0xff, v >> 8
            hl += 4
        else:
            v = out[hl + 1]
            if c in (0, 2, 4):
                lo_at[c // 2] = hl + 1
            elif c in (1, 3, 5):
                ch = c // 2
                at = lo_at[ch]
                assert at is not None, 'a period high byte with no low byte'
                p = scale_period(out[at] | v << 8, 0xfff)
                out[at], out[hl + 1] = p & 0xff, p >> 8
                lo_at[ch] = None
            elif c == 6:
                out[hl + 1] = scale_period(v, 31)
            hl += 2
    for ch, at in enumerate(lo_at):
        assert at is None, 'a period low byte with no high byte'
    return bytes(out)


def render():
    mem = game_image(cpcdisk.Disk(DISK))
    ents = effects(mem)
    base = ents[0][0]
    table = bytearray()
    data = bytearray()
    for i in range(COUNT):
        start, prio = ents[i]
        end = ents[i + 1][0]
        assert start - base == len(data), 'the effects are not in order'
        table += (len(data)).to_bytes(2, 'little') + bytes([prio])
        data += convert(mem, start, end)
    table += (len(data)).to_bytes(2, 'little') + bytes([0])
    return bytes(table), bytes(data)


def build(cache_dir):
    """(table, data), worked out once for this disk and this file."""
    if not os.path.exists(DISK):
        raise SystemExit('нет образа диска %s: звуки берутся с него' % DISK)
    h = hashlib.sha1()
    h.update(open(DISK, 'rb').read())
    h.update(open(__file__, 'rb').read())
    key = h.hexdigest()[:16]
    tpath = os.path.join(cache_dir, 'cpcsfx.%s.tab' % key)
    dpath = os.path.join(cache_dir, 'cpcsfx.%s.bin' % key)
    if os.path.exists(tpath) and os.path.exists(dpath):
        return open(tpath, 'rb').read(), open(dpath, 'rb').read()
    table, data = render()
    for old in os.listdir(cache_dir):
        if old.startswith('cpcsfx.'):
            os.remove(os.path.join(cache_dir, old))
    open(tpath, 'wb').write(table)
    open(dpath, 'wb').write(data)
    return table, data


if __name__ == '__main__':
    table, data = render()
    print('table %d bytes, data %d bytes' % (len(table), len(data)))
