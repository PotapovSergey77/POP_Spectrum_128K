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
; Level twelve's is more than the room holds: all but its entries goes
; where the dungeon's pictures end, short of the palace's (dunfree), which
; the level's block brings with the set -- the level before it is the
; palace's.  build.sh puts each part where it goes.
;
; Thirteen's, Jaffar's, changes a few bytes of the game's fixed code for the
; whole level, and fourteen's -- the way in to the princess -- puts them
; back.
;
; It runs with the background bank paged, as the set's code does, and the
; same rules hold: it calls nothing that leaves another bank in, and its
; bytes are its variables.

                include "lvsyms.inc"
                include "lvnum.inc"

                if      LVNUM = 12
                org     dunfree         ; and the room the dungeon's pictures
                else                    ; leave before the blueprint: see
                org     lvcode          ; build.sh
                endif

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

                if      LVNUM = 12

; ---------------------------------------------------------------- the shadowman
;
; Level twelve's (FinalShad, ADDGUARD, stealsword and CUTCHECK's level
; twelve in AUTO.S; UNHOLY in MISC.S; the phantom bridge in CTRL.S;
; chgmeters, misctimers and DRAWKID's mergetimer in TOPCTRL.S and GAMEBG.S;
; NextFrame's screen 23).  Going right out of screen 18 the shadow steals
; the sword from screen 15 (block 1 of its top row); coming into 15 without
; it there, the kid has him drop in on top of him -- held above the screen
; until the kid is in past X 150.  He fights as a guard does, and every
; point either of them loses the other loses too; and whichever dies, the
; other dies with him.  To be rid of him the kid puts his sword away and
; walks into him: they are one again, the kid a point stronger, flashing
; between the two for 42 frames -- and from then on a floor is there under
; his feet wherever he steps into the gap along the top of screens 2 and 13.
; Out of 13 to the left is the next level.
;
; The shadow is the second character, CharID 1, and his keys are pressed
; here (ovshad, in the dungeon's code) the way AUTO.S presses them.  He
; stays in a room when the kid leaves it -- UPDATEGUARD leaves him out -- so
; he is kept here while the kid is elsewhere, and put back when the kid
; comes back; en garde at the edge he goes along, as any guard does.
;
; What the shadow does differently from the kid and from a guard in the
; control code (the canvas bank, where no room is left) is made so by
; patching it, a few bytes at a time, for his turn only: see pktab.  What
; this code calls there, it calls by way of a few bytes it copies into
; imgbuf, which is free while the moves are made, and which lie in the
; fixed half of the map: they page the canvas bank in, and this one back.

SWORDSCRN       equ     15              ; swordscrn, swordx, swordy
SWORDAT         equ     0 * 10 + 1
STEALFROM       equ     18              ; stealsword: the screen under it,
STEALTO         equ     19              ; and the one right of that
EXITSCRN        equ     13              ; out of its left, screen 23: the next
                                        ; level
SHADSTR         equ     4               ; shadstrength
HOLDX           equ     2 * (150 - 58)  ; FinalShad: OpX 150, our pixels
SWORDTHRES      equ     90
MAXMAXSTR       equ     10
MERGETIME       equ     42
WHITE           equ     7               ; lightcolor $FF, the border's white
mergetimer      equ     createshad      ; level four's, and zeroed with it

; ---- in imgbuf (IB on from where it is here)

IB              equ     imgbuf - ibsrc
IBDATA          equ     imgbuf + 200    ; bytes on their way to a bank

; A routine of the control code's, at HL.

lvlow:                                  ; at dunfree: see build.sh
ibsrc:
tcall:          call    page_canvas
                call    jphl
                jp      page_bg

; BC bytes from HL (in the fixed half) to DE in bank A.

tpoke:          call    pageset
                ldir
                jp      page_bg

; The phantom bridge, in startfall's call of c1addsl (cfsl): CHECKFLOOR's
; level twelve, once the shadow is one with him, on the top row of screen 2,
; or of 13 from block 6 on -- a floor where his feet find none, and no fall.
; CODE1's bank is in, as c1call has it.

tphant:         ld      a, (mergetimer)
                or      a
                jp      p, c1addsl
                ld      a, (blocky)     ; CharBlockY nought, before startfall
                dec     a               ; stepped it on
                jp      nz, c1addsl
                ld      a, (roomnum)
                cp      2
                jr      z, tph1
                cp      13
                jp      nz, c1addsl
                ld      a, (tempbx)     ; tempblockx, of the block underfoot
                cp      6
                jp      c, c1addsl
tph1:           ld      hl, blocky
                dec     (hl)
                ld      a, (tempscrn)   ; sta (BlueType),y, and the block and
                ld      (trscrn), a     ; the one right of it redrawn
                ld      a, (tempbx)
                ld      (trloc), a
                call    trobat
                ld      a, BG_FLOOR
                call    trobtype
                ld      a, LOOSEWIPE
                ld      (redh), a
                call    redplate
                call    ao_masks
                pop     hl              ; c1call's way back, the bank it would
                pop     af              ; have put back, and the rest of
                pop     hl              ; startfall: straight back from
                jp      pageset         ; check_floor

; nrleft, in screen 13: into 23 is into the next level, LoadNextLevel -- or,
; with none on the tape, RESTART.

texit:          ld      hl, lvflag
                ld      a, (hl)
                or      a
                ld      a, 3
                jr      z, tex1
                dec     a
tex1:           ld      (hl), a
                jp      ststop
ibend:

; Put there once a frame, when it is first wanted: after the frame's top
; nothing but a room built uses imgbuf, and after that only tpoke is wanted
; (tpcopy).

ibc:            ld      hl, ibdone
                ld      a, (hl)
                ld      (hl), h
                or      a
                ret     nz
                ld      hl, ibsrc
                ld      de, imgbuf
                ld      bc, ibend - ibsrc
                ldir
                ret

tpcopy:         ld      hl, tpoke
                ld      de, tpoke + IB
                ld      bc, tphant - tpoke
                ldir
                ret

; ---- the control code, patched
;
; Each patch: where, how many bytes, the ones for the shadow's turn, and the
; control code's own.  pkset puts the first in, pkclr the second back and
; leaves HL on the next patch.

pkset:          push    hl
                call    ibc
                pop     hl
                ld      a, 1
                ld      (patched), a
                scf
                jr      pk0
pkclr:          or      a
pk0:            ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      c, (hl)
                inc     hl
                ld      b, 0
                jr      c, pk1
                add     hl, bc
pk1:            push    de
                ld      de, IBDATA
                push    bc
                ldir
                pop     bc
                pop     de
                push    hl
                ld      hl, IBDATA
                ld      a, BANK_CANVAS
                call    tpoke + IB
                pop     hl
                ret

; kid_engarde is the kid's: standing, the shadow goes en garde only as
; FinalShad has him (the down and forward of CTRL.S's standing -- below).

pktab:
pkeng:          dw      kid_engarde
                db      3
                db      0xAF, 0, 0      ; xor a: no sword to draw
                db      0x3A            ; ld a, (gotsword)
                dw      gotsword

; hit_floor: the shadow lands easy from any height short of death (medland).

pkoof:          dw      hfoof + 1
                db      1
                db      DEATHVEL
                db      OOFVEL

; FightCtrl's down: the shadow resheathes, as the kid does (:sstand).

pkalert:        dw      fcalert + 1
                db      1
                db      SQ_RESHEATHE
                db      SQ_GOALERTSTAND

; The kid standing: the shadow in the air or landing, he does not draw on
; him (standing's OpID 1).  Put in for the kid's turn.

pkland:         dw      kedo
                db      3
                db      0xC3            ; jp kesafe
                dw      kesafe
                db      0xCD            ; call do_engarde
                dw      do_engarde

; startfall: the phantom bridge (tphant).  Put in for the kid's turn.

pkfall:         dw      cfsl + 1
                db      2
                dw      tphant + IB
                dw      c1addsl
PKN             equ     5

pkall:          call    tpcopy
                ld      hl, pktab
                ld      b, PKN
pka:            push    bc
                call    pkclr
                pop     bc
                djnz    pka
                ret

; ---- the shadow

; shadpos12, the second character's record: CharX $51, CharY $F0 -- above
; the top of the screen -- facing right, posn 15, stepfall next, the top
; row, action nought, no sword, the shadowman, alive; nothing of him drawn.

shrec:          dw      2 * (0x51 - 58)
                db      0xF0, 1, 15
                dw      seqs + SO_STEPFALL
                db      0, 0, 0, 0, 1, 0xff
                ds      CHRECLEN - 14
                db      192

; HL = a record's first thirteen bytes, over shadpos12's whole one: the
; shadow into the second character's place.

putshad:        push    hl
                ld      hl, shrec
                ld      de, oprec
                ld      bc, CHRECLEN
                ldir
                pop     hl
                ld      de, oprec
                ld      bc, charcu - chrec
                ldir
                ld      a, 1
                ld      (gdhere), a
                ret

; Z when the shadow is here: the second character, and CharID 1.

shhere:         ld      a, (gdhere)
                dec     a
                ret     nz
                ld      a, (charid + OP)
                dec     a
                ret

; HL = his strength: OppStrength here, or what he had where he is kept.

shsp:           ld      hl, shstr
                call    shhere
                ret     nz
                ld      hl, oppstr
                ret

; UNHOLY: the one left alive dies too -- white lightning and a splat.

unholy:         ld      a, WHITE
                ld      (lightcolor), a
                ld      a, 5
                ld      (lightning), a
                ld      a, SND_SPLAT
                jp      addsound

; 0 no shadow, 1 the shadow alive -- here, or kept in shroom -- and 2 dead:
; ShadID 1 and ShadLife.

shst:           db      0
shroom:         db      0
shstr:          db      0               ; his strength, kept
park:           ds      13              ; and the rest of him
shadact:        db      0               ; shadowaction
lastroom:       db      0
came:           db      0               ; the kid came into this room
prevk:          db      0               ; the strengths as the last frame
prevs:          db      0               ; left them
flipped:        db      0               ; the kid drawn as the shadow
patched:        db      0               ; the control code patched
ibdone:         db      0               ; imgbuf has its routines this frame

; ---- ovshad: the shadow's keys, in his turn (Char the shadow, Op the kid)

shad:           ld      a, (lvflag)     ; the next level, or this one again,
                cp      2               ; comes in this frame's room change:
                ret     nc              ; nothing patched that its post would
                                        ; not put back
                ld      hl, pkeng
                call    pkset
                ld      hl, pkoof
                call    pkset
                ld      hl, pkalert
                call    pkset
                call    finalshad
                ld      a, (charact)    ; CUTGUARD: only a free fall takes
                cp      4               ; the shadow off the foot of the
                ret     z               ; screen -- dropping in he is past it
                ld      a, 0xC9         ; ret
                ld      (cgret), a
                ret

; FinalShad.  Screen 15: he is held above it, shadpos12 again, till the kid
; is in past X 150; then he jumps on top of him.

finalshad:      ld      a, (roomnum)
                cp      SWORDSCRN
                jr      nz, fscont
                ld      a, (shadact)
                or      a
                jr      nz, fscont
                ld      hl, (charx + OP)
                ld      de, -HOLDX
                add     hl, de
                bit     7, h
                jr      nz, fsgo
                ld      hl, shrec       ; csps
                ld      de, chrec
                ld      bc, charcu - chrec
                ldir
                ret
fsgo:           ld      a, 1
                ld      (shadact), a

fscont:         ld      a, (charsword)
                cp      2
                jr      nc, fsfight
                ld      a, (charsword + OP)
                cp      2
                jr      nc, fshost
                ld      a, (offguard)
                or      a
                jr      nz, fsface

; Hostile: close enough, en garde -- DoEngarde, which his standing takes at
; once: posn 15, alive -- else turn to face the kid.

fshost:         ld      a, (enemyalert)
                cp      2
                jr      c, fs2
                call    getopdist
                cp      SWORDTHRES
                jr      nc, fs2
                ld      a, (frame)
                cp      15
                ret     nz
                ld      a, (charlife)
                or      a
                ret     p
                ld      a, 2
                ld      (charsword), a
                ld      hl, seqs + SO_ENGARDE
                ld      (seqptr), hl
                ret
fs2:            call    getopdist
                or      a
                ret     p
                jp      pr_back         ; DoBack

; Fighting: the kid has put his sword up -- a moment, then lower yours.

fsfight:        ld      a, (offguard)
                or      a
                jr      z, fseng
                ld      a, (refract)
                or      a
                jp      z, pr_down      ; DoDown
fseng:          call    ibc
                ld      hl, ai_engarde  ; EnGarde
                jp      tcall + IB

; Face to face, swords down: the kid coming, come too; met, whammo.

fsface:         call    getopdist
                or      a
                jp      m, fsmerge
                ld      a, (enemyalert)
                cp      2
                ret     nz
                ld      a, (frame + OP)
                cp      3
                ret     c
                cp      15
                jp      c, pr_fwd       ; startrun and stepfwd
                cp      127
                ret     c
                cp      133
                jp      c, pr_fwd
                ret

; Kid and shadow reunite: white lightning, BOOSTMETER, s_Rejoin -- which the
; CPC has no tune for -- and the flashing; the shadow turns into the kid,
; all but where each was drawn, and is gone (post: VANISHCHAR).

fsmerge:        ld      a, WHITE
                ld      (lightcolor), a
                ld      a, 10
                ld      (lightning), a
                ld      a, (maxkidstr)
                cp      MAXMAXSTR
                adc     a, 0
                ld      (maxkidstr), a
                ld      (kidstr), a     ; RECHARGEMETER
                ld      (meterdirty), a
                ld      a, MERGETIME
                ld      (mergetimer), a
                ld      hl, chrec       ; SaveKid
                ld      de, oprec
                ld      bc, charcu - chrec
                ldir
                xor     a
                ld      (charid + OP), a
                ld      (shst), a       ; ShadID nought
                ret

; ---- the top of the frame, before anything moves

start:          xor     a
                ld      (ibdone), a
                ld      (charid), a     ; the kid himself again (flipped)
                ld      (oppjr + 1), a  ; DRAWOPPMETER: the shadow's shows
                ld      a, (exitopen)   ; the level begun again: nobody's
                or      a               ; shadow yet
                jr      nz, st1
                ld      (shst), a

st1:            ld      hl, mergetimer  ; misctimers: down to 1, and then -1
                ld      a, (hl)         ; for good
                dec     a
                cp      0x7F
                jr      nc, st2
                ld      (hl), a
                or      a
                jr      nz, st2
                dec     (hl)

st2:            ld      a, (shst)       ; UNHOLY, the kid's turn: the shadow
                cp      2               ; dead, he dies too
                jr      nz, st3
                ld      a, (charlife)
                or      a
                jp      p, st3
                xor     a               ; decstr 100
                ld      (kidstr), a
                call    unholy

st3:            call    shhere          ; SHADCTRL: the shadow out of strength
                jr      nz, st4         ; or dead goes -- no victory tune
                ld      a, (charlife + OP)
                or      a
                jp      p, st3a
                ld      a, (oppstr)
                or      a
                jr      nz, st4
st3a:           xor     a
                ld      (charlife + OP), a
                call    gd_gone         ; VANISHCHAR
                ld      a, 2
                ld      (shst), a

st4:            ld      a, (lvflag)     ; (see shad)
                cp      2
                ret     nc
                ld      a, (charid + OP) ; CHECKALERT: c1anim leaves the
                dec     a               ; shadowman out
                jr      nz, st5
                call    ibc
                ld      hl, checkalert
                call    tcall + IB

                call    shhere          ; the shadow in the air or landing
                jr      nz, st5
                ld      a, (charact + OP)
                cp      3
                jr      z, st4a
                ld      a, (frame + OP)
                sub     107
                cp      11
                jr      nc, st5
st4a:           ld      hl, pkland
                call    pkset

st5:            ld      a, (mergetimer) ; the phantom bridge
                or      a
                ld      hl, pkfall
                call    m, pkset

                ld      a, (roomnum)    ; and the way out
                cp      EXITSCRN
                ret     nz
                call    ibc
                ld      a, 0xC3         ; jp texit
                ld      (nrleft), a
                ld      hl, texit + IB
                ld      (nrleft + 1), hl
                ret

; ---- after the moves: the room change is made, the frame not yet drawn

pmain:          ld      hl, patched     ; the control code as it was
                ld      a, (hl)
                ld      (hl), 0
                or      a
                call    nz, pkall
                ld      a, 0xD8         ; ret c
                ld      (cgret), a
                ld      a, 0x3A         ; ld a, (links)
                ld      (nrleft), a
                ld      hl, links
                ld      (nrleft + 1), hl

                ld      a, (shst)       ; merged: VANISHCHAR
                or      a
                jr      nz, pm1
                call    shhere
                call    z, gd_gone

pm1:            ld      hl, lastroom    ; into a room this frame?
                ld      a, (roomnum)
                ld      b, (hl)
                ld      (hl), a
                sub     b
                ld      (came), a
                jr      z, pm2
                ld      a, b            ; stealsword: right out of screen 18
                cp      STEALFROM
                jr      nz, pm2
                ld      a, (roomnum)
                cp      STEALTO
                jr      nz, pm2
                ld      a, BG_FLOOR
                ld      (level + (SWORDSCRN - 1) * 30 + SWORDAT), a

pm2:            ld      a, (shst)       ; the shadow alive, not here
                dec     a
                jr      nz, pm3
                call    shhere
                jr      z, pm3
                ld      a, (roomnum)    ; nor where he was kept
                ld      hl, shroom
                cp      (hl)
                jr      nz, pm3
                ld      a, (came)       ; come back to him: there he is
                or      a
                jr      nz, pmback
                ld      a, 2            ; gone where he was with nobody
                ld      (shst), a       ; leaving: off the foot of the
                jr      pm3             ; screen -- CUTGUARD -- and dead
pmback:         ld      hl, park
                call    putshad
                ld      a, (shstr)
                ld      (oppstr), a

; ADDGUARD's level twelve: into screen 15, the shadow not dropped yet nor
; reabsorbed, and the sword gone -- csps shadpos12, with the shadow's
; strength and guard program 3.

pm3:            ld      a, (came)
                or      a
                jr      z, pm4
                ld      a, (roomnum)
                cp      SWORDSCRN
                jr      nz, pm4
                ld      a, (exitopen)   ; set when he drops
                ld      hl, mergetimer
                or      (hl)
                jr      nz, pm4
                ld      a, (level + (SWORDSCRN - 1) * 30 + SWORDAT)
                and     0x1f
                cp      BG_SWORD
                jr      z, pm4
                ld      a, 1
                ld      (exitopen), a
                ld      (shst), a
                ld      a, SWORDSCRN
                ld      (shroom), a
                xor     a
                ld      (shadact), a
                ld      a, SHADSTR
                ld      (oppstr), a
                ld      (prevs), a
                ld      a, 3
                ld      (guardprog), a
                ld      hl, c1gprob
                call    c1call
                ld      hl, shrec
                call    putshad

; chgmeters: kid against shadow, what the one loses the other loses -- the
; kid's first -- unless it would take him under nought.

pm4:            ld      a, (shst)
                dec     a
                jr      nz, pm6
                call    shsp
                ld      a, (prevs)
                ld      d, a
                ld      a, (prevk)
                ld      e, a
                ld      a, (kidstr)
                ld      c, a
                ld      a, e
                sub     c               ; what the kid lost
                jr      c, pmopp
                jr      z, pmopp
                ld      c, a
                ld      a, d
                sub     c
                jr      nc, pms
                ld      a, d
pms:            ld      (hl), a
                jr      pm5
pmopp:          ld      c, (hl)         ; what the shadow lost
                ld      a, d
                sub     c
                jr      c, pm5
                jr      z, pm5
                ld      c, a
                ld      a, e
                sub     c
                jr      nc, pmk
                ld      a, e
pmk:            ld      (kidstr), a

; UNHOLY, the shadow's turn: the kid dead, the shadow dies too.

pm5:            ld      a, (charlife)
                or      a
                jp      m, pm5a
                ld      a, (hl)
                or      a
                jr      z, pm5a
                ld      (hl), 0
                call    unholy
pm5a:           ld      a, (hl)         ; out of strength where he is kept:
                or      a               ; dead there (SHADCTRL)
                jr      nz, pm6
                call    shhere
                jr      z, pm6
                ld      a, 2
                ld      (shst), a

pm6:            ld      a, (shst)       ; kept as he is, for when the kid
                dec     a               ; leaves him
                jr      nz, pm7
                call    shhere
                jr      nz, pm7
                ld      hl, oprec
                ld      de, park
                ld      bc, charcu - chrec
                ldir
                ld      a, (roomnum)
                ld      (shroom), a
                ld      a, (oppstr)
                ld      (shstr), a

pm7:            ld      a, (kidstr)
                ld      (prevk), a
                call    shsp
                ld      a, (hl)
                ld      (prevs), a

; DRAWKID: while mergetimer counts, on its odd counts the kid is drawn as
; the shadow is -- CharID 1 until the top of the next frame -- and kid_still
; is not let leave him as he was, either way.

                ld      a, (mergetimer)
                cp      0x80
                sbc     a, a
                ld      b, a
                ld      a, (mergetimer)
                and     b
                and     1
                ld      (charid), a
                ld      hl, flipped
                ld      b, (hl)
                ld      (hl), a
                or      b
                ret     z
                call    tpcopy
                ld      a, 0xff
                ld      (IBDATA), a
                ld      hl, IBDATA
                ld      de, kidlast + 3
                ld      bc, 1
                ld      a, BANK_CVS
                jp      tpoke + IB
lvlowend:

; The entries, in the level's own room: the top of the frame, after the
; moves, and six bytes in the shadow's turn (the dungeon's ovshad).

                org     lvcode
post:           jp      c, start
                jp      pmain
                jp      shad

                endif

                if      LVNUM = 13

; ---------------------------------------------------------------- Jaffar
;
; Level thirteen's (STARTKID's :special13, CRUMBLE and DEADENEMY in SUBS.S;
; animfloor, SHAKEM and crushchar in MOVER.S; GoneUpstairs in COLL.S).  The
; kid comes in running, from the level before.  Into screen 23, or 16, the
; loose floors of the room above -- blocks 2 to 7 of its bottom row -- give
; way over him, each after a moment of its own; on this level a floor only
; wiggling never settles, but falls, and landing shakes none.  (A falling
; floor crushes him running here, as crushchar has it on this level only:
; mobcrush in bg.asm does on every level.)  The vizier dead, the exit
; opens: s_Upstairs, white lightning, and the plate in screen 24 pushed.
; Up its stairs, no tune.  jaffmusic's s_Jaffar, as the kid goes in to
; him, the CPC has none of, and the vizier's wait for it to end (Alert in
; AUTO.S) waits for nothing.
;
; What the game does otherwise on this level it does in fixed code, which
; is changed at the top of every frame; level fourteen puts it back.

CRUMBLE1        equ     23              ; CRUMBLE's screens
CRUMBLE2        equ     16
EXITPLATE       equ     24              ; DEADENEMY's rdblock 24, 0, 0
WHITE           equ     7               ; lightcolor $FF, the border's white
LIGHTTIME       equ     10

post:           jp      c, start

; After the moves.  PrepCut's CRUMBLE: into a screen, this frame.

                ld      hl, lastroom
                ld      a, (roomnum)
                cp      (hl)
                ld      (hl), a
                call    nz, crumble

; DEADENEMY's :wingame: the vizier newly dead -- SHADCTRL's tune, s_Upstairs
; put in for s_Vict, is on already.

                ld      a, (exitopen)
                or      a
                ret     nz
                ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (charlife + OP)
                or      a
                ret     nz
                inc     a
                ld      (exitopen), a
                ld      a, WHITE
                ld      (lightcolor), a
                ld      a, LIGHTTIME
                ld      (lightning), a
                ld      a, EXITPLATE    ; the exit opened
                ld      (trscrn), a
                xor     a
                ld      (trloc), a
                call    trobat
                jp      pushpp

; CRUMBLE: blocks 7 down to 2 of the bottom row of the screen above, each a
; loose floor not held from below and not on its way down already set going
; (BREAKLOOSE1) from a state of nought to fifteen below nought.

