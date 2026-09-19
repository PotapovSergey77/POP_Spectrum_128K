"""
What the 128's AY would play, as a WAV: the register writes a run of the
program made, each with the T-state it came at, through a plain AY model --
three square tones, the noise, the envelope, the mixer.  For listening to
the music without a Spectrum.

    render(writes, seconds, path)    writes: [(t_state, register, value)]
"""
import math
import struct
import wave

CPU = 3546900                   # the 128's clock, T-states a second
AY = 1773450                    # and the AY's
RATE = 22050
# the AY's volume steps, near enough
LEVEL = [0.0, 0.0105, 0.0152, 0.0222, 0.0321, 0.0470, 0.0680, 0.0998,
         0.1180, 0.1703, 0.2476, 0.3616, 0.4232, 0.6061, 0.8003, 1.0]


def render(writes, seconds, path):
    regs = [0] * 16
    w = sorted(writes)
    wi = 0
    n = int(seconds * RATE)
    out = bytearray()
    tone_pos = [0.0, 0.0, 0.0]
    tone_out = [1, 1, 1]
    noise_pos = 0.0
    lfsr = 1
    noise_out = 1
    env_pos = 0.0
    env_step = 0
    env_hold = False
    env_attack = False
    per_sample = AY / 8.0 / RATE           # tone counter ticks a sample
    for i in range(n):
        t = i * CPU / RATE
        while wi < len(w) and w[wi][0] <= t:
            _, r, v = w[wi]
            regs[r & 15] = v
            if r == 13:
                env_step = 0
                env_hold = False
                env_attack = bool(v & 4)
            wi += 1
        mix = 0.0
        # noise
        np_ = (regs[6] & 31) or 1
        noise_pos += per_sample / 2
        while noise_pos >= np_:
            noise_pos -= np_
            bit = (lfsr ^ (lfsr >> 3)) & 1
            lfsr = (lfsr >> 1) | (bit << 16)
            noise_out = lfsr & 1
        # envelope
        ep = (regs[11] | regs[12] << 8) or 1
        env_pos += per_sample / 2
        while env_pos >= ep:
            env_pos -= ep
            if not env_hold:
                env_step += 1
                if env_step >= 16:
                    shape = regs[13]
                    if not shape & 8:
                        env_hold = True
                        env_step = 15
                        env_attack = False
                    elif shape & 1:
                        env_hold = True
                        env_step = 15
                        if shape & 2:
                            env_attack = not env_attack
                    else:
                        env_step = 0
                        if shape & 2:
                            env_attack = not env_attack
        ev = env_step if env_attack else 15 - env_step
        if env_hold and not (regs[13] & 8):
            ev = 0
        for ch in range(3):
            p = (regs[2 * ch] | (regs[2 * ch + 1] & 15) << 8) or 1
            tone_pos[ch] += per_sample
            while tone_pos[ch] >= p:
                tone_pos[ch] -= p
                tone_out[ch] ^= 1
            m = regs[7]
            on = ((tone_out[ch] or m & (1 << ch)) and
                  (noise_out or m & (8 << ch)))
            vol = regs[8 + ch]
            level = LEVEL[ev] if vol & 16 else LEVEL[vol & 15]
            mix += level if on else 0.0
        out += struct.pack('<h', int(max(-1.0, min(1.0, mix / 3 * 2 - 0.0)) * 20000))
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(bytes(out))
