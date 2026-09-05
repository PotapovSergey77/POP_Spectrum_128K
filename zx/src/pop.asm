; Prince of Persia -- ZX Spectrum
; One room, one prince, driven by the cursor keys.
;
; Animation follows the sequences from SEQTABLE.S, compiled offline into a
; little byte code: a frame with how far it moves, plus jump, about face,
; bare move, and a marker saying which sequence is running so the keys know
; what may interrupt what.
;
; Erasing and drawing straight on the screen makes the sprite blink, so both
; happen in an off screen copy of the room and only the rectangle that
; changed is copied over afterwards.
;
; Sprites are stored byte aligned as (mask, data) pairs and shifted into
; place at draw time: screen = (screen AND mask) OR data.

                org     24576

                include "assets.inc"

SCREEN          equ     16384
BUFW            equ     8               ; widest sprite plus the shift byte
FRAME_WAIT      equ     3               ; 50Hz frames per game frame
BLOCK_PX        equ     28
WALL_DEPTH      equ     12               ; how far into a wall's tile he goes
X_MIN           equ     40
X_MAX           equ     240

; ---------------------------------------------------------------- entry

start:          di
                ld      sp, stack
                im      1

                xor     a
                out     (254), a

                ld      hl, room        ; the screen and the working copy both
                ld      de, SCREEN      ; start out as the bare room
                ld      bc, 6912
                ldir
                ld      hl, room
                ld      de, work
                ld      bc, 6912
                ldir

                include "seqfix.inc"    ; turn sequence offsets into addresses

                ld      a, START_X
                ld      (charx), a
                ld      a, START_Y
                ld      (chary), a
                xor     a
                ld      (facing), a
                ld      (seqid), a
                ld      (oldw), a       ; nothing to erase on the first pass
                ld      (pendchx), a
                ld      a, revtab / 256 ; the reversal table's page
                ld      (mrev1 + 1), a
                ld      (mrev2 + 1), a
                ld      hl, seqs + SQ_STAND
                ld      (seqptr), hl

                call    step_seq
                call    draw_prince
                call    hide_behind
                call    show_rect
                call    keep_rect
                ei

; ---------------------------------------------------------------- main

main:           ld      b, FRAME_WAIT
mainwait:       halt
                djnz    mainwait

                call    erase_prince
                call    input_step
                call    step_seq
                call    draw_prince
                call    hide_behind
                call    show_rect
                call    keep_rect
                jr      main

; ---------------------------------------------------------------- input
;
; Cursor left is key 5, row F7FE bit 4; cursor right is key 8, row EFFE
; bit 2.  Out: A = 0 none, 1 left, 2 right.

read_keys:      ld      bc, 0xF7FE
                in      a, (c)
                bit     4, a
                jr      nz, keyright
                ld      a, 1
                ret
keyright:       ld      bc, 0xEFFE
                in      a, (c)
                bit     2, a
                jr      nz, keynone
                ld      a, 2
                ret
keynone:        xor     a
                ret

; Standing and running listen to the keys; turning, stopping and turning on
; the run play out to their end, as they do in the original.

; A run that has run out of floor or hit a wall skids to a halt.

input_step:     ld      a, (blocked)
                or      a
                jr      z, inputkeys
                ld      a, (seqid)
                cp      ID_RUNCYC
                jr      z, tostopnow
                cp      ID_STARTRUN
                jr      nz, inputkeys
tostopnow:      ld      hl, seqs + SQ_RUNSTOP
                jr      setseq

inputkeys:      call    read_keys
                ld      b, a
                ld      a, (seqid)
                cp      ID_STAND
                jr      z, fromstand
                cp      ID_STARTRUN
                jr      z, fromrun
                cp      ID_RUNCYC
                jr      z, fromrun
                ret

fromstand:      ld      a, b
                or      a
                ret     z
                dec     a               ; 0 = left, 1 = right
                ld      c, a
                ld      a, (facing)
                cp      c
                jr      z, tostartrun
                ld      hl, seqs + SQ_TURN
                jr      setseq
; No point starting a run into a wall or off the edge, or he twitches on the
; spot: stand still instead.

tostartrun:     ld      a, (charx)
                ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      nz, trright
                sub     BLOCK_PX
                jr      trtest
trright:        add     a, BLOCK_PX
trtest:         call    tile_flags
                bit     1, a
                ret     nz
                bit     0, a
                ret     z
                ld      hl, seqs + SQ_STARTRUN
                jr      setseq

fromrun:        ld      a, b
                or      a
                jr      z, torunstop
                dec     a
                ld      c, a
                ld      a, (facing)
                cp      c
                ret     z
                ld      hl, seqs + SQ_RUNTURN
                jr      setseq
torunstop:      ld      hl, seqs + SQ_RUNSTOP
setseq:         ld      (seqptr), hl
                xor     a               ; a new sequence starts from a stop
                ld      (pendchx), a
                ret

; ---------------------------------------------------------------- sequence
;
; Read byte code until a frame comes out, which is this game frame's picture.
;
; The chx written beside a frame in SEQTABLE.S belongs to the step out of it,
; not into it: the interpreter stops on the frame byte and only moves on the
; next pass.  That matters at an about face, where the move and the turn have
; to happen together for the anchor swapping ends to cancel out.

step_seq:       ld      a, (pendchx)
                or      a
                jr      z, seqnopend
                call    move_by
                xor     a
                ld      (pendchx), a
seqnopend:      ld      hl, (seqptr)
seqloop:        ld      a, (hl)
                inc     hl
                cp      SEQ_GOTO
                jr      nz, seqnogoto
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ex      de, hl
                jr      seqloop
seqnogoto:      cp      SEQ_FACE
                jr      nz, seqnoface
                push    hl
                ld      a, (facing)
                xor     1
                ld      (facing), a
                pop     hl
                jr      seqloop
seqnoface:      cp      SEQ_CHX
                jr      nz, seqnoid
                ld      a, (hl)
                inc     hl
                push    hl
                call    move_by
                pop     hl
                jr      seqloop
seqnoid:        cp      SEQ_ID
                jr      nz, seqframe
                ld      a, (hl)
                inc     hl
                ld      (seqid), a
                jr      seqloop
seqframe:       ld      (frame), a
                ld      a, (hl)
                inc     hl
                ld      (pendchx), a
                ld      (seqptr), hl
                ret

; A = chx in logic units, signed.  A logic unit is two screen pixels, and the
; sign follows whichever way the prince faces.

move_by:        ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      nz, movepos
                neg
movepos:        add     a, a
                ld      e, a
                ld      d, 0
                or      a
                jp      p, moveadd
                dec     d               ; sign extend into DE
moveadd:        ld      a, (charx)
                ld      l, a
                ld      h, 0
                add     hl, de
                ld      a, h
                or      a
                jr      z, moverange
                bit     7, h            ; ran off one end or the other
                jr      z, movehigh
                ld      l, X_MIN
                jr      movestore
movehigh:       ld      l, X_MAX
                jr      movestore
moverange:      ld      a, l
                cp      X_MIN
                jr      nc, movetop
                ld      l, X_MIN
                jr      movestore
movetop:        cp      X_MAX
                jr      c, movestore
                ld      l, X_MAX
; The prince may only stand where there is floor, and never inside a wall.
; blockof turns a screen pixel into a block column and tiles says what is in
; it, both built offline from the room's BLUETYPE.

; A step that runs into something does not simply fail: he goes as far as
; he can and stops there, so he ends up against the wall rather than a
; whole stride short of it.

movestore:      ld      c, l            ; C = where he would end up
                ld      a, l
                ld      (wanted), a
movetry:        ld      a, c
                call    check_spot
                jr      nz, moveok
                ld      a, (charx)      ; back off a pixel towards himself
                cp      c
                jr      z, moveblocked
                jr      c, movedec
                inc     c
                jr      movetry
movedec:        dec     c
                jr      movetry
moveok:         ld      a, c
                ld      (charx), a
                ld      hl, wanted      ; a shortened step still counts as
                cp      (hl)            ; running into something
                jr      nz, moveblocked
                xor     a
                ld      (blocked), a
                ret
moveblocked:    ld      a, 1
                ld      (blocked), a
                ret

; A = a screen x.  Out: NZ if he may stand there.
;
; The room is drawn in perspective, and that cuts both ways.  A floor's
; far corner is empty, so his leading foot must have something under it or
; he looks like he is standing on air.  A wall, on the other hand, stands
; at the BACK of its own tile: he can walk most of the way into that tile,
; with the brick drawn over his leading shoulder, before he meets it.

check_spot:     ld      (spotx), a
                call    tile_flags
                bit     1, a
                jr      nz, spotwall
                bit     0, a
                jr      z, spotno
                ld      a, (facing)
                or      a
                ld      a, (spotx)
                jr      nz, spotfwd
                sub     BLOCK_PX / 2
                jr      spotfoot
spotfwd:        add     a, BLOCK_PX / 2
spotfoot:       call    tile_flags
                or      a
                ret

spotwall:       ld      a, (facing)     ; leaning into the wall's tile is
                or      a               ; fine while his weight is behind
                ld      a, (spotx)
                jr      nz, spotback
                add     a, WALL_DEPTH
                jr      spotcheck
spotback:       sub     WALL_DEPTH
spotcheck:      call    tile_flags
                bit     1, a
                jr      nz, spotno
                and     TILE_FLOOR
                ret
spotno:         xor     a
                ret

; A = a screen x.  Out: A = the tile's flags there, zero off the room.

tile_flags:     ld      l, a
                ld      h, 0
                ld      de, blockof
                add     hl, de
                ld      a, (hl)
                cp      10
                jr      nc, tilenone    ; off the edge of the room
                ld      l, a
                ld      h, 0
                ld      de, tiles
                add     hl, de
                ld      a, (hl)
                ret
tilenone:       xor     a
                ret

; ---------------------------------------------------------------- frames
;
; Out: HL = table entry for the current frame and facing.
;      Entry: width, height, xoff, blob offset (2).

frame_entry:    ld      a, (frame)
                ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, l
                add     hl, hl          ; six bytes each
                add     hl, de
                add     hl, hl
                ld      de, sprites
                add     hl, de
                ret

; ---------------------------------------------------------------- draw

draw_prince:    call    frame_entry
                ld      a, (hl)
                ld      (curw), a
                inc     hl
                ld      a, (hl)
                ld      (curh), a
                inc     hl
                ld      (curent), hl    ; two anchor offsets, then the blob
                ld      a, (facing)
                or      a
                jr      z, dpxoff
                inc     hl
dpxoff:         ld      a, (hl)
                ld      (curoff), a
                ld      hl, (curent)
                inc     hl
                inc     hl
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ld      hl, sprites + SPR_BLOB
                add     hl, de
                ld      (curdat), hl

; The anchor is the leading edge, so the offset differs with facing and is
; kept with the sprite rather than worked out here.

                ld      a, (charx)
                ld      b, a
                ld      a, (curoff)
                add     a, b
                ld      b, a
                and     7
                ld      (curshift), a
                ld      a, b
                rra
                rra
                rra
                and     31
                ld      (newcol), a

                ld      a, (chary)      ; top row = CharY - height + 1
                ld      b, a
                ld      a, (curh)
                ld      c, a
                ld      a, b
                sub     c
                inc     a
                ld      (newtop), a

; Point the shift at the right pair of tables and pick up its edge fills.

                ld      a, (curshift)
                ld      e, a
                ld      d, 0
                ld      hl, fill
                add     hl, de
                ld      a, (hl)
                ld      (fillhi), a
                ld      hl, fill + 8
                add     hl, de
                ld      a, (hl)
                ld      (filllo), a
                ld      a, e
                add     a, shifthi / 256
                ld      (bmhi + 1), a
                ld      (bdhi + 1), a
                ld      a, e
                add     a, shiftlo / 256
                ld      (bmlo + 1), a
                ld      (bdlo + 1), a

                ld      a, (curw)       ; the shift needs one byte more
                inc     a
                ld      (neww), a
                ld      a, (curh)
                ld      (newh), a

                ld      b, a
                ld      hl, (curdat)
                ld      a, (newtop)
                ld      (rowy), a

drawrow:        push    bc
                call    build_row       ; HL walks over the source row
                push    hl
                ld      a, (rowy)
                cp      192
                jr      nc, drawskip
                ld      c, a
                ld      a, (newcol)
                ld      e, a
                ld      a, c
                call    scraddr
                ld      bc, work - SCREEN
                add     hl, bc          ; draw into the working copy
                ld      de, mbuf
                ld      a, (neww)
                ld      b, a
drawblit:       ld      a, (de)         ; mask
                and     (hl)
                ld      c, a
                inc     de
                ld      a, (de)         ; data
                or      c
                ld      (hl), a
                inc     de
                inc     hl
                djnz    drawblit
drawskip:       ld      hl, rowy
                inc     (hl)
                pop     hl
                pop     bc
                djnz    drawrow
                ret

; Copy one source row into mbuf as (mask, data) pairs, then shift it right.
; In: HL = source.  Out: HL past the row.

build_row:      ld      a, (curw)       ; take the row aside
                add     a, a
                ld      c, a
                ld      b, 0
                ld      de, tbuf
                ldir

                ld      a, (facing)
                or      a
                call    nz, mirror_row

                push    hl              ; HL is wanted back past the row
                ld      de, mbuf        ; mask plane: ones shift in at the left
                ld      hl, tbuf
                ld      a, (fillhi)
                ld      c, a
                ld      a, (curw)
                ld      b, a
