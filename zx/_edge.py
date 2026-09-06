import io

p = 'src/pop.asm'
s = io.open(p, encoding='utf-8').read()


def sub(old, new, n=1):
    global s
    assert s.count(old) == n, (s.count(old), old[:80])
    s = s.replace(old, new)


# ---- remember which bank is in, so a lookup can borrow another -------------
sub("""pageset:        or      0x10            ; bit 4 keeps the 48K ROM, which is""",
    """pageset:        ld      (nowbank), a    ; so a routine that has to borrow
                or      0x10            ; another can put this one back
                                        ; bit 4 keeps the 48K ROM, which is""")

sub("""artbank:        db      BANK_ART""",
    """artbank:        db      BANK_ART
nowbank:        db      BANK_ART""")

# ---- the block lookup, with RDBLOCK's handler ------------------------------
sub("""tile_flags:     call    inroom
                jr      nc, tilenone
                ld      de, blockof
                add     hl, de
                ld      a, (hl)
                cp      10
                jr      nc, tilenone
                ld      l, a
                ld      h, 0
                ld      de, (tilerow)   ; the row he stands on
                add     hl, de
                ld      a, (hl)
                and     0x1f            ; getobjid: the low five bits of it
                ret""",
    """tile_flags:     ld      a, (blocky)
                ld      c, a
                jr      tile_in_row2

tile_in_row:    call    blockcol_of
                jr      tirgo""")

sub("""tile_in_row:    call    inroom
                jr      nc, tilenone
                ld      de, blockof
                add     hl, de
                ld      a, (hl)
                cp      10
                jr      nc, tilenone
                ld      b, a
                ld      a, c
                cp      3
                jr      nc, tilenone
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten tiles to the row
                ld      e, b
                ld      d, 0
                add     hl, de
                ld      de, roomids
                add     hl, de
                ld      a, (hl)
                and     0x1f
                ret
tilenone:       xor     a
                ret""",
    """tile_in_row2:   call    blockcol_of
tirgo:          ld      b, a            ; B = the column, C = the row, both
                or      a               ; signed: off the screen is not empty,
                jp      m, tirfar       ; it belongs to the room next door
                cp      10
                jr      nc, tirfar
                ld      a, c
                cp      3
                jr      nc, tirfar

                ld      l, a            ; the common case: this room, and its
                ld      h, 0            ; thirty are already in hand
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten tiles to the row
                ld      e, b
                ld      d, 0
                add     hl, de
                ld      de, roomids
                add     hl, de
                ld      a, (hl)
                and     0x1f
                ret

; HL = a room x.  Out: A = the block column, signed, -2 to 11.  The table
; runs from -64 to 319 so that an index just off either side still resolves.

blockcol_of:    ld      de, BLOCKOF_BIAS
                add     hl, de
                bit     7, h
                jr      nz, bcolow
                ld      a, h
                or      a
                jr      z, bcook
                dec     a
                jr      nz, bcohigh
                ld      a, l
                cp      BLOCKOF_LEN - 256
                jr      nc, bcohigh
bcook:          ld      de, blockof
                add     hl, de
                ld      a, (hl)
                sub     2               ; the table is biased by two columns
                ret
bcolow:         ld      a, -2
                ret
bcohigh:        ld      a, 11
                ret

; The handler of RDBLOCK in CTRLSUBS.S.  A block index outside the screen
; belongs to the room next door; a room that is not there at all reads as
; solid block, never as space -- otherwise walking off the edge of the world
; is a step into thin air.

tirfar:         ld      a, (nowbank)
                push    af
                call    page_bg
                ld      a, (roomnum)
                ld      (tirroom), a
tirhand:        ld      a, b
                bit     7, a
                jr      z, tirh1
                add     a, 10
                ld      b, a
                ld      e, 0            ; left
                call    tirstep
                jr      tirhand
tirh1:          cp      10
                jr      c, tirh2
                sub     10
                ld      b, a
                ld      e, 1            ; right
                call    tirstep
                jr      tirhand
tirh2:          ld      a, c
                bit     7, a
                jr      z, tirh3
                add     a, 3
                ld      c, a
                ld      e, 2            ; up
                call    tirstep
                jr      tirhand
tirh3:          cp      3
                jr      c, tirgot
                sub     3
                ld      c, a
                ld      e, 3            ; down
                call    tirstep
                jr      tirhand

tirgot:         ld      a, (tirroom)
                or      a
                jr      z, tirnull
                ld      l, c            ; ten blocks to the row
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de
                ld      e, b
                ld      d, 0
                add     hl, de
                ld      c, l
                ld      a, (tirroom)
                call    bluepos
                ld      a, (hl)
                and     0x1f
                ld      b, a
                ld      de, 720
                add     hl, de
                ld      c, (hl)
                ld      a, b
                call    subplate
tirdone:        ld      c, a
                pop     af
                call    pageset
                ld      a, c
                ret
tirnull:        ld      a, BLK_BLOCK    ; nothing that way: a solid wall
                jr      tirdone

; E = which way.  Steps (tirroom) that way, zero if there is no room there.

tirstep:        ld      a, (tirroom)
                or      a
                ret     z
                dec     a
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl          ; four bytes to a room
                ld      d, 0
                add     hl, de
                ld      de, level + 1952
                add     hl, de
                ld      a, (hl)
                ld      (tirroom), a
                ret

tirroom:        db      0

tilenone:       xor     a
                ret""")

# ---- the camera is where it belongs the moment he arrives ------------------
sub("""camback:        ld      a, b
                or      a
                ret     z
                dec     b
                jr      camset""",
    """camback:        ld      a, b
                or      a
                ret     z
                dec     b
                jr      camset

; And on the way into a room, straight to the value it would settle at: he
; comes in at the far side of it and a view that starts over would scroll
; across to find him.

camhome:        ld      hl, (charx)
                ld      de, 128         ; put him in the middle of the band
                or      a
                sbc     hl, de
                bit     7, h
                jr      nz, chzero
                ld      a, h
                or      a
                jr      nz, chmax
                ld      a, l
                srl     a
                srl     a
                srl     a               ; eight pixels to the step
                cp      CAM_MAX
                jr      c, chset
chmax:          ld      a, CAM_MAX
                jr      chset
chzero:         xor     a
chset:          ld      (cam), a
                ret""")

io.open(p, 'w', encoding='utf-8').write(s)

# ---- nrgo ------------------------------------------------------------------
p = 'src/bg.asm'
s = io.open(p, encoding='utf-8').read()

sub("""                call    set_row
                xor     a               ; the view starts over
                ld      (cam), a
                ld      (oldw), a""",
    """                call    set_row
                call    camhome         ; the view is already where he is
                xor     a
                ld      (oldw), a""")

io.open(p, 'w', encoding='utf-8').write(s)

# ---- the table itself ------------------------------------------------------
p = 'tools/mkassets.py'
s = io.open(p, encoding='utf-8').read()

sub("""    blockof = bytearray(ROOM_PX + 8)    # room pixel -> block column""",
    """    # RDBLOCK's handler wants a column for coordinates outside the room as
    # well, so the table is biased: index x + BLOCKOF_BIAS, value column + 2,
    # covering -64 to 319 and columns -2 to 11.
    BLOCKOF_BIAS, BLOCKOF_LEN = 64, 384
    blockof = bytearray(BLOCKOF_LEN)""")

sub("""    for x in range(len(blockof)):
        b = (x - angle_px) // BLOCK_PX
        blockof[x] = b if 0 <= b <= 9 else 0xFF
    open(os.path.join(binout, 'blockof.bin'), 'wb').write(bytes(blockof))""",
    """    for i in range(BLOCKOF_LEN):
        b = (i - BLOCKOF_BIAS - angle_px) // BLOCK_PX
        blockof[i] = max(-2, min(11, b)) + 2
    open(os.path.join(binout, 'blockof.bin'), 'wb').write(bytes(blockof))""")

sub("""        f.write('START_ROW   equ %d\\n' % START_ROW)""",
    """        f.write('START_ROW   equ %d\\n' % START_ROW)
        f.write('BLOCKOF_BIAS equ %d\\n' % BLOCKOF_BIAS)
        f.write('BLOCKOF_LEN equ %d\\n' % BLOCKOF_LEN)""")

io.open(p, 'w', encoding='utf-8').write(s)
print('the room next door is not empty space')
