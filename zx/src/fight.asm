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
                call    rect_still
                ld      hl, boxcol + OP
                call    eraseset
                ld      hl, boxcol
                call    eraseset
                ld      hl, mbold       ; and where the floors fell from
                call    eraseset
                ld      hl, mbold + 4
                call    eraseset
                call    draw_flames
                call    draw_mobs       ; behind the two of them
                call    gd_swap
                jr      z, dckid2
                call    gd_pics
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
hbloop:         call    hbseek          ; the next piece whose rows meet his
                ret     z
                push    bc
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
                dec     b
                jr      hbloop

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

; Out: A = table HL's entry for his program.

gd_prog:        ld      a, (guardprog)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      a, (hl)
                ret

; ---------------------------------------------------------------- a frame
;
; DOSHAD in TOPCTRL.S: the guard's turn, after the kid's.  Off the side of
; the screen he thinks but does not move.

do_shad:        call    gd_swap
                ret     z
                ld      hl, jstkx       ; LoadDesel and SaveDesel: the keys
                ld      de, kidkeys     ; and their fresh presses are the
                ld      bc, 8           ; kid's, while the guard's are his own
                ldir
                call    shadctrl        ; SHADCTRL in CTRL.S
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
                call    checkpress      ; a loose floor gives way under him
                call    page_canvas     ; too; and it pages the blueprint in
                call    checkspikes
                call    checkimpale

; And only now are the kid's keys put back -- after everything that reads
; them, not straight after shadctrl.  fall_on takes the button from btn, and
; with the kid's there a held button made a falling guard reach for a ledge
; and hang on it.  POP leaves the guard's keys in place for the whole of
; DoShad and only two-player control ever swaps them (LoadDesel).  They may
; not be left in them past the end of the frame, though: the kid walked off
; on the guard's back press, and a dead guard's release made a held key new
; every frame.

dsoff:          ld      hl, kidkeys
                ld      de, jstkx
                ld      bc, 8
                ldir
                jp      swapchar

; SHADCTRL in CTRL.S: a guard whose strength has run out is dead, and a dead
; one still goes through GENCTRL, which lays him down.

shadctrl:       ld      a, (charlife)
                or      a
                jp      p, sccont
                ld      a, (oppstr)
                or      a
                jr      nz, sccont
                ld      (charlife), a
                ld      a, SONG_VICT    ; DEADENEMY
                ld      c, 25
                call    cue_song
sccont:         call    autoctrl
                jp      ctrl

; The skeleton's own room and the one it lands in, from BONESRISE in MISC.S
; and CUTGUARD in AUTO.S: the bones lie in screen one, block five of the
; second row, and it falls from there into screen three.

SKELSCRN        equ     1
SKELX           equ     5
SKELY           equ     1
SKELTRIG        equ     2
SKELPROG        equ     2
SKELLAND        equ     3
SKELLANDX       equ     0x85            ; ShadX where it lands
SKELLANDBLK     equ     10              ; and its block, as indexblock has it

; CUTGUARD in AUTO.S: a guard fallen out of the bottom of the room is gone
; for good -- except the skeleton, which picks itself up in the room below.

cutguard:       ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (chary + OP) ; CUTGUARD asks this and nothing
                cp      BOTCUT          ; else: ShadY at BotCutEdge or past
                ret     c               ; it.  There was an upper bound here
                                        ; as well, which a fall steps clean
                                        ; over -- it gathers up to TERM_VEL a
                                        ; frame, and the row under the screen
                                        ; has its floor plane at 244, inside
                                        ; the window that was thrown out
                ld      a, (charid + OP)        ; a skeleton that falls into
                cp      4                       ; the room it belongs in gets
                jr      nz, gd_off              ; up again there
                ld      a, (links + 3)
                cp      SKELLAND
                jp      z, skel_down
gd_off:         ld      a, (nowbank)
                push    af
                call    page_bg
                ld      de, 0
                call    gd_field
                ld      (hl), 0xff
                pop     af
                call    pageset
; His old rectangle is left standing.  draw_chars rubs out the box round the
; new one and the old, and with no new one that box is the old alone -- his
; last picture, which cutguard drops him on the frame he falls off the foot
; of the screen.  Clearing it here left that picture lying along the bottom
; until the view next moved.  keep_rect copies the empty new one over it at
; the top of the next frame, so it costs nothing after that one frame.

gd_gone:        xor     a
                ld      (gdhere), a
                ld      (oppstr), a
                ld      (neww + OP), a
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

                ld      a, (charid)     ; SkelProg: the skeleton is always
                cp      4               ; en garde
                jr      nz, acsword
                ld      a, 2
                ld      (charsword), a
acsword:        ld      a, (charsword)  ; GuardProg: en garde already?
                cp      2
                jr      nc, ai_engarde

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
                jr      pr_fwd

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
                jr      pr_up

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
                jr      pr_strike

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
                jr      nz, do_retreat  ; a guard does not waste a block
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
; CharXVel carries him -- and the fighting sequences set it: stabbed, strike
; and retreat -1, advance +1.  A skeleton struck back over the edge goes with
; efightfall, back and clear of it; efightfallfwd carried him forward on to
; the post under the ledge, where he stood instead of dropping to the screen
; below.

fightfall_seq:  ld      a, (charid)
                cp      2
                sbc     a, a            ; the kid drops out, for the guard's
                ld      (droppedout), a ; benefit -- only ever asked if nought
                ld      a, SQ_FIGHTFALL
                ret     nz
                ld      a, (xvel)
                rlca
                ld      a, SQ_EFIGHTFALLFWD
                ret     nc
                ld      a, SQ_EFIGHTFALL
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

; flashon and flashoff in TOPCTRL.S: the frame in which he has been hurt --
; ChgKidStr negative -- goes to the screen red all over, and the one after it
; is itself again.  The border goes red with it.  In the control module,
; so with the canvas bank in, which is where the shown screen may be.

INK_HURT        equ     0x12            ; red on red

hurt_flash:     ld      hl, hurton
                ld      a, (hl)
                or      a
                jr      z, hfcheck
                ld      (hl), 0
                call    shown_attrs
