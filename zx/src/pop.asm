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
;
; This is a 128K program.  The fixed half of the map holds the code, the
; tables the inner loops index, and the off screen copy; the window at 0xC000
; holds the room with its foreground mask in one bank and the prince's pixels
; in another, paged in for the part of the frame that reads them.

                org     24576
PAGEPORT        equ     0x7FFD
BANKM           equ     0x5B5C  ; the 128 ROM's copy of it

; The tape's BASIC loader cannot page banks itself -- OUT is the one statement
; this build cannot try out before it ships -- so it calls in here instead.
; Each of these is four bytes, so the loader knows where they are: 24576 for
; the first, then every four, and the last one starts the game.
;
;   10 CLEAR 24575
;   20 LOAD ""CODE : REM the program
;   30 RANDOMIZE USR 24576 : REM page a bank in
;   40 LOAD ""CODE : REM into it at 49152
;   ...
;   RANDOMIZE USR 24592 : REM go

stubs:          ld      a, BANK_ART
                jr      dopage
                ld      a, BANK_SPR1
                jr      dopage
                ld      a, BANK_SPR2
                jr      dopage
                ld      a, BANK_SPR3
                jr      dopage
                jp      start

; Called from BASIC, so it has to leave everything else about the port alone
; -- above all bit 4, which picks the ROM: switching that while the 128 ROM is
; mid-statement pulls the interpreter out from under itself.  BANKM at 5B5C is
; the ROM's own copy of the port, and it writes that copy back at its leisure,
; so ours has to go through it.

dopage:         and     7
                ld      b, a
                ld      hl, BANKM
                ld      a, (hl)
                and     0xf8
                or      b
                ld      (hl), a
                ld      bc, PAGEPORT
                out     (c), a
                ret

                include "assets.inc"

SCREEN          equ     16384
BUFW            equ     8               ; widest sprite plus the shift byte
; 50Hz frames per game frame.  The Apple ran the kid at about ten a second
; and this is twelve and a half, but the number is not only about speed: a
; game frame that outruns its slot lands late and the motion stutters.  The
; tall frames -- hanging is fifty five scanlines of him -- are the ones that
; do, so the slot has to be wide enough for those.
FRAME_WAIT      equ     3
BLOCK_PX        equ     28
STEP_OFF_FWD    equ     3               ; CTRL.S
STEP_OFF_BACK   equ     8
JUMP_BACK_THRES equ     6
ACCEL_G         equ     3               ; SUBS.S GRAVITY
TERM_VEL        equ     33
FLOOR_HEIGHT    equ     15              ; GAMEEQ.S, the thickness of a floor
; The room runs from block 0 to block 9, and a character on block b has his
; anchor between 28b+2 and 28b+29.  Only walls should stop him inside that --
; these are just to keep him on the map.
X_MIN           equ     14
X_MAX           equ     255

; ---------------------------------------------------------------- entry

start:          di
                ld      sp, stack
                im      1

                xor     a
                out     (254), a

                call    check_banks     ; before anything is written, and it
                                        ; leaves the art bank in

                ld      hl, SCREEN + 6144   ; one colour over the whole room,
                ld      de, SCREEN + 6145   ; so the attributes need not be
                ld      bc, 767             ; carried
                ld      (hl), 0x05
                ldir

                xor     a               ; the view starts at the room's left
                ld      (cam), a
                call    repaint


                ld      a, START_X
                ld      (charx), a
                ld      a, START_Y
                ld      (chary), a
                ld      a, START_ROW
                ld      (blocky), a
                call    set_row
                xor     a
                ld      (yvel), a
                ld      (facing), a
                ld      (oldw), a       ; nothing to erase on the first pass
                ld      a, revtab / 256 ; the reversal table's page
                ld      (mrev1 + 1), a
                ld      (mrev2 + 1), a
                ld      a, SQ_STAND
                call    jumpseq

                call    step_seq
                call    draw_prince
                call    page_art
                call    hide_floor
                call    hide_behind
                call    show_rect
                call    keep_rect
                ei

; ---------------------------------------------------------------- main

main:           ld      b, FRAME_WAIT
mainwait:       halt
                djnz    mainwait

                call    page_art
                call    camera
                call    erase_prince
                call    input_step
                call    step_seq
                call    check_barr
                call    check_floor
                call    do_fall
                call    draw_prince
                call    page_art
                call    hide_floor
                call    hide_behind
                call    show_rect
                call    keep_rect
                jr      main

; ---------------------------------------------------------------- paging
;
; Two things are too big to keep in the fixed half of the map: the room with
; its foreground mask, and the prince's pixels.  Each lives in its own bank at
; 0xC000 and is paged in for the part of the frame that wants it.  Bit 4 keeps
; the 48K ROM, which is what the interrupt handler at 0x38 is.

; The room is 280 pixels wide and the screen is 256, so the room is carried
; whole -- 35 bytes to a scanline, laid out plainly, one byte the camera can
; slide over -- and the visible window is copied out of it.
;
; A = a scanline or a mask's row.  Out: HL = that row's offset.

mul35:          ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; thirty two
                add     hl, de
                add     hl, de
                add     hl, de          ; and three more
                ret

; HL = the room's row under screen column zero.

roomwin:        call    mul35
                ld      de, room
                add     hl, de
                ld      a, (cam)
                ld      e, a
                ld      d, 0
                add     hl, de
                ret

; Thirty two bytes, HL to DE.  Unrolled, because ldir spends a fifth of its
; time counting and this runs over the whole screen when the view moves.

copy32:         ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ldi
                ret

; The working copy starts out as the room, once.  After that it is only ever
; right where the sprite has been, which is all anything reads of it.

repaint:        xor     a
                ld      (rowy), a
                call    roomwin         ; the room walks forward a row at a
                ld      (roomp), hl     ; time, so it is not worked out again
                ld      b, 192
rprow:          push    bc
                ld      e, 0
                ld      a, (rowy)
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de
                ex      de, hl
                ld      hl, (roomp)
                call    copy32
                call    nextrow
                pop     bc
                djnz    rprow
                ld      a, 1
                ld      (fullshow), a
                ret

; copy32 leaves HL past the thirty two it took; the room's rows are three
; longer than that.

nextrow:        ld      de, ROOM_BYTES - 32
                add     hl, de
                ld      (roomp), hl
                ld      hl, rowy
                inc     (hl)
                ret

; Nothing in POP moves a camera: the Apple's room is all on screen at once.
; Ours is 24 pixels short of it, so the view slides a byte at a time and only
; when he leaves the middle of it.  The dead zone is wide, or a single pace
; would set it stepping back and forth.
;
; A step does not repaint the working copy: the screen is redrawn from the
; room itself, and the only part of the working copy anything reads after
; that is the rectangle he is about to be drawn in -- which the draw puts the
; room back under first.  Where he was is forgotten; it is in the old view.

