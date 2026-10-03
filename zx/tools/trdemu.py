"""
A Spectrum 128 with a Beta 128 disk interface, for the disk version: the real
ROMs -- the 128's two and TR-DOS -- on SkoolKit's Z80, and a WD1793 reading
a .trd.  Slow, but whole: the disk is booted as a user boots it, TR-DOS reads
boot and loader, and from there the game's own code drives the controller.

The Beta's ROM is in while the program runs from 0x3D00 to 0x3DFF with the
48K ROM selected, and out again as soon as it runs above 0x3FFF; its ports
answer only while it is in.

    trdemu.py <disk.trd> [frames]      boot it, say where it got

SkoolKit installed, or SKOOLKIT naming a directory with it in (pip install
skoolkit --target there).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ZX = os.path.dirname(HERE)
SK = os.environ.get('SKOOLKIT', r'C:/Users/dev/AppData/Local/Temp/claude/'
                    r'c--Users-dev-development-POP-Spectrum-128K/'
                    r'462e1ff0-e71a-478d-bb70-1ad8c17e9335/scratchpad/sk')
if os.environ.get('SKOOLKIT') or not os.path.isdir(os.path.join(
        sys.prefix, 'Lib', 'site-packages', 'skoolkit')):
    sys.path.insert(0, SK)
sys.path.insert(0, HERE)

from skoolkit.simulator import Simulator    # noqa: E402

FUSE_ROMS = r'C:/Program Files (x86)/Fuse/roms'
TRDOS_ROM = os.path.join(ZX, 'build', 'trdos.rom')

# keyboard: half-row port's high byte bit, and the key's bit in it
KEYMAP = {}
for _row, _keys in enumerate(['^zxcv', 'asdfg', 'qwert', '12345', '09876',
                              'poiuy', '\nlkjh', ' $mnb']):
    for _bit, _k in enumerate(_keys):
        KEYMAP[_k] = (_row, _bit)
KEYMAP['shift'] = KEYMAP['^']
KEYMAP['sym'] = KEYMAP['$']
KEYMAP['enter'] = KEYMAP['\n']
KEYMAP['space'] = KEYMAP[' ']

REVOLUTION = 700000         # T-states a turn of the disk: 300 rpm


class Mem:
    """64K as four 16K pieces, the ROM's not to be written."""
    __slots__ = ('seg',)

    def __init__(self):
        self.seg = [None] * 4

    def __getitem__(self, a):
        return self.seg[a >> 14][a & 0x3FFF]

    def __setitem__(self, a, v):
        if a & 0xC000:
            self.seg[a >> 14][a & 0x3FFF] = v

    def __len__(self):
        return 65536


class WD1793:
    """Enough of the controller for TR-DOS and dload.asm: the stepping
    commands, reading and writing a sector, reading an address, and the
    interrupt; drive A only."""

    def __init__(self, disk):
        self.disk = bytearray(disk)
        self.track = 0
        self.sector = 1
        self.data = 0
        self.cyl = 0
        self.side = 0
        self.drive = 0
        self.intrq = False
        self.drq = False
        self.busy = False
        self.kind = 1
        self.status = 0
        self.hld = False
        self.buf = b''
        self.at = 0
        self.writing = None
        self.dir = 1
        self.log = []           # (command, cylinder, side, sector)

    def ready(self):
        return self.drive == 0 and bool(self.disk)

    def status_now(self, t):
        if self.kind == 1:
            s = 1 if self.busy else 0
            if self.ready():
                if t % REVOLUTION < 10000:
                    s |= 2
                if self.cyl == 0:
                    s |= 4
                if self.hld:
                    s |= 0x20
            else:
                s |= 0x80
            return s
        s = self.status
        if self.busy:
            s |= 1
        if self.drq:
            s |= 2
        return s

    def offset(self):
        return ((self.cyl * 2 + self.side) * 16 + self.sector - 1) * 256

    def found(self):
        return (self.ready() and self.track == self.cyl and 1 <= self.sector <= 16
                and self.cyl < 80)

    def command(self, v):
        if v & 0xF0 == 0xD0:                    # FORCE INTERRUPT
            self.busy = self.drq = False
            self.intrq = bool(v & 0x0F)
            self.kind = 1
            return
        self.intrq = False
        self.log.append((v, self.cyl, self.side, self.sector))
        if not v & 0x80:                        # type I
            hi = v >> 4
            if hi == 0:
                self.cyl = self.track = 0
            elif hi == 1:
                self.cyl = max(0, min(83, self.cyl + self.data - self.track))
                self.dir = 1 if self.data >= self.track else -1
                self.track = self.data
            else:
                if hi >= 6:
                    self.dir = -1
                elif hi >= 4:
                    self.dir = 1
                self.cyl = max(0, min(83, self.cyl + self.dir))
                if v & 0x10:
                    self.track = (self.track + self.dir) & 0xFF
            self.kind = 1
            self.hld = bool(v & 8)
            self.busy = False
            self.intrq = True
            return
        self.kind = 2
        self.status = 0
        if v & 0xE0 == 0x80:                    # READ SECTOR
            if not self.found():
                self.status = 0x10 if self.ready() else 0x80
                self.intrq = True
                return
            o = self.offset()
            self.buf, self.at = self.disk[o:o + 256], 0
            self.busy = self.drq = True
        elif v & 0xE0 == 0xA0:                  # WRITE SECTOR
            if not self.found():
                self.status = 0x10 if self.ready() else 0x80
                self.intrq = True
                return
            self.writing, self.at = self.offset(), 0
            self.busy = self.drq = True
        elif v & 0xF0 == 0xC0:                  # READ ADDRESS
            if not self.ready():
                self.status = 0x80
                self.intrq = True
                return
            self.buf, self.at = bytes([self.cyl, 0, 1, 1, 0, 0]), 0
            self.busy = self.drq = True
        else:                                   # the track ones: none here
            self.intrq = True

    def read(self, port, t):
        if port == 0x1F:
            self.intrq = False
            return self.status_now(t)
        if port == 0x3F:
            return self.track
        if port == 0x5F:
            return self.sector
        if port == 0x7F:
            if self.drq and self.writing is None:
                self.data = self.buf[self.at]
                self.at += 1
                if self.at == len(self.buf):
                    self.drq = self.busy = False
                    self.intrq = True
            return self.data
        return (0x80 if self.intrq else 0) | (0x40 if self.drq else 0) | 0x3F

    def write(self, port, v, t):
        if port == 0x1F:
            self.command(v)
        elif port == 0x3F:
            self.track = v
        elif port == 0x5F:
            self.sector = v
        elif port == 0x7F:
            self.data = v
            if self.drq and self.writing is not None:
                self.disk[self.writing + self.at] = v
                self.at += 1
                if self.at == 256:
                    self.writing = None
                    self.drq = self.busy = False
                    self.intrq = True
        else:
            self.drive = v & 3
            self.side = 0 if v & 0x10 else 1
            if not v & 4:                       # reset: and RESTORE after it
                self.busy = self.drq = False
                self.intrq = False
                self.sector = 1
                self.cyl = self.track = 0
                self.kind = 1


class Machine:
    def __init__(self, disk, pentagon=False):
        if pentagon:
            roms = [os.path.join(ZX, 'build', '128p-%d.rom' % i) for i in (0, 1)]
        else:
            roms = [os.path.join(FUSE_ROMS, '128-%d.rom' % i) for i in (0, 1)]
        self.roms = [bytearray(open(p, 'rb').read()) for p in roms]
        self.trrom = bytearray(open(TRDOS_ROM, 'rb').read())
        self.banks = [bytearray(0x4000) for _ in range(8)]
        self.mem = Mem()
        self.p7ffd = 0
        self.trdos = False
        self.page()
        self.fd = 71680 if pentagon else 70908
        self.inta = 32 if pentagon else 36
        self.sim = Simulator(self.mem, {'PC': 0, 'SP': 0xFFFF},
                             config={'frame_duration': self.fd,
                                     'int_active': self.inta})
        self.sim.set_tracer(self)
        self.R = self.sim.registers
        self.wd = WD1793(open(disk, 'rb').read() if isinstance(disk, str) else disk)
        self.kb = [0] * 8
        self.ay = [0] * 16
        self.ayreg = 0
        self.border = 7
        self.next_int = self.fd
        self.frames = 0
        self.traps = {}

    # -- the hardware ---------------------------------------------------

    def page(self):
        s = self.mem.seg
        s[0] = self.trrom if self.trdos else self.roms[(self.p7ffd >> 4) & 1]
        s[1] = self.banks[5]
        s[2] = self.banks[2]
        s[3] = self.banks[self.p7ffd & 7]

    def read_port(self, registers, port):
        lo = port & 0xFF
        if self.trdos and lo in (0x1F, 0x3F, 0x5F, 0x7F, 0xFF):
            return self.wd.read(lo, registers[25])
        if not port & 1:
            v = 0
            hi = port >> 8
            for row in range(8):
                if not hi & (1 << row):
                    v |= self.kb[row]
            return 0xBF & ~v
        if lo == 0x1F:
            return 0                            # Kempston, at rest
        if port & 0xC002 == 0xC000:
            return self.ay[self.ayreg]
        return 0xFF

    def write_port(self, registers, port, value, *args):
        lo = port & 0xFF
        if self.trdos and lo in (0x1F, 0x3F, 0x5F, 0x7F, 0xFF):
            self.wd.write(lo, value, registers[25])
            return
        if not port & 1:
            self.border = value & 7
        if not port & 0x8002 and not self.p7ffd & 0x20:
            self.p7ffd = value
            self.page()
        if port & 0xC002 == 0xC000:
            self.ayreg = value & 15
        elif port & 0xC002 == 0x8000:
            self.ay[self.ayreg] = value

    def press(self, *keys):
        self.kb = [0] * 8
        for k in keys:
            row, bit = KEYMAP[k]
            self.kb[row] |= 1 << bit

    # -- running ----------------------------------------------------------

    def run(self, frames=None, until=None, tmax=None):
        """On until `frames` more interrupts, or until(pc) says so, or the
        clock reaches tmax.  Out: why it stopped."""
        R, mem, ops = self.R, self.mem, self.sim.opcodes
        sim = self.sim
        stop_frame = None if frames is None else self.frames + frames
        traps = self.traps
        while True:
            pc = R[24]
            if pc < 0x4000:
                if not self.trdos and pc & 0xFF00 == 0x3D00 and self.p7ffd & 0x10:
                    self.trdos = True
                    self.page()
            elif self.trdos:
                self.trdos = False
                self.page()
            if pc in traps:
                traps[pc](self)
                pc = R[24]
            if until is not None and until(pc):
                return 'until'
            ops[mem[pc]]()
            t = R[25]
            if t >= self.next_int:
                if t < self.next_int + self.inta:
                    if R[26] and sim.accept_interrupt(R, mem, pc):
                        self.next_int += self.fd
                        self.frames += 1
                        if stop_frame is not None and self.frames >= stop_frame:
                            return 'frames'
                else:
                    self.next_int += self.fd
                    self.frames += 1
                    if stop_frame is not None and self.frames >= stop_frame:
                        return 'frames'
            if R[28] and R[26] and R[25] < self.next_int:
                R[25] = self.next_int
            if tmax is not None and t >= tmax:
                return 'time'

    def type_keys(self, seq, hold=4, gap=4):
        """Each a key, or a tuple of keys held together."""
        for k in seq:
            self.press(*(k if isinstance(k, tuple) else (k,)))
            self.run(frames=hold)
            self.press()
            self.run(frames=gap)

    def state(self):
        """Everything that changes, to come back to (restore)."""
        wd = dict((k, v) for k, v in vars(self.wd).items() if k != 'disk')
        return {'banks': [bytes(b) for b in self.banks], 'R': list(self.R),
                'p7ffd': self.p7ffd, 'trdos': self.trdos, 'kb': list(self.kb),
                'ay': list(self.ay), 'ayreg': self.ayreg,
                'next_int': self.next_int, 'frames': self.frames,
                'border': self.border, 'wd': wd}

    def restore(self, st):
        for b, d in zip(self.banks, st['banks']):
            b[:] = d
        self.R[:] = st['R']
        for k in ('p7ffd', 'trdos', 'ayreg', 'next_int', 'frames', 'border'):
            setattr(self, k, st[k])
        self.kb, self.ay = list(st['kb']), list(st['ay'])
        for k, v in st['wd'].items():
            setattr(self.wd, k, v)
        self.page()

    def screen(self):
        bank = 7 if self.p7ffd & 8 else 5
        return bytes(self.banks[bank][:6912])

    def peek(self, a):
        return self.mem[a]

    def peekw(self, a):
        return self.mem[a] | self.mem[(a + 1) & 0xFFFF] << 8

    def bank(self, n):
        return self.banks[n]

    def boot_trdos(self):
        """Reset into 48K BASIC, paging left free as Pentagon's TR-DOS
        leaves it; RANDOMIZE USR 15616, and RUN: TR-DOS loads boot."""
        self.p7ffd = 0x10
        self.page()
        self.R[24] = 0
        self.run(frames=150)                    # the RAM test, and the prompt
        self.type_keys(['t', ('shift', 'sym'), 'l', '1', '5', '6', '1', '6',
                        'enter'])
        self.run(frames=50)
        self.type_keys(['r', 'enter'])


def save_screen(m, path):
    import zxscreen
    zxscreen.preview(m.screen(), path)


def main(argv):
    m = Machine(argv[1], pentagon='--pentagon' in argv)
    m.boot_trdos()
    n = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else 200
    m.run(frames=n)
    print('PC %04X, кадров %d, 7FFD %02X' % (m.R[24], m.frames, m.p7ffd))
    save_screen(m, os.path.join(ZX, 'build', 'png', 'trdemu.png'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
