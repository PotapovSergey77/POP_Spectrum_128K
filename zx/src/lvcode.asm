; ---------------------------------------------------------------- a level's code
;
; What only one level does -- level four's mirror, five's thief, six's
; plunge, eight's mouse -- rides with its blueprint, at lvcode in the
; background bank: LVCODE_LEN bytes after the level's head and its colours,
; loaded with them whenever the level is, the last of them the level's
; basicstrength (LVSTR).  The set's code (bgovl.asm) goes to it after the
; frame's moves: ovpost is a jump here; the dungeon's comes at the top of
; the frame as well, with carry set.  Assembled once for each level on
; the tape (LVNUM, from 1) and put in the level's block by build.sh; what it
; uses of the game and of the set's code comes from their symbols,
; lvsyms.inc.  A level with nothing of its own is a ret.
;
; It runs with the background bank paged, as the set's code does, and the
; same rules hold: it calls nothing that leaves another bank in, and its
; bytes are its variables.

                include "lvsyms.inc"
                include "lvnum.inc"

                org     lvcode

                if      LVNUM = 4
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

; After the frame's moves, before it is drawn, from the set's ovpost.

post:           ld      a, (exitopen)   ; MIRAPPEAR, called by MOVER when
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
                ld      a, SK_FWD       ; DoFwd
                ld      (shadkey), a
                ret

lastroom:       db      0
rfcol:          db      0

                endif

                if      LVNUM = 5

; ---------------------------------------------------------------- the thief
;
; Level five's (ShadLevel5 and ADDGUARD's :not5 in AUTO.S): in screen 24,
; while its flask is there, the shadowman stands just off the left of it
; (shadpos5); once the gate in its top row is up past 20 he plays back
; ShadProg5 -- runs in, drinks the flask, turns and runs off -- and past
; CharX 15 he is gone.  Made here the frame the kid is in the room without
; him, which is ADDGUARD's moment: nothing else ever stands there.

FLASKSCRN       equ     24              ; flaskscrn, flaskx, flasky
FLASKAT         equ     0 * 10 + 3
THGATE          equ     0 * 10 + 1      ; ShadLevel5's rdblock 1, 0
THX             equ     2 * (0x37 - 58) ; shadpos5's CharX, our pixels
THOUT           equ     X_MIN + 2       ; ShadLevel5's CharX 15 is -86 of
                                        ; ours, past move_by's backstop at
                                        ; X_MIN: gone there, well out of sight

post:           ld      a, (roomnum)
                cp      FLASKSCRN
                ret     nz
                ld      a, (gdhere)
                or      a
                jr      nz, thplay
                ld      a, (roomids + FLASKAT)
                and     0x1f
                cp      BG_FLASK
                ret     nz

; csps shadpos5: posn 15, standing, facing right, on the top row's floor,
; stand next, and the shadow's strength, four.  He never fights, so no
; program: ShadowProg is his, and plays him back.

                ld      hl, threc
                ld      de, oprec
                ld      bc, CHRECLEN
                ldir
                ld      a, 4            ; shadstrength
                ld      (oppstr), a
                ld      hl, shprog5     ; PlayCount and PreRecPtr nought
                ld      (thptr), hl
                xor     a
                ld      (playcount), a
                inc     a
                ld      (gdhere), a
                                        ; and on: nothing pressed yet -- not
                                        ; the last shadow's forward

; AUTOPLAYBACK: a frame's count, and the command whose frame it has come
; to -- or the one before it again -- for the next frame's keys.  Not
; begun until the gate is up.

thplay:         xor     a
                ld      (shadkey), a
                ld      a, (charid + OP)
                dec     a
                ret     nz
                ld      hl, playcount
                ld      a, (hl)
                or      a
                jr      nz, thgo
                ld      a, (roomids + 30 + THGATE)
                cp      20
                ret     c
thgo:           ld      a, (hl)
                cp      254
                jr      nc, thout
                inc     (hl)
                ld      a, (hl)
                ld      hl, (thptr)
                cp      (hl)
                jr      c, thlast       ; not there yet: the last again
                inc     hl
                ld      a, (hl)
                inc     hl
                ld      (thptr), hl
                jr      thset
