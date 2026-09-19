"""
A small Z80 core, enough to run the demo and look at what it drew.

Not a complete Spectrum: there is no ROM and no interrupt routine.  HALT with
interrupts enabled counts a frame and falls through, which is nearly all the
program uses it for, and IN reads come from a key map the harness sets.

The one thing the ROM does that the program leans on is the three byte frame
count at 23672, which the main loop reads to pace itself and the redraw
queue reads to know how much of a frame is left.  It moves on at every
interrupt, as the machine's does -- at each FRAME_TSTATES of the clock, in
the middle of work or at a halt alike -- or neither would see the truth.

Undocumented flags and instructions are left out; DAA, DD/FD and the block
compare/IO groups are not implemented, and hitting one raises rather than
quietly doing the wrong thing.
"""

SF, ZF, YF, HF, XF, PF, NF, CF = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

PARITY = [0] * 256
for _i in range(256):
    _b, _n = _i, 0
    while _b:
        _n += _b & 1
        _b >>= 1
    PARITY[_i] = PF if not _n & 1 else 0


# What the 48K ROM's handler at 0x38 costs, counting and scanning the keys.
ROM_INT_TSTATES = 1500

# T-states between interrupts on a 128K -- 228 to the line, 311 lines.
FRAME_TSTATES = 70908


# What each unprefixed instruction takes, in T-states, the way the book has
# it -- a conditional jump, call or return at its not-taken time, TAKEN below
# what it adds when it goes; CB and ED count their own on top of the four of
# the prefix.  Every instruction was four once, which made the frames here
# look half what they are on the machine and hid every one that ran late.

TSTATES = [
    4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,
    8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,
    7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,
    7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,
] + [7 if (op & 7 == 6 or op >> 3 & 7 == 6) and op != 0x76 else 4
     for op in range(0x40, 0xC0)] + [
    5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 4, 10, 17, 7, 11,
    5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 4, 7, 11,
    5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 4, 7, 11,
    5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 4, 7, 11,
]
# op: (its length, what it adds when taken)
TAKEN = {0x10: (2, 5)}
for _op in (0x20, 0x28, 0x30, 0x38):
    TAKEN[_op] = (2, 5)
for _y in range(8):
    TAKEN[0xC0 | _y << 3] = (1, 6)                      # ret cc
    TAKEN[0xC4 | _y << 3] = (3, 7)                      # call cc


class Z80:
    def __init__(self, mem=None):
        self.mem = bytearray(65536) if mem is None else mem
        self.a = self.f = 0
        self.b = self.c = self.d = self.e = self.h = self.l = 0
        self.a_ = self.f_ = 0
        self.bc_ = self.de_ = self.hl_ = 0
        self.pc = self.sp = 0
        self.iff1 = self.iff2 = 0
        self.im = 0
        self.i = 0
        self.halted = False
        self.frames = 0
        self.next_tick = FRAME_TSTATES      # when the interrupt next comes
        # POP_SLOW stretches every instruction, a rough stand-in for the
        # memory contention a real 128K has and this core does not model.
        import os
        self.slow = float(os.environ.get('POP_SLOW', '1.0'))
        # POP_CONTEND models the 128K's contention itself: while the ULA
        # fetches the picture, an access to 0x4000-0x7FFF, or to the window
        # with an odd bank in it, waits for the ULA -- 6, 5, 4, 3, 2, 1, 0, 0
        # T by where in its eight it falls, from T 14361 of the frame, for
        # the first 128 T of each of the 192 lines.  An instruction's
        # accesses are taken three T apart, which is near enough.  The code
        # from 0x6000 to 0x7FFF runs in contended memory, and a uniform
        # stretch was far too kind to it.
        # POP_CONTEND=plus3 is the +2A and +3 instead: banks 4 to 7 are the
        # slow ones there -- the room's among them -- and the pattern is
        # 1, 0, 7, 6, 5, 4, 3, 2 from T 14365.
        self._acc = 0
        # POP_FREELOW: where the slow half of the low 32K ends, for asking
        # what code moved out of it would gain
        self._clo = int(os.environ.get('POP_FREELOW', '0x4000'), 0)
        mode = os.environ.get('POP_CONTEND', '')
        if mode:
            self.rb = self._rb_c
            self.wb = self._wb_c
        if mode == 'plus3':
            self._cbanks, self._cfirst = (4, 5, 6, 7), 14365
            self.CONT = (1, 0, 7, 6, 5, 4, 3, 2)
        else:
            self._cbanks, self._cfirst = (1, 3, 5, 7), 14361
        self.halted_now = False
        self.cycles = 0
        self.ports = {}          # port -> value returned by IN
        self.traps = {}          # address -> what the harness does there
        self.default_in = 0xFF
        # 128K paging.  Rather than route every read through a mapper -- which
        # would cost more than the rest of the interpreter -- the window is
        # swapped in and out of the flat 64K array when the port is written.
        self.banks = [bytearray(0x4000) for _ in range(8)]
        self.page = 0
        self.shadow = False     # bit 3: the ULA shows bank 7, not bank 5

    def set_page(self, n):
        """Put RAM bank n at 0xC000, keeping what the old one held."""
        n &= 7
        if n == self.page:
            return
        self.banks[self.page][:] = self.mem[0xC000:]
        self.mem[0xC000:] = self.banks[n]
        self.page = n

    def io_write(self, port, value):
        # 0x7FFD is decoded on A15 and A1 both low, which is how every real
        # 128K program addresses it.
        if not port & 0x8002:
            self.set_page(value & 7)
            self.shadow = bool(value & 8)

    def screen(self):
        """The 6912 bytes the ULA is showing: bank 5 at 0x4000, or bank 7
        when bit 3 of the port asks for the second screen."""
        if not self.shadow:
            return bytes(self.mem[0x4000:0x5B00])
        if self.page == 7:
            return bytes(self.mem[0xC000:0xDB00])
        return bytes(self.banks[7][:6912])

    # -- registers ------------------------------------------------------

    def _get_bc(self):
        return (self.b << 8) | self.c

    def _set_bc(self, v):
        self.b, self.c = (v >> 8) & 0xff, v & 0xff

    def _get_de(self):
        return (self.d << 8) | self.e

    def _set_de(self, v):
        self.d, self.e = (v >> 8) & 0xff, v & 0xff

    def _get_hl(self):
        return (self.h << 8) | self.l

    def _set_hl(self, v):
        self.h, self.l = (v >> 8) & 0xff, v & 0xff

    bc = property(_get_bc, _set_bc)
    de = property(_get_de, _set_de)
    hl = property(_get_hl, _set_hl)

    def _get_af(self):
        return (self.a << 8) | self.f

    def _set_af(self, v):
        self.a, self.f = (v >> 8) & 0xff, v & 0xff

    af = property(_get_af, _set_af)

    # -- memory ---------------------------------------------------------

    def rb(self, addr):
        return self.mem[addr & 0xffff]

    def wb(self, addr, val):
        self.mem[addr & 0xffff] = val & 0xff

    CONT = (6, 5, 4, 3, 2, 1, 0, 0)

    def _contend(self, addr):
        t = self.cycles + self._acc
        self._acc += 3
        if self._clo <= addr < 0x8000 or (addr >= 0xC000 and self.page in self._cbanks):
            t = t % FRAME_TSTATES - self._cfirst
            if 0 <= t < 192 * 228:
                lt = t % 228
                if lt < 128:
                    self.cycles += self.CONT[lt & 7]

    def _rb_c(self, addr):
        addr &= 0xffff
        self._contend(addr)
        return self.mem[addr]

    def _wb_c(self, addr, val):
        addr &= 0xffff
        self._contend(addr)
        self.mem[addr] = val & 0xff

    def rw(self, addr):
        return self.rb(addr) | (self.rb(addr + 1) << 8)

    def ww(self, addr, val):
        self.wb(addr, val)
        self.wb(addr + 1, val >> 8)

    def fetch(self):
        v = self.rb(self.pc)
        self.pc = (self.pc + 1) & 0xffff
        return v

    def fetch_w(self):
        v = self.rw(self.pc)
        self.pc = (self.pc + 2) & 0xffff
        return v

    def push(self, v):
        self.sp = (self.sp - 2) & 0xffff
        self.ww(self.sp, v)

    def pop(self):
        v = self.rw(self.sp)
        self.sp = (self.sp + 2) & 0xffff
        return v

    # -- register file access by index ----------------------------------

    R = ['b', 'c', 'd', 'e', 'h', 'l', None, 'a']

    def get_r(self, i):
        if i == 6:
            return self.rb(self.hl)
        return getattr(self, self.R[i])

    def set_r(self, i, v):
        if i == 6:
            self.wb(self.hl, v)
        else:
            setattr(self, self.R[i], v & 0xff)

    RP = ['bc', 'de', 'hl', 'sp']

    def get_rp(self, i):
        return self.sp if i == 3 else getattr(self, self.RP[i])

    def set_rp(self, i, v):
        if i == 3:
            self.sp = v & 0xffff
        else:
            setattr(self, self.RP[i], v & 0xffff)

    # -- flag helpers ---------------------------------------------------

    def sz(self, v):
        return (v & SF) | (ZF if v == 0 else 0) | (v & (YF | XF))

    def add8(self, a, b, carry=0):
        r = a + b + carry
        h = ((a & 15) + (b & 15) + carry) & 0x10
        v = PF if ((a ^ ~b) & (a ^ r) & 0x80) else 0
        res = r & 0xff
        self.f = self.sz(res) | (h and HF) | v | (CF if r > 255 else 0)
        return res

    def sub8(self, a, b, carry=0):
        r = a - b - carry
        h = ((a & 15) - (b & 15) - carry) & 0x10
        v = PF if ((a ^ b) & (a ^ r) & 0x80) else 0
        res = r & 0xff
        self.f = self.sz(res) | (h and HF) | v | NF | (CF if r < 0 else 0)
        return res

    def cond(self, i):
        return [not self.f & ZF, self.f & ZF, not self.f & CF, self.f & CF,
                not self.f & PF, self.f & PF, not self.f & SF,
                self.f & SF][i]

    def tick_frames(self):
        """The ROM's own counter at 23672, which the main loop reads."""
        for a in (23672, 23673, 23674):
            self.mem[a] = (self.mem[a] + 1) & 0xFF
            if self.mem[a]:
                break

    # -- execution ------------------------------------------------------

    def step(self):
        self._acc = 0
        if self.pc in self.traps:
            # a routine the harness does itself -- the ROM's, which is
            # not here -- and returns from as the routine would
            self.traps[self.pc](self)
            self.pc = self.pop()
            return
        if self.pc == 0x0038 and self.im == 2:
            # IM 2 handlers call the ROM's own at 0x38 for the frame count
            # and the keyboard, and there is no ROM here: the count, the
            # time a keyboard scan takes, and back with interrupts on.
            self.tick_frames()
            self.cycles += ROM_INT_TSTATES
            self.iff1 = self.iff2 = 1
            self.pc = self.pop()
            self.interrupt_due()
            return
        if self.slow == 1.0:
            self._step()
        else:                                       # contended memory,
            c = self.cycles                         # roughly: every
            self._step()                            # instruction a little
            if not self.halted_now:                 # longer than the book
                self.cycles = c + int((self.cycles - c) * self.slow + 0.5)
        self.interrupt_due()

    def interrupt_due(self):
        while self.cycles >= self.next_tick:        # the interrupt: the ROM
            self.next_tick += FRAME_TSTATES         # counts a frame
            if not self.iff1:
                continue
            if self.im == 2:                        # or the program's own
                self.iff1 = self.iff2 = 0           # handler runs, through
                self.push(self.pc)                  # the vector the floating
                self.pc = self.rw((self.i << 8) | 0xFF)     # bus reads
                self.cycles += 19
                return
            self.tick_frames()

    def _step(self):
        pc = self.pc
        op = self.mem[pc]
        self._exec()
        self.cycles += TSTATES[op] - 4
        t = TAKEN.get(op)
        if t and self.pc != (pc + t[0]) & 0xffff:
            self.cycles += t[1]

    def _exec(self):
        self.halted_now = False
        op = self.fetch()
        self.cycles += 4

        if op == 0x00:                                  # nop
            return
        if op == 0x76:                                  # halt
            if self.iff1:
                # A halt waits for the interrupt, so the clock jumps to the
                # next one.  Without this the cycle count is the work only and
                # says nothing about how long a frame actually takes, which is
                # the question the pace of the game turns on.
                self.cycles += FRAME_TSTATES - self.cycles % FRAME_TSTATES
                self.frames += 1
                self.halted_now = True
            else:
                self.halted = True
            return
        if 0x40 <= op < 0x80:                           # ld r,r'
            self.set_r((op >> 3) & 7, self.get_r(op & 7))
            return
        if 0x80 <= op < 0xC0:                           # alu a,r
            self.alu((op >> 3) & 7, self.get_r(op & 7))
            return

        hi, lo = op >> 6, op & 7
        if hi == 0:
            self.group0(op)
            return
        if hi == 3:
            self.group3(op)
            return
        raise NotImplementedError('opcode %02X at %04X' % (op, self.pc - 1))

    def alu(self, kind, v):
        c = 1 if self.f & CF else 0
        if kind == 0:
            self.a = self.add8(self.a, v)
        elif kind == 1:
            self.a = self.add8(self.a, v, c)
        elif kind == 2:
            self.a = self.sub8(self.a, v)
        elif kind == 3:
            self.a = self.sub8(self.a, v, c)
        elif kind == 4:
            self.a &= v
            self.f = self.sz(self.a) | HF | PARITY[self.a]
        elif kind == 5:
            self.a ^= v
            self.f = self.sz(self.a) | PARITY[self.a]
        elif kind == 6:
            self.a |= v
            self.f = self.sz(self.a) | PARITY[self.a]
        else:
            self.sub8(self.a, v)

    def group0(self, op):
        z, y = op & 7, (op >> 3) & 7
        if z == 0:
            if y == 0:
                return
            if y == 1:                                  # ex af,af'
                self.a, self.a_ = self.a_, self.a
                self.f, self.f_ = self.f_, self.f
                return
            d = self.fetch()
            d = d - 256 if d > 127 else d
            if y == 2:                                  # djnz
                self.b = (self.b - 1) & 0xff
                if self.b:
                    self.pc = (self.pc + d) & 0xffff
                return
            if y == 3 or self.cond(y - 4):              # jr / jr cc
                self.pc = (self.pc + d) & 0xffff
            return
        if z == 1:
            if not y & 1:                               # ld rr,nn
                self.set_rp(y >> 1, self.fetch_w())
            else:                                       # add hl,rr
                a, b = self.hl, self.get_rp(y >> 1)
                r = a + b
                self.f = ((self.f & (SF | ZF | PF)) |
                          (((a ^ b ^ r) >> 8) & HF) |
                          ((r >> 8) & (YF | XF)) | (CF if r > 0xffff else 0))
                self.hl = r
            return
        if z == 2:
            if y == 0:
                self.wb(self.bc, self.a)
            elif y == 1:
                self.a = self.rb(self.bc)
            elif y == 2:
                self.wb(self.de, self.a)
            elif y == 3:
                self.a = self.rb(self.de)
            elif y == 4:
                self.ww(self.fetch_w(), self.hl)
            elif y == 5:
                self.hl = self.rw(self.fetch_w())
            elif y == 6:
                self.wb(self.fetch_w(), self.a)
            else:
                self.a = self.rb(self.fetch_w())
            return
        if z == 3:
            rp = y >> 1
            v = self.get_rp(rp)
            self.set_rp(rp, v + (1 if not y & 1 else -1))
            return
        if z == 4 or z == 5:                            # inc/dec r
            v = self.get_r(y)
            c = self.f & CF
            if z == 4:
                r = self.add8(v, 1)
            else:
                r = self.sub8(v, 1)
            self.f = (self.f & ~CF) | c
            self.set_r(y, r)
            return
        if z == 6:                                      # ld r,n
            self.set_r(y, self.fetch())
            return
        # z == 7: rotates and friends
        if y == 0:                                      # rlca
            self.a = ((self.a << 1) | (self.a >> 7)) & 0xff
            self.f = (self.f & (SF | ZF | PF)) | (self.a & (YF | XF)) | (self.a & CF)
        elif y == 1:                                    # rrca
            c = self.a & 1
            self.a = ((self.a >> 1) | (c << 7)) & 0xff
            self.f = (self.f & (SF | ZF | PF)) | (self.a & (YF | XF)) | c
        elif y == 2:                                    # rla
            c = 1 if self.f & CF else 0
            nc = self.a >> 7
            self.a = ((self.a << 1) | c) & 0xff
            self.f = (self.f & (SF | ZF | PF)) | (self.a & (YF | XF)) | nc
        elif y == 3:                                    # rra
            c = 1 if self.f & CF else 0
            nc = self.a & 1
            self.a = ((self.a >> 1) | (c << 7)) & 0xff
            self.f = (self.f & (SF | ZF | PF)) | (self.a & (YF | XF)) | nc
        elif y == 5:                                    # cpl
            self.a ^= 0xff
            self.f = (self.f & (SF | ZF | PF | CF)) | HF | NF | (self.a & (YF | XF))
        elif y == 6:                                    # scf
            self.f = (self.f & (SF | ZF | PF)) | (self.a & (YF | XF)) | CF
        elif y == 7:                                    # ccf
            c = self.f & CF
            self.f = ((self.f & (SF | ZF | PF)) | (self.a & (YF | XF)) |
                      (HF if c else 0) | (0 if c else CF))
        else:
            raise NotImplementedError('daa at %04X' % (self.pc - 1))

    def group3(self, op):
        z, y = op & 7, (op >> 3) & 7
        if z == 0:                                      # ret cc
            if self.cond(y):
                self.pc = self.pop()
            return
        if z == 1:
            if not y & 1:                               # pop rr
                v = self.pop()
                if y >> 1 == 3:
                    self.af = v
                else:
                    self.set_rp(y >> 1, v)
                return
            q = y >> 1
            if q == 0:                                  # ret
                self.pc = self.pop()
            elif q == 1:                                # exx
                self.bc, self.bc_ = self.bc_, self.bc
                self.de, self.de_ = self.de_, self.de
                self.hl, self.hl_ = self.hl_, self.hl
            elif q == 2:                                # jp (hl)
                self.pc = self.hl
            else:                                       # ld sp,hl
                self.sp = self.hl
            return
        if z == 2:                                      # jp cc,nn
            a = self.fetch_w()
            if self.cond(y):
                self.pc = a
            return
        if z == 3:
            if y == 0:
                self.pc = self.fetch_w()
            elif y == 1:
                self.cb()
            elif y == 2:                                # out (n),a
                self.io_write((self.a << 8) | self.fetch(), self.a)
            elif y == 3:                                # in a,(n)
                n = self.fetch()
                v = self.default_in
                if n == 0xFE:                           # the keyboard: every
                    for r in range(8):                  # half row whose line
                        if not self.a & (1 << r):       # is low, ANDed
                            v &= self.ports.get(((0xFF ^ (1 << r)) << 8)
                                                | 0xFE, 0xFF)
                self.a = v
            elif y == 4:                                # ex (sp),hl
                v = self.rw(self.sp)
                self.ww(self.sp, self.hl)
                self.hl = v
            elif y == 5:                                # ex de,hl
                self.de, self.hl = self.hl, self.de
            elif y == 6:
                self.iff1 = self.iff2 = 0
            else:
                self.iff1 = self.iff2 = 1
            return
        if z == 4:                                      # call cc,nn
            a = self.fetch_w()
            if self.cond(y):
                self.push(self.pc)
                self.pc = a
            return
        if z == 5:
            if not y & 1:                               # push rr
                self.push(self.af if y >> 1 == 3 else self.get_rp(y >> 1))
                return
            q = y >> 1
            if q == 0:                                  # call nn
                a = self.fetch_w()
                self.push(self.pc)
                self.pc = a
            elif q == 2:
                self.ed()
            else:
                raise NotImplementedError('DD/FD at %04X' % (self.pc - 1))
            return
        if z == 6:                                      # alu a,n
            self.alu(y, self.fetch())
            return
        self.push(self.pc)                              # rst
        self.pc = y * 8

    def cb(self):
        op = self.fetch()
        z, y, kind = op & 7, (op >> 3) & 7, op >> 6
        self.cycles += 4 if z != 6 else 8 if kind == 1 else 11
        v = self.get_r(z)
        if kind == 0:
            c = 1 if self.f & CF else 0
            if y == 0:                                  # rlc
                nc = v >> 7
                v = ((v << 1) | nc) & 0xff
            elif y == 1:                                # rrc
                nc = v & 1
                v = ((v >> 1) | (nc << 7)) & 0xff
            elif y == 2:                                # rl
                nc = v >> 7
                v = ((v << 1) | c) & 0xff
            elif y == 3:                                # rr
                nc = v & 1
                v = ((v >> 1) | (c << 7)) & 0xff
            elif y == 4:                                # sla
                nc = v >> 7
                v = (v << 1) & 0xff
            elif y == 5:                                # sra
                nc = v & 1
                v = ((v >> 1) | (v & 0x80)) & 0xff
            elif y == 6:                                # sll
                nc = v >> 7
                v = ((v << 1) | 1) & 0xff
            else:                                       # srl
                nc = v & 1
                v = (v >> 1) & 0xff
            self.f = self.sz(v) | PARITY[v] | nc
            self.set_r(z, v)
        elif kind == 1:                                 # bit
            r = v & (1 << y)
            self.f = ((self.f & CF) | HF | (self.sz(r) & (SF | ZF)) |
                      (0 if r else PF) | (v & (YF | XF)))
        elif kind == 2:                                 # res
            self.set_r(z, v & ~(1 << y))
        else:                                           # set
            self.set_r(z, v | (1 << y))

    def ed(self):
        op = self.fetch()
        z, y = op & 7, (op >> 3) & 7
        if op in (0xA0, 0xA8, 0xB0, 0xB8):              # ldi/ldd/ldir/lddr
            step = 1 if not op & 8 else -1
            while True:
                self.wb(self.de, self.rb(self.hl))
                self.hl = (self.hl + step) & 0xffff
                self.de = (self.de + step) & 0xffff
                self.bc = (self.bc - 1) & 0xffff
                # ldi/ldd take 16; ldir/lddr take 21 for every pass but the
                # last, which is a plain 16 -- and counting them all at 21
                # made every block move look a third dearer than it is.
                repeat = op & 0x10 and self.bc
                self.cycles += 21 if repeat else 16
                if not repeat:
                    break
            self.cycles -= 4                            # the prefix's, counted
            self.f &= SF | ZF | CF
            self.f |= PF if self.bc else 0
            return
        if not 0x40 <= op < 0x80:                       # the rest is undefined
            return
        self.cycles += (8, 8, 11, 16, 4, 10, 4, 5)[z]    # the prefix's four on
        if op in (0x67, 0x6F):                          # rrd, rld
            raise NotImplementedError('ED %02X at %04X' % (op, self.pc - 2))
        if op in (0x44, 0x4C, 0x54, 0x5C, 0x64, 0x6C, 0x74, 0x7C):   # neg
            self.a = self.sub8(0, self.a)
            return
        if op in (0x45, 0x4D, 0x55, 0x5D, 0x65, 0x6D, 0x75, 0x7D):   # ret[in]
            self.pc = self.pop()
            self.iff1 = self.iff2
            return
        if z == 0:                                      # in r,(c)
            v = self.ports.get(self.bc, self.default_in)
            if y != 6:
                self.set_r(y, v)
            self.f = (self.f & CF) | self.sz(v) | PARITY[v]
            return
        if z == 1:                                      # out (c),r
            self.io_write(self.bc, 0 if y == 6 else self.get_r(y))
            return
        if z == 2:                                      # sbc/adc hl,rr
            a, b = self.hl, self.get_rp(y >> 1)
            c = 1 if self.f & CF else 0
            if not y & 1:
                r = a - b - c
                h = ((a ^ b ^ (r & 0xffff)) >> 8) & HF
                v = PF if ((a ^ b) & (a ^ r) & 0x8000) else 0
                self.f = (self.sz((r >> 8) & 0xff) & (SF | YF | XF)) | h | v | NF
                self.f |= CF if r < 0 else 0
            else:
                r = a + b + c
                h = ((a ^ b ^ (r & 0xffff)) >> 8) & HF
                v = PF if ((a ^ ~b) & (a ^ r) & 0x8000) else 0
                self.f = (self.sz((r >> 8) & 0xff) & (SF | YF | XF)) | h | v
                self.f |= CF if r > 0xffff else 0
            r &= 0xffff
            self.f |= ZF if r == 0 else 0
            self.hl = r
            return
        if z == 3:                                      # ld (nn),rr / ld rr,(nn)
            a = self.fetch_w()
            if not y & 1:
                self.ww(a, self.get_rp(y >> 1))
            else:
                self.set_rp(y >> 1, self.rw(a))
            return
        if z == 6:                                      # im n
            self.im = [0, 0, 1, 2][y & 3]
            return
        if z == 7:                                      # ld i,a and friends
            if op == 0x47:
                self.i = self.a
            elif op == 0x57:
                self.a = self.i
                self.f = (self.f & CF) | self.sz(self.a) | (PF if self.iff2 else 0)
            return
        raise NotImplementedError('ED %02X at %04X' % (op, self.pc - 2))

    # -- running --------------------------------------------------------

    def run(self, frames=1, limit=40000000):
        """Run until `frames` HALTs have gone by, or the limit is reached."""
        target = self.frames + frames
        n = 0
        while self.frames < target and n < limit:
            self.step()
            n += 1
        return n
