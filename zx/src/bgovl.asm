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
; ovpost and ovset.  The dungeon has only the last.

                if      OVLSET
                jp      stripe
                jp      start
                jp      post
                else
                ret
                ds      2
                ret
                ds      2
                ret
                ds      2
                endif
                jp      setup

; The set into the program, from newroom: the room's colour, and the meters'
; empty cells; the flame's foot, yellow in the dungeon and the room's own in
; the palace, which is all yellow already; the space MAKESPACE leaves -- the
; palace's has its stripe; and whether drawfrnt stamps a post, or masks it
; in as the palace does.

                if      OVLSET
SETINK          equ     INK_PAL
SETFLAME        equ     INK_PAL
SETDF           equ     dfgo - dfpost - 4
                else
SETINK          equ     INK_DUN
SETFLAME        equ     INK_FLAME_LOW
SETDF           equ     dfsta - dfpost - 4
                endif

setup:          ld      a, SETINK
                ld      (saink + 1), a
                ld      (mmrink + 1), a
                ld      a, SETFLAME
                ld      (flcolour + 2), a
                ld      a, OVLSET
                ld      (mkspace1 + 1), a
                ld      (mkspace2 + 1), a
                ld      a, SETDF
                ld      (dfpost + 3), a
                ret

                if      OVLSET

; DRAWB's :stripe in FRAMEADV.S, the palace's alone: after the B section of
; the piece to the left, bstripe's picture for it on the wall, 32 lines up
; from Ay.  In: that B section drawn, the bank paged.

stripe:         ld      a, (preced)
                ld      hl, bgtables + T_BSTRIPE
                call    bgentry
                or      a
                ret     z
                ld      c, a
                ld      a, (ay)
                sub     32
                ld      (yco), a
                ld      a, c
                ld      c, BG_ORA
                jp      bglay

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

start:          ld      a, (reflon)
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
                call    mirappear
                call    mirrmusic
                call    reflection
                jp      shadow

; MIRAPPEAR, called by MOVER when the exit opens: the mirror in its block,
; as the blueprint has it from then on.

mirappear:      ld      a, (exitopen)
                or      a
                ret     z
                ld      a, BG_MIRROR
                ld      (level + (MIRSCRN - 1) * 30 + MIRY * 10 + MIRX), a
                ret

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
                ld      a, (blocky)
                cp      MIRY
                ret     nz
                ld      a, (exitopen)
                or      a
                ret     z
                cp      77
                ret     z
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

rfkid:          call    base_x          ; the kid's block
                push    hl
                call    blockcol_of
                ld      (rfcol), a
                pop     hl
                ld      a, (createshad) ; the reflection comes to life,
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
                ld      a, (rfcol)
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                or      a
                sbc     hl, de          ; 28 a block
                ld      de, ANGLE_PX + 6
                add     hl, de
                add     hl, hl
                ld      de, (charx)
                or      a
                sbc     hl, de
                ld      (charx + OP), hl
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

reflon:         db      0               ; the second character is a reflection
lastroom:       db      0
rfcol:          db      0

                endif

ovlend:
