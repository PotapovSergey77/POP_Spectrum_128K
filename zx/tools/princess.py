"""
The opening scene in the princess's room, PlayCut0 in SUBS.S, run as the
Apple runs it -- to look at, and for the Spectrum's to be checked against.

Two characters, each a CharX, CharY, CharFace and a place in SEQTABLE.S:
the vizier (the "kid" slot, CharID 6) and the princess (the "shadow" slot,
CharID 5).  Each frame of `play` steps both through ANIMCHAR, then FrameAdv
draws the room: the hourglass when it has changed, the two characters
masked in, the post over them, two torch flames, a star's twinkle and the
sand.  With the music off every PlaySongI is that many frames of `play`.

The characters' pictures are ALTSET2 in FRAMEDEF.S: chtable6, and chtable7
for five of the vizier's.

    princess.py [dir]      every frame as a PNG strip, to look at
"""
import os
import sys

import pngwrite
import popframe
import popimg
import poprincess
import popseq

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMEDEF = os.path.join(HERE, '..', '..', '01 POP Source', 'Source',
                        'FRAMEDEF.S')

SCRN_LEFT = 58
FLOOR_Y = 151

# SEQDATA.S
PSTAND, VSTAND, VAPPROACH, VSTOP, PALERT, PBACK, VEXIT, VRAISE = \
    94, 95, 96, 97, 98, 99, 100, 102
PSLUMP = 113

GOTO, ABOUTFACE, CHX, CHY, ACT = 0xFF, 0xFE, 0xFB, 0xFA, 0xF9


def load_altset2():
    frames, inside = {}, False
    for line in open(FRAMEDEF, encoding='latin-1'):
        if line.startswith('ALTSET2'):
            inside = True
        elif inside and 'S W O R D' in line:
            break
        m = popframe._LINE.match(line.rstrip('\n')) if inside else None
        if m:
            vals = [popframe._num(t) for t in m.group(2).split(',')]
            if len(vals) == 5:
                n = int(m.group(1))
                frames[n] = popframe.Frame(n, vals, m.group(3))
    return frames


class Char:
    def __init__(self, seq, x, y, face):
        self.table = seq
        self.x, self.y, self.face = x, y, face
        self.posn = 0
        self.ptr = None

    def jumpseq(self, n):
        self.ptr = self.table.at[self.table.entries[n]]

    def addx(self, d):
        d = d - 256 if d > 127 else d
        return self.x + (-d if self.face == -1 else d)

    def animchar(self):
        code = self.table.code
        while True:
            b = code[self.ptr]
            if b == CHX:
                self.x = self.addx(code[self.ptr + 1])
                self.ptr += 2
            elif b == CHY:
                d = code[self.ptr + 1]
                self.y += d - 256 if d > 127 else d
                self.ptr += 2
            elif b == ABOUTFACE:
                self.face = -1 - self.face
                self.ptr += 1
            elif b == GOTO:
                self.ptr = self.table.at[self.table.target(self.ptr + 1)]
            elif b == ACT:
                self.ptr += 2
            else:
                self.posn = b
                self.ptr += 1
                return


# Two and a half seconds of the first frame before the scene moves, the
# torches burning (SPEED 12 frames, eight and an eighth fiftieths each in
# cutplay.asm): the music, which starts from the first of them, came too
# late for what it goes with.
LEAD = 15


def cut0():
    """[state per frame]: speed, vizier and princess (posn, x, y, face) or
    None, the hourglass state or None, whether the sand flows, flash."""
    seq = popseq.load()
    frames = []
    speed = [12]
    glass = [None]
    sand = [False]
    flash = [0]
    viz = Char(seq, 197, FLOOR_Y, -1)
    viz.jumpseq(VSTAND)
    viz.animchar()
    prn = Char(seq, 120, FLOOR_Y, -1)
    prn.jumpseq(PSTAND)
    prn.animchar()

    def play(n, still=False):
        for _ in range(n):
            if not still:
                viz.animchar()
                prn.animchar()
            frames.append({
                'speed': speed[0],
                'vizier': (viz.posn, viz.x, viz.y, viz.face),
                'princess': (prn.posn, prn.x, prn.y, prn.face),
                'glass': glass[0], 'sand': sand[0], 'flash': flash[0] > 0})
            if flash[0]:
                flash[0] -= 1

    # The CPC's tunes run ahead of the Apple's scene: they start where
    # they would have without the frames put in front of it.
    def tune():
        tunes.append(len(frames) - LEAD)

    tunes = []
    play(LEAD, still=True)
    play(2)
    tune()
    play(8)                 # s_Princess: the CPC's tune 2
    play(5)
    prn.jumpseq(PALERT)
    play(9)
    tune()                  # s_Squeek: its tune 3, where the Apple's plays
    speed[0] = 7
    play(5)
    viz.jumpseq(VAPPROACH)
    play(6)
    viz.jumpseq(VSTOP)
    play(4)
    tune()
    play(12)                # s_Vizier: its tune 4, which plays on to the end
    play(4)
    viz.jumpseq(VAPPROACH)
    play(30)
    viz.jumpseq(VSTOP)
    play(4)
    play(25)                # s_Buildup
    viz.jumpseq(VRAISE)
    play(1)
    prn.jumpseq(PBACK)
    play(13)
    glass[0] = 0            # the hourglass appears
    flash[0] = 5
    speed[0] = 12
    play(5)
    sand[0] = True
    play(8)                 # s_Magic
    speed[0] = 7
    viz.jumpseq(VEXIT)
    play(17)
    glass[0] = 1
    play(12)
    prn.jumpseq(PSLUMP)
    play(28)
    speed[0] = 12
    play(20)                # s_StTimer
    for n in tunes:
        frames[n]['tune'] = True
    return frames


# The hourglass PlayCut1 has: GETGLASS's state for more than forty minutes
# left, which is what there is after level one -- the Spectrum keeps no
# clock yet.  GAMEBG.S's glassimg[3], and its sandht cuts the flow short.
CUT1_GLASS = 3


def cut1():
    """PlayCut1, the princess waiting between levels one and two: INITIT,
    the hourglass and its sand (GETGLASS, ADDGLASS), STARTP1 -- STARTP0
    turned to face right -- two frames of PLAY, and PlaySongX's s_Timer,
    the CPC's tune 6, for which the last frame is held (see 'hold')."""
    seq = popseq.load()
    frames = []
    prn = Char(seq, 120, FLOOR_Y, -1)
    prn.jumpseq(PSTAND)
    prn.animchar()
    prn.face = 0

    def play(n):
        for _ in range(n):
            prn.animchar()
            frames.append({
                'speed': 12, 'vizier': None,
                'princess': (prn.posn, prn.x, prn.y, prn.face),
                'glass': CUT1_GLASS, 'sand': True, 'flash': False})

    play(2)
    play(1)
    frames[-1]['tune'] = True           # s_Timer, and the song plays out
    play(1)
    frames[-1]['hold'] = True           # over this frame, shown until then
    return frames


ALT = None
T6 = T7 = None


def picture(posn):
    """The frame's image, its Fdx and Fdy, and Fcheck."""
    global ALT, T6, T7
    if ALT is None:
        ALT = load_altset2()
        mem = poprincess.memory()
        T6 = popimg.Table.from_memory(mem, poprincess.CHTABLE6)
        T7 = popimg.Table.from_memory(mem, poprincess.CHTABLE7)
    f = ALT[posn]
    table = T6 if f.table == 5 else T7
    return table.get(f.index), f.dx, f.dy, f.check


def place(posn, x, y, face):
    """(left x, bottom y, image, mirrored) in the Apple's pixels, SETUPCHAR's
    way: FCharX = 2(CharX + Fdx - ScrnLeft), one more where Fcheck and the
    facing agree; facing right the picture is mirrored with its right edge
    there."""
    img, dx, dy, check = picture(posn)
    fx = 2 * ((x + (-dx if face == -1 else dx)) - SCRN_LEFT)
    if not ((check ^ (face & 0xFF)) & 0x80):
        fx += 1
    fy = y + dy
    if face == -1:
        return fx, fy, img, False
    return fx - img.px_width, fy, img, True


def main(argv):
    out = argv[1] if len(argv) > 1 else '.'
    room = poprincess.hires_bits(poprincess.sng_expand(poprincess.memory()))[0]
    frames = cut0()
    print('%d frames' % len(frames))
    strip = []
    for i, st in enumerate(frames[::6]):
        scr = [row[:] for row in room]
        for who in ('princess', 'vizier'):
            left, bottom, img, mir = place(*st[who])
            pix = list(img.pixels())
            for j, line in enumerate(pix):
                if mir:
                    line = line[::-1]
                yy = bottom - len(pix) + 1 + j
                for k, v in enumerate(line):
                    if v and 0 <= yy < 192 and 0 <= left + k < 280:
                        scr[yy][left + k] = 2
        strip.append(scr)
    rows = []
    for scr in strip:
        for y in range(80, 192):
            rows.append(bytes(c for v in scr[y] for c in
                              ((255, 80, 80) if v == 2 else
                               (200, 200, 200) if v else (0, 0, 0))))
    pngwrite.write_rgb(os.path.join(out, 'cut0.png'), 280, len(rows), rows)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