crumble:        cp      CRUMBLE1
                jr      z, cr1
                cp      CRUMBLE2
                ret     nz
cr1:            ld      a, (links + 2)  ; scrnAbove
                or      a
                ret     z
                ld      (trscrn), a
                ld      a, 2 * 10 + 7
cr2:            ld      (trloc), a
                call    trobat
                cp      BG_LOOSE
                jr      nz, cr3
                ld      hl, (blueptr)   ; reqmask
                bit     5, (hl)
                jr      nz, cr3
                ld      a, (trobst)     ; wiggling, or not going yet
                or      a
                jr      z, cr2a
                jp      p, cr3
cr2a:           call    rnd
                and     0x0f
                neg
                ld      (trobst), a
                call    trobsave
                xor     a               ; down
                ld      (trdirec), a
                call    addtrob
                ld      a, LOOSEWIPE
                ld      (redh), a
                call    redplate
cr3:            ld      a, (trloc)
                dec     a
                cp      2 * 10 + 2
                jr      nc, cr2
                ret

; The top of the frame, before anything moves.  The level begun, or begun
; again -- levelgo leaves createshad nought: STARTKID's :special13, which
; jumps him to running where it would have turned him -- CharX and CharFace
; as they were before the turn, and ANIMCHAR once -- and CRUMBLE for the
; screen he starts in.