thlast:         dec     hl
                ld      a, (hl)
thset:          ld      (shadkey), a
thout:          ld      hl, (charx + OP)
                ld      de, -THOUT
                add     hl, de
                bit     7, h
                jp      nz, gd_gone     ; VANISHCHAR
                ret

; ShadProg5: frame, command -- Ctr, Fwd, Ctr, Press, Release, Back, Fwd,
; as shadkey has them: letting go is nothing pressed -- and 254 the end.

shprog5:        db      0, 0, 1, SK_FWD, 14, 0, 18, SK_PRESS, 29, 0
                db      45, SK_BACK, 49, SK_FWD, 255, 254

; shadpos5 as the second character's record: CharX, CharY, facing right,
; posn 15, stand, the top row, standing, no sword, the shadowman, alive,
; nothing of him drawn, and his picture whole.

threc:          dw      THX
                db      55, 1, 15
                dw      seqs + SO_STAND
                db      0, 0, 0, 0, 1, 0xff
                ds      CHRECLEN - 14
                db      192

playcount:      db      0               ; PlayCount
thptr:          dw      0               ; and PreRecPtr, where it points

                endif

                if      LVNUM = 6

; ---------------------------------------------------------------- the plunge
;
; Level six's (ShadLevel6 and ADDGUARD's :not6 in AUTO.S, cutchar's :CUTDOWN
; and MASTER.S's level six): in screen 1 the shadowman stands across the
; chasm (shadpos6a) and "Danger" plays, the first time in the level; when
; the kid, jumping it, is at posn 43 short of the middle of the screen, the
; shadow steps forward onto the plate -- DoPress, DoFwd.  And falling off
; screen 1 is no cut to the room below: CharY runs on round, and under 20
; the next level has him -- level seven, which STARTKID begins with him
; falling in (mkassets' level_head).

PLSCRN          equ     1
PLX             equ     2 * (0x51 - 58) ; shadpos6a's CharX, our pixels
PLMID           equ     2 * (0x80 - 58) ; ShadLevel6's KidX $80
PLCUT           equ     nrdown - ccdown - 2     ; cutchar's jr, as it is

post:           ld      a, (roomnum)
                cp      PLSCRN
                ld      b, PLCUT
                jr      nz, plcut
                ld      a, (lvflag)     ; while the level goes on, no cut
                cp      2               ; down: the jr jumps nowhere
                jr      nc, plcut
                ld      b, 0
                ld      a, (chary)      ; KidY under 20: NextLevel -- or,
                cp      20              ; with none on the tape, RESTART
                jr      nc, plcut
                ld      hl, lvflag
                ld      a, (hl)
                or      a
                ld      a, 3
                jr      z, plnext
                dec     a
plnext:         ld      (hl), a
                call    ststop          ; and at once, no tune to wait for
                ld      b, PLCUT
plcut:          ld      a, b
                ld      (ccdown + 1), a
                or      a
                ret     nz              ; not screen 1, or not any more

                xor     a               ; nothing pressed, unless below
                ld      (shadkey), a
                ld      a, (gdhere)
                or      a
                jr      nz, plkeys

; ADDGUARD's :not6: "Danger", once, and csps shadpos6a -- posn 15,
; standing, facing right, on the middle row's floor, stand next, and the
; shadow's strength.

                ld      a, (exitopen)
                cp      77
                jr      z, plmake
                ld      a, 77           ; so we don't repeat theme
                ld      (exitopen), a
                ld      a, SONG_DANGER
                ld      c, 50
                call    cue_song
plmake:         ld      hl, plrec
                ld      de, oprec
                ld      bc, CHRECLEN
                ldir
                ld      a, 4            ; shadstrength
                ld      (oppstr), a
                ld      a, 1
                ld      (gdhere), a
                ret

; Shad6a: the kid at posn 43, KidX short of $80.

plkeys:         ld      a, (charid + OP)
                dec     a
                ret     nz
                ld      a, (frame)
                cp      43
                ret     nz
                ld      hl, (charx)
                ld      de, -PLMID
                add     hl, de
                bit     7, h
                ret     z
                ld      a, SK_PRESS + SK_FWD
                ld      (shadkey), a
                ret

plrec:          dw      PLX
                db      118, 1, 15
                dw      seqs + SO_STAND
                db      1, 0, 0, 0, 1, 0xff
                ds      CHRECLEN - 14
                db      192

                endif

                if      LVNUM = 8

; ---------------------------------------------------------------- the mouse
;
; Level eight's (misctimers in TOPCTRL.S, MOUSERESCUE in MISC.S, MouseProg
; in AUTO.S): with the exit open, once the kid has been in screen 16 for
; mousetimer frames the mouse comes in from the right of its top row, runs
; left on to the raise plate there, stops and lifts his head, turns and
; runs off the way he came.
;
; He is the second character, and all through the frame's moves the
; shadowman as far as the game can tell -- which is what SHADCTRL makes of
; him: no guard's program, no alert, nobody's meter, not left behind in a
; room -- so he presses the plate as anyone does.  Only while he is drawn,
; from the moves' end to the next frame's top, is he CharID nought, so that
; he is laid down whole, in the main set's pictures, as the kid is; and his
; strength nought, so that no meter shows it.  Nobody else is ever either
; of those on this level.
;
; The dungeon's set comes here twice a frame: at the top, before anything
; moves -- ovstart, with carry set -- and after the moves, ovpost.

MSCRN           equ     16              ; misctimers' screen
MOUSETIMER      equ     150             ; and mousetimer
MOUSEX          equ     2 * (200 - 58)  ; MOUSERESCUE's CharX, our pixels:
                                        ; MouseProg's VanishChar at it too
MLEAVEX         equ     2 * (166 - 58)  ; and short of CharX 166 he leaves

post:           jr      c, start
                ld      a, (gdhere)     ; to be drawn: the kid's way
                or      a
                ret     z
                ld      a, (charid + OP)
                dec     a
                ret     nz
                ld      (charid + OP), a
                ld      (oppstr), a
                ret

start:          ld      a, (gdhere)     ; the mouse, drawn: the shadowman
                or      a               ; again, for the moves
                jr      z, mtimer
                ld      a, (charid + OP)
                or      a
                jr      nz, mtimer
                inc     a
                ld      (charid + OP), a
                ld      (oppstr), a

; MouseProg: scurrying, short of CharX 166 he leaves -- Mleave, and the
; ANIMCHAR that follows it, its act 0 and first frame, for the next step to
; go on from; stopped, at CharX 200 he is gone.

                ld      hl, (charx + OP)
                ld      a, (charact + OP)
                or      a
                jr      z, mstopped
                ld      de, -MLEAVEX
                add     hl, de
                bit     7, h
                jr      z, mtimer
                ld      hl, seqs + SO_MLEAVE + 3
                ld      (seqptr + OP), hl
                xor     a
                ld      (charact + OP), a
                jr      mtimer
mstopped:       ld      de, -MOUSEX
                add     hl, de
                bit     7, h
                call    z, gd_gone      ; VANISHCHAR

; misctimers: in screen 16 with the exit open, exitopen counts the frames up
; to mousetimer, and then the mouse comes -- once.

mtimer:         ld      a, (roomnum)
                cp      MSCRN
                ret     nz
                ld      hl, exitopen
                ld      a, (hl)
                or      a
                ret     z
                cp      MOUSETIMER
                jr      c, minc
                ret     nz

; MOUSERESCUE: CharID 24 at CharX 200, the top row's floor, facing left,
; alive, strength one, Mscurry and a step of it -- act 1 and his first
; frame.  Nothing of him drawn yet.

                push    hl
                ld      hl, mrec
                ld      de, oprec
                ld      bc, CHRECLEN
                ldir
                pop     hl
                ld      a, 1
                ld      (oppstr), a
                ld      (gdhere), a
minc:           inc     (hl)
                ret

mrec:           dw      MOUSEX
                db      55, 0, 186
                dw      seqs + SO_MSCURRY + 3
                db      0, 0, 1, 0, 1, 0xff
                ds      CHRECLEN - 14
                db      192

                endif

                if      LVNUM < 4 or LVNUM = 7
post:           ret
                endif

lvend:
