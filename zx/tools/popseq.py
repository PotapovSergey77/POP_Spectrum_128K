"""
Read SEQTABLE.S.

POP animates every character from a byte code of its own, and SEQTABLE.S is
the whole of it: a numbered entry table, then the sequences.  Rather than
transcribe the ones we happen to want -- which is how mistakes get in -- this
parses the file and keeps POP's own encoding, opcodes, numbering and all.

    db 7,chx,5          frame 7, then five units forward
    db goto / dw hang   jump to another sequence

A byte under 0xF1 is a frame; 0xFF down to 0xF1 are the instructions, exactly
the values SEQDATA.S gives them.  Labels beginning with a colon are local to
the global label above them, as the Apple assembler had it.

    entries   {sequence number: label}, from the :N dw lines
    code      the assembled byte code
    at        {label: offset into code}
    fixups    [(offset, label)] -- two byte addresses to fill in once placed
"""
import os
import re

OPCODES = {
    'goto': -1, 'aboutface': -2, 'up': -3, 'down': -4, 'chx': -5, 'chy': -6,
    'act': -7, 'setfall': -8, 'ifwtless': -9, 'die': -10, 'jaru': -11,
    'jard': -12, 'effect': -13, 'tap': -14, 'nextlevel': -15,
}
SKIP = ('org', 'tr', 'lst', 'lstdo', 'sav', 'dsk', 'put', 'end')


class Table(object):
    def __init__(self, path):
        self.entries, self.at, self.fixups = {}, {}, []
        self.code = bytearray()
        self._parse(path)

    def _parse(self, path):
        """Line by line into ('label'|'byte'|'word', text)."""
        stream = []
        for raw in open(path):
            line = raw.rstrip()
            if not line.strip() or line.lstrip().startswith('*'):
                continue
            label, rest = self._split(line)
            if rest.startswith('='):
                continue                            # an equate, not a label
            if label:
                stream.append(('label', label))
            if not rest:
                continue
            op, _, args = rest.partition(' ')
            op = op.lower()
            if op in SKIP or '=' in rest.split(' ')[0]:
                continue
            if op not in ('db', 'dw'):
                continue
            args = args.split(';')[0]               # trailing comment
            args = [a.strip() for a in args.split(',') if a.strip()]
            for a in args:
                stream.append(('byte' if op == 'db' else 'word', a))
        self._assemble(stream)

    @staticmethod
    def _split(line):
        """A label in column one, and whatever follows it."""
        if line[0] in ' \t':
            return None, line.strip()
        m = re.match(r'(\S+)\s*(.*)$', line)
        return m.group(1), m.group(2).strip()

    def _assemble(self, stream):
        """
        Two things share the file: the numbered entry table at the top, whose
        labels are :1 .. :114 with no global label above them, and then the
        sequences.  A local label belongs to the global label above it, so a
        reference to :loop means the one inside the sequence being read.
        """
        scope, entry = '', None
        for kind, val in stream:
            if kind == 'label':
                if val.startswith(':'):
                    if not scope and re.match(r'^:\d+$', val):
                        entry = int(val[1:])        # still in the entry table
                        continue
                    self.at.setdefault(scope + val, len(self.code))
                else:
                    scope, entry = val, None
                    self.at.setdefault(val, len(self.code))
                continue
            if kind == 'byte':
                self.code.append(self._value(val) & 0xff)
                continue
            if entry is not None:                   # :N dw label
                self.entries[entry] = val
                continue
            self.fixups.append((len(self.code),
                                scope + val if val.startswith(':') else val))
            self.code += bytes(2)

    def _value(self, tok):
        if tok in OPCODES:
            return OPCODES[tok]
        if re.match(r'^-?\d+$', tok):
            return int(tok)
        if tok.startswith('$'):
            return int(tok[1:], 16)
        raise SystemExit('SEQTABLE: did not understand %r' % tok)

    # -- what the rest of the build wants ----------------------------------

    # How many bytes of operand each instruction takes.
    OPERANDS = {0xFF: 2, 0xFE: 0, 0xFD: 0, 0xFC: 0, 0xFB: 1, 0xFA: 1,
                0xF9: 1, 0xF8: 2, 0xF7: 2, 0xF6: 0, 0xF5: 0, 0xF4: 0,
                0xF3: 1, 0xF2: 1, 0xF1: 0}

    def target(self, off):
        """The label a two byte address at `off` points at."""
        for at, label in self.fixups:
            if at == off:
                return label
        return None

    def walk(self, entries):
        """
        Frames reachable from these sequence numbers, following every goto.
        A guard's or the princess's frames are in the file too, and there is
        no reason to carry them.
        """
        seen, frames = set(), []
        todo = [self.at[self.entries[n]] for n in entries if n in self.entries]
        while todo:
            i = todo.pop()
            while True:
                if i in seen or i >= len(self.code):
                    break
                seen.add(i)
                b = self.code[i]
                if b < 0xF1:
                    if b not in frames:
                        frames.append(b)
                    i += 1
                    continue
                nops = self.OPERANDS.get(b, 0)
                if b in (0xFF, 0xF7):               # goto, ifwtless
                    label = self.target(i + 1)
                    if label in self.at:
                        todo.append(self.at[label])
                    if b == 0xFF:
                        break                       # goto does not fall thru
                i += 1 + nops
        return frames


def load(root=None):
    root = root or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', '..', '01 POP Source', 'Source')
    return Table(os.path.join(root, 'SEQTABLE.S'))
