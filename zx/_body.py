import io

# ---- the reference: where a front piece is solid enough to hide him -------
p = 'tools/mkassets.py'
s = io.open(p, encoding='utf-8').read()


def sub(old, new, n=1):
    global s
    assert s.count(old) == n, (s.count(old), old[:80])
    s = s.replace(old, new)


sub("""    fore = [bytearray(ROOM_PX) for _ in range(192)]""",
    """    # A front piece is not opaque across its whole rectangle.  A column is
    # thirteen pixels of body and then seven of thinly dithered shadow beside
    # it; a pillar is eight pixels of nothing, then its body.  Masking the
    # whole rectangle hides him where he should be seen, and masking only the
    # lit pixels lets him through the body's own dither -- which on the Apple
    # reads as solid colour and here does not.  So the mask is the span of
    # columns that are lit in half their rows or more.
    fore = [bytearray(ROOM_PX) for _ in range(192)]""")

sub("""            x0 = (col * 4 + renderroom.bg.frontx[t]) * 7
            ybot = ay + renderroom.bg.fronty[t]
            for y in range(max(0, ybot - img.height + 1), min(192, ybot + 1)):
                for x in range(max(0, x0), min(ROOM_PX, x0 + img.width * 7)):
                    fore[y][x] = 1""",
    """            lo, hi = front_body(img)
            if lo is None:
                continue
            x0 = (col * 4 + renderroom.bg.frontx[t]) * 7 + lo
            ybot = ay + renderroom.bg.fronty[t]
            for y in range(max(0, ybot - img.height + 1), min(192, ybot + 1)):
                for x in range(max(0, x0), min(ROOM_PX, x0 + hi - lo + 1)):
                    fore[y][x] = 1""")

sub("""def band_mask(px):""",
    """def front_body(img):
    \"\"\"The columns of a front piece that are lit in half their rows or more.\"\"\"
    wide = img.width * 7
    dense = []
    for x in range(wide):
        lit = sum(1 for y in range(img.height)
                  if img.data[y * img.width + x // 7] & 0x7f & (1 << (x % 7)))
        if lit * 2 >= img.height:
            dense.append(x)
    return (dense[0], dense[-1]) if dense else (None, None)


def band_mask(px):""")

io.open(p, 'w', encoding='utf-8').write(s)
print('the reference masks the body, not the rectangle')