hfcheck:        ld      a, (kidstr)
                ld      hl, lastkidstr
                cp      (hl)
                ld      (hl), a
                ret     nc
                ld      a, 1
                ld      (hurton), a
                ld      (lightning), a
                ld      a, 2
                ld      (lightcolor), a
                ld      a, (scrsel + 1)
                or      0x58
                ld      h, a
                ld      l, 0
                ld      d, h
                ld      e, 1
                ld      bc, 767
                ld      (hl), INK_HURT
                ldir
                ret

hurton:         db      0
lastkidstr:     db      0

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
                ld      a, SND_STABBED  ; the CPC's sound of a blade going in
                call    addsound
                ld      a, (charsword)
                cp      2
                jr      nz, scdefenceless
                ld      a, (charid)     ; the skeleton has no life points
                cp      4
                jr      z, scwounded
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
kidkeys:        ds      8

; ---------------------------------------------------------------- the exit
;
; Standing, up, in CTRL.S: the exit under him, behind him or in front of him
; -- the first of those that is one -- and its door raised past stairthres,
; and he climbs the stairs instead of jumping.  Stairs puts him ten units
; into the exit's block, facing left.  Out: NZ when he does.

STAIRTHRES      equ     30

stairs_up:      call    base_x
                call    blockcol_of
                ld      c, a            ; under him
                ld      a, (facing)
                or      a
                ld      b, 1
                jr      nz, stdir
                ld      b, -1
stdir:          ld      a, c
                call    st_exit
                jr      z, stfound
                ld      a, c            ; behind
                sub     b
                call    st_exit
                jr      z, stfound
                ld      a, c            ; in front
                add     a, b
                call    st_exit
                jr      z, stfound
stno:           xor     a
                ret
stfound:        ld      a, (tilestate)  ; the door far enough up?
                rrca
                rrca
                and     0x3f
                cp      STAIRTHRES
                jr      c, stno
                ld      a, (stcol)
                ld      l, a            ; BlockEdge + 10: 28 pixels a column
                ld      h, 0            ; and 20 on
                add     hl, hl
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                sbc     hl, de
                ld      de, 20
                add     hl, de
                ld      (charx), hl
                xor     a
                ld      (facing), a
                ld      a, (blocky)
                ld      (strow), a
                ld      a, SQ_CLIMBSTAIRS
                call    jumpseq
                or      1
                ret

; A = a column of his row.  Z when the exit is in it; B and C kept.

st_exit:        ld      (stcol), a
                push    bc
                ld      a, (blocky)
                ld      c, a
                ld      a, (stcol)
                call    tile_at
                pop     bc
                cp      BG_EXIT
                ret

; CROPCHAR: from frame 224 on he goes in under the door, and nothing of him
; shows above two rows below its bottom edge -- doortop, as drawexitb works
; it out: Ay less fourteen, less the door's height.

stairs_crop:    ld      a, (strow)
                ld      c, a
                ld      a, (stcol)
                call    tile_at
                ld      a, (strow)
                inc     a
                ld      e, a
                ld      d, 0
                ld      hl, blockbot
                add     hl, de
                ld      a, (tilestate)
                rrca
                rrca
                and     0x3f
                ld      c, a
                ld      a, (hl)
                sub     3 + 14 - 2      ; Ay - 14, and the two
                sub     c
                ld      (charcu), a
                ret

stcol:          db      0
strow:          db      0

; :drop in CTRL.S.  Open behind him and nothing underfoot, he falls; else he
; drops the half storey, first pushed seven back off a wall he hangs against.

hang_release:   call    clrall
                ld      (clrd), a
                call    behind_flags
                call    cmp_space
                jr      nz, hdrop
                call    under_flags
                call    cmp_space
                ld      a, SQ_HANGFALL
                jp      z, jumpseq
hdrop:          call    under_flags
                cp      BLK_BLOCK
                jr      z, hsheer
                ld      b, a
                ld      a, (facing)     ; facing right: clear
                or      a
                jr      nz, hclear
                ld      a, b
                cp      BG_PANELWOF
                jr      z, hsheer
                cp      BG_PANELWIF
                jr      nz, hclear
hsheer:         ld      a, -7
                call    move_by
hclear:         ld      a, SQ_HANGDROP
                jp      jumpseq

; sl_sync's flip, which has to be out here as the room is in a bank of its
; own: DE = the tile's first room byte, imgbuf the bits to flip, SLROWS rows
; of four.  And the block shown straight after, which redshow takes from the
; room -- (blockcol), (dy) and (redh) are set for it.

slxor:          call    page_art
                ld      hl, imgbuf
                ld      b, SLROWS
slx1:           rept    3
                ld      a, (de)
                xor     (hl)
                ld      (de), a
                inc     hl
                inc     de
                endm
                ld      a, (de)
                xor     (hl)
                ld      (de), a
                inc     hl
                ld      a, e
                add     a, ROOM_BYTES - 3
                ld      e, a
                jr      nc, slx3
                inc     d
slx3:           djnz    slx1
                jp      redshow

; ---------------------------------------------------------------- sound
;
; The sounds are the CPC release's: its twenty effects -- tunes among them --
; and its driver, ported from the game at &B15D, one fiftieth of a second to
; a tick.  One plays at a time; a new one takes over unless it matters less
; than the one playing, which is how a footstep never breaks into a tune.
; cpcsound.py has the data and its commands.

SONG_ACCID      equ     1               ; SOUNDNAMES.S
SONG_HEROIC     equ     2
SONG_DANGER     equ     3
SONG_SWORD      equ     4
SONG_VICT       equ     7
SONG_STAIRS     equ     8
SONG_UPSTAIRS   equ     9
SONG_POTION     equ     11
SONG_SHORTPOT   equ     12

; ADDSOUND: A = one of POP's sounds.  CUESONG: A = one of its tunes (C, the
; frames POP would let it wait for a still moment, is not wanted).  Each is
; played as its CPC effect, if the CPC has one.  Every register kept.

addsound:       push    af
                push    bc
                push    de
                push    hl
                ld      e, a
                cp      SOUNDS
                jr      c, sfxgo
                jr      sfxdone
