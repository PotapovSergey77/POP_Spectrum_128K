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
; ovpost, ovset, ovflame and ovattr.  The dungeon has only ovset and ovflame.

                ret                     ; (drawb's stripe was here: bg.asm)
                ds      2
                if      OVLSET
                jp      start
                jp      post
                else
                ret
                ds      2
                ret
                ds      2
                endif
                jp      setup
                jp      flame
                if      OVLSET
                jp      attrs
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

; A frame of a torch's flame, from DE into flbuf, for flame_one.  The bank
; has each frame once, as it stands over an even column, and two bytes of
; each row, the third being empty; over an odd column it is four pixels
; further right, and the copy moves it there -- the mask flame_one has
; picked says which.

flame:          ex      de, hl
                ld      de, flbuf
                ld      b, FLAME_BYTES / 3
flrow:          ld      a, (hl)
                ld      (de), a
                inc     hl
                inc     de
                ld      a, (hl)
                ld      (de), a
                inc     hl
                inc     de
                xor     a
                ld      (de), a
                inc     de
                djnz    flrow
                ld      a, (flmbase)
                cp      flamemask & 0xff
                ret     z
                ld      hl, flbuf
                ld      b, FLAME_BYTES / 3
flshift:        xor     a
                rrd
                inc     hl
                rrd
                inc     hl
                rrd
                inc     hl
                djnz    flshift
                ret

                if      OVLSET

; ---------------------------------------------------------------- the mirror
;
; Level four's: TOPCTRL.S has it in screen 4, block 4 of the top row, and it
; is there once the exit is open (MIRAPPEAR in SUBS.S).  The kid standing
; before it is drawn again in it, turned about (REFLECTION in MISC.S); on a
; running jump from its right he goes through (COLL.S -- ckmirr in pop.asm),
; and the reflection comes to life as the shadow, who takes his strength and
; runs off the other way (CreateShad, and ShadLevel4 in AUTO.S).
;
; The reflection is drawn as the guard would be -- the second character --
; and it is only that while the frame is drawn: from c1post to the top of the
; next frame.  So nothing that moves or fights a guard ever sees it.  The
; shadow, once he is made, is the second character for good, until he is
; gone.

MIRSCRN         equ     4               ; mirscrn, mirx, miry
MIRX            equ     4
MIRY            equ     0
MIRRIGHT        equ     11              ; the screen right of it
MIRCL           equ     (MIRX * 28 + 7 + 7) / 8 ; FCharCL, mirx * 4 + 1:
                                        ; the room's byte at its left edge
SHADOUT         equ     2 * (80 - 58)   ; ShadLevel4's CharX 80, our pixels
LEVEL4          equ     3               ; curlev is the level less one

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

; After the frame's moves, before it is drawn: the level's own.

post:           ld      a, (curlev)
                cp      LEVEL4
                ret     nz
                ld      a, (exitopen)   ; MIRAPPEAR, called by MOVER when
                or      a               ; the exit opens: the mirror in its
                jr      z, post1        ; block, as the blueprint has it from
                ld      a, BG_MIRROR    ; then on
                ld      (level + (MIRSCRN - 1) * 30 + MIRY * 10 + MIRX), a
post1:          call    mirrmusic
                call    reflection
                jp      shadow

; mirrmusic in AUTO.S, which CUTCHECK calls going left: out of the screen
; right of the mirror on its row, with the exit open, "Danger" -- once.

mirrmusic:      ld      hl, lastroom
                ld      a, (roomnum)
                ld      b, (hl)
                ld      (hl), a
                cp      MIRSCRN
                ret     nz
                ld      a, b
                cp      MIRRIGHT
                ret     nz
                ld      a, (blocky)     ; MIRY, the top row
                or      a
                ret     nz
                ld      a, (exitopen)   ; open, and not yet 77
                cp      1
                ret     nz
                ld      a, 77           ; so we don't repeat theme
                ld      (exitopen), a
                ld      a, SONG_DANGER
                ld      c, 50
                jp      cue_song

; REFLECTION, getreflect and CreateShad in MISC.S.  Elsewhere than the
; mirror's room nobody is cut off at the left; in it the shadow is, at the
; mirror's edge, as setupshad clips him coming out of it.

reflection:     ld      a, (roomnum)
                cp      MIRSCRN
                ld      a, 0
                jr      nz, rfclip
                call    base_x          ; the kid's block
                push    hl
                call    blockcol_of
                ld      (rfcol), a
                cp      MIRX            ; under the mirror, jumping up at it
                jr      nz, rfnb        ; or hanging from it facing right --
                ld      a, (blocky)     ; he cannot climb it that way -- he
                dec     a               ; is behind the glass, which shows
                jr      nz, rfnb        ; the floor it reflects: not drawn
                ld      a, (facing)     ; at all, as the user asked, his
                or      a               ; clip past the screen's right
                jr      z, rfnb
                ld      a, (charact)    ; -- only hanging, or jumping up:
                cp      2               ; standing against the block under
                jr      z, rfhide       ; it he is before it
                ld      a, (frame)
                sub     67
                cp      14
                jr      nc, rfnb
rfhide:         ld      a, 32
                ld      (clipl), a
rfnb:           pop     hl
                ld      a, (gdhere)
                or      a
                jr      z, rfkid

rfedge:         ld      a, (cam)        ; FCharCL on the screen
                ld      b, a
                ld      a, MIRCL
                sub     b
                jr      nc, rfclip
                xor     a
rfclip:         ld      (clipl + OP), a
                ret

rfkid:          ld      a, (createshad) ; the reflection comes to life,
                inc     a               ; wherever it is
                jr      z, rfmake
                ld      a, (rfcol)
                cp      10
                ret     nc
                ld      de, -28         ; dmirr: GETDIST's offset into the
rfmod:          add     hl, de          ; block, less two -- short of that
                jr      c, rfmod        ; he is on the wrong side of the
                ld      a, l            ; glass.  The offset is x less
                add     a, 28           ; angle, round the block, and two
                sub     ANGLE_PX        ; units are four pixels
                jr      nc, rfoff
                add     a, 28
rfoff:          cp      4
                ret     c
                ld      a, (blocky)     ; getunderft: a mirror under his feet
                cp      3
                ret     nc
                call    mul10
                ld      a, (rfcol)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      de, roomids
                add     hl, de
                ld      a, (hl)
                and     0x1f
                cp      BG_MIRROR
                ret     nz

; The kid again, turned about the mirror: CharX 2 * mirrx less his, where
; mirrx is getblockej + angle + 3 of his block.  No sword: addreflobj is the
; figure alone.

rfmake:         ld      hl, chrec
                ld      de, oprec
                ld      bc, charcu - chrec
                ldir
                ld      a, (xvel)
                ld      (xvel + OP), a
                ld      a, (facing)
                xor     1
                ld      (facing + OP), a
                ld      a, 1            ; the second character, for the
                ld      (gdhere), a     ; frame -- drawn as the kid is, his
                xor     a               ; CharID nought: only the shadow is 1
                ld      (charid + OP), a
                ld      (charsword + OP), a
                ld      a, (rfcol)      ; 28 a block
                ld      b, a
                inc     b
                ld      hl, ANGLE_PX + 6
                ld      de, 28
                jr      rfm2
rfm1:           add     hl, de
rfm2:           djnz    rfm1
                add     hl, hl
                ld      de, (charx)
                or      a
                sbc     hl, de
                ld      (charx + OP), hl
                ld      de, -108        ; the frame's foot rises to the right,
                ld      a, (facing + OP)        ; a line for every two pixels
                or      a               ; from its left, 57: the reflection
                jr      z, rff1         ; stops at its top edge under his
                ld      de, -124        ; middle -- which is behind his anchor
rff1:           add     hl, de          ; the way he faces -- and only glass
                sra     h               ; shows him.  Three lines lower, as
                rr      l               ; the user wanted
                ld      a, 59           ; (a line up: the far toe off it)
                sub     l
                ld      (clipb + OP), a
                ld      a, (createshad)
                inc     a
                jr      z, rfshad
                inc     a               ; a reflection, this frame
                ld      (reflon), a
                jp      rfedge

; CreateShad: the shadowman, with the kid's strength -- the kid left one
; point of it -- and the glass cracking.

rfshad:         ld      (createshad), a
                inc     a               ; the shadowman's CharID
                ld      (charid + OP), a
                ld      a, 192          ; and stands on the floor
                ld      (clipb + OP), a
                ld      a, SND_MIRRORCRACK
                call    addsound
                ld      a, (maxkidstr)
                ld      (oppstr), a
                ld      a, 1            ; set, not lost: no hurt flash
                ld      (kidstr), a
                ld      (lastkidstr), a
                ld      (meterdirty), a
                jp      rfedge

; ShadLevel4 in AUTO.S, for what he presses next frame: from CharX 80 on he
; runs forward, off the screen; short of it, he is gone.

shadow:         ld      a, (reflon)
                or      a
                ret     nz
                ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (charid + OP)
                dec     a
                ret     nz
                ld      hl, (charx + OP)
                ld      de, -SHADOUT
                add     hl, de
                bit     7, h
                jp      nz, gd_gone     ; VANISHCHAR
                ld      a, 0xff         ; DoFwd
                ld      (shadkey), a
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
lastroom:       db      0
rfcol:          db      0

                endif

ovlend:
