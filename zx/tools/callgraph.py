"""
Which code only the building of a room reaches, and how big it is.

    callgraph.py [entry ...]

The source is read the way the assembler reads it -- pop.asm with bg.asm in
its place -- and cut at every label into regions, each the bytes up to the
next label (sizes from build/sym.json).  A region reaches every label its
operands name, and the next region too unless it ends in an unconditional
ret, jp or jr, or is data.  What the main loop reaches without going in by
one of the entries (newroom and readlinks by default) has to stay in the
fixed half of the map; what only the entries reach need only be there while
a room is built.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'src')
LABEL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):?\s*(.*)$')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
DATA = ('db', 'dw', 'ds', 'incbin', 'defb', 'defw', 'defs')


def lines():
    out = []
    for raw in open(os.path.join(SRC, 'pop.asm'), encoding='utf-8'):
        m = re.match(r'\s+include\s+"(bg\.asm)"', raw)
        if m:
            out.extend(open(os.path.join(SRC, m.group(1)), encoding='utf-8'))
        else:
            out.append(raw)
    return out


def regions(sym):
    regs = []                       # [name, [instructions]]
    for raw in lines():
        code = raw.split(';', 1)[0].rstrip()
        if not code.strip():
            continue
        if not code[0].isspace():
            m = LABEL.match(code)
            name, rest = m.group(1), m.group(2).strip()
            if rest.split()[:1] == ['equ']:
                continue
            regs.append([name, []])
            if rest:
                regs[-1][1].append(rest)
        elif regs:
            regs[-1][1].append(code.strip())
    return [r for r in regs if r[0] in sym]


def ends(ins):
    if not ins:
        return False
    op = ins[-1].split()
    m = op[0].lower()
    if m in DATA:
        return True
    if m in ('ret', 'reti', 'retn') and len(op) == 1:
        return True
    if m in ('jp', 'jr') and ',' not in ins[-1]:
        return True
    return False


def main(argv):
    sym = json.load(open(os.path.join(HERE, '..', 'build', 'sym.json')))
    entries = argv[1:] or ['newroom', 'readlinks']
    regs = regions(sym)
    names = [r[0] for r in regs]
    idx = {n: i for i, n in enumerate(names)}
    size = {}
    for i, n in enumerate(names):
        nxt = sym[names[i + 1]] if i + 1 < len(names) else sym['codeend']
        size[n] = max(0, nxt - sym[n])
    edges = {}
    data = set()
    for i, (n, ins) in enumerate(regs):
        refs = set()
        for s in ins:
            parts = s.split(None, 1)
            if parts[0].lower() in DATA:
                data.add(n)
            if len(parts) > 1:
                refs.update(t for t in IDENT.findall(parts[1]) if t in idx)
        if not ends(ins) and i + 1 < len(regs):
            refs.add(names[i + 1])
        edges[n] = refs

    def reach(roots, stop):
        seen, todo = set(), list(roots)
        while todo:
            n = todo.pop()
            if n in seen or n in stop:
                continue
            seen.add(n)
            todo.extend(edges.get(n, ()))
        return seen

    init = set(names[idx['start']:idx['initend']]) if 'initend' in idx else set()
    resident = reach(['main'], set(entries))
    room = reach(entries, resident | init)
    fixed_end = sym['codeend']
    mov = [n for n in names if n in room and sym[n] < fixed_end]
    code_b = sum(size[n] for n in mov if n not in data)
    data_b = sum(size[n] for n in mov if n in data)
    print('only a room build reaches %d bytes of code and %d of data:'
          % (code_b, data_b))
    run = []
    for n in mov:
        if run and idx[n] == idx[run[-1]] + 1:
            run.append(n)
        else:
            if run:
                print('  %-14s .. %-14s %5d' % (run[0], run[-1],
                                                 sum(size[x] for x in run)))
            run = [n]
    if run:
        print('  %-14s .. %-14s %5d' % (run[0], run[-1],
                                         sum(size[x] for x in run)))
    # a moved region that falls into a resident one, or the other way
    for i, n in enumerate(names[:-1]):
        m = names[i + 1]
        if m in edges[n] and not ends(regs[i][1]) and ((n in room) != (m in room)):
            print('  falls through: %s -> %s' % (n, m))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