cue_song:       push    af
                push    bc
                push    de
                push    hl
                cp      SONGS
                jr      nc, sfxdone
                add     a, SOUNDS
                ld      e, a
sfxgo:          ld      a, (inisr)      ; the handler ticks what this sets up:
                or      a               ; not while it is half done -- and not
                jr      nz, sfxg1       ; LD A,I, whose flag an interrupt
                di                      ; arriving on it clears, and left the
sfxg1:          call    page_sfx        ; game halted with them off for good
                ld      d, 0
                ld      hl, sfxmap
                add     hl, de
                ld      a, (hl)
                call    sfx_play
                call    page_back
                ld      a, (inisr)
                or      a
                jr      nz, sfxdone
                ei
sfxdone:        pop     hl
                pop     de
                pop     bc
                pop     af
                ret

; A = the CPC effect.  From its first tick, unless it matters less than the
; one playing.  With the sounds' bank in and interrupts off.

sfx_play:       cp      SFXCOUNT
                ret     nc
                ld      c, a
                add     a, a
                add     a, c
                ld      e, a
                ld      d, 0
                ld      hl, sfxtab
                add     hl, de
                ld      e, (hl)         ; where it starts
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      a, (sfxprio)
                cp      (hl)
                jr      z, sfxtake
                ret     nc              ; the one playing matters more
sfxtake:        ld      a, c
                ld      (sfxcur), a
                ld      a, (hl)
                ld      (sfxprio), a
                inc     hl
                ld      c, (hl)         ; and where the next one starts
                inc     hl
                ld      b, (hl)
                ld      hl, sfxdata
                add     hl, de
                ld      (sfxptr), hl
                ld      (sfxstart), hl
                ld      hl, sfxdata
                add     hl, bc
                ld      (sfxend), hl
                ld      a, 1
                ld      (sfxtimer), a
                jp      sfx_quiet

; The sounds' bank in the window, and back: straight to the port, leaving
; nowbank to whoever the handler interrupted.

page_sfx:       ld      a, (pgbits + 1)
                ld      hl, sfxbank     ; the sounds' bank: the canvas bank's,
                or      (hl)            ; or the art bank's for the titles
                jr      pgout
page_back:      ld      a, (pgbits + 1)
                ld      hl, nowbank
                or      (hl)
pgout:          push    bc
                ld      bc, PAGEPORT
                out     (c), a
                pop     bc
                ret

; The program's own interrupt, IM 2, fifty times a second as the CPC's is.
; I points into the 48K ROM's long run of 0xFF, so whatever the bus holds the
; vector is 0xFFFF: the top byte of whichever bank is paged, where start puts
; a JR -- whose displacement is the DI at 0x0000, back to 0xFFF4 -- and a jump
; here.  The ROM's own handler still counts the frames and reads the keys;
; then a tick of the sound, with the effects' bank paged in and the one that
; was put back, without touching nowbank, which the interrupted code owns.

ISRPAGE         equ     0x3A            ; 0x39FF to 0x3B00 is all 0xFF

isr:            push    af
                push    bc
                push    de
                push    hl
                call    0x0038          ; FRAMES and the keyboard; it enables
                di                      ; interrupts, which wait for the end
                ld      a, 1
                ld      (inisr), a
                ld      a, (songwait)   ; a tune waiting its time
                or      a
                jr      z, isrnow
                dec     a
                ld      (songwait), a
                jr      nz, isrnow
                ld      a, (songpend)
                call    cue_song
isrnow:         ld      a, (sfxtimer)
                or      a
                jr      z, isrout
                call    page_sfx
                call    sfx_tick
                ld      a, (sfxcur)     ; the CPC's frame handler stops effect
                cp      11              ; 11 a fraction of a tick after it has
                call    z, ststop       ; started: a click, not a hiss
                call    page_back
isrout:         xor     a
                ld      (inisr), a
                pop     hl
                pop     de
                pop     bc
                pop     af
                ei
                ret

; What start writes at the top of every bank: a jump to the handler at 0xFFF4
; and the JR at 0xFFFF.

songwait:       db      0               ; interrupts until songpend is cued
songpend:       db      0

isrstub:        jp      isr
                ds      8
                db      0x18
ISRSTUBLEN      equ     12

; One tick: the wait counted down, and when it is out the commands up to the
; next wait.  Past its end an effect starts again from its start.

sfx_tick:       ld      hl, sfxtimer
                ld      a, (hl)
                or      a
                ret     z
                dec     (hl)
                ret     nz
                inc     (hl)
                ld      hl, (sfxptr)
stloop:         ld      de, (sfxend)
                push    hl
                or      a
                sbc     hl, de
                pop     hl
                jr      c, stin
                ld      hl, (sfxstart)
stin:           ld      a, (hl)
                inc     hl
                bit     7, a
                jr      z, streg
                and     0x7f
                jr      nz, stcmd
                ld      a, (hl)         ; 80 v: the accumulator
                inc     hl
                ld      (sfxacc), a
                jr      stloop
stcmd:          dec     a
                jr      nz, stwait
                ld      b, (hl)         ; 81 r d t: a step towards t
                inc     hl
                ld      a, (sfxacc)
                add     a, (hl)
                inc     hl
                cp      (hl)
                jr      nz, stramp
                ld      c, a            ; there: on to what follows
                ld      a, b
                jr      stwrite
stramp:         ld      (sfxacc), a     ; not yet: this step, and the same
                ld      c, a            ; command next tick
                ld      a, b
                call    sfx_out
                dec     hl
                dec     hl
                dec     hl
                jr      stsave
stwait:         ld      a, (hl)         ; 8x n: wait n + 1 ticks, or stop
                or      a
                jr      z, ststop
                inc     a
                ld      (sfxtimer), a
                inc     hl
stsave:         ld      (sfxptr), hl
                ret
streg:          ld      c, (hl)         ; r v
                cp      11
                jr      nz, stwrite
                inc     hl              ; 11 lo 12 hi: the envelope period,
                inc     hl              ; halved
                ld      b, (hl)
                srl     b
                rr      c
                push    bc
                call    sfx_out
                pop     bc
                ld      a, 12
                ld      c, b