camera:         ld      a, (cam)
                ld      b, a
                add     a, a
                add     a, a
                add     a, a
                ld      c, a            ; the view's left edge
                ld      a, (charx)
                sub     c               ; where he stands on screen
                cp      160
                jr      c, camnear
                ld      a, b
                cp      CAM_MAX
                ret     nc
                inc     b
                jr      camset
camnear:        cp      96
                ret     nc
                ld      a, b
                or      a
                ret     z
                dec     b
camset:         ld      a, b
                ld      (cam), a
                ld      a, 1
                ld      (fullshow), a
                ld      (camstep), a
                xor     a               ; where he was is in the old view and
                ld      (oldw), a       ; the screen is about to be redrawn
                ret                     ; whole, so there is nothing to rub out

; Every bank is signed at its end, and a red border says one did not arrive:
; a black screen leaves nothing to go on.

check_banks:    ld      a, BANK_ART
                call    pageset
                ld      hl, (SIG_ART_AT)
                ld      de, SIG_ART
                or      a
                sbc     hl, de
                jp      nz, badload
                ld      hl, sigtab
                ld      b, 3
cbloop:         push    bc
                ld      a, (hl)
                inc     hl
                call    pageset
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                push    hl
                ex      de, hl
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ld      hl, SIG_SPR
                or      a
                sbc     hl, de
                pop     hl
                pop     bc
                jp      nz, badload
                djnz    cbloop
                ld      a, BANK_ART
                jp      pageset

sigtab:         db      BANK_SPR1
                dw      SIG_SPR1_AT
                db      BANK_SPR2
                dw      SIG_SPR2_AT
                db      BANK_SPR3
                dw      SIG_SPR3_AT

; A bank that did not arrive: red border, and nothing else is going to work.

badload:        ld      a, 2
                out     (254), a
                jr      badload

page_art:       ld      a, (artbank)
                jr      pageset

; The frame's own bank: the top two bits of its blob offset say which.

page_frame:     ld      a, (curbank)
                ld      l, a
                ld      h, 0
                ld      de, banktab
                add     hl, de
                ld      a, (hl)
pageset:        or      0x10            ; bit 4 keeps the 48K ROM, which is
                push    bc              ; what the handler at 0x38 is.  By now
                ld      bc, PAGEPORT    ; BASIC is gone and BANKM with it
                out     (c), a
                pop     bc
                ret

; [0] where the tape left the first bank of sprites, [1] the rest of them,
; [2] the room and its mask.
banktab:        db      BANK_SPR1, BANK_SPR2, BANK_SPR3
artbank:        db      BANK_ART

; ---------------------------------------------------------------- input
;
; CTRL.S.  POP reads a joystick, so the keys are turned into one first:
;
;   JSTKX   which way he is pushed RELATIVE TO THE WAY HE FACES,
;           forward negative, back +1, centred 0
;   JSTKY   -1 up, +1 down, 0 centred
;   btn     the button, caps shift here
;
; and on top of that the "smart input" of GENCTRL: clrF, clrB, clrU, clrD and
; clrbtn, which are -1 on a FRESH press, 0 while nothing is pushed, and 1 once
; a handler has used the press.  Without them a held key repeats its action
; every frame, which is not how the game plays at all.
;
;   left    key 5, row F7FE bit 4        up      key 7, row EFFE bit 3
;   right   key 8, row EFFE bit 2        down    key 6, row EFFE bit 4
;   button  space, row 7FFE bit 0
;
; Not caps shift, tempting though it is: there are no cursor keys on a
; Spectrum, and every emulator makes them caps shift and 5-6-7-8.  Using it
; for the button would mean every step was a careful one.

read_input:     ld      bc, 0xF7FE
                in      a, (c)
                ld      d, a            ; D = the 1-5 half row
                ld      bc, 0xEFFE
                in      a, (c)
                ld      e, a            ; E = the 6-0 half row

                xor     a               ; JSTKY
                bit     3, e
                jr      nz, riydn
                dec     a
                jr      riy2
riydn:          bit     4, e
                jr      nz, riy2
                inc     a
riy2:           ld      (jstky), a

                xor     a               ; JSTKX, stored the way SPECIALK.S
                bit     4, d            ; stores it: as if he faced left, so
                jr      nz, rix1        ; forward is the left key
                dec     a
rix1:           bit     2, e
                jr      nz, rix2
                inc     a
rix2:           ld      (jstkx), a

                ld      bc, 0x7FFE
                in      a, (c)
                cpl
                and     1
                ld      (btn), a

; CLRJSTK in SPECIALK.S.  A flag already at -1 stays there until someone uses
; it; otherwise it goes to 0 when the key is up, and to -1 the frame the key
; goes down, unless it is still at 1 from the last time.

                ld      a, (jstkx)      ; forward
                or      a
                ld      c, 0
                jp      p, cjf
                dec     c
cjf:            ld      hl, clrf
                call    clr_one

                ld      a, (jstkx)      ; back
                dec     a
                ld      c, 0
                jr      nz, cjb
                dec     c
cjb:            ld      hl, clrb
                call    clr_one

                ld      a, (jstky)      ; up
                or      a
                ld      c, 0
                jp      p, cju
                dec     c
cju:            ld      hl, clru
                call    clr_one

                ld      a, (jstky)      ; down
                dec     a
                ld      c, 0
                jr      nz, cjd
                dec     c
cjd:            ld      hl, clrd
                call    clr_one

                ld      a, (btn)        ; the button
                or      a
                ld      c, 0
                jr      z, cjbt
                dec     c
cjbt:           ld      hl, clrbtn
                jr      clr_one

; HL = the flag, C = 0xFF while the key is down.

clr_one:        ld      a, (hl)
                or      a
                ret     m               ; a press already waiting
                ld      b, a
                ld      a, c
                or      a
                jr      nz, clrdown
                ld      (hl), 0
                ret
clrdown:        ld      a, b
                or      a
                ret     nz              ; the press was used already
                ld      (hl), 0xff
                ret

; clrall: forget every pending press.  A handler calls it and then marks the
; one it used with 1, so the key has to be let go before it counts again.

clrall:         xor     a
                ld      (clrf), a
                ld      (clrb), a
                ld      (clru), a
                ld      (clrd), a
                ld      a, 1
                ret

; A run that has run out of floor or hit a wall skids to a halt.

; FACEJSTK.  POP keeps the stick and the fresh press flags as if he faced
; left, and turns them into his own terms for the length of GENCTRL only.  It
; is a swap, so the one routine does both ways.  Without it a key held through
; a turn reads as a new press the moment he faces the other way, and he sets
; off running on his own.

facejstk:       ld      a, (facing)
                or      a
                ret     z               ; facing left: stored as it is
                ld      a, (jstkx)
                neg
                ld      (jstkx), a
                ld      a, (clrf)
                ld      b, a
                ld      a, (clrb)
                ld      (clrf), a
                ld      a, b
                ld      (clrb), a
                ret

input_step:     call    read_input
                call    facejstk
                call    ctrl_all
                jp      facejstk

ctrl_all:       ld      a, (blocked)
                or      a
                jr      z, ctrl
                ld      a, (frame)
                cp      7
                jr      z, tostopnow
                cp      11
                jp      nz, ctrl
tostopnow:      ld      a, SQ_RUNSTOP
                jp      jumpseq

; GENCTRL.  Falling and being bumped are not under control; otherwise what he
; does next depends on what he is doing now, which CTRL.S reads off CharPosn,
; the frame he was last drawn in.

ctrl:           ld      a, (charact)
                cp      5               ; mid-bump
                jr      z, ctrlclr
                cp      4               ; or falling: not under control, and
                jr      nz, ctrlon      ; forget whatever was pressed
ctrlclr:        jp      clrall

ctrlon:         ld      a, (frame)
                cp      15
                jp      z, standing
                cp      48
                jp      z, turning
                cp      50
                jp      c, ctrl0
                cp      53
                jp      c, standing     ; turn 7-8-9 and the crouch
ctrl0:          cp      4
                jp      c, starting     ; run 4-5-6
                cp      67              ; 6502 carry is the other way round:
                jp      c, ctrl4        ; bcc means below, which is jr c here
                cp      70
                jp      c, stjumpup
ctrl4:          cp      15
                jp      c, running      ; run 8-17
                cp      87
                jp      c, ctrl1
                cp      100
                jp      c, hanging      ; hanging, and swinging on the ledge
ctrl1:          cp      109
                jp      z, crouching
                ret

; ------------------------------------------------------------------ standing

standing:       ld      a, (btn)
                or      a
                jp      z, stnobtn

                ld      a, (clrb)       ; button down
                or      a
                jp      m, do_turn
                ld      a, (clru)
                or      a
                jp      m, do_up
                ld      a, (clrd)
                or      a
                jp      m, do_down
                ld      a, (jstkx)
                or      a
                ret     p
                ld      a, (clrf)
                or      a
                ret     p
                jp      do_stepfwd

stnobtn:        ld      a, (clrf)       ; button up
                or      a
                jp      m, do_startrun
                ld      a, (clrb)
                or      a
                jp      m, do_turn
                ld      a, (clru)
                or      a
                jp      m, do_up
                ld      a, (clrd)
                or      a
                jp      m, do_down
                ld      a, (jstkx)      ; or simply held forward
                or      a
                ret     p
                jp      do_startrun

; No point starting a run into a wall, or he twitches on the spot.

; DoStartrun.  Very close to a barrier it becomes a careful step instead,
; and it clears no flag of its own.

do_startrun:    call    get_fwd_dist
                ld      b, a
                ld      a, (fwdkind)
                cp      1               ; a barrier ahead?
                jr      nz, srgo
                ld      a, b
                cp      8
                jr      nc, srgo
                ld      a, (clrf)
                or      a
                ret     p
                jp      do_stepfwd
srgo:           ld      a, SQ_STARTRUN
                jp      jumpseq

do_turn:        call    clrall
                ld      (clrb), a
                ld      a, SQ_TURN
                jp      jumpseq

; ------------------------------------------------------------------ turning

turning:        ld      a, (btn)
                or      a
                ret     nz
                ld      a, (jstkx)
                or      a
                ret     p               ; not still pushed forward
                ld      a, (jstky)
                or      a
                ret     m
                ld      a, SQ_TURNRUN   ; make it a running turn
                jp      jumpseq

; ------------------------------------------------------------------ running

; The first frames of a run.  Up with the stick still forward turns it into a
; standing jump -- which is how pressing both at once comes out as one: the
; forward press wins in `standing` and starts the run, and this catches it
; three frames later.  DoStandjump, not DoRunjump: that is what CTRL.S says.

starting:       ld      a, (jstky)
                or      a
                ret     p
                ld      a, (jstkx)
                or      a
                ret     p
                jp      do_standjump

running:        ld      a, (jstkx)
                or      a
                jr      z, runstop
                jp      p, runturn

                ld      a, (jstky)      ; forward: keep running
                or      a
                jp      m, runjumpq
                ld      a, (clrd)
                or      a
                ret     p
                ld      a, SQ_RDIVEROLL ; down: dive and roll
                jp      jumpseq

runjumpq:       ld      a, (clru)
                or      a
                ret     p
                jp      do_runjump

runstop:        ld      a, (frame)      ; only on run-10 and run-14
                cp      7
                jr      z, runstop1
                cp      11
                ret     nz
runstop1:       call    clrall
                ld      (clrf), a
                ld      a, SQ_RUNSTOP
                jp      jumpseq

runturn:        call    clrall
                ld      (clrb), a
                ld      a, SQ_RUNTURN
                jp      jumpseq

; ------------------------------------------------------------------ hanging

hanging:        ld      a, (jstky)
                or      a
                jp      m, hangup       ; up: climb
                ld      a, (btn)
                or      a
                jr      z, hangdrop     ; let go of the button, let go of the
                                        ; ledge
                ld      a, (charact)    ; hanging on the side of a block is
                cp      6               ; hanging straight
                ret     z
                call    under_flags     ; hanging on the side of a block
                cp      BLK_BLOCK
                ret     nz
                ld      a, SQ_HANGSTRAIGHT
                jp      jumpseq

; :climbup in CTRL.S reads the block above but only to refuse a mirror, a
; slicer or a gate that is not open far enough.  There is no "is there floor
; up there" test -- he is holding the ledge, so there is.

hangup:         call    clrall
                ld      (clru), a
                ld      a, SQ_CLIMBUP
                jp      jumpseq

hangdrop:       call    clrall
                ld      (clrd), a
                ld      a, SQ_HANGDROP
                jp      jumpseq

; ------------------------------------------------------------------ crouching

crouching:      ld      a, (jstky)      ; still holding down?
                cp      1
                jr      z, crawlmaybe
                ld      a, SQ_STANDUP
                jp      jumpseq
crawlmaybe:     ld      a, (clrf)
                or      a
                ret     p
                call    clrall
                ld      (clrf), a
                ld      a, SQ_CRAWL
                jp      jumpseq

; --------------------------------------------------------------- jumping up
;
; DoJumpup.  A ledge overhead within reach is worth grabbing; up with the
; stick pushed forward is a standing jump instead; otherwise he jumps on the
; spot.  POP also tries a step back first, which comes later.

; The first frames of a jump up.  Forward now -- held or freshly pressed --
; makes it a standing jump instead, which is the other way round of pressing
; the two keys: up first, then the direction.

stjumpup:       ld      a, (jstkx)
                or      a
                jp      m, do_standjump
                ld      a, (clrf)
                or      a
                jp      m, do_standjump
                ret

; CHECKLEDGE.  In: A = the block to hold on to, C = the one that has to be
; clear above him.  Out: NZ if he can grab it.

check_ledge:    ld      b, a
                ld      a, (blockid)
                cp      BLK_BLOCK
                jr      z, clno
                call    cmp_space
                jr      nz, clno        ; not clear over his head
                ld      a, b
                jp      cmp_space       ; and the ledge has to be solid
clno:           xor     a
                ret

; DoJumpup.  A ledge above and in front is grabbed where he stands; failing
; that, POP asks whether he could reach the one directly overhead from a step
; back, and takes the step.  That second question was missing here, and it is
; the one that gets him back up the way he came down.

do_up:          call    clrall
                ld      (clru), a
                ld      a, (jstkx)
                or      a
                jp      m, do_standjump

                call    above_flags     ; must be clear over his head
                ld      (blockid), a
                call    abovefront_flags
                call    check_ledge
                jp      nz, do_jumphang

                call    abovebehind_flags
                ld      (blockid), a
                call    above_flags
                call    check_ledge
                jr      z, jumphigh

                call    get_dist        ; step back and take that one
                cp      JUMP_BACK_THRES
                jr      c, jumphigh     ; too far to fudge
                call    behind_flags
                call    cmp_space
                jr      z, do_jumpedge  ; no floor behind: jump backwards
                call    get_dist
                sub     14
                call    move_by
                jp      do_jumphang

; His back is to the ledge, so he jumps backwards on to it.

do_jumpedge:    call    get_dist
                sub     10
                call    move_by
                ld      a, SQ_JUMPBACKHANG
                jp      jumpseq

; DoJumphang.  Which of the two reaches the ledge best, and then his X is
; fudged so it comes out exactly -- without that he grabs on with the empty
; block still counting as his own, and cannot pull up onto anything.

do_jumphang:    call    get_dist
                ld      (atemp), a
                cp      4
                jr      c, jhmed
jhlong:         ld      a, (atemp)
                sub     4               ; Long adds four of its own
                call    move_by
                ld      a, SQ_JUMPHANGLONG
                jp      jumpseq
jhmed:          call    get_fwd_dist
                cp      4
                jr      c, jhlong       ; too close to the wall for Med
                ld      a, (atemp)
                call    move_by
                ld      a, SQ_JUMPHANGMED
                jp      jumpseq

jumphigh:       ld      a, SQ_HIGHJUMP
                jp      jumpseq

; DoStandjump marks both presses used and clears nothing else -- the
; direction is very likely still held, and a fresh clrF on landing would set
; him running.

do_standjump:   ld      a, 1
                ld      (clru), a
                ld      (clrf), a
                ld      a, SQ_STANDJUMP
                jp      jumpseq

do_runjump:     call    clrall
                ld      (clru), a
                ld      a, SQ_RUNJUMP
                jp      jumpseq

; ------------------------------------------------------------------ down
;
; Facing a cliff and close to it, he steps off it; with his BACK to one and
; close to that, he lowers himself over it; otherwise he crouches.  Straight
; out of CTRL.S, and the way round it goes matters: you climb down backwards,
; holding the ledge you were standing on.

do_down:        ld      a, 1            ; :down sets clrD and nothing else
                ld      (clrd), a
                call    front_flags
                call    cmp_space
                jr      nz, downback    ; no cliff in front of him
                call    get_dist
                cp      STEP_OFF_FWD
                jr      nc, downback    ; not close enough to the edge
                ld      a, 5            ; step off it; the fall follows
                jp      move_by

downback:       call    behind_flags
                call    cmp_space
                jr      nz, do_crouch   ; no cliff behind him either
                call    get_dist
                cp      STEP_OFF_BACK
                jr      c, do_crouch    ; not backed up to the edge
                call    under_flags     ; and there has to be a ledge to hold
                call    cmp_space
                jr      z, do_crouch
                call    get_dist        ; line him up with it
                sub     9
                call    move_by
                ld      a, SQ_CLIMBDOWN
                jp      jumpseq

do_crouch:      ld      a, SQ_STOOP
                call    jumpseq
                call    clrall
                ld      (clrd), a
                ret

; ------------------------------------------------------------ careful step
;
; GETFWDDIST in COLL.S: how far he may safely go forward.  A wall or a drop
; ahead means as far as the edge of his own block and no further; anything he
; can walk on means a whole one.

; Out: A = how far he may go, and fwdkind = what he is stepping up to:
; 0 an edge, 1 a barrier, 2 clear ground, as GETFWDDIST reports in X.

get_fwd_dist:   call    front_flags
                ld      c, a
                call    cmp_barr
                jr      z, fwdnobarr
                ld      a, 1
                ld      (fwdkind), a
                jp      get_dist
fwdnobarr:      ld      a, c
                call    cmp_space
                jr      nz, fwdclear
                xor     a               ; an edge
                ld      (fwdkind), a
                jp      get_dist
fwdclear:       ld      a, 2
                ld      (fwdkind), a
                ld      a, 14
                ret

; POP keeps fourteen step sequences so that a step always ends where it
; should: against the wall, or with his toes exactly on the edge.

do_stepfwd:     ld      a, 1
                ld      (clrf), a
                ld      (clrbtn), a
                call    get_fwd_dist
                or      a
                jr      z, steptest     ; nothing left to step: test his foot
                dec     a
                add     a, SQ_STEP1
                jp      jumpseq
steptest:       ld      a, SQ_TESTFOOT
                jp      jumpseq

; ---------------------------------------------------------------- sequence
;
; ANIMCHAR out of COLL.S: read the byte code until a frame number comes out,
; which is this game frame's picture.  Everything under 0xF1 is a frame; the
; fifteen values above it are the instructions, exactly as SEQDATA.S numbers
; them.  A chx written beside a frame therefore belongs to the step OUT of it
; -- the reader stops on the frame and picks the chx up next time round.

SEQ_GOTO        equ     0xFF
SEQ_FACE        equ     0xFE
SEQ_UP          equ     0xFD
SEQ_DOWN        equ     0xFC
SEQ_CHX         equ     0xFB
SEQ_CHY         equ     0xFA
SEQ_ACT         equ     0xF9
SEQ_SETFALL     equ     0xF8
SEQ_IFWTLESS    equ     0xF7
SEQ_EFFECT      equ     0xF3
SEQ_TAP         equ     0xF2
SEQ_FIRSTOP     equ     0xF1

; A = one of POP's sequence numbers.  Start it.

jumpseq:        ld      l, a
                ld      h, 0
                add     hl, hl
                ld      de, seqtab
                add     hl, de
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
seqbase:        ld      hl, seqs        ; the table holds offsets, not
                add     hl, de          ; addresses, so nothing has to be
                ld      (seqptr), hl    ; relocated at startup
                ret

step_seq:       ld      hl, (seqptr)
seqloop:        ld      a, (hl)
                inc     hl
                cp      SEQ_FIRSTOP
                jr      c, seqframe

                cp      SEQ_GOTO
                jr      z, sqgoto
                cp      SEQ_FACE
                jr      z, sqface
                cp      SEQ_UP
                jr      z, sqrowup
                cp      SEQ_DOWN
                jr      z, sqrowdn
                cp      SEQ_CHX
                jr      z, sqchx
                cp      SEQ_CHY
                jr      z, sqchy
                cp      SEQ_ACT
                jr      z, sqact
                cp      SEQ_SETFALL
                jr      z, sqsetfall
                cp      SEQ_IFWTLESS
                jr      z, sqskip2
                cp      SEQ_EFFECT
                jr      z, sqskip1
                cp      SEQ_TAP
                jr      z, sqskip1
                jr      seqloop         ; die, jaru, jard, nextlevel: no data

seqframe:       ld      (frame), a
                ld      (seqptr), hl
                ret

sqgoto:         ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ld      hl, seqs
                add     hl, de
                jr      seqloop

sqface:         push    hl
                ld      a, (facing)
                xor     1
                ld      (facing), a
                pop     hl
                jr      seqloop

sqrowup:        push    hl
                ld      hl, blocky
                dec     (hl)
                call    set_row
                pop     hl
                jr      seqloop

sqrowdn:        push    hl
                ld      hl, blocky
                inc     (hl)
                call    set_row
                pop     hl
                jr      seqloop

sqchx:          ld      a, (hl)
                inc     hl
                push    hl
                call    move_by
                pop     hl
                jr      seqloop

sqchy:          ld      a, (hl)
                inc     hl
                push    hl
                ld      hl, chary
                add     a, (hl)
                ld      (hl), a
                pop     hl
                jr      seqloop

sqact:          ld      a, (hl)
                inc     hl
                ld      (charact), a
                jp      seqloop

sqsetfall:      inc     hl              ; the X velocity, which we do not use
                ld      a, (hl)
                inc     hl
                ld      (yvel), a
                jp      seqloop

sqskip2:        inc     hl              ; ifwtless: never weightless here
sqskip1:        inc     hl
                jp      seqloop

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
; ADDCHARX, and nothing more.  A chx in the byte code just moves him: POP
; does not test anything here, and neither may we -- climbup steps five units
; forward while his own block is still the wall he is climbing, and a test in
; the middle of the sequence refuses that and leaves him hanging in the air.
; Collisions are a pass of their own, below.

movestore:      ld      a, l
                ld      (charx), a
                ret

; CHECKBARR: having moved, he may be standing in a wall.  Push him back out
; the way he came, a pixel at a time, and say he was blocked -- which is what
; turns a run into a skid.

; CHECKBARR begins by naming the states a character is collision proof in --
; turning, in POP's case.  Ours needs more of them: hanging, his coordinate is
; over the wall he is holding on to, and in the air it may be over anything.
; Pushing him out of those is how he ends up back where he jumped from.

; COLLISIONS opens by naming the situations a character is let through a
; barrier in: hanging, either kind, and the frames of a climb.  Exactly that
; list, and nothing of mine.

check_barr:     ld      a, (charact)
                cp      2               ; hanging
                ret     z
                cp      6
                ret     z
                ld      a, (frame)
                cp      135
                jr      c, cbgo
                cp      149
                ret     c               ; climbing
cbgo:           xor     a
                ld      (blocked), a
                ld      b, 32           ; he cannot be deeper in than this
cbtry:          ld      a, (charx)      ; his own coordinate, not his foot:
                call    tile_flags      ; the wall stops his body
                call    cmp_barr
                ret     z
                ld      a, 1
                ld      (blocked), a
                ld      a, (facing)
                or      a
                ld      a, (charx)
                jr      z, cbback
                dec     a               ; facing right: back is left
                jr      cbset
cbback:         inc     a
cbset:          ld      (charx), a
                djnz    cbtry
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
                ld      de, (tilerow)   ; the row he stands on
                add     hl, de
                ld      a, (hl)
                ret
tilenone:       xor     a
                ret

; CMPSPACE and CMPBARR out of CTRLSUBS.S, as the tables they may as well be.
; In: A = a block type.  cmp_space: Z when the block is clear -- and a solid
; block counts as clear here, which is why onground has a case of its own for
; it.  cmp_barr: Z when nothing is in the way, else the barrier's code.

cmp_space:      ld      l, a
                ld      h, 0
                ld      de, cmpspace
                add     hl, de
                ld      a, (hl)
                or      a
                ret

cmp_barr:       ld      l, a
                ld      h, 0
                ld      de, cmpbarr
                add     hl, de
                ld      a, (hl)
                or      a
                ret

; In: A = a screen x, C = a block row.  Out: A = that tile's flags.  The row
; is free here, which tile_flags cannot afford -- it runs inside movetry.

tile_in_row:    ld      l, a
                ld      h, 0
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
                ld      de, tiles
                add     hl, de
                ld      a, (hl)
                ret

; Ten tiles to a block row.  Worked out only when the row changes, so that
; tile_flags stays short and leaves C alone for movetry.

set_row:        ld      a, (blocky)
                ld      l, a
                ld      h, 0
                add     hl, hl          ; two
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl          ; eight
                add     hl, de          ; ten
                ld      de, tiles
                add     hl, de
                ld      (tilerow), hl
                ret

; ---------------------------------------------------------------- crop
;
; CROPCHAR in CTRLSUBS.S -- the half of it that keeps a character out of the
; floor above.  Drawn plainly he is laid over the finished room and shows
; through anything higher up; POP cuts his picture off at the top of his own
; block row instead, and the floor is left covering him.
;
; It crops only when both the blocks his picture reaches into up there are
; solid, and when he has got no further into them than a floor is thick.
; Beyond that he is climbing into the room above for real, and cutting him
; off would take his head with it.

crop_char:      xor     a
                ld      (charcu), a

                ld      a, (newtop)     ; topej -- the row his picture starts
                call    get_blocky
                ld      (croprow), a

                ld      a, (croprow)
                ld      c, a
                ld      a, (curleft)
                call    tile_in_row
                call    crop_solid
                ret     z               ; open over his left: leave him be

                ld      a, (charact)    ; CROPCHAR is more lenient about a
                or      a               ; character jumping up to touch the
                jr      nz, cropboth    ; ceiling: his left block is enough
                ld      a, (frame)
                cp      79
                jr      z, cropyes
                cp      81
                jr      z, cropyes

cropboth:       ld      a, (croprow)
                ld      c, a
                ld      a, (curleft)    ; and the block over his right
                ld      b, a
                ld      a, (curw)
                add     a, a
                add     a, a
                add     a, a
                add     a, b
                jr      c, cropwide     ; his picture runs off the screen
                dec     a
                jr      cropright
cropwide:       ld      a, 255
cropright:      call    tile_in_row
                call    crop_solid
                ret     z

cropyes:        ld      a, (blocky)     ; BlockTop of his own row
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, blocktop
                add     hl, de
                ld      a, (hl)
                ld      (croptop), a
                ld      a, (blocky)
                or      a
                jr      z, cropset      ; the top row is cut at the screen

                ld      a, (croptop)    ; the floor has to be above his feet
                ld      hl, fchary
                cp      (hl)
                ret     nc
                ld      a, (croptop)    ; and he no further than a floor into
                sub     FLOOR_HEIGHT    ; it
                ld      hl, newtop
                cp      (hl)
                ret     nc

cropset:        ld      a, (croptop)
                ld      (charcu), a
                ret

; In: A = a block type.  Out: Z when it is open -- the test CROPCHAR makes,
; where a solid block counts as solid rather than as the space cmp_space
; calls it.

crop_solid:     cp      BLK_BLOCK
                jr      z, cropsolid1
                jp      cmp_space
cropsolid1:     or      a
                ret

; GETBLOCKY in CTRLSUBS.S.  In: A = a scanline.  Out: A = the block row it
; falls in, 3 below the room and -1 above it.

get_blocky:     ld      c, a
                ld      b, 3
                ld      hl, blocktop + 4
gby:            ld      a, c
                cp      (hl)
                jr      nc, gbyhit
                dec     hl
                djnz    gby
                ld      a, c
                cp      (hl)
                jr      nc, gbytop
                ld      a, 0xff
                ret
gbytop:         xor     a
                ret
gbyhit:         ld      a, b
                ret

; GETBASEX in CTRLSUBS.S: the point POP measures everything from.  Not his
; coordinate but where his weight is -- the frame's own Fdx, less the footmark
; in the low bits of its Fcheck, applied the way he faces.

base_x:         ld      a, (frame)
                ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, l
                ld      bc, fcheck
                add     hl, bc
                ld      a, (hl)
                and     F_FOOTMARK
                ld      b, a
                ld      hl, fdx
                add     hl, de
                ld      a, (hl)
                sub     b               ; Fdx - footmark, in logic units
                add     a, a            ; two screen pixels to the unit
                ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      nz, bxfwd
                neg
bxfwd:          ld      b, a
                ld      a, (charx)
                add     a, b
                ret

; Out: A = the flags of the tile he is standing on.

under_flags:    call    base_x
                jp      tile_flags

; Out: A = the flags of the block one along, the way he faces or the way he
; came -- GETINFRONT and GETBEHIND.  Off the map reads as space, which is
; what it looks like.

front_flags:    ld      a, (facing)
                or      a
                jr      z, ffback
fffwd:          call    base_x
                add     a, BLOCK_PX
                jr      c, ffnone
                jp      tile_flags
ffback:         call    base_x
                sub     BLOCK_PX
                jr      c, ffnone
                jp      tile_flags
ffnone:         xor     a
                ret

behind_flags:   ld      a, (facing)
                or      a
                jr      z, fffwd
                jr      ffback

; GETABOVE and GETABOVEINF: the same, a block row higher.

above_flags:    call    base_x
                jr      arow
abovebehind_flags:
                call    base_x
                ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      nz, afleft      ; behind is the other way round
                jr      afright

abovefront_flags:
                call    base_x
                ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      z, afleft
afright:
                add     a, BLOCK_PX
                jr      c, ffnone
                jr      arow
afleft:         sub     BLOCK_PX
                jr      c, ffnone
arow:           ld      b, a
                ld      a, (blocky)
                or      a
                jr      z, ffnone       ; nothing above the top row
                dec     a
                ld      c, a
                ld      a, b
                jp      tile_in_row

; InsideBlock in CTRL.S.  A solid block reads as clear to cmpspace, so a
; character who ends up over one would drop straight through it.  This bumps
; him out to whichever side he can go and hands back what is under him then.

inside_block:   call    get_dist
                cp      8
                jr      nc, ibback
                call    front_flags
                cp      BLK_BLOCK
                jr      z, ibback
                call    get_dist
                add     a, 4
                jr      ibreland
ibback:         call    behind_flags
                cp      BLK_BLOCK
                jr      z, ibstuck
                call    get_dist
                cpl
                add     a, 8
                jr      ibreland
ibstuck:        call    get_dist        ; both sides blocked: two back
                add     a, 14
                cpl
                add     a, 8
ibreland:       call    move_by
                jp      under_flags

; GETDIST: how far he is from the edge of his own block, in POP's units of
; two pixels, measured the way he faces.  Standing in the middle of a block
; is offset 7, so seven units to the edge behind and six to the one ahead.

get_dist:       call    base_x
                ld      l, a
                ld      h, 0
                ld      de, distof
                add     hl, de
                ld      b, (hl)
                ld      a, (facing)
                or      a
                ld      a, b
                ret     z
                ld      a, 13
                sub     b
                ret

; Out: A = FloorY for the row below his feet -- the plane he lands on.

floor_plane:    ld      a, (blocky)
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, floory
                add     hl, de
                ld      a, (hl)
                ret

; ---------------------------------------------------------------- falling
;
; CHECKFLOOR in CTRL.S: with nothing underfoot he goes over the edge.  POP
; counts CharBlockY as the floor just below his feet while he is in the air,
; so it steps down here and again each time he passes a floor plane.

check_floor:    ld      a, (charact)
                cp      2               ; hanging
                ret     z
                cp      6               ; hanging straight
                ret     z
                cp      3               ; in the air already
                ret     z
                cp      4
                ret     z
                ld      a, (frame)      ; does this frame look for floor?
                ld      l, a
                ld      h, 0
                ld      de, fcheck
                add     hl, de
                ld      a, (hl)
                and     F_CHECK
                ret     z
                call    under_flags
                cp      BLK_BLOCK       ; inside a block: bump him out first
                jr      nz, cfspace
                call    inside_block
cfspace:        call    cmp_space       ; solid: he stays where he is
                ret     nz
                ld      hl, blocky
                inc     (hl)
                call    set_row
                ld      a, 3
                ld      (charact), a
                xor     a
                ld      (yvel), a
                ld      a, SQ_STEPFALL
                jp      jumpseq

; GRAVITY and ADDFALL, then the floor plane test of `falling`.  stepfall
; carries its own chy for the first four frames and gravity only takes over
; at the setfall, which is why the velocity is left alone until then.

do_fall:        ld      a, (charact)
                cp      4               ; only a free fall has weight: the
                ret     nz              ; four frames of stepfall carry their
                ld      a, (yvel)       ; own chy, and climbing none at all
                add     a, ACCEL_G
                cp      TERM_VEL + 1
                jr      c, fallvel
                ld      a, TERM_VEL
fallvel:        ld      (yvel), a
                ld      b, a
                ld      a, (chary)
                add     a, b
                ld      (chary), a
fallplane:      call    floor_plane
                ld      b, a
                ld      a, (chary)
                cp      b
                ret     c               ; not down to the plane yet
                call    under_flags
                cp      BLK_BLOCK
                jr      nz, dfspace
                call    inside_block
dfspace:        call    cmp_space
                jr      nz, hit_floor
                ld      hl, blocky      ; straight through, keep going
                ld      a, (hl)
                cp      3
                ret     nc              ; nothing below the bottom row
                inc     (hl)
                jp      set_row

hit_floor:      call    floor_plane
                ld      (chary), a
                xor     a
                ld      (yvel), a
                ld      a, 1
                ld      (charact), a
                ld      a, SQ_SOFTLAND
                jp      jumpseq

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
                ld      a, d            ; the top two bits are the bank
                rlca
                rlca
                and     3
                ld      (curbank), a
                ld      a, d
                and     0x3f
                ld      d, a
                ld      hl, sprblob
                add     hl, de
                ld      (curdat), hl

; The anchor is the leading edge, so the offset differs with facing and is
; kept with the sprite rather than worked out here.

                ld      a, (charx)
                ld      b, a
                ld      a, (curoff)
                add     a, b
                ld      b, a
                ld      (curleft), a    ; CROPCHAR wants the picture's edges
                and     7
                ld      (curshift), a
                ld      a, b
                rra
                rra
                rra
                and     31
                ld      b, a            ; the room's byte column; the camera
                ld      a, (cam)        ; says where that is on screen
                neg
                add     a, b
                ld      (newcol), a

; SETUPCHAR: the picture sits at CharY + Fdy, not at CharY.  Every frame of a
; sequence has its own, and that is what carries him up and down within it.

                ld      a, (frame)
                ld      l, a
                ld      h, 0
                ld      de, fdy
                add     hl, de
                ld      a, (chary)
                add     a, (hl)
                ld      (fchary), a
                ld      b, a            ; top row = that, less the height
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
                call    crop_char
                call    erase_new

; Only now: everything above reads the room and the tables, and the sprite's
; bank goes over the top of the room.

                call    page_frame

                ld      a, (newh)       ; the calls above have had A
                ld      b, a
                ld      hl, (curdat)
                ld      a, (newtop)
                ld      (rowy), a

                ld      a, (newcol)
                ld      (linecol), a
                call    startrows
drawrow:        push    bc
                call    build_row       ; HL walks over the source row
                push    hl
                ld      a, (rowy)
                cp      192
                jr      nc, drawblank
                ld      c, a
                ld      a, (charcu)     ; cut off by the floor above?
                cp      c
                jr      c, drawgo
                jr      z, drawgo
                call    line_addr       ; above the cut, but the row still
                jr      drawskip        ; counts towards where the next one is
drawblank:      call    startrows
                jr      drawskip
drawgo:         call    line_addr
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

; QUICKFLOOR in CTRLSUBS.S, with DRAWFLOOR and DRAWHALF out of FRAMEADV.S.
;
; A character who is falling, hanging or climbing reaches up into the floor
; above him, and POP marks those floorpieces so that they are laid down again
; after he has been drawn.  What they cover is not a rectangle: the floor's
; near edge is drawn in perspective, so the piece is a wedge, and without it
; he shows through the triangle at the end of the tile.
;
; Climbing up has its own, shorter wedge -- DRAWHALF -- which leaves the
; hands he has on the ledge showing.  Standing and running mark nothing, so
; his own floor never covers his feet.
;
; Out: HL = the mask to lay down, or zero.

quickfloor:     ld      hl, halfmask
                ld      a, (frame)      ; the climbup frames
                cp      135
                jr      c, qfact
                cp      149
                ret     c
qfact:          ld      hl, floormask
                ld      a, (charact)
                cp      1
                jr      nz, qfair
                ld      a, (frame)      ; on the ground, only the two frames
                cp      78              ; of stepping off an edge
                jr      c, qfnone
                cp      80
                ret     c
                jr      qfnone
qfair:          cp      2               ; hanging, in the air, free fall,
                ret     z               ; hanging straight
                cp      3
                ret     z
                cp      4
                ret     z
                cp      6
                ret     z
qfnone:         ld      hl, 0
                ret

hide_floor:     call    quickfloor
                ld      a, h
                or      l
                ret     z
                ld      (coverm), hl
                ld      hl, floorband
                ld      (coverb), hl
                jp      cover_rows

; Put the foreground back over the prince.  The mask carries only the rows a
; front piece reaches; foreband says which row of it a scanline is, or -1.

hide_behind:    ld      hl, foremask
                ld      (coverm), hl
                ld      hl, foreband
                ld      (coverb), hl

; Walk the sprite's rows and lay the mask's own pixels back over him.  Three
; things line up on each row: the mask, the room the mask picks out of, and
; the working copy he was drawn into.

cover_rows:     ld      a, (newcol)
                call    mastercol
                ld      (masterc), a
                ld      a, (newh)
                ld      b, a
                ld      a, (newcol)
                ld      (linecol), a
                ld      a, (newtop)
                ld      (rowy), a
                call    startrows
coverrow:       push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, coverblank
                call    room_addr       ; both walk on whatever the mask says
                push    hl
                call    line_addr
                ld      a, (rowy)
                ld      l, a
                ld      h, 0
                ld      de, (coverb)
                add     hl, de
                ld      a, (hl)
                inc     a
                jr      z, coverpop     ; the mask has nothing on this row
                dec     a
                call    mul35
                ld      de, (coverm)
                add     hl, de
                ld      a, (masterc)
                ld      e, a
                ld      d, 0
                add     hl, de
                push    hl              ; the mask's row
                ld      hl, (rowptr)
                ld      de, work - SCREEN
                add     hl, de
                ld      (workp), hl     ; the working copy
                pop     hl              ; the mask
                pop     de              ; the room
                ld      a, (neww)
                ld      b, a
                call    cover_apply
                jr      covernxt
coverpop:       pop     hl
                jr      covernxt
coverblank:     call    startrows
covernxt:       ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    coverrow
                ret

; In: HL = mask, DE = room, (workp) = working copy, B = bytes.

cover_apply:    ld      a, (hl)
                or      a
                jr      z, covernext
                ld      c, a
                push    hl
                ld      hl, (workp)
                cpl
                and     (hl)            ; what the prince may keep
                ld      (hl), a
                ld      a, (de)
                and     c               ; and the piece's own pixels
                or      (hl)
                ld      (hl), a
                pop     hl
covernext:      inc     hl
                inc     de
                push    hl
                ld      hl, workp       ; a screen row never crosses a page
                inc     (hl)
                pop     hl
                djnz    cover_apply
                ret

; ---------------------------------------------------------------- erase
;
; Put the room back over where the sprite was, in the working copy.

erase_prince:   ld      hl, oldcol
                jr      eraseset

; The view has moved, so the room under where he is about to be drawn is a
; byte out.  The erase has already put back where he was; this does where he
; is going, and between them the working copy is right everywhere the screen
; is about to read it.

erase_new:      ld      a, (camstep)
                or      a
                ret     z
                xor     a
                ld      (camstep), a
                ld      hl, newcol

eraseset:       ld      de, ercol       ; col, top, width, height, in order
                ld      bc, 4
                ldir

                ld      a, (erw)
                or      a
                ret     z
                ld      a, (ercol)      ; mastercol has B, so it goes first
                call    mastercol
                ld      (masterc), a
                ld      a, (ertop)
                ld      (rowy), a
                ld      a, (erh)
                ld      b, a
                ld      a, (ercol)
                ld      (linecol), a
                call    startrows
eraserow:       push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, eraseskip
                call    room_addr
                push    hl
                call    line_addr
                ld      de, work - SCREEN
                add     hl, de
                ex      de, hl
                pop     hl              ; HL = room, DE = working copy
                ld      a, (erw)
                ld      c, a
                ld      b, 0
                ldir
                jr      erasenext
eraseskip:      call    startrows       ; off the screen: begin again below it
erasenext:      ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    eraserow
                ret

startrows:      ld      hl, 0
                ld      (rowptr), hl
                ld      (roomp), hl
                ret

; Four passes a frame walk the same rows, and each of them was working out
; a screen address from scratch for every one.  A scanline down is a short
; step from the one above -- the third's line number lives in the high byte
; and only overflows every eighth row -- so the address is worked out once
; and walked after that.  The room's rows are simply thirty five bytes apart.
;
; (rowptr) is the screen address of the row in hand, or zero for "not yet".
; A row off the screen puts it back to zero, so the next one on starts again.

nextline:       inc     h               ; the next line within the third
                ld      a, h
                and     7
                ret     nz
                ld      a, l            ; every eighth, the next row of it
                add     a, 32
                ld      l, a
                ret     c
                ld      a, h            ; and every eighth of those, the
                sub     8               ; next third, which the carry gave
                ld      h, a
                ret

; In: (rowy), (linecol).  Out: HL = the screen address of that row.

line_addr:      ld      hl, (rowptr)
                ld      a, h
                or      l
                jr      z, lafirst
                call    nextline
                ld      (rowptr), hl
                ret
lafirst:        ld      a, (linecol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      (rowptr), hl
                ret

; The same for the room, whose rows are plain.  In: (masterc).

room_addr:      ld      hl, (roomp)
                ld      a, h
                or      l
                jr      z, rafirst
                ld      de, ROOM_BYTES
                add     hl, de
                ld      (roomp), hl
                ret
rafirst:        ld      a, (rowy)
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (masterc)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (roomp), hl
                ret

; A screen byte column, and which byte of the room the camera puts under it.

mastercol:      ld      b, a
                ld      a, (cam)
                add     a, b
                ret

; ---------------------------------------------------------------- show
;
; Copy the rectangle covering both the old and the new sprite from the
; working copy to the screen.  This is the only moment the screen changes.

; The view moved, so the whole screen is redrawn -- from the room itself,
; not from the working copy, which is only right where he has been.  His own
; rectangle follows out of the working copy, as always.

show_rect:      ld      a, (fullshow)
                or      a
                jr      z, showpart
                xor     a
                ld      (fullshow), a
                ld      (rowy), a
                call    roomwin
                ld      (roomp), hl
                ld      b, 192
fsrow:          push    bc
                ld      e, 0
                ld      a, (rowy)
                call    scraddr
                ex      de, hl
                ld      hl, (roomp)
                call    copy32
                call    nextrow
                pop     bc
                djnz    fsrow

; Two rectangles reach the screen, not the box around them: where he was and
; where he is.  The box would take in corners neither of them covers, and the
; working copy is only ever put right under the two.

showpart:       ld      a, (oldw)
                or      a
                jr      z, shownew
                ld      hl, oldcol
                call    show_one
shownew:        ld      hl, newcol

show_one:       ld      de, shcol       ; col, top, width, height, in order
                ld      bc, 4
                ldir

showgo:         ld      a, (shh)
                or      a
                ret     z
                ld      b, a
                ld      a, (shtop)
                ld      (rowy), a
                ld      a, (shcol)
                ld      (linecol), a
                call    startrows
showrow:        push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, showskip
                call    line_addr
                ld      d, h
                ld      e, l            ; DE = screen
                ld      bc, work - SCREEN
                add     hl, bc          ; HL = working copy
                ld      a, (shw)
                ld      c, a
                ld      b, 0
                ldir
                jr      shownext
showskip:       call    startrows
shownext:       ld      hl, rowy
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

; In: A = a scanline, E = a byte column.  Out: HL = the screen address.
; A table beats working the interleave out: four passes a frame ask for it.

scraddr:        push    bc
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      bc, rowaddr
                add     hl, bc
                ld      a, (hl)
                inc     hl
                ld      h, (hl)
                ld      l, a
                ld      a, e
                add     a, l
                ld      l, a
                pop     bc
                ret

; ---------------------------------------------------------------- data



charx:          db      0
chary:          db      0
facing:         db      0               ; 0 left, 1 right
frame:          db      0
seqptr:         dw      0
jstkx:          db      0
jstky:          db      0
btn:            db      0
clrf:           db      0
clrb:           db      0
clru:           db      0
clrd:           db      0
clrbtn:         db      0
atemp:          db      0
fwdkind:        db      0
blockid:        db      0
blocked:        db      0
blocky:         db      0
tilerow:        dw      0
charcu:         db      0               ; FCharCU, the row his picture is cut at
fchary:         db      0
curleft:        db      0
croprow:        db      0
croptop:        db      0
yvel:           db      0
charact:        db      1
wanted:         db      0

curw:           db      0
curh:           db      0
curoff:         db      0
curshift:       db      0
curdat:         dw      0
curbank:        db      0
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

cam:            db      0               ; the view's left edge, in bytes
fullshow:       db      0
masterc:        db      0
coverm:         dw      0
coverb:         dw      0
workp:          dw      0
roomp:          dw      0
rowptr:         dw      0
linecol:        db      0
camstep:        db      0
ercol:          db      0
ertop:          db      0
erw:            db      0
erh:            db      0
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
seqtab:         incbin  "seqtab.bin"
tiles:          incbin  "tiles.bin"
cmpspace:       incbin  "cmpspace.bin"
cmpbarr:        incbin  "cmpbarr.bin"
floory:         incbin  "floory.bin"
blocktop:       incbin  "blocktop.bin"
floorband:      incbin  "floorband.bin"
foreband:       incbin  "foreband.bin"
blockof:        incbin  "blockof.bin"
distof:         incbin  "distof.bin"
                ds      (($ + 255) / 256 * 256) - $
rowaddr:        incbin  "rowaddr.bin"
fcheck:         incbin  "fcheck.bin"
fdx:            incbin  "fdx.bin"
fdy:            incbin  "fdy.bin"
fill:           incbin  "fill.bin"
                ds      (($ + 255) / 256 * 256) - $
shifthi:        incbin  "shifthi.bin"
shiftlo:        incbin  "shiftlo.bin"
revtab:         incbin  "revtab.bin"
sprites:        incbin  "sprtab.bin"        ; the pixels live in a bank
codeend:

; The tape carries one block, so both bank images ride along inside it.
;
; The room and its mask sit below the window and are copied into their bank at
; startup.  The sprites are put at 0xC000 itself, which means the tape drops
; them straight into whichever bank happens to be paged -- so they need no
; copying at all, only finding, which the signature at the end of them does.
;
; The working copy is never loaded, only written, so it goes over the room
; image once that has been moved out of the way.

; The working copy is never loaded, only written, so it lives past the end of
; the tape image rather than taking six kilobytes of loading time.  It mirrors
; the bitmap and not the attributes, which nothing here touches.

work            equ     codeend

                end     start
