"""
A 6502, enough of one to run Music System ][ as it ran on the Apple: every
documented instruction, with the cycles the real part takes, and a hook for
the memory reads that are really soft switches -- the speaker at $C030.
No decimal mode: nothing run here uses it.
"""

MODES = """
00 BRK imp 7;01 ORA izx 6;05 ORA zp 3;06 ASL zp 5;08 PHP imp 3;09 ORA imm 2;0A ASL acc 2;0D ORA abs 4;0E ASL abs 6;
10 BPL rel 2;11 ORA izy 5;15 ORA zpx 4;16 ASL zpx 6;18 CLC imp 2;19 ORA aby 4;1D ORA abx 4;1E ASL abx 7;
20 JSR abs 6;21 AND izx 6;24 BIT zp 3;25 AND zp 3;26 ROL zp 5;28 PLP imp 4;29 AND imm 2;2A ROL acc 2;2C BIT abs 4;2D AND abs 4;2E ROL abs 6;
30 BMI rel 2;31 AND izy 5;35 AND zpx 4;36 ROL zpx 6;38 SEC imp 2;39 AND aby 4;3D AND abx 4;3E ROL abx 7;
40 RTI imp 6;41 EOR izx 6;45 EOR zp 3;46 LSR zp 5;48 PHA imp 3;49 EOR imm 2;4A LSR acc 2;4C JMP abs 3;4D EOR abs 4;4E LSR abs 6;
50 BVC rel 2;51 EOR izy 5;55 EOR zpx 4;56 LSR zpx 6;58 CLI imp 2;59 EOR aby 4;5D EOR abx 4;5E LSR abx 7;
60 RTS imp 6;61 ADC izx 6;65 ADC zp 3;66 ROR zp 5;68 PLA imp 4;69 ADC imm 2;6A ROR acc 2;6C JMP ind 5;6D ADC abs 4;6E ROR abs 6;
70 BVS rel 2;71 ADC izy 5;75 ADC zpx 4;76 ROR zpx 6;78 SEI imp 2;79 ADC aby 4;7D ADC abx 4;7E ROR abx 7;
81 STA izx 6;84 STY zp 3;85 STA zp 3;86 STX zp 3;88 DEY imp 2;8A TXA imp 2;8C STY abs 4;8D STA abs 4;8E STX abs 4;
90 BCC rel 2;91 STA izy 6;94 STY zpx 4;95 STA zpx 4;96 STX zpy 4;98 TYA imp 2;99 STA aby 5;9A TXS imp 2;9D STA abx 5;
A0 LDY imm 2;A1 LDA izx 6;A2 LDX imm 2;A4 LDY zp 3;A5 LDA zp 3;A6 LDX zp 3;A8 TAY imp 2;A9 LDA imm 2;AA TAX imp 2;AC LDY abs 4;AD LDA abs 4;AE LDX abs 4;
B0 BCS rel 2;B1 LDA izy 5;B4 LDY zpx 4;B5 LDA zpx 4;B6 LDX zpy 4;B8 CLV imp 2;B9 LDA aby 4;BA TSX imp 2;BC LDY abx 4;BD LDA abx 4;BE LDX aby 4;
C0 CPY imm 2;C1 CMP izx 6;C4 CPY zp 3;C5 CMP zp 3;C6 DEC zp 5;C8 INY imp 2;C9 CMP imm 2;CA DEX imp 2;CC CPY abs 4;CD CMP abs 4;CE DEC abs 6;
D0 BNE rel 2;D1 CMP izy 5;D5 CMP zpx 4;D6 DEC zpx 6;D8 CLD imp 2;D9 CMP aby 4;DD CMP abx 4;DE DEC abx 7;
E0 CPX imm 2;E1 SBC izx 6;E4 CPX zp 3;E5 SBC zp 3;E6 INC zp 5;E8 INX imp 2;E9 SBC imm 2;EA NOP imp 2;EC CPX abs 4;ED SBC abs 4;EE INC abs 6;
F0 BEQ rel 2;F1 SBC izy 5;F5 SBC zpx 4;F6 INC zpx 6;F8 SED imp 2;F9 SBC aby 4;FD SBC abx 4;FE INC abx 7
"""
OPS = {}
for _item in MODES.replace('\n', '').split(';'):
    _item = _item.strip()
    if _item:
        _c, _mn, _mode, _cyc = _item.split()
        OPS[int(_c, 16)] = (_mn, _mode, int(_cyc))

READS_CROSS = ('ORA', 'AND', 'EOR', 'ADC', 'LDA', 'LDX', 'LDY', 'CMP', 'SBC')


class CPU:
    def __init__(self):
        self.mem = bytearray(0x10000)
        self.a = self.x = self.y = 0
        self.sp = 0xff
        self.pc = 0
        self.c = self.z = self.i = self.v = self.n = 0
        self.cycles = 0
        self.on_read = {}               # address -> fn(cpu), for soft switches

    def rd(self, a):
        f = self.on_read.get(a)
        if f:
            f(self)
        return self.mem[a]

    def wr(self, a, v):
        self.mem[a] = v & 0xff

    def nz(self, v):
        v &= 0xff
        self.z = int(v == 0)
        self.n = v >> 7
        return v

    def push(self, v):
        self.mem[0x100 + self.sp] = v & 0xff
        self.sp = (self.sp - 1) & 0xff

    def pull(self):
        self.sp = (self.sp + 1) & 0xff
        return self.mem[0x100 + self.sp]

    def flags(self):
        return ((self.n << 7) | (self.v << 6) | 0x30 | (self.i << 2)
                | (self.z << 1) | self.c)

    def setflags(self, p):
        self.n, self.v, self.i = p >> 7 & 1, p >> 6 & 1, p >> 2 & 1
        self.z, self.c = p >> 1 & 1, p & 1

    def step(self):
        m = self.mem
        mn, mode, cyc = OPS[m[self.pc]]
        pc = self.pc + 1
        addr = None
        if mode == 'imm':
            addr = pc
            pc += 1
        elif mode == 'zp':
            addr = m[pc]
            pc += 1
        elif mode == 'zpx':
            addr = (m[pc] + self.x) & 0xff
            pc += 1
        elif mode == 'zpy':
            addr = (m[pc] + self.y) & 0xff
            pc += 1
        elif mode == 'abs':
            addr = m[pc] | m[pc + 1] << 8
            pc += 2
        elif mode in ('abx', 'aby'):
            base = m[pc] | m[pc + 1] << 8
            pc += 2
            addr = (base + (self.x if mode == 'abx' else self.y)) & 0xffff
            if (base ^ addr) & 0xff00 and mn in READS_CROSS:
                cyc += 1
        elif mode == 'izx':
            zp = (m[pc] + self.x) & 0xff
            pc += 1
            addr = m[zp] | m[(zp + 1) & 0xff] << 8
        elif mode == 'izy':
            zp = m[pc]
            pc += 1
            base = m[zp] | m[(zp + 1) & 0xff] << 8
            addr = (base + self.y) & 0xffff
            if (base ^ addr) & 0xff00 and mn != 'STA':
                cyc += 1
        elif mode == 'ind':
            p = m[pc] | m[pc + 1] << 8
            pc += 2
            addr = m[p] | m[(p & 0xff00) | ((p + 1) & 0xff)] << 8
        elif mode == 'rel':
            off = m[pc]
            pc += 1
            addr = (pc + (off - 256 if off > 127 else off)) & 0xffff
        self.pc = pc
        self.cycles += cyc
        getattr(self, 'op_' + mn)(mode, addr)

    def val(self, mode, addr):
        return self.a if mode == 'acc' else self.rd(addr)

    def put(self, mode, addr, v):
        if mode == 'acc':
            self.a = v & 0xff
        else:
            self.wr(addr, v)

    def branch(self, cond, addr):
        if cond:
            self.cycles += 1 + (((self.pc ^ addr) & 0xff00) != 0)
            self.pc = addr

    def op_ORA(self, mo, a): self.a = self.nz(self.a | self.rd(a))
    def op_AND(self, mo, a): self.a = self.nz(self.a & self.rd(a))
    def op_EOR(self, mo, a): self.a = self.nz(self.a ^ self.rd(a))
    def op_LDA(self, mo, a): self.a = self.nz(self.rd(a))
    def op_LDX(self, mo, a): self.x = self.nz(self.rd(a))
    def op_LDY(self, mo, a): self.y = self.nz(self.rd(a))
    def op_STA(self, mo, a): self.wr(a, self.a)
    def op_STX(self, mo, a): self.wr(a, self.x)
    def op_STY(self, mo, a): self.wr(a, self.y)
    def op_TAX(self, mo, a): self.x = self.nz(self.a)
    def op_TAY(self, mo, a): self.y = self.nz(self.a)
    def op_TXA(self, mo, a): self.a = self.nz(self.x)
    def op_TYA(self, mo, a): self.a = self.nz(self.y)
    def op_TSX(self, mo, a): self.x = self.nz(self.sp)
    def op_TXS(self, mo, a): self.sp = self.x
    def op_INX(self, mo, a): self.x = self.nz(self.x + 1)
    def op_INY(self, mo, a): self.y = self.nz(self.y + 1)
    def op_DEX(self, mo, a): self.x = self.nz(self.x - 1)
    def op_DEY(self, mo, a): self.y = self.nz(self.y - 1)
    def op_INC(self, mo, a): self.wr(a, self.nz(self.rd(a) + 1))
    def op_DEC(self, mo, a): self.wr(a, self.nz(self.rd(a) - 1))
    def op_CLC(self, mo, a): self.c = 0
    def op_SEC(self, mo, a): self.c = 1
    def op_CLI(self, mo, a): self.i = 0
    def op_SEI(self, mo, a): self.i = 1
    def op_CLV(self, mo, a): self.v = 0
    def op_CLD(self, mo, a): pass
    def op_SED(self, mo, a): pass
    def op_NOP(self, mo, a): pass
    def op_PHA(self, mo, a): self.push(self.a)
    def op_PLA(self, mo, a): self.a = self.nz(self.pull())
    def op_PHP(self, mo, a): self.push(self.flags())
    def op_PLP(self, mo, a): self.setflags(self.pull())

    def cmp(self, r, v):
        t = r - v
        self.c = int(t >= 0)
        self.nz(t)

    def op_CMP(self, mo, a): self.cmp(self.a, self.rd(a))
    def op_CPX(self, mo, a): self.cmp(self.x, self.rd(a))
    def op_CPY(self, mo, a): self.cmp(self.y, self.rd(a))

    def op_ADC(self, mo, a):
        v = self.rd(a)
        t = self.a + v + self.c
        self.v = int(((self.a ^ t) & (v ^ t) & 0x80) != 0)
        self.c = int(t > 0xff)
        self.a = self.nz(t)

    def op_SBC(self, mo, a):
        v = self.rd(a) ^ 0xff
        t = self.a + v + self.c
        self.v = int(((self.a ^ t) & (v ^ t) & 0x80) != 0)
        self.c = int(t > 0xff)
        self.a = self.nz(t)

    def op_BIT(self, mo, a):
        v = self.rd(a)
        self.z = int((self.a & v) == 0)
        self.n, self.v = v >> 7 & 1, v >> 6 & 1

    def op_ASL(self, mo, a):
        v = self.val(mo, a)
        self.c = v >> 7
        self.put(mo, a, self.nz(v << 1))

    def op_LSR(self, mo, a):
        v = self.val(mo, a)
        self.c = v & 1
        self.put(mo, a, self.nz(v >> 1))

    def op_ROL(self, mo, a):
        v = self.val(mo, a)
        t = (v << 1) | self.c
        self.c = v >> 7
        self.put(mo, a, self.nz(t))

    def op_ROR(self, mo, a):
        v = self.val(mo, a)
        t = (v >> 1) | (self.c << 7)
        self.c = v & 1
        self.put(mo, a, self.nz(t))

    def op_JMP(self, mo, a): self.pc = a

    def op_JSR(self, mo, a):
        r = (self.pc - 1) & 0xffff
        self.push(r >> 8)
        self.push(r)
        self.pc = a

    def op_RTS(self, mo, a):
        lo = self.pull()
        hi = self.pull()
        self.pc = (((hi << 8) | lo) + 1) & 0xffff

    def op_RTI(self, mo, a):
        self.setflags(self.pull())
        lo = self.pull()
        hi = self.pull()
        self.pc = hi << 8 | lo

    def op_BRK(self, mo, a):
        raise RuntimeError('BRK at %04X' % ((self.pc - 1) & 0xffff))

    def op_BPL(self, mo, a): self.branch(not self.n, a)
    def op_BMI(self, mo, a): self.branch(self.n, a)
    def op_BVC(self, mo, a): self.branch(not self.v, a)
    def op_BVS(self, mo, a): self.branch(self.v, a)
    def op_BCC(self, mo, a): self.branch(not self.c, a)
    def op_BCS(self, mo, a): self.branch(self.c, a)
    def op_BNE(self, mo, a): self.branch(not self.z, a)
    def op_BEQ(self, mo, a): self.branch(self.z, a)

    def call(self, addr, limit=10 ** 8):
        """JSR addr, and run until it returns."""
        self.push(0xff)
        self.push(0xfe)                 # returns to $FFFF
        self.pc = addr
        n = 0
        while self.pc != 0xffff:
            self.step()
            n += 1
            if n > limit:
                raise RuntimeError('ran away at %04X' % self.pc)