stwrite:        call    sfx_out
                inc     hl
                jr      stloop
ststop:         xor     a
                ld      (sfxtimer), a
                ld      (sfxprio), a

; The three volumes to nought.

sfx_quiet:      ld      a, 8
                call    sfx_zero
                ld      a, 9
                call    sfx_zero
                ld      a, 10
sfx_zero:       ld      c, 0

; Register A = C.  The mixer's top two bits are the I/O ports', left as inputs.

sfx_out:        cp      7
                jr      nz, sfxo1
                res     6, c
                res     7, c
sfxo1:          push    bc
                push    de
                ld      d, c
                ld      bc, 0xfffd
                out     (c), a
                ld      b, 0xbf
                out     (c), d
                pop     de
                pop     bc
                ret

inisr:          db      0
sfxcur:         db      0xff
sfxstart:       dw      0
sfxend:         dw      0
sfxptr:         dw      0
sfxtimer:       db      0
sfxacc:         db      0
sfxprio:        db      0

; ADDLOWERSOUND in SUBS.S, line for line: on every other step of the bars
; (the odd states), for a gate in the room on screen but not in its column
; nine, or in column nine of the room to the left, whose bars stand at this
; room's left edge -- and always for the gate of screen two of level three,
; the one the plate by the three slicers opens, which is heard closing
; wherever he runs to reach it.

lowersound:     ld      a, (trobst)
                rrca
                ret     nc              ; the even states are quiet
                ld      a, (curlev)
                cp      2
                jr      nz, ls1
                ld      a, (trscrn)
                cp      2
                jr      z, lsyes        ; level three, screen two
ls1:            call    trrowcol
                ld      a, (links)      ; the room to the left?
                ld      hl, trscrn
                cp      (hl)
                jr      nz, ls2
                ld      a, (blockcol)
                cp      9
                ret     nz
                jr      lsyes
ls2:            call    onscreen
                ret     nz
                ld      a, (blockcol)
                cp      9
                ret     z
lsyes:          ld      a, SND_LOWERINGGATE
                jp      addsound

; ---------------------------------------------------------------- spikes
;
; The state of a spikes block, as MOVER.S keeps it: 0 in the floor, 1 to 4
; coming out, 5 out, 6 to 8 going back; with bit 7 set they are out and the
; rest is a timer; 0xff they are jammed out through somebody.

SPIKEEXT        equ     5
SPIKERET        equ     9
SPIKETIMER      equ     15 + 128
SPIKEWIPE       equ     31

; ---------------------------------------------------------------- slicers
;
; A slicer's state, as MOVER.S keeps it: nought at rest, and from its
; trigger 1 to slicetimer round and round, the jaws shut at slicerExt and
; open again from slicerRet; bit 7 is the blood, once it has cut someone.

SLICEREXT       equ     2               ; shut: it bars, cuts and clashes
SLICERRET       equ     6
SLICETIMER      equ     15

; DRAWSLICERA in FRAMEADV.S: the jaws as the state has them -- the bottom
; one at Ay, smeared once it has cut, and the top one slicergap over it.

slicer_ma:      call    slicer_x
                ld      hl, bgtables + T_SLICERBOT
                ld      a, (state)
                or      a
                jp      p, smclean
                ld      hl, bgtables + T_SLICERBOT2
smclean:        ld      a, c
                push    bc
                call    bgentry
                or      a
                jr      z, smtop
                ld      c, a
                ld      a, (ay)
                ld      (yco), a
                ld      a, c
                ld      c, BG_ORA
                call    bglay
                call    page_bg
smtop:          pop     bc
                ld      a, c
                push    af
                ld      hl, bgtables + T_SLICERGAP
                call    bgentry
                ld      c, a
                ld      a, (ay)
                sub     c
                ld      (yco), a
                pop     af
                ld      hl, bgtables + T_SLICERTOP
                call    bgentry
                or      a
                ret     z
                ld      c, BG_ORA
                jp      bglay

; Which picture the state is, out of slicerseq.  POP has five of them and
; moves the jaws every frame; this port has two, shut and open, and nothing
; in between -- each is a tile of the room's made when it is built (sl_make)
; and the three middle ones would be three more a slicer, in a bank with no
; room for them; all they show is the jaws part way.  The two that are left
; are the two that matter: the state the jaws cut at, and everything else.
; slpic makes the same choice.
;
; Out: C = the picture, 0 to 4, and the background bank in.

slicer_x:       call    page_bg
                ld      a, (state)
                and     0x7f
                cp      SLICEREXT
                ld      a, SLICEREXT
                jr      z, sx1
                ld      a, SLICERRET
sx1:            ld      hl, bgtables + T_SLICERSEQ
                call    bgentry
                dec     a
                ld      c, a
                ret

; DRAWSPIKEA and DRAWSPIKEB in FRAMEADV.S: the blades, out as far as the
; state says, a row above Ay, the A half over the block and the B half in
; the block to its right.

spike_ma:       call    page_bg
                ld      a, (state)
                ld      hl, bgtables + T_SPIKEA
                jr      spikelay
spike_mb:       call    page_bg
                ld      a, (spreced)
                ld      hl, bgtables + T_SPIKEB
spikelay:       or      a
                jp      p, spkframe
                ld      a, SPIKEEXT
spkframe:       call    bgentry
                or      a
                ret     z
                ld      c, a
                ld      a, (ay)
                dec     a
                ld      (yco), a
                ld      a, c
                ld      c, BG_ORA
                jp      bglay

; ANIMSPIKES in MOVER.S.

aospikes:       ld      a, (trdirec)
                or      a
                jp      m, aosred       ; stopped: only the redraw
                ld      a, (trobst)
                or      a
                jp      m, aostimer
                inc     a
                ld      (trobst), a
                dec     a
                cp      SPIKEEXT        ; out: the timer starts
                jr      z, aosout
                cp      SPIKERET        ; back in: ready again
                jr      nz, aosred
                xor     a
                ld      (trobst), a
                call    stopobj
                jr      aosred