start:          ld      a, (createshad)
                or      a
                jr      nz, st1
                ld      (lastroom), a
                inc     a
                ld      (createshad), a
                ld      a, (roomnum)    ; a test tape begun elsewhere starts
                ld      hl, level + LV_KIDSCRN  ; him where it says
                cp      (hl)
                jr      nz, st1
                ld      hl, (level + LV_HEAD)
                ld      (charx), hl
                ld      a, (level + LV_HEAD + 4)
                ld      (facing), a
                ld      hl, trun
                ld      de, imgbuf
                ld      bc, trunend - trun
                ldir
                call    imgbuf

; And the level's own ways, in the fixed code: animfloor's wiggling floor
; not settled (its ret c a ret), SHAKEM left out (a ret at slrow, past
; taking the jar off), s_Upstairs for the vizier's death, and the stairs
; climbed past their tune (stairsq).  And a floor due to fall waits,
; still, for room among the falling (ibff): six of them come down at once
; here, and moblist has room for four -- the fifth and sixth were lost, and
; never landed.  Still, for its shaking would be drawn first, and nothing
; falls while a picture waits to go first (animmobs).

st1:            ld      a, 0xC9         ; ret
                ld      (afwiggle + 2), a
                ld      (slrow), a
                ld      a, SONG_UPSTAIRS
                ld      (scvict + 1), a
                ld      hl, stairsq
                ld      (stcall + 1), hl
                ld      hl, ibff
                ld      de, imgbuf
                ld      bc, ibffend - ibff
                ldir
                ld      a, 0xCD         ; call imgbuf
                ld      (affall), a
                ld      hl, imgbuf
                ld      (affall + 1), hl
                ret

; animfloor's cp BG_FFALLING and ret c, from imgbuf, where start puts it
; each frame: animtrans comes straight after, and nothing between.

ibff:           cp      BG_FFALLING
                jr      c, ibff1
                ld      a, (nummob)
                cp      MAXMOB
                ret     c
                xor     a               ; no room: it waits, still -- a floor
                ld      (redwant), a    ; wiggling holds up those falling
ibff1:          pop     hl              ; not yet: out of animfloor
                ret
ibffend:

; Run from imgbuf: the sequences are in the canvas bank.

trun:           call    page_canvas
                ld      a, SQ_RUNNING
                call    jumpseq
                call    page_canvas
                call    step_seq
                jp      page_bg
trunend:

lastroom:       db      0               ; the screen he was in last frame

                endif

                if      LVNUM = 14

; ---------------------------------------------------------------- the princess
;
; Level fourteen's (PrepCut and YouWin in TOPCTRL.S): out of screen 1 to the
; left is the princess's room, screen 5, which is never shown as a room --
; the game is won.  cutprincess, PlayCut7 and the Epilog come off the tape
; the way the next level would, the scene first: in screen 1 the way left
; is the way to the next level (nrlevel), and this level's head has the
; scene's length (LH_CUT) and the Epilog's place.  The scene never comes
; back.
;
; And level thirteen's changes to the fixed code are put back, every frame
; after the moves: see there.

YOUWINSCRN      equ     1               ; the screen right of screen 5

post:           ld      a, 0xD8         ; ret c
                ld      (afwiggle + 2), a
                ld      (affall + 2), a
                ld      hl, BG_FFALLING * 256 + 0xFE    ; cp BG_FFALLING
                ld      (affall), hl
                ld      a, 0x4F         ; ld c, a
                ld      (slrow), a
                ld      a, SONG_VICT
                ld      (scvict + 1), a
                ld      hl, stairseq
                ld      (stcall + 1), hl
                ld      a, (roomnum)
                cp      YOUWINSCRN
                ld      a, 0x3A         ; ld a, (links)
                ld      hl, links
                jr      nz, pw1
                ld      a, 0xC3         ; jp nrlevel
                ld      hl, nrlevel
pw1:            ld      (nrleft), a
                ld      (nrleft + 1), hl
                ret

                endif

                if      LVNUM = 3
; ---------------------------------------------------------------- the bones
;
; Level three's, out of the program's fixed half, which had no room left:
; the skeleton getting up, and falling into the screen below.  The entries:
; the top of the frame -- the dungeon's ovstart, carry set -- after the
; frame's moves, and cutguard's at lvcode + 5.

post:           jr      c, bones
                jp      skel
                jp      skeldown

; BONESRISE in MISC.S: with the exit open and nobody else in the room, the
; skeleton lying in screen one gets up as the kid comes level with it.  The
; bones are a piece of the background until then; they become floor, that
; block and the one to its right are redrawn, and what stands up is a guard
; of the kid's own making -- CharID 4, program two, three points of strength
; he can never be made to lose.  NextFrame has it after animtrans, which
; opens the exit; here it comes just before, from ovstart, so an exit that
; is all the way open on the very frame he comes level with the bones has
; them rise a frame later.

bones:          ld      a, (gdhere)     ; nobody in the room yet
                or      a
                ret     nz
                ld      a, (roomnum)
                cp      SKELSCRN
                ret     nz
                ld      a, (exitopen)
                or      a
                ret     z
                ld      hl, (charx)     ; KidBlockX: level with the bones,
                call    blockcol_of     ; or one short of them
                cp      SKELTRIG
                jr      z, brtrig
                cp      SKELTRIG + 1
                ret     nz

brtrig:         ld      a, SKELY * 10 + SKELX
                ld      (trloc), a
                ld      a, (roomnum)
                ld      (trscrn), a
                call    trobat          ; what lies there
                push    af
                ld      a, BG_FLOOR     ; floor from now on, and the block
                call    trobtype        ; and the one right of it redrawn --
                ld      a, 24           ; markred and markwipe, 24 rows deep
                ld      (redh), a
                call    redplate
                pop     af
                cp      BG_BONES
                ret     nz

                ld      hl, brtramp     ; the control code is in the canvas
                ld      de, imgbuf      ; bank: it is called from down there
                ld      bc, brtrend - brtramp
                ldir
                call    swapchar        ; he is made in Char, as POP makes
                ld      a, SKELY        ; him
                ld      (blocky), a
                ld      a, (floory + SKELY + 1) ; on its floor
                ld      (chary), a
                ld      hl, SKELX * BLOCK_PX + BLOCK_PX ; getblockej + angle
                ld      (charx), hl                     ; + 7
                xor     a
                ld      (facing), a     ; POP's -1, left
                ld      a, SQ_ARISE
                ld      hl, bumpseq     ; jumpseq, then animchar
                call    imgbuf
                ld      a, SKELPROG
                ld      (guardprog), a
                ld      hl, c1gprob     ; its tables are CODE1's
                call    c1call
                ld      a, 0xff
                ld      (charlife), a
                ld      a, 3
                ld      (oppstr), a
                xor     a
                ld      (alertguard), a
                ld      (refract), a
                ld      (justblocked), a
                ld      (yvel), a
                ld      hl, newcol      ; nothing of him drawn yet, and his
                ld      b, 13           ; rectangles, and CharXVel
brclr:          ld      (hl), a
                inc     hl
                djnz    brclr
                ld      a, 2
                ld      (charsword), a
                ld      a, 4            ; the skeleton
                ld      (charid), a
                ld      a, 1            ; and a guard in the room from here
                ld      (gdhere), a
                jp      swapchar

; Run from imgbuf: a routine of the control code's at HL, A in and out.

brtramp:        push    af
                call    page_canvas
                pop     af
                call    jphl
                push    af
                call    page_bg
                pop     af
                ret
brtrend:

; CUTGUARD in AUTO.S for the skeleton: one that falls into the room it
; belongs in gets up again there -- UPDATEGUARD for the room below, which
; ADDGUARD will raise him in again: a fresh start, and he is gone from this
; one.  Anywhere else he is gone for good, as any guard is.

skeldown:       ld      a, (links + 3)
                cp      SKELLAND
                jp      nz, gd_off
                ld      a, SND_SPLAT
                call    addsound
                ld      de, 0           ; out of this room's list, which a
                call    gd_field        ; visit before may have left him in:
                ld      (hl), 0xff      ; he is not up here any more
                ld      bc, SKELLANDBLK * 256 + SKELLANDX
                ld      hl, (charx + OP) ; CUTGUARD puts him on the middle
                ld      de, -140        ; row whichever side he went off; off
                add     hl, de          ; the left he falls past it, on to
                jr      c, skd1         ; the bottom row (the user's): there,
                ld      hl, (charx + OP) ; where he is
                sra     h
                rr      l
                ld      a, l
                add     a, SCRNLEFT
                ld      c, a
                ld      b, 20
skd1:           ld      a, SKELLAND     ; his fields, GdStart* for the room,
                ld      de, 0           ; 24 apart
                call    gd_field_in
                ld      (hl), b         ; the block (its row)
                ld      de, 24
                add     hl, de
                ld      (hl), 0         ; facing right
                add     hl, de
                ld      (hl), c         ; ShadX
                ld      e, 48
                add     hl, de
                ld      a, (guardprog)
                ld      (hl), a         ; the program
                ld      e, 24
                add     hl, de
                ld      (hl), 0         ; alive: ADDGUARD starts him afresh
                jp      gd_gone

; Two things the user asked for, for screen three, where he lands and where
; the loose floor is (the rest of his rooms have no floor to fall from under
; him).  When the floor under his front foot has fallen and
; his base still stands -- he had stepped back off it -- he goes on into the
; hole and down it, rather than standing there over it; and once he falls,
; drifting the way he was fighting does not take him over the block beside
; the hole, to come down inside it.

skel:           ld      a, (gdhere)
                or      a
                ret     z
                call    swapchar        ; him in hand
                call    skfix
                jp      swapchar

skfix:          ld      a, (charact)
                cp      3
                jr      c, skgnd
                cp      5
                ret     nc              ; neither on the ground nor falling
                ld      hl, skfell      ; falling: where he went down, kept,
                ld      a, (hl)         ; and back to it should what he
                inc     (hl)            ; drifts over be a block of the row
                or      a               ; he will land on -- he would come
                jr      nz, skf1        ; down inside it
                ld      hl, (charx)
                ld      (skfx), hl
                ret
skf1:           call    base_x
                call    sktile
                cp      BG_BLOCK
                ret     nz
                ld      hl, (skfx)
                ld      (charx), hl
                ret
skgnd:          xor     a               ; on the ground, his front foot
                ld      (skfell), a     ; over none: a step towards it each
                ld      hl, (charx)     ; frame, till his base -- the back
                call    sktile          ; foot, en garde -- is over it too
                ret     nz              ; and he falls
                ld      de, 8
                ld      a, (facing)
                or      a
                jr      nz, skg1
                ld      de, -8
skg1:           ld      hl, (charx)
                add     hl, de
                ld      (charx), hl
                ret

; HL = a room x on his row.  Out: Z when there is nothing there.

sktile:         ld      a, (blocky)
                ld      c, a
                call    tile_in_row
                or      a
                ret

skfell:         db      0
skfx:           dw      0

                endif

                if      LVNUM = 9
; ---------------------------------------------------------------- upside down
;
; Level nine's two tall flasks hold potion four, which turns the screen over
; (POTIONEFFECT in MISC.S: invert, and INVERTY turns the Apple's tables of
; line addresses round) -- and back again, a second one.  potion_effect only
; turns the flag over: createshad, which nothing else on this level uses and
; levelgo clears, as MASTER.S does invert when a level begins.  The screen
; comes back the right way up when he dies (TOPCTRL.S) and when the level is
; left -- here as soon as he has gone through the door at the top of the
; stairs; the meters stay at the foot, where the Spectrum has their colours.
;
; Everything is drawn as ever, the room and the working copy the right way
; up; only what goes to the screen goes upside down, and always into bank 5,
; the screen shown:
;
; - showgo, every rectangle from the working copy: from shabove on, flshow,
;   a row at a time with the row's place turned over;
; - fullshow, the screen laid from the room: its rows go to the line turned
;   over (laflip), and him out of the working copy afterwards by showpart --
;   which shows his rectangles through flshow -- not row by row;
; - set_attrs, the colours: worked out as ever, then their rows turned over
;   (flattr); shown_attrs, after a hurt, goes through it too;
; - a new view: the view ahead goes on being made in bank 7 -- never shown
;   now -- and when it is ready the screen is laid whole from the room
;   instead (camflip), so bank 5 is the one shown from first to last.
;
; A screen line y goes to 191 - y: its address's high byte H to 0x97 - H,
; the low byte's character row turned over, L xor 0xE0.  The code for this
; that has to be in the fixed half -- two ways into the background bank and
; laflip -- goes over ckmirr, the mirror's, which no level after four ever
; runs; the eight patches are put in and taken out again from here.

WORKOFS         equ     (work - SCREEN) / 256

post:           ret     c               ; (the top of the frame)
                ld      a, (createshad)
                ld      b, a
                ld      a, (lvflag)     ; up again when a level is to come --
                cp      2
                jr      nc, upright
                ld      a, (frame)      ; already once he is through the
                or      a               ; door at the top of the stairs, the
                jr      z, upright      ; blank frames before nextlevel: on
                                        ; the frame that sets lvflag, ENTER
                                        ; held changes the level at once
                ld      a, (charlife)   ; and when he is dead
                rla
                jr      c, inv1
upright:        xor     a
                ld      (createshad), a
                ld      b, a
inv1:           ld      a, (inverted)   ; as it is: nothing to do
                cp      b
                ret     z
                ld      a, b
                ld      (inverted), a
                ld      a, 1            ; the screen laid again, either way
                ld      (fullshow), a
                ld      hl, ibsrc
                ld      de, ckmirr
                ld      bc, IBLEN
                ldir
                ld      hl, ptab
                ld      a, NPATCH
inv2:           push    af
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                push    hl
                ld      a, (inverted)
                or      a
                jr      nz, inv3
                inc     hl              ; the bytes as they were
                inc     hl
                inc     hl
inv3:           ldi
                ldi
                ldi
                pop     hl
                ld      bc, 6
                add     hl, bc
                pop     af
                dec     a
                jr      nz, inv2
                ret

; A rectangle of the working copy to the screen, upside down: from showgo's
; shabove, by bgcall.  B = its rows, C = the first; shcall has the copy's way
; in for its width.  Rows the meters lie over now are its top eight.

flshow:         ld      a, c
                cp      8
                jr      nc, fls1
                ld      a, 1
                ld      (meterdirty), a
fls1:           ld      hl, (shcall + 1)
                ld      (flcall + 1), hl
                ld      a, (shcol)
                ld      e, a
                ld      a, c
                call    scraddr
                ld      a, h            ; HL = the working copy
                add     a, WORKOFS
                ld      h, a
flrow:          push    bc
                ld      a, 0x97 + WORKOFS       ; DE = the screen, the line
                sub     h                       ; turned over
                ld      d, a
                ld      a, l
                xor     0xe0
                ld      e, a
                push    hl
                ld      c, 255
flcall:         call    0               ; patched: the copy
                pop     hl
                inc     h               ; a line down the working copy
                ld      a, h
                and     7
                jr      nz, fls2
                ld      a, l
                add     a, 32
                ld      l, a
                jr      c, fls2
                ld      a, h
                sub     8
                ld      h, a
fls2:           pop     bc
                djnz    flrow
                ret

; set_attrs, and the colour's rows turned over: by bgcall from set_attrs.

flattr:         ld      hl, SCREEN + 6144
                call    set_attrs_at
                ld      hl, SCREEN + 6144
                ld      de, SCREEN + 6144 + 23 * 32
                ld      b, 12
fla1:           push    bc
                ld      b, 32
fla2:           ld      a, (de)
                ld      c, (hl)
                ld      (hl), a
                ld      a, c
                ld      (de), a
                inc     hl
                inc     de
                djnz    fla2
                ex      de, hl
                ld      bc, -64
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    fla1
                ret

; Over ckmirr: the ways in from showgo and set_attrs, and fullshow's line.

ibsrc:          ld      de, flshow
                jp      bgcall
                ld      de, flattr
                jp      bgcall
                call    line_addr       ; laflip: line_addr's, turned over
                ld      a, l
                xor     0xe0
                ld      l, a
                ld      a, 0x97
                sub     h
                ld      h, a
                ret
IBLEN           equ     $ - ibsrc       ; up to createshad, 25
TRSHOW          equ     ckmirr
TRATTR          equ     ckmirr + 6
LAFLIP          equ     ckmirr + 12

; The patches: where, the bytes upside down, and as they were.

ptab:           dw      shabove
                db      0xc3
                dw      TRSHOW
                db      0x3a
                dw      shcol
                dw      set_attrs
                db      0xc3
                dw      TRATTR
                db      0x21
                dw      SCREEN + 6144
                dw      fsline
                db      0xcd
                dw      LAFLIP
                db      0xcd
                dw      line_addr
                dw      fsspr1
                db      0xcd
                dw      fsnone + 1      ; a ret
                db      0xcd
                dw      fs_sprite
                dw      fsspr2
                db      0xcd
                dw      fsnone + 1
                db      0xcd
                dw      fs_sprite
                dw      fsflames
                db      0xc3
                dw      showpart
                db      0xc3
                dw      show_flames
                dw      camflip
                db      0x32
                dw      fullshow
                db      0x32
                dw      flipnow
                dw      shattrs
                db      0xc3
                dw      set_attrs
                db      0xc3
                dw      set_attrs_at
NPATCH          equ     ($ - ptab) / 8

inverted:       db      0               ; as the patches stand

                endif

                if      LVNUM < 3 or LVNUM = 7 or LVNUM = 10 or LVNUM = 11
post:           ret
                endif

lvend:
