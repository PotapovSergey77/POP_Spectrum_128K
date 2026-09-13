"""
The game's music, off the Apple's own disk and played by its own player.

MASTER.S loads the game's songs from side A, track 20, sectors 0 to 3, to
MusicTable at $D000; MSYS.S -- Music System ][ by Kyle Freeman -- lives on
track 34 from byte $600, at $D400.  Neither is in the sources, only on the
disk.  The player is a one-bit speaker synthesiser: two voices taking turns a
call each, a note a train of clicks whose rate is the pitch and whose width
the loudness, shaped by envelope and "harmonic" tables.

So nothing of it is transcribed.  The player is run, as the 6502 it was
written for, MINIT and then MPLAY until the song says it is over, and every
click of the speaker is timed.  Each MPLAY call belongs to one voice and plays
one stretch of one note: the rate of its clicks is the note, their width
against that its loudness.  A voice holds its note until its next call, the
calls are laid out in time as the Apple ran them, and the result is sampled at
the Spectrum's fifty frames a second as a tone and a volume for each voice --
AY channels B and C.

    songs.bin   [song n: offset of its record, 0 when not carried] * 17
                record: offset of voice 2's stream; voice 1's follows
                stream: frames, period lo, volume << 4 | period hi ... 0

Rendering takes a while, so the result is kept in build/ against a hash of
the disk and of this file.
"""
import hashlib
import math
import os

import mos6502
import popdisk

HERE = os.path.dirname(os.path.abspath(__file__))
DISK = os.path.join(HERE, '..', 'disk', 'Prince of Persia side A.nib')

APPLE_HZ = 1022727.0
AY_CLOCK = 1750000.0
FPS = 50.0

MPLAY, MINIT = 0xD403, 0xD400
CLICK_ON = (0xDE27, 0xDFDA)             # M30A, M20A: the voices' first touch
CLICK_OFF = (0xDE2D, 0xDFE0)            # M30B, M20B: and their second
TWOVOICE, TURN = 0x0F, 0x15             # R+15, R+21

# SOUNDNAMES.S: the songs the first level cues.
SONGS = {1: 'Accid', 2: 'Heroic', 3: 'Danger', 4: 'Sword', 7: 'Vict',
         8: 'Stairs', 9: 'Upstairs', 11: 'Potion', 12: 'ShortPot'}
TOP = 17


def load_player():
    disk = popdisk.Disk(DISK)
    return disk.track(20)[:0x400], disk.track(34)[0x600:0x1200]


def calls(music, msys, song):
    """[(start, end, voice, click period, duty)] in 6502 cycles."""
    cpu = mos6502.CPU()
    cpu.mem[0xD000:0xD400] = music
    cpu.mem[0xD400:0xD400 + len(msys)] = msys
    clicks = []
    cpu.on_read[0xC030] = lambda c: clicks.append((c.cycles, c.pc))
    cpu.a = song
    cpu.call(MINIT)
    out = []
    while len(out) < 5000:
        # MPLAY: with two voices it turns R+21 over, and voice 1 plays when
        # that leaves it set.
        voice = 0
        if cpu.mem[TWOVOICE] and not cpu.mem[TURN] ^ 1:
            voice = 1
        start = cpu.cycles
        del clicks[:]
        cpu.call(MPLAY)
        on = [t for t, pc in clicks if pc in CLICK_ON]
        off = [t for t, pc in clicks if pc in CLICK_OFF]
        period, duty = 0, 0.0
        if len(on) > 2:
            gaps = sorted(b - a for a, b in zip(on, on[1:]))
            period = gaps[len(gaps) // 2]
            widths = [b - a for a, b in zip(on, off)]
            duty = sum(widths) / float(len(widths)) / period
        out.append((start, cpu.cycles, voice, period, duty))
        if cpu.a == 0:                  # the song has set song 0: done
            break
    return out


def ay_period(period):
    return max(1, min(4095, int(round(AY_CLOCK / 16.0 * period / APPLE_HZ))))


def ay_volume(duty, loudest):
    """A click train's fundamental goes with its width; the AY's steps are
    near three decibels, two to a halving."""
    if duty <= 0:
        return 0
    return max(0, min(15, 15 + int(round(2 * math.log2(duty / loudest)))))


def stream(events, end):
    """One voice's (start, period, volume) as frames, merged where nothing
    changes."""
    out = bytearray()
    runs = []
    for i, (t, p, v) in enumerate(events):
        if runs and runs[-1][1:] == (p, v):
            continue
        runs.append((t, p, v))
    for i, (t, p, v) in enumerate(runs):
        stop = runs[i + 1][0] if i + 1 < len(runs) else end
        frames = int(round(stop / APPLE_HZ * FPS)) - int(round(t / APPLE_HZ * FPS))
        while frames > 0:
            n = min(frames, 255)
            out += bytes([n, p & 0xff, (v << 4) | (p >> 8)])
            frames -= n
    return bytes(out) + b'\0'


def render():
    music, msys = load_player()
    played = dict((n, calls(music, msys, n)) for n in SONGS)
    loudest = max(d for c in played.values() for _, _, _, _, d in c)
    body = bytearray()
    heads = [0] * TOP
    base = 2 * TOP
    for n in sorted(played):
        c = played[n]
        end = c[-1][1]
        voices = [[], []]
        for start, stop, voice, period, duty in c:
            voices[voice].append((start, ay_period(period) if period else 0,
                                  ay_volume(duty, loudest) if period else 0))
        one = stream(voices[0], end)
        two = stream(voices[1], end) if voices[1] else b'\0'
        heads[n] = base + len(body)
        body += (2 + len(one)).to_bytes(2, 'little') + one + two
    return b''.join(h.to_bytes(2, 'little') for h in heads) + bytes(body)


def songs(cache_dir):
    """songs.bin, rendered once for this disk and this file."""
    if not os.path.exists(DISK):
        raise SystemExit('нет образа диска %s: музыка берётся с него' % DISK)
    h = hashlib.sha1()
    h.update(open(DISK, 'rb').read())
    h.update(open(__file__, 'rb').read())
    h.update(open(mos6502.__file__, 'rb').read())
    key = h.hexdigest()
    path = os.path.join(cache_dir, 'songs.%s.bin' % key[:16])
    if os.path.exists(path):
        return open(path, 'rb').read()
    data = render()
    for old in os.listdir(cache_dir):
        if old.startswith('songs.') and old.endswith('.bin'):
            os.remove(os.path.join(cache_dir, old))
    open(path, 'wb').write(data)
    return data


if __name__ == '__main__':
    data = render()
    print('songs.bin %d bytes' % len(data))
