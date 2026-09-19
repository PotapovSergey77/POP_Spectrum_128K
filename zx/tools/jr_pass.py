"""
Every jp that can be a jr, made one: a byte each, and the map is that full.

A jp is taken in hand only if it is plain or on z, nz, c or nc, to a label,
and not one the program patches (a label on its line that the source takes
+1 or +2 of) nor in the interrupt's stub, which is copied to the top of every
bank and would not jump from there.  A label is put in front of each, the
source assembled, and those whose target is in reach of the next address are
turned into jr.  Taking bytes out only brings things closer, so a jump in
reach before is in reach after.

    jr_pass.py [--dry]          from zx/
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ZX = os.path.join(HERE, '..')
SRC = os.path.join(ZX, 'src')
FILES = ('pop.asm', 'bg.asm', 'fight.asm', 'intro.asm', 'roomblk.asm')
JP = re.compile(r'^(?P<lab>[a-z_][a-z0-9_]*:)?(?P<sp>\s+)jp(?P<sp2>\s+)'
                r'(?:(?P<cc>nz|z|nc|c),\s*)?(?P<t>[a-z_][a-z0-9_]*)\s*(?P<rest>;.*)?$')
SKIP_IN = ('isrstub',)


def main(argv):
    dry = '--dry' in argv
    text = {f: open(os.path.join(SRC, f), encoding='utf-8').read() for f in FILES}
    code = '\n'.join(l.split(';')[0] for t in text.values() for l in t.split('\n'))
    patched = set(re.findall(r'\b([a-z_][a-z0-9_]*)\s*\+\s*[12]\b', code))
    marked = {}
    n = 0
    for f in FILES:
        out = []
        last = None
        for l in text[f].split('\n'):
            m = re.match(r'^([a-z_][a-z0-9_]*):', l)
            if m:
                last = m.group(1)
            j = JP.match(l)
            if j and last not in SKIP_IN and not (j.group('lab') and j.group('lab')[:-1] in patched):
                name = 'jrq_%d' % n
                n += 1
                marked[name] = (f, len(out) + 1, j.group('t'))
                out.append(name + ':')
            out.append(l)
        text[f + '.tmp'] = '\n'.join(out)
    for f in FILES:
        open(os.path.join(SRC, f), 'w', encoding='utf-8').write(text[f + '.tmp'])
    try:
        subprocess.run([os.path.join(ZX, 'tools', 'pasmo.exe'), '--bin', 'pop.asm',
                        '../build/jrq.bin', '../build/jrq.sym'], cwd=SRC, check=True,
                       capture_output=True)
        sym = {}
        for line in open(os.path.join(ZX, 'build', 'jrq.sym')):
            m = re.match(r'(\S+)\s+EQU\s+([0-9A-Fa-f]+)H', line.strip())
            if m:
                sym[m.group(1)] = int(m.group(2), 16)
    finally:
        for f in FILES:
            open(os.path.join(SRC, f), 'w', encoding='utf-8').write(text[f])
    turn = {}
    for name, (f, idx, t) in marked.items():
        if t not in sym:
            continue
        off = sym[t] - (sym[name] + 2)
        if -128 <= off <= 127:
            turn.setdefault(f, set()).add(idx)
    total = 0
    for f in FILES:
        lines = text[f + '.tmp'].split('\n')
        keep = []
        for i, l in enumerate(lines):
            if re.match(r'^jrq_\d+:$', l):
                continue
            if i in turn.get(f, ()):
                l = re.sub(r'^(\S*\s+)jp(\s+)', r'\1jr\2', l, count=1)
                total += 1
            keep.append(l)
        if not dry:
            open(os.path.join(SRC, f), 'w', encoding='utf-8').write('\n'.join(keep))
    print('%d of %d jp turned into jr%s' % (total, len(marked), ' (dry run)' if dry else ''))


if __name__ == '__main__':
    sys.exit(main(sys.argv))