bmask:          ld      a, (hl)
                inc     hl
                inc     hl
                push    hl
bmhi:           ld      h, 0            ; patched with the hi table's page
                ld      l, a
                ld      a, (hl)
                or      c
                ld      (de), a
                inc     de
                inc     de
bmlo:           ld      h, 0            ; and with the lo table's
                ld      c, (hl)
                pop     hl
                djnz    bmask
                ld      a, (filllo)
                or      c
                ld      (de), a

                ld      de, mbuf + 1    ; data plane: zeros shift in
                ld      hl, tbuf + 1
                ld      c, 0
                ld      a, (curw)
                ld      b, a
bdata:          ld      a, (hl)
                inc     hl
                inc     hl
                push    hl
bdhi:           ld      h, 0
                ld      l, a
                ld      a, (hl)
                or      c
                ld      (de), a
                inc     de
                inc     de
bdlo:           ld      h, 0
                ld      c, (hl)
                pop     hl
                djnz    bdata
                ld      a, c
                ld      (de), a
                pop     hl
                ret

; Facing right is the same picture the other way round: the pairs come in
; reverse order and every byte has its bits turned about.

mirror_row:     push    hl
                ld      a, (curw)
                ld      b, a
                add     a, a
                ld      e, a
                ld      d, 0
                ld      hl, tbuf
                add     hl, de
                dec     hl
                dec     hl
                ld      de, mbuf        ; mbuf is free until the shift runs
mrloop:         ld      a, (hl)
                push    hl
mrev1:          ld      h, 0            ; patched with the reversal table
                ld      l, a
                ld      a, (hl)
                pop     hl
                ld      (de), a
                inc     de
                inc     hl
                ld      a, (hl)
                push    hl
mrev2:          ld      h, 0
                ld      l, a
                ld      a, (hl)
                pop     hl
                ld      (de), a
                inc     de
                dec     hl
                dec     hl
                dec     hl
                djnz    mrloop
                ld      a, (curw)
                add     a, a
                ld      c, a
                ld      b, 0
                ld      hl, mbuf
                ld      de, tbuf
                ldir
                pop     hl
                ret

; ---------------------------------------------------------------- walls
;
; A byte column lying wholly inside solid blocks is simply put back from the
; room, so the wall covers the prince rather than the other way round.  Which
; columns those are never changes, so the map is built offline, one row of 32
; per block row.

; Put the foreground back over the prince.  foremask has a bit per pixel,
; set where a front piece covers, and it sits at the same offsets as the
; screen, so one lookup gives both the mask and the room byte to restore.

hide_behind:    ld      a, (newh)
                ld      b, a
                ld      a, (newtop)
                ld      (rowy), a
hiderow:        push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, hideskip
                ld      a, (newcol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      (hideadr), hl
                ld      a, (neww)
                ld      (hidecnt), a
hidecol:        ld      hl, (hideadr)
                ld      de, foremask - SCREEN
                add     hl, de
                ld      a, (hl)         ; which pixels here are covered
                or      a
                jr      z, hidenext
                ld      (hidebits), a
                ld      hl, (hideadr)
                ld      d, h
                ld      e, l
                ld      bc, room - SCREEN
                add     hl, bc          ; HL = room
                ex      de, hl
                ld      bc, work - SCREEN
                add     hl, bc
                ex      de, hl          ; HL = room, DE = working copy
                ld      a, (hidebits)
                ld      c, a
                ld      a, (hl)
                and     c               ; the foreground's own pixels
                ld      b, a
                ld      a, c
                cpl
                ex      de, hl
                and     (hl)            ; what the prince may keep
                or      b
                ld      (hl), a
hidenext:       ld      hl, hideadr
                inc     (hl)
                ld      hl, hidecnt
                dec     (hl)
                jr      nz, hidecol
hideskip:       ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    hiderow
                ret

; ---------------------------------------------------------------- erase
;
; Put the room back over where the sprite was, in the working copy.

erase_prince:   ld      a, (oldw)
                or      a
                ret     z
                ld      a, (oldh)
                ld      b, a
                ld      a, (oldtop)
                ld      (rowy), a
eraserow:       push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, eraseskip
                ld      a, (oldcol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      d, h
                ld      e, l
                ld      bc, room - SCREEN
                add     hl, bc          ; HL = room
                ex      de, hl
                ld      bc, work - SCREEN
                add     hl, bc
                ex      de, hl          ; HL = room, DE = working copy
                ld      a, (oldw)
                ld      c, a
                ld      b, 0
                ldir
eraseskip:      ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    eraserow
                ret

; ---------------------------------------------------------------- show
;
; Copy the rectangle covering both the old and the new sprite from the
; working copy to the screen.  This is the only moment the screen changes.

show_rect:      ld      a, (oldw)
                or      a
                jr      nz, showunion
                ld      a, (newcol)     ; nothing old: just the new box
                ld      (shcol), a
                ld      a, (neww)
                ld      (shw), a
                ld      a, (newtop)
                ld      (shtop), a
                ld      a, (newh)
                ld      (shh), a
                jr      showgo

showunion:      ld      a, (oldcol)     ; leftmost of the two
                ld      b, a
                ld      a, (newcol)
                cp      b
                jr      c, showcol
                ld      a, b
showcol:        ld      (shcol), a

                ld      a, (oldcol)     ; rightmost end of the two
                ld      b, a
                ld      a, (oldw)
                add     a, b
                ld      c, a
                ld      a, (newcol)
                ld      b, a
                ld      a, (neww)
                add     a, b
                cp      c
                jr      nc, showend
                ld      a, c
showend:        ld      b, a
                ld      a, (shcol)
                neg
                add     a, b
                ld      (shw), a

                ld      a, (oldtop)     ; topmost of the two
                ld      b, a
                ld      a, (newtop)
                cp      b
                jr      c, showtop
                ld      a, b
showtop:        ld      (shtop), a

                ld      a, (oldtop)     ; lowest bottom of the two
                ld      b, a
                ld      a, (oldh)
                add     a, b
                ld      c, a
                ld      a, (newtop)
                ld      b, a
                ld      a, (newh)
                add     a, b
                cp      c
                jr      nc, showbot
                ld      a, c
showbot:        ld      b, a
                ld      a, (shtop)
                neg
                add     a, b
                ld      (shh), a

showgo:         ld      a, (shh)
                or      a
                ret     z
                ld      b, a
                ld      a, (shtop)
                ld      (rowy), a
showrow:        push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, showskip
                ld      a, (shcol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      d, h
                ld      e, l            ; DE = screen
                ld      bc, work - SCREEN
                add     hl, bc          ; HL = working copy
                ld      a, (shw)
                ld      c, a
                ld      b, 0
                ldir
showskip:       ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    showrow
                ret

; Remember where the sprite went, so the next frame can rub it out.

keep_rect:      ld      a, (newcol)
                ld      (oldcol), a
                ld      a, (neww)
                ld      (oldw), a
                ld      a, (newtop)
                ld      (oldtop), a
                ld      a, (newh)
                ld      (oldh), a
                ret

; ---------------------------------------------------------------- helpers
;
; A = scanline, E = byte column.  Out: HL = screen address.

scraddr:        ld      b, a
                and     %00000111
                ld      h, a
                ld      a, b
                rrca
                rrca
                rrca
                and     %00011000
                or      h
                or      %01000000
                ld      h, a
                ld      a, b
                and     %00111000
                rlca
                rlca
                add     a, e
                ld      l, a
                ret

; ---------------------------------------------------------------- data

charx:          db      0
chary:          db      0
facing:         db      0               ; 0 left, 1 right
frame:          db      0
seqid:          db      0
seqptr:         dw      0
pendchx:        db      0
blocked:        db      0
spotx:          db      0
wanted:         db      0

curw:           db      0
curh:           db      0
curoff:         db      0
curshift:       db      0
curdat:         dw      0
curent:         dw      0
fillhi:         db      0
filllo:         db      0
rowy:           db      0

newcol:         db      0
newtop:         db      0
neww:           db      0
newh:           db      0

oldcol:         db      0
oldtop:         db      0
oldw:           db      0
oldh:           db      0

hideadr:        dw      0
hidecnt:        db      0
hidebits:       db      0
shcol:          db      0
shtop:          db      0
shw:            db      0
shh:            db      0

mbuf:           ds      BUFW * 2
tbuf:           ds      BUFW * 2

                ds      64
stack:

seqs:           incbin  "seqs.bin"
tiles:          incbin  "tiles.bin"
blockof:        incbin  "blockof.bin"
foremask:       incbin  "foremask.bin"
fill:           incbin  "fill.bin"
                ds      (($ + 255) / 256 * 256) - $
shifthi:        incbin  "shifthi.bin"
shiftlo:        incbin  "shiftlo.bin"
revtab:         incbin  "revtab.bin"
room:           incbin  "room.bin"
sprites:        incbin  "sprites.bin"
dataend:

; The working copy is never loaded, only written, so it lives past the end of
; the tape image rather than taking 7K of loading time.
work            equ     dataend

                end     start