aosout:         ld      a, SPIKETIMER
                ld      (trobst), a
                jr      aosred
aostimer:       dec     a
                ld      (trobst), a
                and     0x7f
                jp      nz, aodone      ; waiting: nothing to draw
                ld      a, SPIKEEXT + 1 ; time's up: going back
                ld      (trobst), a
aosred:         ld      a, 1
                ld      (redwant), a
                ld      a, SPIKEWIPE
                ld      (redh), a
                jp      aodone

; The spikes block at column A, row C of this room into trloc and trscrn,
; and its state read.  Out: A = the id.

spk_at:         ld      b, a
                ld      a, c
                add     a, a
                ld      e, a
                add     a, a
                add     a, a
                add     a, e
                add     a, b
                ld      (trloc), a
                ld      a, (roomnum)
                ld      (trscrn), a
                jp      trobat

; TRIGSPIKES: in the floor they spring; out, their timer starts again.

trig_spikes:    call    spk_at
                ld      a, (trobst)
                or      a
                jr      z, tsready
                ret     p               ; on their way: leave them
                inc     a
                ret     z               ; jammed
                ld      a, SPIKETIMER
                ld      (trobst), a
                jp      trobsave
tsready:        ld      a, 1
                ld      (trdirec), a
                call    addtrob
                ld      a, SND_SPIKES   ; the CPC's, for spikes springing
                call    addsound
                ld      a, SPIKEWIPE
                ld      (redh), a
                jp      redplate

; CHECKSPIKES in CTRLSUBS.S: every block his picture spans, in his row, and
; down through open space below each one.

checkspikes:    ld      a, (spkroom)    ; none in the room
                or      a
                ret     z
                ld      a, (nowbank)
                push    af
                call    char_edges
                ld      hl, (edger)
                call    blockcol_of
                bit     7, a
                jr      nz, cksdone
                ld      (csright), a
                ld      hl, (edgel)
                call    blockcol_of
                bit     7, a
                jr      z, cksloop
                xor     a
cksloop:        ld      (csx), a
                cp      10
                jr      nc, cksdone
                ld      a, (blocky)
                ld      (csy), a
cksdown:        ld      a, (csy)
                cp      3
                jr      nc, cksnext
                ld      c, a
                ld      a, (csx)
                call    tile_at
                cp      BG_SPIKES
                jr      z, ckstrig
                call    cmp_space
                jr      nz, cksnext
                ld      hl, csy
                inc     (hl)
                jr      cksdown
ckstrig:        ld      a, (csy)
                ld      c, a
                ld      a, (csx)
                call    trig_spikes
cksnext:        ld      a, (csx)
                ld      hl, csright
                cp      (hl)
                jr      nc, cksdone
                inc     a
                jr      cksloop
cksdone:        pop     af
                jp      pageset

; GETSPIKES in MOVER.S, for the tile just read.  Out: A = 0 safe (in, going
; in, or jammed), 1 out, 2 springing; Z when safe.

getspikes:      ld      a, (tilestate)
                or      a
                jp      m, gssprung
                ret     z
                cp      SPIKEEXT
                jr      c, gsspring
                xor     a
                ret
gssprung:       inc     a
                ret     z
                ld      a, 1
                or      a
                ret
gsspring:       ld      a, 2
                or      a
                ret

; CHECKIMPALE in CTRL.S: running on to springing spikes, or landing a jump
; on to spikes that are out.  Landing from a fall is land_spikes.

checkimpale:    ld      a, (spkroom)
                or      a
                ret     z
                ld      hl, (charx)     ; CharBlockX, CharBlockY
                call    blockcol_of
                cp      10
                ret     nc
                ld      b, a
                ld      a, (blocky)
                cp      3
                ret     nc
                ld      c, a
                ld      a, b
                push    af
                call    tile_at
                pop     bc
                cp      BG_SPIKES
                ret     nz
                ld      a, (frame)
                cp      7
                ret     c
                cp      15
                jr      c, cirun
                cp      43              ; runjump-10
                jr      z, cijump
                cp      26              ; standjump-19
                ret     nz
cijump:         call    getspikes
                ret     z
                jr      ciimpale
cirun:          call    getspikes
                cp      2
                ret     c
ciimpale:       ld      a, b
                jr      doimpale

; CHECKFLOOR's hitflr, landing: spikes out behind him, when he is at least
; twelve units into his block, or under him.  Out: NZ when he is impaled.

land_spikes:    call    base_x
                call    blockcol_of
                ld      b, a
                push    bc
                call    get_dist        ; which has B
                pop     bc
                cp      12
                jr      c, lsunder
                ld      a, (facing)     ; the block behind
                or      a
                ld      a, b
                jr      z, lsleft
                sub     2
lsleft:         inc     a
                call    ls_spikes
                jr      nz, lsunder
                call    getspikes
                jr      nz, lsimpale
                jr      lsno            ; there, but not lethal
lsunder:        ld      a, b
                call    ls_spikes
                jr      nz, lsno
                call    getspikes
                jr      z, lsno
lsimpale:       ld      a, (lscol)
                call    doimpale
                or      1
                ret
lsno:           xor     a
                ret

; A = a column of his row.  Z when spikes are in it; B kept.

ls_spikes:      ld      (lscol), a
                cp      10
                jr      nc, lsnot
                push    bc
                ld      a, (blocky)
                ld      c, a
                ld      a, (lscol)
                call    tile_at
                pop     bc
                cp      BG_SPIKES
                ret
lsnot:          or      a               ; off the room: not spikes
                ret

; DOIMPALE: the spikes are jammed out through him, he is put square on them
; at the floor, and he dies on them.  A = their column.

doimpale:       ld      (lscol), a
                ld      a, (blocky)
                ld      c, a
                ld      a, (lscol)
                call    spk_at          ; JAMSPIKES
                ld      a, 0xff
                ld      (trobst), a
                call    trobsave
                ld      a, 0xff
                ld      (trdirec), a
                call    addtrob
                ld      a, SPIKEWIPE
                ld      (redh), a
                call    redplate
                ld      a, SND_IMPALED
                call    addsound
                call    page_canvas     ; move_by is in the canvas bank
                call    floor_plane
                ld      (chary), a
                ld      a, (lscol)      ; the edge of the spikes, ten on
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                sbc     hl, de
                ld      de, 20
                add     hl, de
                ld      (charx), hl
                ld      a, 8            ; and eight the way he faces
                call    move_by
                xor     a
                ld      (yvel), a
                ld      a, 100
                call    decstr
                call    page_canvas
                ld      a, SQ_IMPALE
                call    jumpseq
                jp      step_seq

csx:            db      0
csy:            db      0
csright:        db      0
lscol:          db      0

; ---------------------------------------------------------------- potions
;
; What a potion does is potion_effect's, in CODE1; the flashes' colours are
; the meters' too.

RED             equ     2
GREEN           equ     4

; DRAWFLASKA and SETUPFLASK: the bubbles over the bottle, a frame of them for
; the low five bits of its state, two bytes in and two pixels on -- three for
; the tall bottles past the boost.
;
; Blocks are 28 pixels and colour cells 8, so a flask in an odd column stands
; four pixels further into its cells than one in an even column, and its
; bubbles cross from one cell into the next.  There the whole flask, bottle
; and bubbles, goes five pixels to the left -- a byte back and two pixels on
; -- and every flask then has its bubbles in a single cell, which is the one
; its colour goes in; flask_front moves the bottle the same way.  And a tall
; bottle's bubbles go up into one cell row, seven rows (eight in the top
; block row: see talltop) -- but not potion five's, which drawfrnt gives the
; ordinary bottle: SETUPFLASK raises them all the same, and they stood off
; its neck.  The bottle itself stands two pixels lower, every one of them,
; so that its top is in the cell row under the bubbles' and takes none of
; their colour.

flask_ma:       ld      a, (state)
                and     0x1f
                cp      9               ; bubbLast
                ret     nc              ; past it: frame nought, the blank one
                ld      e, a
                ld      d, 0
                ld      hl, bubble
                add     hl, de
                ld      a, (hl)
                inc     a
                ret     z               ; $b2: nothing to lay
                dec     a
                ld      c, a            ; C = which bubble, 0 to 2
                ld      hl, BUBBLES + 256 * BUBMASK
                ld      de, 0x06ff      ; E = the tall bottle's rounding,
                                        ; D what the short one adds back
                ld      a, (state)
                and     0xe0
                jr      z, fmcont       ; empty
                cp      0x40
                jr      c, fmcont       ; refresh
                jr      z, fmtall       ; boost
                ld      hl, BUBBLES + 3 + 256 * (BUBMASK + 1)
                cp      0xa0            ; potion five is in the ordinary
                jr      z, fmcont       ; bottle, and bubbles at its height
fmtall:         ld      de, 0x00f8      ; the tall bottle: down to a cell
                                        ; line six under the short one's --
                                        ; seven up in the lower block rows,
                                        ; eight in the top one: see talltop
fmcont:         ld      a, (ay)
                sub     20
                and     e
                add     a, d
                ld      (yco), a
                ld      b, 2            ; B = bytes in
                ld      a, (blockcol)
                rra
                jr      nc, fmx
                dec     b               ; odd: a byte less, two pixels on
fmx:            ld      a, (xco)
                add     a, b
                ld      (xco), a
                push    bc
                push    hl
                call    fm_shift
                ld      a, h
                ld      c, BG_AND
                call    bglay
                pop     hl
                pop     bc
                push    bc
                call    fm_shift
                ld      a, l
                add     a, c
                ld      c, BG_ORA
                call    bglay
                pop     bc
                ld      a, (xco)
                sub     b
                ld      (xco), a
                ret

fm_shift:       ld      a, (blockcol)
                and     1
                add     a, a
                ld      (bgshift), a
                ret

; bubble in GAMEBG.S, as which of the three drawn ones: $b2 is -1.

bubble:         db      -1, 0, 1, 2, 1, 0, 2, 1, 0

; ANIMFLASK and GETFLASKFRAME in MOVER.S: out of sight it comes off the list;
; otherwise the bubbles go round frames one to eight, every frame.

FLASKWIPE       equ     32              ; the second band up: the bubbles are
                                        ; seventeen to twenty nine rows above
                                        ; the floor line

aoflask:        call    onscreen
                jp      nz, stopobj
                ld      a, (trobst)
                ld      b, a
                and     0x1f
                inc     a
                cp      9
                jr      c, afframe
                ld      a, 1
afframe:        ld      c, a
                ld      a, b
                and     0xe0
                or      c
                ld      (trobst), a
                call    bubble_poke
                xor     a               ; nothing for the queue to redraw
                ld      (redwant), a
                jp      aodone

; A block redraw a frame for three pixels was the heaviest thing in a room
; with a flask in it.  The bubbles keep to one byte column and six rows, and
; nothing but they change there, so the new picture goes straight into those
; bytes -- of the room, of the working copy, and to the screen through the
; queue of rectangles, and into a view being made -- exactly as flask_ma lays
; it: the five pixels cleared, and the frame's bits in.

bubble_poke:    call    trrowcol
                ld      a, (trobst)     ; which picture, or none
                and     0x1f
                ld      e, a
                ld      d, 0
                ld      hl, bubble
                add     hl, de
                ld      a, (hl)
                ld      c, a            ; C = 0 to 2, or -1
                ld      a, (trobst)     ; the potion: the tall bottles are
                and     0xe0            ; at the short ones' height, as flask_ma has
                ld      de, 0x0102      ; them, and past the boost a pixel on
                cp      0x40            ; -- potion five too, though its
                jr      c, bpshort      ; bottle and its bubbles' height are
                jr      z, bptall       ; the ordinary one's
                dec     e               ; E = the shift into the byte
                cp      0xa0
                jr      z, bpshort
bptall:         ld      d, talltop - blockbot   ; talltop's row: flask_ma
bpshort:        ld      a, (blockcol)
                rra
                jr      nc, bpeven
                inc     e               ; odd: a pixel further back in its cell
bpeven:         ld      a, e
                ld      (bpshift), a
                ld      hl, blockbot    ; the top row: 23 over the floor
                ld      a, (blockrow)   ; line, or talltop's -- the tables
                add     a, d            ; on one page
                add     a, l
                ld      l, a
                ld      a, (hl)
                sub     23
                ld      (rowy), a
                ld      a, (blockcol)   ; its byte column, as flask_attrs has it
                ld      b, a
                add     a, a
                add     a, a
                bit     0, b
                jr      z, bpcol16
                sub     4
bpcol16:        add     a, 16
                rrca
                rrca
                rrca
                and     0x1f
                add     a, b
                add     a, b
                add     a, b
                ld      (bpcol), a
                inc     c               ; the picture's six rows of bits,
                ld      a, c            ; the blank one's first
                add     a, a
                add     a, c
                add     a, a
                ld      e, a
                ld      d, 0
                ld      hl, bubblebits
                add     hl, de
                ld      (bpbits), hl
                ld      a, (bpshift)    ; the five pixels, where they go
                ld      b, a
                ld      a, 0x1f
bpm:            add     a, a
                djnz    bpm
                cpl
                ld      (bpmask), a
                call    page_art
                ld      a, (rowy)
                call    roomrow
                ld      a, (bpcol)
                ld      e, a
                ld      d, 0
                add     hl, de          ; HL = the room's top byte of them
                ld      de, (bpbits)
                ld      c, 6
bprow:          ld      a, (de)
                ld      b, a
                ld      a, (bpshift)
bpsh:           sla     b
                dec     a
                jr      nz, bpsh
                ld      a, (bpmask)
                and     (hl)
                or      b
                ld      (hl), a
                inc     de
                push    de
                ld      de, ROOM_BYTES
                add     hl, de
                pop     de
                dec     c
                jr      nz, bprow

                ld      a, (rowy)       ; a view being made wants the rows
                ld      b, 6
                call    vw_mark
                ld      a, (bpcol)      ; and the working copy and the screen
                ld      hl, cam         ; the bytes, if they are in view
                sub     (hl)
                cp      32
                ret     nc
                ld      (linecol), a
                ld      (bprect), a
                ld      a, (rowy)
                ld      (bprect + 1), a
                ld      hl, bprect
                call    eraseset
                ld      a, 1
                ld      (rdw), a
                ld      a, 6
                ld      (redh), a
                call    dirty_add
                ld      a, 63           ; and the band height as it was
                ld      (redh), a
                ret

bprect:         db      0, 0, 1, 6
bpmask:         db      0
bpshift:        db      0
bpcol:          db      0
bpbits:         dw      0
bubblebits:     incbin  "bubblebits.bin"

lastpotion:     db      0
takeid:         db      0
lightning:      db      0
lightcolor:     db      0
weightless:     db      0
maxkidstr:      db      3               ; MaxKidStr: initmaxstr in TOPCTRL.S

; ---------------------------------------------------------------- meters
;
; UPDATEMETERS in GAMEBG.S: the kid's strength at the bottom left, a bullet a
; point up to his most, and his opponent's at the bottom right, mirrored.  The
; last one flashes.  They go straight onto the screen that is shown, after
; everything else has gone to it this frame, the way POP adds them last: the
; working copy never has them, so nothing that is put back from it can leave
; one behind.  A bullet is eight pixels on from the one before, as KidStrX
; and KidStrOFF place them, which on a Spectrum is a byte each.

METERTOP        equ     184             ; the meters' character row
METERY          equ     185             ; the bullet's top row, down to the
BULLETH         equ     7               ; foot of the screen, seven tall
INK_KIDMETER    equ     0x42            ; bright red, as on the Apple
INK_OPPMETER    equ     0x41            ; and his opponent's bright blue
MAXKIDMETER     equ     10              ; maxmaxstr: the most he can have
MAXOPPMETER     equ     4               ; the most a guard of this level has

show_meters:    call    page_canvas
                call    hurt_flash
                ld      hl, lightning   ; a flash is the border, a frame at a
                ld      a, (hl)         ; time, for as many as it says
                or      a
                jr      z, smdark
                dec     (hl)
                ld      a, (lightcolor)
                cp      GREEN           ; the sword's: the whole ground green
                call    z, green_attrs
smdark:         out     (254), a
                ld      a, (lightning)  ; the flash over, the colours back
                or      a
                jr      nz, smgreen
                ld      hl, greenon
                or      (hl)
                jr      z, smgreen
                ld      (hl), 0
                call    shown_attrs
smgreen:
                ld      hl, weightless  ; and weightlessness wears off
                ld      a, (hl)
                or      a
                jr      z, smwt
                dec     (hl)
smwt:           call    page_canvas     ; bank 7, in case it is the one shown
                ld      hl, mflash      ; PAGE, which POP flips every frame
                inc     (hl)

; They were going down every frame, a dozen thousand cycles with a guard in
; the room, for what changes a few times a fight.  Now only when a strength
; has changed, when one is down to its last and flashing, or when something
; has been put on the screen over them -- a rectangle reaching their row, a
; view turned round, the whole screen or its colours redone.

                call    oppshown        ; C = his opponent's, as shown
                ld      c, a
                cp      1
                jr      z, smdraw       ; flashing
                ld      a, (kidstr)
                cp      1
                jr      z, smdraw
                ld      hl, meterdirty
                ld      a, (hl)
                ld      (hl), 0
                or      a
                jr      nz, smdraw
                ld      hl, smlast
                ld      a, (kidstr)
                cp      (hl)
                jr      nz, smdraw
                inc     hl
                ld      a, (maxkidstr)
                cp      (hl)
                jr      nz, smdraw
                inc     hl
                ld      a, c
                cp      (hl)
                ret     z               ; nothing to do
smdraw:         ld      hl, smlast
                ld      a, (kidstr)
                ld      (hl), a
                inc     hl
                ld      a, (maxkidstr)
                ld      (hl), a
                inc     hl
                ld      (hl), c
                ld      a, INK_KIDMETER
                ld      (mmink), a
                ld      a, (kidstr)     ; his, every place drawn -- till he
                or      a               ; has none left, when they go, and
                ld      a, (kiddrawn)   ; the room is put back where they were
                ld      (mmprev), a
                ld      a, 10
                jr      nz, smkid
                xor     a
smkid:          ld      (kiddrawn), a
                ld      (mmdrawn), a
                ld      hl, bullet
                ld      a, (kidstr)
                ld      c, a
                ld      a, (maxkidstr)
                ld      b, a
                ld      de, 0x0100      ; from the left, a byte on each time
                call    meter
                ld      a, INK_OPPMETER
                ld      (mmink), a
                xor     a               ; his opponent's: a place spent is
                ld      (mmdrawn), a    ; the room again, once
                ld      a, (oppdrawn)
                ld      (mmprev), a
                call    oppshown
                ld      c, a
                ld      hl, bullet + BULLETH
                ld      b, MAXOPPMETER
                ld      de, 0xff1f      ; from the right, a byte back each time
                call    meter
                ld      a, (mmlast)
                ld      (oppdrawn), a
                ret

; DRAWOPPMETER: what his opponent's meter shows -- nothing at all for the
; skeleton, which has no strength to lose.

oppshown:       ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (charid + OP)
                cp      4
                jr      z, oppnone
                ld      a, (oppstr)
                ret
oppnone:        xor     a
                ret

; The screen shown with green in place of its black ground, ink kept.  A is
; kept, for the border.

green_attrs:    push    af
                ld      a, 1
                ld      (greenon), a
                call    page_canvas
                ld      a, (scrsel + 1)
                or      0x58
                ld      h, a
                ld      l, 0
                ld      bc, 768
galoop:         ld      a, (hl)
                and     0xc7
                or      GREEN * 8
                ld      (hl), a
                inc     hl
                dec     bc
                ld      a, b
                or      c
                jr      nz, galoop
                pop     af
                ret

greenon:        db      0

; HL = the bullet's rows, B = how many places, C = how many are lit,
; E = the first column and D the step to the next; (mmink) their colour.  A
; place is a whole character cell -- the rows round the bullet kept black
; as well, so that the colour takes nothing of the wall above it.  A place not
; lit is black up to (mmdrawn) places; past that it is put back from the room,
; in the room's colour, if it was one of the (mmprev) drawn the time before,
; and is otherwise left.

meter:          ld      (mmimg), hl
                ld      (mmfirst), de
                ld      a, c
                cp      1
                jr      nz, mmlitn
                ld      a, (mflash)     ; down to one: it flashes
                rra
                jr      nc, mmlitn
                ld      c, 0
mmlitn:         ld      a, c
                ld      (mmlast), a
                ld      (mmlit), a
                xor     a
                ld      (mmidx), a
mmplace:        push    bc
                ld      hl, mmidx
                ld      a, (mmlit)
                cp      (hl)
                ld      a, 0            ; lit
                jr      z, mmoff
                jr      nc, mmmode
mmoff:          ld      a, (mmdrawn)
                cp      (hl)
                ld      a, 1            ; black
                jr      z, mmroom
                jr      nc, mmmode
mmroom:         ld      a, (mmprev)     ; the room, if there was a bullet
                cp      (hl)
                jr      z, mmnext
                jr      c, mmnext
                ld      a, 2
mmmode:         ld      (mmwhat), a
                ld      a, METERTOP
mmrow:          push    af
                ld      e, a
                sub     METERY          ; C = the bullet's row there, if any
                ld      c, a
                ld      a, (mmwhat)
                cp      2
                jr      nz, mmscr
                ld      a, e            ; the room's byte, from the art bank
                call    roomwin
                ld      a, (mmfirst)
                ld      e, a
                ld      d, 0
                add     hl, de
                call    page_art
                ld      a, (hl)
                ld      (mmbyte), a
                call    page_canvas
                pop     af
                push    af
                ld      e, a
mmscr:          ld      a, (mmfirst)
                ld      d, a
                ld      a, e
                ld      e, d
                call    scraddr
                ld      a, (mmwhat)
                or      a
                jr      z, mmbul
                cp      2
                ld      a, (mmbyte)
                jr      z, mmput
                xor     a
                jr      mmput
mmbul:          ld      a, c
                cp      BULLETH
                ld      a, 0
                jr      nc, mmput       ; over or under the bullet
                push    hl
                ld      hl, (mmimg)
                ld      b, 0
                add     hl, bc
                ld      a, (hl)
                pop     hl
mmput:          ld      e, a
                ld      a, (scrsel + 1)
                or      h
                ld      h, a
                ld      (hl), e
                pop     af
                inc     a
                cp      METERTOP + 8
                jr      c, mmrow
                ld      a, (mmfirst)    ; and the cell's colour
                add     a, 0xe0
                ld      l, a
                ld      a, (scrsel + 1)
                or      0x5a
                ld      h, a
                ld      a, (mmwhat)
                cp      2
                ld      a, INK_ROOM
                jr      z, mmink1
                ld      a, (mmink)
mmink1:         ld      (hl), a
mmnext:         ld      hl, mmfirst
                ld      a, (mmstep)
                add     a, (hl)
                ld      (hl), a
                ld      hl, mmidx
                inc     (hl)
                pop     bc
                dec     b
                jp      nz, mmplace
                ret

mmimg:          dw      0
mmfirst:        db      0
mmstep:         db      0
mmlit:          db      0
mmlast:         db      0
mmidx:          db      0
mmwhat:         db      0               ; 0 lit, 1 black, 2 the room
mmbyte:         db      0
mmink:          db      0
mmdrawn:        db      0
oppdrawn:       db      0
smlast:         ds      3               ; the strengths last drawn
kiddrawn:       db      10
mmprev:         db      0               ; the places drawn the time before
mflash:         db      0
bullet:         incbin  "bullet.bin"

; ---------------------------------------------------------------- state

gdhere:         db      0               ; a guard in this room: ShadFace <> 86
guardprog:      db      0
gdkeep:         db      0               ; and one who followed him in: see
                                        ; leave_room, whose block is put by
                                        ; and brought back a room at a time
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
