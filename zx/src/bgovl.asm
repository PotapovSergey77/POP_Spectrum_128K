; ---------------------------------------------------------------- a set's code
;
; What only one background set wants -- the palace, BGset1 1 in MISC.S -- is
; not in the program: it rides with the set's pictures in the background
; bank, BGOVL_LEN bytes after the piece tables, and comes off the tape with
; them when a level of the other set begins.  Assembled once for each set
; (OVLSET, 0 the dungeon, 1 the palace) and put in the bank's image and the
; level blocks by build.sh; what it uses of the game comes from the game's
; symbols, bgsyms.inc.
;
; It runs with the background bank paged, so it is only ever gone into where
; that bank is in, and it calls nothing that leaves another in.  Its bytes
; are in that bank too, so they are its variables as well.

                include "bgsyms.inc"
                include "ovlset.inc"

                org     bgovl

; The entries, three bytes apart, where pop.asm has them: ovstripe, ovstart,
; ovpost, ovset, ovhb, ovattr and ovshad.  ovpost is the level's own code,
; which rides with its blueprint (lvcode.asm); the dungeon's ovstart goes
; there too, carry set to tell them apart -- level eight's mouse wants the
; top of the frame.  Its shadowman is level eight's mouse, who presses
; nothing, and level twelve's, whose keys are that level's code's too.

                ret                     ; (drawb's stripe was here: bg.asm)
                ds      2
                if      OVLSET
                jp      start
                jp      lvcode
                else
                jp      dstart
                jp      dpost
                endif
                jp      setup
                jp      hbfirst         ; ovhb: hide_behind's, both sets
                if      OVLSET
                jp      attrs
                jp      shad
                else
                ret                     ; (ovattr: the palace's)
                ds      2
                jp      dshad

dstart:         scf
                jp      lvcode
dpost:          or      a
                jp      lvcode

; FinalShad in AUTO.S, six bytes into level twelve's code: see there.

dshad:          ld      a, (curlev)
                cp      11
                ret     nz
                jp      lvcode + 6
                endif

; The set into the program, from newroom: the room's colour, and the meters'
; empty cells; the flame's foot, yellow in the dungeon and the room's own in
; the palace, which is all yellow already; the space MAKESPACE leaves -- the
; palace's has its stripe; and whether drawfrnt stamps a post, or masks it
; in as the palace does.

                if      OVLSET
SETINK          equ     INK_PAL
SETFLAME        equ     INK_FLAME_LOW
SETDF           equ     dfgo - dfpost - 4
SETATTR         equ     palattr
                else
SETINK          equ     INK_DUN
SETFLAME        equ     INK_FLAME_LOW
SETDF           equ     dfsta - dfpost - 4
SETATTR         equ     flask_attrs
                endif

setup:          ld      a, SETINK
                ld      (saink + 1), a  ; the meters read it there too
                ld      a, SETFLAME
                ld      (flcolour + 2), a
                ld      a, OVLSET
                ld      (mkspace1 + 1), a       ; and mkspace2 reads it
                ld      a, SETDF
                ld      (dfpost + 3), a
                ld      hl, SETATTR     ; and the palace's own colours before
                ld      (saflask + 1), hl       ; the flasks'
                if      OVLSET = 0
                ld      a, oppnone - oppjr - 2  ; DRAWOPPMETER: the shadow's
                ld      (oppjr + 1), a  ; strength shows on level twelve
                                        ; alone, whose code shows it
                ld      a, (curlev)     ; GETBELOW in FRAMEADV.S: with no
                cp      11              ; room down and to the left, what
                ld      a, BG_BLOCK     ; is there is a block -- and on
                jr      nz, sublk       ; level twelve space ("sorry
                ld      a, BG_SPACE     ; Lance!")
sublk:          ld      (rebcnone + 1), a
                endif
                if      OVLSET
                ld      a, (roomnum)    ; this room's, of the level's
                add     a, a            ; rectangles: how many yellow and
                dec     a               ; three bytes each, then how many
                ld      b, a            ; blue and theirs
                ld      hl, palcols
                jr      sucount
sunext:         ld      a, (hl)
                ld      e, a
                add     a, a
                add     a, e
                inc     a
                add     a, l
                ld      l, a
                jr      nc, sucount
                inc     h
sucount:        djnz    sunext
                ld      (palist), hl
                endif
                ret

; hide_behind's start: the front list, and the Apple bytes he can meet a
; piece in.  His room bytes are rb to rb + w, eight pixels each and an
; Apple byte seven, so his first Apple byte is at least rb + rb/8 and his
; last at most x + x/8 + 1, x = rb + w; and a piece's body ends at most
; five Apple bytes past its column (bgexport asserts it).  So a piece meets
; him only if its column less (first - 5) is no more than (last + 1) less
; that -- one unsigned comparison, which a column of 255, a byte left of
; the room, also comes out of right.  By bgcall (ovhb), which keeps B and
; HL.  Out: HL = frontlist.

hbfirst:        ld      a, (cam)
                ld      hl, newcol
                add     a, (hl)
                ld      c, a            ; rb
                rrca
                rrca
                rrca
                and     0x1f
                add     a, c
                sub     5
                ld      (hbxlo + 1), a
                ld      e, a
                ld      a, (neww)
                add     a, c
                ld      c, a            ; x
                rrca
                rrca
                rrca
                and     0x1f
                add     a, c
                inc     a
                sub     e
                inc     a
                ld      (hbxn + 1), a
                ld      hl, frontlist
                ret

                if      OVLSET

; The top of a frame: last frame's reflection out of the way -- nobody in the
; second character's place, and nothing of him drawn, so that whatever is
; left of him is rubbed out if he is not drawn again.

start:          xor     a               ; the kid shown whole, unless the
                ld      (clipl), a      ; mirror has him behind it
                ld      a, (reflon)
                or      a
                ret     z
                xor     a
                ld      (reflon), a
                ld      (gdhere), a
                ld      (neww + OP), a
                ret

; The shadow's keys, from autoctrl by bgcall: what his level's code
; (lvcode.asm) has left in shadkey for this frame -- DoFwd, DoBack, DoPress,
; one bit each -- on top of DoRelease, which has let go of everything.

shad:           ld      hl, shadkey
                bit     0, (hl)         ; SK_FWD
                jr      z, sh1
                ld      a, 0xff
                ld      (clrf), a
                ld      (jstkx), a
sh1:            bit     1, (hl)         ; SK_BACK
                jr      z, sh2
                ld      a, 0xff
                ld      (clrb), a
                ld      a, 1
                ld      (jstkx), a
sh2:            bit     2, (hl)         ; SK_PRESS
                ret     z
                ld      a, 0xff
                ld      (clrbtn), a
                ld      (btn), a
                ret

; ---------------------------------------------------------------- colour
;
; The palace is grey, and some of its cells are not: its windows yellow,
; the frames of its exit doors, the panels over its gates and the arches'
; lattice blue -- the user's choice, the last two as the Apple has them.
; Which cells, room by room, mkassets works out (palcolour.py) and puts
; after the level's head: rectangles of cells in the room's own columns.
; set_attrs lays them over the grey, before the flasks and the torches, by
; way of palattr -- which may have the other screen's bank in, where this
; one is, so what does it is copied down into imgbuf with this room's
; rectangles after it, and run there.  Nothing in it may jump to itself but
; by jr.

attrs:          ld      hl, pacode
                ld      de, imgbuf
                ld      bc, PALEN
                ldir
                ld      hl, (palist)
                ld      bc, PALISTMAX   ; the most a room has
                ldir
                ret

; In imgbuf, with whatever bank set_attrs had in.  A rectangle is its left
; cell in the room, its top row * 8 + its rows - 1, and its width; the
; camera takes its cells off the left, and the view's edges cut it.  How
; many blue ones and then they, and the same for the yellow, laid over
; them.

pacode:         ld      hl, imgbuf + PALEN
                ld      c, INK_PALBLUE
                call    imgbuf + parun - pacode
                ld      c, INK_PALWIN
                call    imgbuf + parun - pacode
                jp      flask_attrs
parun:          ld      b, (hl)         ; how many
                inc     hl
                inc     b
                jr      pa9
pa1:            push    bc
                ld      a, (cam)
                ld      e, a
                ld      a, (hl)         ; the left cell, less the camera:
                inc     hl              ; -34 to 34
                sub     e
                ld      e, a
                ld      a, (hl)         ; row and rows
                inc     hl
                ld      d, (hl)         ; the width
                push    hl
                ld      b, a
                and     0xf8            ; the row, thirty two cells a row
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      a, b
                and     7
                inc     a
                ld      b, a            ; B = rows
                ld      a, e
                add     a, d            ; its right, in the view
                bit     7, a
                jr      nz, pa8         ; all of it left of the view
                cp      33
                jr      c, pa2
                ld      a, 32
pa2:            bit     7, e
                jr      z, pa3
                ld      e, 0
pa3:            sub     e               ; what the view has of it
                jr      z, pa8
                jr      c, pa8
                ld      d, a
                ld      a, l            ; a row's first cell has the low five
                add     a, e            ; bits clear
                ld      l, a
                push    de
                ld      de, (atbase)
                add     hl, de
                pop     de
pa4:            push    hl
                push    bc
                ld      b, d
pa5:            ld      (hl), c
                inc     hl
                djnz    pa5
                pop     bc
                pop     hl
                ld      a, l
                add     a, 32
                ld      l, a
                jr      nc, pa6
                inc     h
pa6:            djnz    pa4
pa8:            pop     hl
                inc     hl
                pop     bc
pa9:            djnz    pa1
                ret
PALEN           equ     $ - pacode

palist:         dw      0               ; this room's rectangles

reflon:         db      0               ; the second character is a reflection

                endif

ovlend:
