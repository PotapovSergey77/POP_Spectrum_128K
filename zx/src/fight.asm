; ---------------------------------------------------------------- the guard
;
; The guard and the fight: AUTO.S, the fighting half of CTRL.S, TestStrike
; and StabChar, and a second character drawn beside the first.  All of it
; sits in the fixed half of the map, above the working copy, so it runs with
; whatever bank is in -- the control code it calls needs the canvas bank, the
; drawing the art, and nothing here pages anything of its own.

; LOADSHADWOP and SAVESHADWOP in CTRLSUBS.S are one exchange here: Char and Op
; trade places.  Done twice, everything is back where it was.
;
; Out: flags as they came in -- gd_swap below counts on it.

swapchar:       ld      hl, chrec
                ld      de, oprec
                ld      b, CHRECLEN
swloop:         ld      a, (de)
                ld      c, (hl)
                ld      (hl), a
                ld      a, c
                ld      (de), a
                inc     hl
                inc     de
                djnz    swloop
                ret

; The guard in hand, if there is one.  Out: NZ with him swapped in, Z when
; there is nobody and nothing was done.

gd_swap:        ld      a, (gdhere)
                or      a
                ret     z
                jr      swapchar

; GETOPDIST in CTRLSUBS.S: how far forward the character in hand has to go
; to reach the other one, in POP's 140 wide units and held to 127 either way.
; Facing opposite ways, the width of a figure goes on top.

ESTWIDTH        equ     13

getopdist:      ld      hl, (charx + OP)
                ld      de, (charx)
                or      a
                sbc     hl, de          ; two pixels to the unit
                sra     h
                rr      l
                bit     7, h
                jr      nz, godneg
                ld      a, h
                or      a
                jr      nz, god127
                ld      a, l
                cp      128
                jr      c, godgot
god127:         ld      a, 127
                jr      godgot
godneg:         ld      a, h
                inc     a
                jr      nz, godm127
                ld      a, l
                cp      129
                jr      nc, godgot
godm127:        ld      a, -127
godgot:         ld      b, a            ; facing left, forward is the other
                ld      a, (facing)     ; way
                or      a
                ld      a, b
                jr      nz, godface
                neg
godface:        ld      b, a
                ld      a, (facing + OP)
                ld      c, a
                ld      a, (facing)
                xor     c
                ld      a, b
                ret     z
                cp      127 - ESTWIDTH  ; unsigned, as POP compares it
                ret     nc
                add     a, ESTWIDTH
                ret

; ---------------------------------------------------------------- drawing
;
; Both characters go through the kid's own drawing, a pass at a time: each
; one's rectangle first, then both rubbed out from the room, then the flames,
; then both pictures -- the guard first, so the kid is in front, as addchars
; in TOPCTRL.S puts him.  Rubbing out one after drawing the other would take
; the first away wherever the two overlap.
;
; What is rubbed out is the box round where each one was and where he is
; now, once: the two rectangles overlap nearly all over from one frame to the
; next, and were being done twice.  Everything in the box is then the room,
; the flames and whoever stands in it, so the box can go to the screen whole
; as well, and the corners are right too.

draw_chars:     call    gd_swap
                jr      z, dckid
                call    dp_rect
                call    swapchar
dckid:          call    dp_rect
                ld      hl, newcol + OP ; a guard gone still has his last
                call    rect_box        ; picture to rub out
                ld      hl, newcol
                call    rect_box
                ld      hl, boxcol + OP
                call    eraseset
                ld      hl, boxcol
                call    eraseset
                call    draw_flames
                call    gd_swap
                jr      z, dckid2
                call    dp_pics
                call    swapchar
dckid2:         jp      dp_pics

; HL = a character's new rectangle, his old one after it and his box after
; that.  Out: the box round the two, or whichever of them is not empty.

rect_box:       push    hl
                ld      de, 8
                add     hl, de
                ex      de, hl          ; DE = the box
                pop     hl              ; HL = new
                push    hl
                push    de
                inc     hl
                inc     hl
                ld      a, (hl)
                dec     hl
                dec     hl
                or      a
                ld      bc, 4
                jr      nz, rxcopy
                add     hl, bc          ; no new one: the old one
rxcopy:         ldir
                pop     de
                pop     hl
                ld      bc, 4
                add     hl, bc          ; HL = old
                inc     hl
                inc     hl
                ld      a, (hl)
                dec     hl
                dec     hl
                or      a
                ret     z

; HL = one rectangle, DE = another, which becomes the two together.  SPAN
; compares by difference, so either can hang off an edge.

union4:         push    de
                push    hl
                call    span            ; the columns
                pop     hl
                pop     de
                ld      (de), a
                inc     de
                inc     de
                ld      a, b
                ld      (de), a
                dec     de
                inc     hl
                push    de
                call    span            ; and the rows
                pop     de
                ld      (de), a
                inc     de
                inc     de
                ld      a, b
                ld      (de), a
                ret

; Put the foreground back over the character in hand.  The mask carries only
; the rows a front piece reaches -- foreband says which row of it a scanline
; is, or -1 -- and build_fore paints it one rectangle a piece, out of the
; front list.  So the list says where he and a piece can meet at all, and
; only there are his rows walked: walking every row of him found nothing on
; most of them, and with two of them fighting it was a sixth of the frame.

hide_behind:    ld      hl, foremask
                ld      (coverm), hl
                ld      hl, foreband
                ld      (coverb), hl
                ld      a, (neww)
                or      a
                ret     z
                ld      a, (nfront)
                or      a
                ret     z
                ld      hl, newcol
                ld      de, hbsave
                ld      bc, 4
                ldir
                ld      b, a
                ld      hl, frontlist
hbloop:         push    bc
                push    hl              ; the entry: byte column, bottom row,
                inc     hl              ; body x, body width, height
                ld      a, (hl)
                add     a, 64           ; the rows first, which throw out most
                ld      c, a
                inc     hl
                inc     hl
                inc     hl
                ld      b, (hl)
                sub     b
                inc     a
                ld      b, a
                ld      hl, hbsave + 1  ; his: all of it 64 up, so that above
                call    hbmeet          ; the top compares as less
                jr      c, hbnext
                ld      (hbrows), a
                ld      a, b
                ld      (hbtop), a
                pop     hl
                push    hl
                ld      a, (hl)         ; its byte column times seven, and
                inc     hl              ; the body on: in pixels
                inc     hl
                ld      c, (hl)
                inc     hl
                ld      b, (hl)
                push    bc
                ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, a
                add     hl, hl
                add     hl, hl
                add     hl, hl
                sbc     hl, de
                pop     bc
                ld      e, c
                add     hl, de
                push    hl
                ld      e, b            ; and where it ends
                add     hl, de
                dec     hl
                call    hbcol
                ld      c, a            ; C = its last column on the screen
                pop     hl
                call    hbcol
                ld      b, a            ; B = its first
                ld      hl, hbsave
                call    hbmeet
                jr      c, hbnext
                ld      (neww), a
                ld      a, b
                ld      (newcol), a
                ld      a, (hbrows)
                ld      (newh), a
                ld      a, (hbtop)
                ld      (newtop), a
                call    cover_rows
                ld      hl, hbsave
                ld      de, newcol
                ld      bc, 4
                ldir
hbnext:         pop     hl
                ld      de, 5
                add     hl, de
                pop     bc
                djnz    hbloop
                ret

; B..C, 64 up, against the run at HL -- its start, and two on its length.
; Out: carry when they do not meet; otherwise B = where they start, back
; down, and A = how many.

hbmeet:         ld      a, (hl)
                add     a, 64
                cp      b
                jr      c, hbm0
                ld      b, a
hbm0:           inc     hl
                inc     hl
                add     a, (hl)
                dec     a
                cp      c
                jr      nc, hbm1
                ld      c, a
hbm1:           ld      a, c
                sub     b
                ret     c
                inc     a
                ld      c, a
                ld      a, b
                sub     64
                ld      b, a
                ld      a, c
                ret

; HL = a room pixel.  Out: A = the screen column its byte is in, 64 up.

hbcol:          srl     h
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      a, (cam)
                ld      e, a
                ld      a, l
                sub     e
                add     a, 64
                ret

hbsave:         ds      4
hbrows:         db      0
hbtop:          db      0

; The floor and the front laid back over the guard, as over the kid.

hide_guard:     call    gd_swap
                ret     z
                call    page_art
                call    hide_floor
                call    hide_behind
                jp      swapchar

; ---------------------------------------------------------------- the rooms
;
; ADDGUARD and UPDATEGUARD in AUTO.S.  A room keeps its guard in the level's
; own INFO, in the background bank: which block he stands on, where, which way
; he faces, his program, and how far through a sequence he was.  Walking in
; brings him to life out of that; walking out writes him back into it.

GDINFO          equ     level + 2048 + 71
GDFACE          equ     24
GDX             equ     48
GDSEQL          equ     72
GDPROG          equ     96
GDSEQH          equ     120
NUMPROGS        equ     12

; HL = the byte of GdStart array DE for this room.

gd_field:       ld      a, (roomnum)
gd_field_in:    dec     a               ; A = the room
                ld      l, a
                ld      h, 0
                add     hl, de
                ld      de, GDINFO
                add     hl, de
                ret

add_guard:      ld      a, (gdkeep)     ; one who came along is already here
                or      a
                jr      z, agfresh
                xor     a
                ld      (gdkeep), a
                ld      hl, newcol + OP ; nothing of him drawn in this room
                ld      b, 12
agclr:          ld      (hl), a
                inc     hl
                djnz    agclr
                ret
agfresh:        xor     a
                ld      (gdhere), a
                ld      (offguard), a
                ld      a, (nowbank)
                push    af
                call    page_bg
                ld      de, 0
                call    gd_field
                ld      a, (hl)
                cp      30
                jp      nc, agnone
                push    af
                call    swapchar        ; he is made in Char, as POP makes him
                pop     af

                ld      b, 0            ; the block: ten to a row
agrow:          cp      10
                jr      c, agcol
                sub     10
                inc     b
                jr      agrow
agcol:          ld      a, b
                ld      (blocky), a
                ld      de, GDX
                call    gd_field
                ld      a, (hl)         ; CharX, 140 wide, to the room's pixels
                sub     SCRNLEFT
                ld      l, a
                ld      h, 0
                jr      nc, agx
                dec     h
agx:            add     hl, hl
                ld      (charx), hl
                ld      de, GDFACE
                call    gd_field
                ld      a, (hl)         ; -1 left, which is our 0
                inc     a
                jr      z, agface
                ld      a, 1
agface:         ld      (facing), a
                ld      de, GDPROG
                call    gd_field
                ld      a, (hl)
                cp      NUMPROGS
                jr      c, agprog
                ld      a, 3            ; the default
agprog:         ld      (guardprog), a
                ld      a, 2
                ld      (charid), a
                ld      de, GDSEQH
                call    gd_field
                ld      a, (hl)
                or      a
                jr      nz, agseq
                xor     a               ; 0 is a fresh start
                ld      (charsword), a
                call    page_canvas
                ld      a, SQ_ALERTSTAND
                call    jumpseq
                jr      aganim
agseq:          ld      d, a
                push    de
                ld      de, GDSEQL
                call    gd_field
                pop     de
                ld      e, (hl)
                ld      (seqptr), de
                call    page_canvas
aganim:         call    step_seq

                call    floor_plane
                ld      (chary), a
                xor     a
                ld      (yvel), a
                ld      hl, newcol      ; nothing of him drawn yet
                ld      b, 8
agrect:         ld      (hl), a
                inc     hl
                djnz    agrect
                inc     a
                ld      (charact), a
                ld      a, (frame)
                cp      185             ; killed
                jr      z, agdead
                cp      177             ; impaled
                jr      z, agdead
                cp      178             ; halved
                jr      z, agdead
                ld      a, 0xff
                ld      (charlife), a
                xor     a
                ld      (alertguard), a
                ld      (refract), a
                ld      (justblocked), a
                ld      hl, extrastrength
                call    gd_prog
                add     a, BASICSTR
                jr      agstr
agdead:         ld      a, 1
                ld      (charlife), a
                xor     a
agstr:          ld      (oppstr), a
                call    swapchar
                ld      a, 1
                ld      (gdhere), a
agnone:         pop     af
                jp      pageset

; Out: A = table HL's entry for his program.

gd_prog:        ld      a, (guardprog)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      a, (hl)
                ret

; UPDATEGUARD: leaving him behind.  A live guard starts over when the kid
; comes back; a dead one keeps the sequence that laid him down.

update_guard:   ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (nowbank)
                push    af
                call    page_bg
                ld      de, 0
                call    gd_field
                ld      a, (blocky + OP)
                add     a, a            ; ten to a row: ADDGUARD takes the
                ld      b, a            ; column from CharX
                add     a, a
                add     a, a
                add     a, b
                ld      (hl), a
                ld      de, GDX
                call    gd_field
                push    hl
                ld      hl, (charx + OP)
                sra     h
                rr      l
                ld      a, l
                add     a, SCRNLEFT
                pop     hl
                ld      (hl), a
                ld      de, GDFACE
                call    gd_field
                ld      a, (facing + OP)
                dec     a               ; our 0 left is POP's -1
                ld      (hl), a
                ld      de, GDPROG
                call    gd_field
                ld      a, (guardprog)
                ld      (hl), a
                ld      de, GDSEQH
                call    gd_field
                ld      a, (charlife + OP)
                or      a
                ld      a, 0
                jp      m, ugseq
                ld      a, (seqptr + OP + 1)
ugseq:          ld      (hl), a
                ld      de, GDSEQL
                call    gd_field
                ld      a, (seqptr + OP)
                ld      (hl), a
                pop     af
                call    pageset
                jp      gd_gone

; ---------------------------------------------------------------- a frame
;
; DOSHAD in TOPCTRL.S: the guard's turn, after the kid's.  Off the side of
; the screen he thinks but does not move.

do_shad:        call    gd_swap
                ret     z
                call    shadctrl
                call    step_seq        ; ANIMCHAR
                ld      hl, (charx)     ; CharX under ScrnLeft - 14, or at
                ld      de, 28          ; ScrnRight + 14 and over
                add     hl, de
                bit     7, h
                jr      nz, dsoff
                ld      de, -334
                add     hl, de
                bit     7, h
                jr      z, dsoff
                call    enemycoll
                call    check_floor
                call    do_fall
dsoff:          jp      swapchar

; SHADCTRL in CTRL.S: a guard whose strength has run out is dead, and a dead
; one still goes through GENCTRL, which lays him down.

shadctrl:       ld      a, (charlife)
                or      a
                jp      p, sccont
                ld      a, (oppstr)
                or      a
                jr      nz, sccont
                ld      (charlife), a
sccont:         call    autoctrl
                jp      ctrl

; CUTGUARD in AUTO.S: a guard fallen out of the bottom of the room is gone
; for good.

cutguard:       ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (chary + OP)
                cp      BOTCUT
                ret     c
                cp      TOPCUTMI        ; not wrapped round past the top
                ret     nc
                ld      a, (nowbank)
                push    af
                call    page_bg
                ld      de, 0
                call    gd_field
                ld      (hl), 0xff
                pop     af
                call    pageset
gd_gone:        xor     a
                ld      (gdhere), a
                ld      (oppstr), a
                ld      (neww + OP), a  ; rubbed out where he was, and no more
                ld      (oldw + OP), a
                ret

; ---------------------------------------------------------------- AUTO.S
;
; AUTOCTRL for a guard: he presses the keys, and GENCTRL takes them the way
; it takes the kid's.

autoctrl:       ld      hl, jstkx       ; DoRelease
                ld      b, 8
                xor     a
acrel:          ld      (hl), a
                inc     hl
                djnz    acrel
                ld      hl, justblocked
                call    dec_nz
                ld      hl, gdtimer
                call    dec_nz
                ld      hl, refract     ; the refractory period after a hit
                call    dec_nz

                ld      a, (charsword)  ; GuardProg: en garde already?
                cp      2
                jp      nc, ai_engarde

; Alert.  The kid behind him turns him round; seeing him, he draws.

                ld      a, (charlife + OP)
                or      a
                ret     p               ; the kid is dead: relax
                call    getopdist
                ld      c, a
                ld      a, (blocky + OP)
                ld      b, a
                ld      a, (blocky)
                cp      b
                ld      a, c
                jr      nz, aldiff
                cp      -8              ; right on top of him: en garde
                jr      nc, aleng
aldiff:         ld      hl, alertguard  ; otherwise a sound has to wake him
                ld      b, (hl)
                ld      (hl), 0
                inc     b
                dec     b
                jr      z, alok
                cp      128
                jr      c, aleng
                cp      -4
                jr      nc, alok        ; overlapping: stand still
                jp      pr_down         ; DoTurn
alok:           cp      128
                ret     nc              ; the kid is behind him
aleng:          ld      a, (enemyalert)
                or      a
                ret     z
                jp      pr_engarde

dec_nz:         ld      a, (hl)
                or      a
                ret     z
                dec     (hl)
                ret

STRIKETHRES1    equ     12
STRIKETHRES2    equ     29
BLOCKTHRES1     equ     10
BLOCKTHRES2     equ     29
TOOCLOSE        equ     12
TOOFAR          equ     35
OFFGUARDTHRES   equ     8
JUMPTHRES       equ     50
RUNTHRES        equ     40
BLOCKTIME       equ     4

; EnGarde.

ai_engarde:     ld      a, (frame)
                cp      166
                ret     z
                cp      150
                ret     c               ; wait till he is ready
                ld      a, (enemyalert)
                cp      2
                jr      nc, aiea2
                cp      1               ; in sight, but a gap or a barrier
                ret     z               ; between: stay put
                ld      a, (droppedout) ; out of sight: follow him down, or
                or      a               ; back to the alert
                jp      nz, followkid
                jp      pr_dropguard

aiea2:          call    getopdist       ; a stunned kid is let recover, unless
                bit     7, a            ; he is right on top of him
                jr      nz, ainorec
                cp      12
                jr      c, ainorec
                ld      a, (frame + OP)
                cp      102
                jr      c, ainorec
                cp      118
                jr      nc, ainorec
                ld      a, (charact + OP)
                cp      5
                ret     z
ainorec:        call    getopdist       ; to the closest safe distance
                cp      TOOFAR
                jr      nc, aiout
                ld      c, a
                ld      a, (charsword)
                cp      2
                ld      a, c
                jr      c, aioffg
                cp      TOOCLOSE
                jr      c, aiclose
                jp      inrange
aioffg:         cp      OFFGUARDTHRES
                jr      c, aiclose
                jp      inrange

aiout:          ld      a, (refract)
                or      a
                ret     nz
                ld      a, (facing + OP)
                ld      b, a
                ld      a, (facing)
                cp      b
                jr      z, ainojump     ; chase him
                ld      a, (frame + OP)
                cp      7
                jr      c, ainorun
                cp      15
                jr      c, airunwait
ainorun:        cp      34
                jr      c, ainojump
                cp      44
                jr      c, aijumpwait   ; running at him: stay put
ainojump:       call    front_flags     ; no advancing but on solid floor
                call    cmp_space
                jp      z, pr_back
                call    front2_flags
                call    cmp_space
                jp      nz, pr_fwd
                jp      pr_back

aijumpwait:     call    getopdist       ; trying to get past: cut him down
                cp      JUMPTHRES
                ret     nc
                jp      pr_strike
airunwait:      call    getopdist
                cp      RUNTHRES
                ret     nc
                jp      pr_strike

aiclose:        ld      a, (facing + OP) ; too close to hit him
                ld      b, a
                ld      a, (facing)
                cp      b
                jp      z, pr_back
                jp      pr_fwd

; FollowKid: the kid has dropped out of the fight.  Advance to the edge, and
; follow him down only a single storey onto solid floor, if he is still
; there.

followkid:      ld      a, (charact + OP)
                cp      2
                ret     z
                cp      6
                ret     z               ; hanging on the ledge: wait
                call    front_flags
                ld      (ztemp), a
                call    cmp_barr
                jr      nz, fkstop
                ld      a, (ztemp)
                call    cmp_space
                jp      nz, pr_fwd
                call    front_x         ; at the edge: what is under it?
                ld      a, (blocky)
                inc     a
                ld      c, a
                call    tile_in_row
                ld      (ztemp), a
                cp      BG_SPIKES
                jr      z, fkstop
                cp      BG_LOOSE
                jr      z, fkstop
                call    cmp_barr
                jr      nz, fkstop
                ld      a, (ztemp)
                call    cmp_space
                jr      z, fkstop
                ld      a, (blocky)
                inc     a
                ld      b, a
                ld      a, (blocky + OP)
                cp      b
                jp      z, pr_fwd
fkstop:         xor     a
                ld      (droppedout), a
                jp      pr_back         ; so he can kill him if he climbs up

; InRange.  An unarmed or unready kid is mauled; one en garde is fought.

inrange:        ld      a, (charsword + OP)
                cp      2
                jr      z, genfight
                ld      a, (refract)
                or      a
                ret     nz
                call    getopdist
                cp      STRIKETHRES2
                jp      nc, pr_fwd
                jp      pr_strike

; GenFight: face to face, en garde, and too close to advance safely.

genfight:       call    getopdist
                cp      BLOCKTHRES1
                jr      c, mayadvance
                cp      BLOCKTHRES2
                jr      nc, mayadvance
                call    maybeblock
                ld      a, (refract)
                or      a
                ret     nz
                call    getopdist
                cp      STRIKETHRES1
                jr      c, mayadvance
                cp      STRIKETHRES2
                jr      nc, mayadvance
                jr      maybestrike

mayadvance:     ld      a, (guardprog)  ; guard 0 is too dumb to wait
                or      a
                jr      z, madumb
                ld      a, (gdtimer)
                or      a
                ret     nz
madumb:         ld      hl, advprob
                call    chance
                ret     nc
                jp      pr_fwd

maybeblock:     ld      a, (frame + OP)
                cp      152             ; guy4
                jr      z, mb99
                cp      153             ; guy5
                jr      z, mb99
                cp      162             ; guy22, block to strike
                ret     nz
mb99:           ld      hl, blockprob
                ld      a, (justblocked)
                or      a
                jr      z, mbtry
                ld      hl, impblockprob
mbtry:          call    chance
                ret     nc
                jp      pr_up

maybestrike:    ld      a, (frame + OP)
                cp      169
                ret     z
                cp      151             ; starting to strike: don't
                ret     z
                ld      hl, strikeprob
                ld      a, (frame)
                cp      161             ; just blocked: restrike?
                jr      z, msre
                cp      150
                jr      nz, mstry
msre:           ld      hl, restrikeprob
mstry:          call    chance
                ret     nc
                jp      pr_strike

; RNDP: a throw against his program's entry in table HL.  Carry when it comes
; in under it.

chance:         call    gd_prog
                ld      c, a
                call    rnd
                cp      c
                ret

; What he presses.

pr_fwd:         ld      a, 0xff
                ld      (clrf), a
                ld      (jstkx), a
                ret
pr_back:        ld      a, 0xff
                ld      (clrb), a
                ld      a, 1
                ld      (jstkx), a
                ret
pr_up:          ld      a, 0xff
                ld      (clru), a
                ld      (jstky), a
                ret
pr_down:        ld      a, 0xff
                ld      (clrd), a
                ld      a, 1
                ld      (jstky), a
                ret
pr_dropguard:   ld      a, 0xff
                ld      (clrd), a
                jr      pr_back
pr_engarde:     ld      a, 0xff
                ld      (clrd), a
                jr      pr_fwd
pr_strike:      ld      a, 0xff
                ld      (clrbtn), a
                ld      (btn), a
                ret

; The tile a block or two ahead.

front_x:        call    base_x
                ld      de, BLOCK_PX
                ld      a, (facing)
                or      a
                jr      nz, fx1
                ld      de, -BLOCK_PX
fx1:            add     hl, de
                ret

front2_flags:   call    front_x
                add     hl, de
                jp      tile_flags

;               strike  0   1   2   3   4   5   6   7   8   9   10  11
strikeprob:     db      75, 100, 75, 75, 75, 50, 100, 220, 0, 60, 40, 60
restrikeprob:   db      0, 0, 0, 5, 5, 175, 20, 10, 0, 255, 255, 150
blockprob:      db      0, 150, 150, 200, 200, 255, 200, 250, 0, 255, 255, 255
impblockprob:   db      0, 75, 75, 100, 100, 145, 100, 250, 0, 145, 255, 175
advprob:        db      255, 200, 200, 200, 255, 255, 200, 0, 0, 255, 100, 100
refractimer:    db      20, 20, 20, 20, 10, 10, 10, 10, 0, 10, 0, 0

; ---------------------------------------------------------------- CTRL.S
;
; The fighting half of GENCTRL runs with the control code, and lives with it
; in the canvas bank.

mfix6:
                org     mpc5            ; into the canvas bank: see MODORG

; FightCtrl: en garde (CharSword 2), on level ground.

SWORDTHRES      equ     90
BLOCKTHRES      equ     32
GRACEPERIOD     equ     9
GDPATIENCE      equ     15

fight_ctrl:     ld      a, (charact)
                cp      2
                ret     nc
                call    under_flags     ; the alert over: sheathe -- unless he
                cp      BG_LOOSE        ; stands on a loose floor
                jr      z, fcskip
                ld      a, (enemyalert)
                cp      2
                jr      c, fcdropgd
fcskip:         call    getopdist       ; behind him: turn to face him
                cp      SWORDTHRES
                jr      c, fconalert
                cp      128
                jr      c, fcdropgd
                cp      -4
                jr      nc, fconalert   ; overlapping
                ld      a, SQ_TURNENGARDE
                jp      jumpseq

fcdropgd:       ld      a, (charid)     ; out of range: a guard stays en garde
                or      a
                jr      nz, fcd1
                ld      (heroic), a
                jr      fcd2
fcd1:           cp      2
                jr      nc, fconalert
fcd2:           ld      a, (frame)
                cp      171             ; wait for the ready position
                ret     nz
                xor     a
                ld      (charsword), a
                ld      a, SQ_RESHEATHE
                jp      jumpseq

fconalert:      ld      a, (frame)
                cp      161             ; a successful block: restrike or
                jr      nz, fcnobloc    ; retreat
                ld      a, (clrbtn)
                or      a
                jp      m, fcbts
                ld      a, SQ_RETREAT
                jp      jumpseq
fcnobloc:       ld      a, (clrbtn)     ; a fresh press strikes
                or      a
                jp      p, fcnostrike
fcbts:          ld      a, (charid)
                or      a
                jr      nz, fc11
                ld      a, GDPATIENCE
                ld      (gdtimer), a
fc11:           call    do_strike
                ld      a, (clrbtn)
                cp      1
                ret     z               ; struck
fcnostrike:     ld      a, (clrd)       ; down lowers the sword
                or      a
                jp      p, fcnodrop
                ld      a, (frame)
                cp      158
                jr      z, fcready
                cp      170
                jr      z, fcready
                cp      171
                ret     nz
fcready:        ld      a, 1
                ld      (clrd), a
                xor     a
                ld      (charsword), a
                ld      a, (charid)
                or      a
                jr      z, fcdrop
                ld      a, SQ_GOALERTSTAND
                jp      jumpseq
fcdrop:         ld      a, 1
                ld      (offguard), a
                ld      a, GRACEPERIOD
                ld      (refract), a
                xor     a
                ld      (heroic), a
                ld      a, SQ_FASTSHEATHE
                jp      jumpseq

fcnodrop:       ld      a, (clru)       ; up blocks, forward advances, back
                or      a               ; retreats
                jp      m, do_block
                ld      a, (clrf)
                or      a
                jp      m, do_advance
                ld      a, (clrb)
                or      a
                jp      m, do_retreat
                ret

; DoBlock.

do_block:       ld      a, (frame)
                cp      158             ; ready
                jr      z, dbready
                cp      170
                jr      z, dbready
                cp      171
                jr      z, dbready
                cp      168             ; guy-2
                jr      z, dbready
                cp      165             ; advance
                jr      z, dbready
                cp      167             ; blocked strike
                ret     nz
                ld      a, SQ_STRIKEBLOCK
                jr      dbdoit
dbready:        call    getopdist
                cp      BLOCKTHRES
                jr      nc, dbmiss      ; too far
                ld      a, (charid)
                or      a
                jr      z, dbkid
                ld      a, (frame + OP) ; the guard sees the kid a frame ahead
                cp      152
                ret     nz
                jr      dbdo
dbkid:          ld      a, (frame + OP)
                cp      168             ; a frame too early: wait one
                ret     z
                cp      151
                jr      z, dbdo
                cp      152
                jr      z, dbdo
                cp      162
                jr      z, dbdo
                cp      153             ; a frame too late: skip one
                jr      nz, dbmiss
                call    dbdo
                jp      step_seq
dbmiss:         ld      a, (charid)
                or      a
                jp      nz, do_retreat  ; a guard does not waste a block
dbdo:        ld      a, SQ_READYBLOCK
dbdoit:         push    af
                ld      a, 1
                ld      (clru), a
                pop     af
                jp      jumpseq

; DoStrike, from the ready position, an advance, or a block.

do_strike:      ld      a, (frame)
                cp      157
                jr      z, dsready
                cp      158
                jr      z, dsready
                cp      170
                jr      z, dsready
                cp      171
                jr      z, dsready
                cp      165
                jr      z, dsready
                cp      150             ; from a missed block
                jr      z, dsblock
                cp      161             ; or a good one
                ret     nz
dsblock:        ld      a, SQ_BLOCKTOSTRIKE
                jr      dsdo
dsready:        ld      a, (charid)     ; the kid is fast, the rest slow
                or      a
                ld      a, SQ_FASTSTRIKE
                jr      z, dsdo
                ld      a, SQ_STRIKE
dsdo:           push    af
                ld      a, 1
                ld      (clrbtn), a
                pop     af
                jp      jumpseq

do_retreat:     call    is_ready
                ret     nz
                ld      a, 1
                ld      (clrb), a
                ld      a, SQ_RETREAT
                jp      jumpseq

do_advance:     call    is_ready
                ret     nz
                ld      a, 1
                ld      (clrf), a
                ld      a, (charid)
                or      a
                ld      a, SQ_FASTADVANCE
                jp      z, jumpseq
                ld      a, SQ_ADVANCE
                jp      jumpseq

; Z on one of the three ready frames.

is_ready:       ld      a, (frame)
                cp      158
                ret     z
                cp      170
                ret     z
                cp      171
                ret

; GuardCtrl: standing alert, down and forward draws, down alone turns.

guard_ctrl:     ld      a, (frame)
                cp      166
                ret     nz
                ld      a, (clrd)
                or      a
                ret     p
                ld      a, (clrf)
                or      a
                jp      m, do_engarde
                ld      a, 1
                ld      (clrd), a
                ld      a, SQ_ALERTTURN
                jp      jumpseq

; DoEngarde.

do_engarde:     call    clrall
                ld      (clrf), a
                ld      (clrbtn), a
                ld      a, 2
                ld      (charsword), a
                ld      a, (charid)
                or      a
                ld      a, SQ_GUARDENGARDE
                jp      nz, jumpseq
                xor     a
                ld      (offguard), a
                ld      a, SQ_ENGARDE
                jp      jumpseq

; The kid, standing, with the sword: an enemy within range and he goes en
; garde, or turns to face one behind him.  Put away with a press of down, it
; comes out again with the button.  Out: NZ when he has done something and
; standing is over, Z to go on with it.

kid_engarde:    ld      a, (gotsword)
                or      a
                ret     z
                ld      a, (offguard)
                or      a
                jr      z, kenotoffg
                ld      a, (btn)        ; off guard: the button draws it
                or      a
                ret     z
kenotoffg:      ld      a, (enemyalert)
                cp      2
                jr      c, kesafe
                call    getopdist
                cp      -10             ; swordthresN: behind him
                jr      nc, kedanger
                cp      SWORDTHRES
                jr      nc, kesafe
kedanger:       ld      b, a
                ld      a, 1
                ld      (heroic), a
                ld      a, b
                cp      -6
                jr      nc, kebehind
                call    do_engarde
                or      1
                ret
kebehind:       call    do_turn
                or      1
                ret
kesafe:         xor     a
                ld      (offguard), a
                ret

; DoTurn: with an enemy behind him and room to do it, he draws as he turns.
; Out: A = the sequence.

turnseq:        ld      a, (gotsword)
                or      a
                jr      z, tsturn
                ld      a, (enemyalert)
                cp      2
                jr      c, tsturn
                call    getopdist
                or      a
                jp      p, tsturn
                call    get_dist        ; to the end of his block
                cp      2
                jr      c, tsturn
                ld      a, 2
                ld      (charsword), a
                xor     a
                ld      (offguard), a
                ld      a, SQ_TURNDRAW
                ret
tsturn:         ld      a, SQ_TURN
                ret

; STARTFALL from a fighting stance.  POP picks the guard's fall by which way
; CharXVel carries him, and nothing here gives him one: forward.

fightfall_seq:  ld      a, (charid)
                cp      2
                jr      c, ffkid
                xor     a
                ld      (droppedout), a
                ld      a, SQ_EFIGHTFALLFWD
                ret
ffkid:          ld      a, 1
                ld      (droppedout), a ; for the guard's benefit
                ld      a, SQ_FIGHTFALL
                ret

; FIRSTGUARD in MISC.S: the kid cannot run or jump past a guard en garde.

firstguard:     ld      a, (enemyalert)
                cp      2
                ret     c
                ld      a, (charsword)
                or      a
                ret     nz
                ld      a, (charsword + OP)
                or      a
                ret     z
                ld      a, (charact + OP)
                cp      2
                ret     nc
                ld      a, (facing + OP)
                ld      b, a
                ld      a, (facing)
                cp      b
                ret     z
                call    getopdist
                cp      -15
                ret     c
                call    floor_plane     ; bump off him
                ld      (chary), a
                ld      a, SQ_BUMP
                call    jumpseq
                jp      step_seq

mpc6:
                org     mfix6

; ---------------------------------------------------------------- the blade
;
; CHECKSTRIKE in AUTO.S, with both of them where the coming frame puts them.

checkstrike:    ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (frame)
                or      a
                ret     z
                cp      219
                jr      c, csclimb
                cp      229
                ret     c               ; on the staircase
csclimb:        call    swapchar
                call    teststrike
                call    swapchar

; TestStrike: on a strike frame and in range, the other is blocking or is
; run through -- which is only marked here, as Action 99, for CHECKSTAB.

teststrike:     ld      a, (charsword)
                cp      2
                ret     nz
                ld      a, (blocky + OP)
                ld      b, a
                ld      a, (blocky)
                cp      b
                ret     nz
                ld      a, (frame)
                cp      153             ; guy5, the frame before full extension
                jr      z, tstest
                cp      154             ; guy6, full extension
                ret     nz
tstest:         call    getopdist
                cp      BLOCKTHRES2
                jr      nc, tsnobloc
                ld      a, (frame + OP)
                cp      161
                jr      z, tsbloc
                cp      150             ; blocking?
                jr      nz, tsnobloc
                ld      a, 161          ; yes: a successful block
                ld      (frame + OP), a
tsbloc:         ld      a, (charid)
                or      a
                jr      z, tsblocked
                ld      a, BLOCKTIME    ; a guard blocked blocks worse a while
                ld      (justblocked), a
tsblocked:      ld      a, SQ_BLOCKEDSTRIKE
                call    jumpseq
                jp      step_seq

tsnobloc:       ld      a, (frame)      ; skewer him?
                cp      154
                ret     nz
                call    getopdist
                ld      c, a
                ld      a, (charsword + OP)
                cp      2
                ld      a, c
                jr      nc, tsong
                cp      OFFGUARDTHRES
                jr      nc, tscont
                ret
tsong:          cp      STRIKETHRES1
                ret     c
tscont:         cp      STRIKETHRES2
                ret     nc
                ld      a, 99           ; stabbed
                ld      (charact + OP), a
                ret

; CHECKSTAB: whoever was run through takes it; both at once, the kid wins.

checkstab:      ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (charact + OP)
                cp      99
                jr      nz, cskid
                ld      a, (charact)
                cp      99
                jr      nz, csguard
                ld      a, 1
                ld      (charact), a
csguard:        call    swapchar
                call    stabchar
                call    swapchar
                ld      hl, refractimer
                call    gd_prog
                ld      (refract), a
cskid:          ld      a, (charact)
                cp      99
                ret     nz

; STABCHAR in MISC.S.  En garde it costs a point, and the last one kills him;
; caught defenceless he dies outright.  Killed at an edge, he goes over it.

stabchar:       ld      a, (charlife)
                or      a
                ret     p               ; already dead
                ld      a, (charsword)
                cp      2
                jr      nz, scdefenceless
                ld      a, 1
                call    decstr
                jr      nz, scwounded
sckilled:       call    behind_flags
                call    cmp_space
                jr      nz, sconground
                call    get_dist        ; to the end of the block
                cp      4
                jr      c, sconground
                sub     14
                call    move_by
                ld      hl, blocky
                inc     (hl)
                ld      a, SQ_FIGHTFALL
                call    jumpseq
                jp      step_seq
sconground:     ld      a, SQ_STABKILL
                jr      scseq
scwounded:      ld      a, SQ_STABBED
scseq:          call    jumpseq
                call    floor_plane
                ld      (chary), a
                xor     a
                ld      (yvel), a
                jp      step_seq
scdefenceless:  ld      a, 100
                call    decstr
                jr      sckilled

; CHECKALERT in MISC.S.  2: the two of them on the same stretch of floor; 1:
; in sight across a gap, a loose floor, a slicer or a closed gate; 0: they
; cannot see each other.

GFIGHTTHRES     equ     28 * 4

checkalert:     xor     a
                ld      (enemyalert), a
                ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (frame)
                or      a
                ret     z
                cp      219
                jr      c, canoclimb
                cp      229
                ret     c               ; on the staircase
canoclimb:      ld      a, (charlife + OP)
                ld      b, a
                ld      a, (charlife)
                and     b
                ret     p               ; one of them is dead
                ld      a, (blocky + OP)
                ld      b, a
                ld      a, (blocky)
                cp      b
                ret     nz
                ld      a, 2
                ld      (enemyalert), a

                ld      hl, (charx)     ; the blocks between them, left to right
                call    blockcol_of
                ld      c, a
                push    bc
                ld      hl, (charx + OP)
                call    blockcol_of
                pop     bc
                ld      b, a
                sub     c
                jp      p, caorder
                ld      a, b
                ld      b, c
                ld      c, a
caorder:        ld      a, c
                ld      (cacount), a
                ld      a, b
                ld      (caend), a
                ld      a, (cacount)    ; a slicer at the left is left out
                call    ca_read
                cp      BG_SLICER
                jr      nz, ca1
                ld      hl, cacount
                inc     (hl)
ca1:            ld      a, (caend)      ; and a gate at the right
                call    ca_read
                cp      BG_GATE
                jr      nz, ca20
                ld      hl, caend
                dec     (hl)
ca20:           ld      a, (caend)
                ld      b, a
                ld      a, (cacount)
                sub     b
                jr      z, caloop
                ret     p
caloop:         ld      a, (cacount)
                call    ca_read
                cp      BG_BLOCK        ; solid: they cannot see each other
                jr      z, casafe
                cp      BG_PANELWIF
                jr      z, casafe
                cp      BG_PANELWOF
                jr      z, casafe
                cp      BG_LOOSE
                jr      z, caview
                cp      BG_GATE
                jr      nz, ca2
                ld      a, (tilestate)
                cp      GFIGHTTHRES
                jr      nc, caclear
                jr      caview
ca2:            cp      BG_SLICER
                jr      z, caview
                call    cmp_space
                jr      nz, caclear
caview:         ld      a, 1
                ld      (enemyalert), a
caclear:        ld      a, (caend)
                ld      hl, cacount
                cp      (hl)
                ret     z
                inc     (hl)
                jr      caloop
casafe:         xor     a
                ld      (enemyalert), a
                ret

ca_read:        ld      b, a
                ld      a, (blocky)
                ld      c, a
                ld      a, b
                jp      tile_at

; CUTCHECK in AUTO.S: the kid is going into room A the way C says -- 0 up,
; 1 down, 2 left, 3 right.  A live guard en garde close to that side goes
; with him, unless a live guard is waiting in the new room; anyone else is
; left behind and written back into his own.

leave_room:     ld      (lrroom), a
                ld      a, c
                ld      (lrdir), a
                ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (charlife + OP)
                or      a
                jp      p, update_guard ; dead: left behind
                ld      a, (charsword + OP)
                cp      2
                jp      nz, update_guard
                ld      a, (nowbank)
                push    af
                call    page_bg
                ld      a, (lrroom)     ; a live guard there already?
                ld      de, 0
                call    gd_field_in
                ld      a, (hl)
                cp      30
                jr      nc, lrnonew
                ld      a, (lrroom)
                ld      de, GDSEQH
                call    gd_field_in
                ld      a, (hl)
                or      a
                jp      z, lrleave
lrnonew:        ld      a, (lrdir)
                or      a
                jr      z, lrup
                dec     a
                jr      z, lrdown
                dec     a
                jr      z, lrleft
                ld      hl, (charx + OP) ; right: ShadX past ScrnWidth + 25
                ld      de, -2 * (140 + 25 - SCRNLEFT)
                add     hl, de
                bit     7, h
                jp      nz, lrleave
                ld      de, -280
                jr      lrsideways
lrleft:         ld      hl, (charx + OP) ; left: ShadX under 256 - ScrnWidth - 25
                ld      de, -2 * (256 - 140 - 25 - SCRNLEFT)
                add     hl, de
                bit     7, h
                jp      z, lrleave
                ld      de, 280
lrsideways:     ld      hl, (charx + OP)
                add     hl, de
                ld      (charx + OP), hl
                jr      lrtake
lrup:           ld      a, (blocky + OP)
                or      a
                jp      p, lrleave
                add     a, 3
                ld      (blocky + OP), a
                ld      a, (chary + OP)
                add     a, 189
                jr      lrvert
lrdown:         ld      a, (blocky + OP)
                cp      3
                jr      c, lrleave
                sub     3
                ld      (blocky + OP), a
                ld      a, (chary + OP)
                sub     189
lrvert:         ld      (chary + OP), a
lrtake:         ld      de, 0           ; TRANSFERGUARD: out of both rooms'
                call    gd_field        ; lists, and along with the kid
                ld      (hl), 0xff
                ld      a, (lrroom)
                ld      de, 0
                call    gd_field_in
                ld      (hl), 0xff
                ld      a, 1
                ld      (gdkeep), a
                pop     af
                jp      pageset
lrleave:        pop     af
                call    pageset
                jp      update_guard

lrroom:         db      0
lrdir:          db      0
gdkeep:         db      0

; ENEMYCOLL in COLL.S: a guard en garde backing into a wall or a closed gate
; is put at its edge, and bumps back en garde.

enemycoll:      ld      a, (charact)
                cp      1
                ret     nz              ; on the ground
                ld      a, (charlife)
                or      a
                ret     p               ; alive
                ld      a, (charsword)
                cp      2
                ret     c               ; en garde
                call    base_x          ; GETUNDERFT
                call    blockcol_of
                ld      (ecx), a
                call    ec_read
                cp      BG_BLOCK
                jr      z, eccollide
                cp      BG_PANELWIF
                jr      z, eccollide
                cp      BG_GATE
                jr      nz, ecbehind
                call    gatebarr
                jr      c, eccollide
ecbehind:       ld      a, (facing)     ; facing right, the block behind too
                or      a
                ret     z
                ld      hl, ecx
                dec     (hl)
                call    ec_read
                cp      BG_PANELWIF
                jr      z, eccollide
                cp      BG_GATE
                ret     nz
                call    gatebarr
                ret     nc
eccollide:      call    cd_edges        ; SETUPCHAR and GETEDGES
                ld      a, (ecx)
                call    edge140
                ld      (cbedge), a
                call    ec_read
                ld      c, a
                cp      BG_GATE         ; CHECKCOLL: a gate only while it bars
                jr      nz, ecbarr
                call    gatebarr
                ret     nc
ecbarr:         ld      a, c
                call    cmp_barr
                ret     z
                ld      (cccode), a
                ld      a, (facing)     ; DBarr2: the barrier behind him
                or      a
                jr      nz, ecright
                call    leftbar         ; facing left, it is to his right
                ld      hl, cdright
                sub     (hl)
                jr      ecdist
ecright:        call    rightbar        ; facing right, to his left
                ld      c, a
                ld      a, (cdleft)
                sub     c
ecdist:         or      a
                ret     p
                neg
                call    move_by
                ld      a, SQ_BUMPENGBACK
                call    jumpseq
                jp      step_seq

ec_read:        ld      a, (blocky)
                ld      c, a
                ld      a, (ecx)
                jp      tile_at

ecx:            db      0

; ---------------------------------------------------------------- meters
;
; UPDATEMETERS in GAMEBG.S: the kid's strength at the bottom left, a bullet a
; point up to his most, and his opponent's at the bottom right, mirrored.  The
; last one flashes.  They go straight onto the screen that is shown, after
; everything else has gone to it this frame, the way POP adds them last: the
; working copy never has them, so nothing that is put back from it can leave
; one behind.  A bullet is eight pixels on from the one before, as KidStrX
; and KidStrOFF place them, which on a Spectrum is a byte each.

METERY          equ     188             ; YCO 191, four rows up
MAXKIDMETER     equ     3               ; MaxKidStr: initmaxstr in TOPCTRL.S
MAXOPPMETER     equ     4               ; the most a guard of this level has

show_meters:    call    page_canvas     ; bank 7, in case it is the one shown
                ld      hl, mflash      ; PAGE, which POP flips every frame
                inc     (hl)
                ld      hl, bullet
                ld      a, (kidstr)
                ld      c, a
                ld      b, MAXKIDMETER
                ld      de, 0x0100      ; from the left, a byte on each time
                call    meter
                ld      a, (gdhere)
                or      a
                jr      z, smgone
                ld      a, (oppstr)
                or      a
                jr      z, smgone
                ld      c, a
                ld      a, 1
                ld      (oppshown), a
                ld      hl, bullet + 4
                ld      b, MAXOPPMETER
                ld      de, 0xff1f      ; from the right, a byte back each time
                jr      meter

smgone:         ld      a, (oppshown)   ; the room back where it was, once
                or      a
                ret     z
                xor     a
                ld      (oppshown), a
                ld      a, METERY
smrest:         push    af
                ld      e, 32 - MAXOPPMETER
                call    scraddr
                push    hl
                ld      de, work - SCREEN
                add     hl, de
                pop     de
                ld      a, (scrsel + 1)
                or      d
                ld      d, a
                ld      bc, MAXOPPMETER
                ldir
                pop     af
                inc     a
                cp      METERY + 4
                jr      c, smrest
                ret

; HL = the bullet's four rows, B = how many places, C = how many are lit,
; E = the first column and D the step to the next.

meter:          ld      (mtimg), hl
                ld      (mtfirst), de
                ld      a, b
                ld      (mtslots), a
                ld      a, c
                cp      1
                jr      nz, mtlitn
                ld      a, (mflash)     ; down to one: it flashes
                rra
                jr      nc, mtlitn
                ld      c, 0
mtlitn:          ld      a, METERY
mtline:          push    af
                ld      de, (mtfirst)
                call    scraddr
                ld      a, (scrsel + 1)
                or      h
                ld      h, a
                ld      de, (mtimg)
                ld      a, (de)
                ld      d, a            ; D = this row of a bullet
                ld      a, (mtslots)
                ld      b, a
                ld      e, c
mtplace:         xor     a               ; lit, or black
                inc     e
                dec     e
                jr      z, mtlay
                dec     e
                ld      a, d
mtlay:          ld      (hl), a
                ld      a, (mtstep)
                add     a, l
                ld      l, a
                djnz    mtplace
                ld      hl, (mtimg)
                inc     hl
                ld      (mtimg), hl
                pop     af
                inc     a
                cp      METERY + 4
                jr      c, mtline
                ret

mtimg:          dw      0
mtfirst:          db      0
mtstep:         db      0
mtslots:        db      0
mflash:         db      0
oppshown:       db      0
bullet:         incbin  "bullet.bin"

; ---------------------------------------------------------------- state

gdhere:         db      0               ; a guard in this room: ShadFace <> 86
guardprog:      db      0
oppstr:         db      0               ; OppStrength
enemyalert:     db      0               ; EnemyAlert
alertguard:     db      0
refract:        db      0
justblocked:    db      0
gdtimer:        db      0
offguard:       db      0
droppedout:     db      0
heroic:         db      0
ztemp:          db      0
cacount:        db      0               ; CHECKALERT's ]Xcount and ]Xend, as
caend:          db      0               ; block columns

BASICSTR        equ     3               ; basicstrength for level 1

extrastrength:  db      0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0
