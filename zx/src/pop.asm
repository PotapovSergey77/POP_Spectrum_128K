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
                ld      a, BANK_BG
                jr      dopage
                ld      a, BANK_CANVAS
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
                include "bg.inc"

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
; anchor between 28b+2 and 28b+29 -- so the room is 280 pixels wide and his
; coordinate does not fit in a byte.  POP keeps FCharX in two, and so must we:
; capping it at 255 stopped him a whole tile short of the right hand wall and
; forced the room to change before he had left the screen.
;
; Nothing but a wall should stop him inside the room; these are a backstop for
; a coordinate that has gone wrong, no more.  The cut fires well before them.
X_MIN           equ     -40
X_MAX           equ     320

; ---------------------------------------------------------------- entry

start:          di
                ld      sp, stack
                im      1

                xor     a
                out     (254), a

                call    check_banks     ; before anything is written, and it
                                        ; leaves the art bank in
                call    newroom         ; and the room is composed, not loaded
                call    readlinks

                call    set_attrs

                xor     a               ; the view starts at the room's left
                ld      (cam), a
                call    repaint


                ld      hl, START_X
                ld      (charx), hl
                ld      a, START_Y
                ld      (chary), a
                ld      a, START_ROW
                ld      (blocky), a
                xor     a
                ld      (yvel), a
                ld      (facing), a
                ld      (oldw), a       ; nothing to erase on the first pass
                ld      a, revtab / 256 ; the reversal table's page
                ld      (mrev1 + 1), a
                ld      (mrev2 + 1), a
                call    page_canvas     ; paging has A, so it goes first
                ld      a, SQ_STAND
                call    jumpseq
                call    page_art

                call    page_canvas
                call    step_seq
                call    page_art
                call    draw_prince
                call    page_art
                call    hide_floor
                call    hide_behind
                ei

; ---------------------------------------------------------------- main

; The screen is written the moment the interrupt returns, while the beam is
; still in the border above the room.  Everything else -- rubbing him out,
; reading the keys, running his sequence, drawing him -- happens afterwards,
; into the working copy, and reaches the screen at the top of the next frame.
; A frame's worth of lag, and nothing torn: the beam never catches the blit
; halfway through him.

main:           ld      b, FRAME_WAIT
mainwait:       halt
                djnz    mainwait

                call    page_art
                call    show_rect
                call    keep_rect

                call    camera
                call    erase_prince
                call    page_canvas     ; the sequences live there, and
                call    input_step      ; everything down to here starts one
                call    step_seq
                call    check_barr
                call    check_floor
                call    do_fall
                call    page_art
                call    nextroom        ; before anything reads his row again
                call    checkpress
                call    shakeloose
                call    animtrans
                call    draw_prince
                call    page_art
                call    hide_floor
                call    hide_behind
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
; room itself, and the only parts of the working copy anything reads are the
; two rectangles the erases put the room back under anyway.

camera:         ld      a, (cam)
                ld      b, a
                add     a, a
                add     a, a
                add     a, a
                ld      e, a            ; the view's left edge
                ld      d, 0
                ld      hl, (charx)
                or      a
                sbc     hl, de          ; where he stands on screen
                bit     7, h
                jr      nz, camback     ; off the left of it
                ld      a, h
                or      a
                jr      nz, camfwd      ; and off the right
                ld      a, l
                cp      160
                jr      nc, camfwd
                cp      96
                ret     nc
camback:        ld      a, b
                or      a
                ret     z
                dec     b
                jr      camset

; And on the way into a room, straight to the value it would settle at: he
; arrives at the far side of it, and a view that started over would be seen
; scrolling across to find him.

camhome:        ld      hl, (charx)
                ld      de, 128         ; the middle of the band the camera
                or      a               ; holds him in
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
                ret
camfwd:         ld      a, b
                cp      CAM_MAX
                ret     nc
                inc     b
camset:         ld      a, b
                ld      (cam), a
                ld      a, 1
                ld      (fullshow), a
                ret

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
pageset:        ld      (nowbank), a    ; so a lookup that has to borrow
                or      0x10            ; another bank can put this one back
                                        ; bit 4 keeps the 48K ROM, which is
                push    bc              ; what the handler at 0x38 is.  By now
                ld      bc, PAGEPORT    ; BASIC is gone and BANKM with it
                out     (c), a
                pop     bc
                ret

; [0] where the tape left the first bank of sprites, [1] the rest of them,
; [2] the room and its mask.
banktab:        db      BANK_SPR1, BANK_SPR2, BANK_SPR3
artbank:        db      BANK_ART
nowbank:        db      BANK_ART

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
SEQ_JARU        equ     0xF5
SEQ_JARD        equ     0xF4
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
                jp      z, sqchx
                cp      SEQ_CHY
                jp      z, sqchy
                cp      SEQ_ACT
                jp      z, sqact
                cp      SEQ_SETFALL
                jp      z, sqsetfall
                cp      SEQ_IFWTLESS
                jp      z, sqskip2
                cp      SEQ_JARU
                jp      z, sqjaru
                cp      SEQ_JARD
                jp      z, sqjard
                cp      SEQ_EFFECT
                jp      z, sqskip1
                cp      SEQ_TAP
                jp      z, sqskip1
                jp      seqloop         ; die and nextlevel: no data

seqframe:       ld      (frame), a
                ld      (seqptr), hl
                ret

sqgoto:         ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ld      hl, seqs
                add     hl, de
                jp      seqloop

sqface:         push    hl
                ld      a, (facing)
                xor     1
                ld      (facing), a
                pop     hl
                jp      seqloop

; A jump or a hard landing jars the floorboards -- jaru those in the row
; above him, jard those in his own.  TOPCTRL.S acts on it once a frame.

sqjaru:         ld      a, 1
                ld      (jarabove), a
                jp      seqloop
sqjard:         ld      a, 0xff
                ld      (jarabove), a
                jp      seqloop

sqrowup:        push    hl
                ld      hl, blocky
                dec     (hl)
                pop     hl
                jp      seqloop

sqrowdn:        push    hl
                ld      hl, blocky
                inc     (hl)
                pop     hl
                jp      seqloop

sqchx:          ld      a, (hl)
                inc     hl
                push    hl
                call    move_by
                pop     hl
                jp      seqloop

sqchy:          ld      a, (hl)
                inc     hl
                push    hl
                ld      hl, chary
                add     a, (hl)
                ld      (hl), a
                pop     hl
                jp      seqloop

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
moveadd:        ld      hl, (charx)
                add     hl, de
                push    hl              ; only a coordinate that has gone
                ld      de, X_MIN       ; wrong is caught here
                or      a
                sbc     hl, de
                pop     hl
                jp      p, movetop
                ld      hl, X_MIN
                jr      movestore
movetop:        push    hl
                ld      de, X_MAX
                or      a
                sbc     hl, de
                pop     hl
                jp      m, movestore
                ld      hl, X_MAX
; ADDCHARX, and nothing more.  A chx in the byte code just moves him: POP
; does not test anything here, and neither may we -- climbup steps five units
; forward while his own block is still the wall he is climbing, and a test in
; the middle of the sequence refuses that and leaves him hanging in the air.
; Collisions are a pass of their own, below.

movestore:      ld      (charx), hl
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
cbtry:          ld      hl, (charx)     ; his own coordinate, not his foot:
                call    tile_flags      ; the wall stops his body
                call    cmp_barr
                ret     z
                ld      a, 1
                ld      (blocked), a
                ld      hl, (charx)
                ld      a, (facing)
                or      a
                jr      z, cbback
                dec     hl              ; facing right: back is left
                jr      cbset
cbback:         inc     hl
cbset:          ld      (charx), hl
                djnz    cbtry
                ret

; HL = a room x, which may be off either end.  Out: A = the tile's flags
; there, zero off the room.

tile_flags:     ld      a, (blocky)
                ld      c, a
                jp      tile_in_row

tilenone:       xor     a
                ret

; Carry set if HL is a room x the tables cover -- blockof and distof run one
; block past the room's 280 so the block ahead can be asked for.

inroom:         bit     7, h
                jr      nz, notinroom   ; behind the left hand wall
                ld      a, h
                or      a
                jr      z, inroomyes    ; under 256, and the table is longer
                dec     a
                jr      nz, notinroom
                ld      a, l
                cp      280 + 8 - 256   ; the tables run a block past the room
                jr      nc, notinroom
inroomyes:      scf
                ret
notinroom:      or      a
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

tile_in_row:    call    blockcol_of
                ld      b, a            ; B = the column, C = the row, both
                or      a               ; signed: a block off the screen is
                jp      m, tirfar       ; not empty, it belongs to the room
                cp      10              ; next door
                jr      nc, tirfar
                ld      a, c
                cp      3
                jr      nc, tirfar

                ld      l, a            ; the common case: this room, whose
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
; runs from -64 to 319 so an index just off either side still resolves.

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
; solid block, never as space -- otherwise the edge of the world is a step
; into thin air, and he falls through it for ever.

tirfar:         ld      a, (nowbank)
                push    af
                call    page_bg
                ld      a, (roomnum)
                ld      (tirroom), a
                ld      a, 6            ; POP's handler expects an index at
                ld      (tirsteps), a   ; most one screen out.  If it is not,
tirhand:        ld      hl, tirsteps    ; something has run away, and walking
                dec     (hl)            ; the whole level a room at a time is
                jr      z, tirnull      ; how the game came to look hung
                ld      a, b
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
tirnull:        ld      a, BLK_BLOCK    ; nothing that way is a solid wall
                jr      tirdone

; E = which way to step.  Zero if there is no room there.

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
tirsteps:       db      0

; ---------------------------------------------------------------- flames
;
; A torch burns.  MOVER.S gives every one of them a state and animtorch picks
; the next at random each frame; FRAMEADV.S draws that frame as the B section
; of the block to the torch's RIGHT, one byte in and 43 scanlines above that
; block's A section -- which is why a torch in the last column has none.
;
; The room is baked here rather than drawn block by block, so each of the
; nine frames is baked with the room already behind it and goes down as one
; rectangle: nothing to rub out first.  It goes down before the prince, so he
; passes in front of it, as he does in POP.

; RND in GRAFIX.S: the seed times five, and twenty three on top.

rnd:            ld      a, (rndseed)
                add     a, a
                add     a, a
                ld      b, a
                ld      a, (rndseed)
                add     a, b
                add     a, 23
                ld      (rndseed), a
                ret

; GETFLAMEFRAME in MOVER.S.  In and out: A = the torch's state.  A fresh
; number if it is in range and not the one it is already on, otherwise the
; next one round.

flameframe:     ld      (fstate), a
                call    rnd
                ld      b, a
                ld      a, (fstate)
                cp      b
                jr      z, ffnext
                ld      a, b
                cp      18
                ret     c
                ld      a, (fstate)
ffnext:         inc     a
                cp      18
                ret     c
                xor     a
                ret

draw_flames:    ld      a, (torches)
                or      a
                ret     z
                ld      (flleft), a
                ld      hl, torches + 1
                ld      (flrec), hl
                ld      hl, flstate
                ld      (flst), hl
flnext:         call    flame_one
                ld      hl, flleft
                dec     (hl)
                jr      nz, flnext
                ret

; One torch: its next frame, and that frame laid into the working copy.
; A record is column, top, width, height, the size of one frame, and where
; the nine of them start.

flame_one:      ld      hl, (flrec)
                ld      de, flrect
                ld      bc, 4
                ldir
                ld      a, (hl)
                ld      (flstride), a
                inc     hl
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      (flrec), hl
                ld      a, d            ; the offset says which shift it is,
                or      e               ; and so which mask goes with it
                ld      bc, flamemask
                jr      z, flmask1
                ld      bc, flamemask + 3
flmask1:        ld      (flmbase), bc
                ld      hl, flames      ; the record carries an offset
                add     hl, de
                ld      (flsrc), hl

                ld      hl, (flst)
                ld      a, (hl)
                push    hl
                call    flameframe
                pop     hl
                ld      (hl), a
                inc     hl
                ld      (flst), hl

                ld      hl, flametab    ; which of the nine that state is
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      b, (hl)
                ld      hl, (flsrc)
                ld      a, b
                or      a
                jr      z, flgot
                ld      d, 0
                ld      a, (flstride)
                ld      e, a
flmul:          add     hl, de
                djnz    flmul
flgot:          ld      (flsrc), hl

                ld      a, (flrect)     ; the camera says where that lands
                ld      b, a
                ld      a, (cam)
                neg
                add     a, b
                ld      (linecol), a
                call    startrows
                ld      a, (flrect + 1)
                ld      (rowy), a
                ld      a, (flrect + 3)
                ld      b, a
flrow:          push    bc
                call    line_addr       ; the working copy on this row
                ld      de, work - SCREEN
                add     hl, de
                ld      (flwork), hl
                ld      a, (rowy)       ; and the room under it
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (flrect)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (flroom), hl
                ld      hl, (flmbase)   ; the mask starts again each row
                ld      (flmask), hl
                ld      a, (flrect + 2)
                ld      b, a
flbyte:         push    bc
                ld      hl, (flsrc)     ; the flame's own pixels
                ld      a, (hl)
                inc     hl
                ld      (flsrc), hl
                ld      c, a
                ld      hl, (flmask)    ; which of them are its own
                ld      a, (hl)
                inc     hl
                ld      (flmask), hl
                cpl
                ld      hl, (flroom)    ; the room shows through the rest
                and     (hl)
                inc     hl
                ld      (flroom), hl
                or      c
                ld      hl, (flwork)
                ld      (hl), a
                inc     hl
                ld      (flwork), hl
                pop     bc
                djnz    flbyte
                ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    flrow
                ret

; Colour, which the Spectrum keeps in cells of eight pixels by eight.  The
; map is the room's width and the camera slides over it in whole cells, so
; the window is simply copied out -- again when the view moves.

set_attrs:      ld      hl, SCREEN + 6144
                ld      de, SCREEN + 6145
                ld      bc, 767
                ld      (hl), INK_ROOM
                ldir

                ld      a, (torches)    ; and red where a torch burns
                or      a
                ret     z
                ld      (flleft), a
                ld      hl, torches + 1
                ld      (flrec), hl
sanext:         ld      hl, (flrec)
                ld      a, (hl)         ; its column, less the camera
                inc     hl
                ld      b, a
                ld      a, (cam)
                neg
                add     a, b
                ld      (sacol), a
                ld      a, (hl)         ; the top of it, in cells
                inc     hl
                ld      b, a
                srl     a
                srl     a
                srl     a
                ld      (sarow), a
                ld      a, (hl)         ; how many cells across
                inc     hl
                ld      (sawide), a
                ld      a, (hl)         ; and down: the last row it reaches
                add     a, b
                dec     a
                srl     a
                srl     a
                srl     a
                ld      b, a
                ld      a, (sarow)
                neg
                add     a, b
                inc     a
                ld      (satall), a
                ld      de, 4           ; on to the next torch's record
                add     hl, de
                ld      (flrec), hl

                ld      a, (satall)
                ld      b, a
                ld      a, (sarow)
sarowloop:      push    bc
                push    af
                ld      l, a            ; thirty two cells to the row
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                ld      de, SCREEN + 6144
                add     hl, de
                ld      a, (sacol)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      a, (sawide)
                ld      b, a
sacell:         ld      (hl), INK_FLAME
                inc     hl
                djnz    sacell
                pop     af
                inc     a
                pop     bc
                djnz    sarowloop

                ld      hl, flleft
                dec     (hl)
                jr      nz, sanext
                ret

sacol:          db      0
sarow:          db      0
sawide:         db      0
satall:         db      0

; Where a room's torches are.  FRAMEADV.S draws a flame as the B section of
; the block to the torch's RIGHT, one byte in and 43 scanlines above that
; block's A section, so it lands at room pixel 28*col + 35 -- three off a
; byte boundary on an even column and seven on an odd one, which is why two
; shifts of the flame are enough for a whole level.

maketorches:    xor     a
                ld      (torches), a
                ld      hl, torches + 1
                ld      (flrec), hl
                xor     a
                ld      (mtrow), a
mtr:            xor     a
                ld      (mtcol), a
mtc:            ld      a, (mtrow)
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten blocks to the row
                ld      a, (mtcol)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      de, roomids
                add     hl, de
                ld      a, (hl)
                and     0x1f
                cp      BG_TORCH
                jp      nz, mtnext
                ld      a, (mtcol)
                cp      9               ; the last column has no flame
                jp      nc, mtnext

                ld      l, a            ; room pixel 28*col + 35, which
                ld      h, 0            ; does not fit in eight bits
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl          ; four
                ld      b, h
                ld      c, l
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; thirty two
                or      a
                sbc     hl, bc          ; less four is twenty eight
                ld      de, 35
                add     hl, de
                ld      a, l
                and     7               ; three or seven
                ld      (mtal), a
                srl     h               ; and which byte it starts in
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      a, l
                ld      hl, (flrec)
                ld      (hl), a
                inc     hl
                ld      a, (mtrow)      ; its block row gives the height
                inc     a
                ld      e, a
                ld      d, 0
                push    hl
                ld      hl, blockbot
                add     hl, de
                ld      a, (hl)
                pop     hl
                sub     3               ; Ay
                sub     43              ; the flame's bottom row
                sub     15              ; and its top
                ld      (hl), a
                inc     hl
                ld      (hl), 3         ; three bytes across
                inc     hl
                ld      (hl), 16        ; sixteen down
                inc     hl
                ld      (hl), 48        ; the size of one frame
                inc     hl
                ld      de, 0           ; which shift of the nine to use
                ld      a, (mtal)
                cp      3
                jr      z, mtshift
                ld      de, 9 * 48
mtshift:        ld      (hl), e
                inc     hl
                ld      (hl), d
                inc     hl
                ld      (flrec), hl
                ld      hl, torches
                inc     (hl)

mtnext:         ld      hl, mtcol
                inc     (hl)
                ld      a, (hl)
                cp      10
                jp      c, mtc
                ld      hl, mtrow
                inc     (hl)
                ld      a, (hl)
                cp      3
                jp      c, mtr
                ret

mtrow:          db      0
mtcol:          db      0
mtal:           db      0

; And on to the screen, wherever the view has put them.

show_flames:    ld      a, (torches)
                or      a
                ret     z
                ld      (flleft), a
                ld      hl, torches + 1
                ld      (flrec), hl
sfnext:         ld      hl, (flrec)
                ld      de, shcol
                ld      bc, 4
                ldir
                ld      de, 3
                add     hl, de
                ld      (flrec), hl
                ld      a, (shcol)
                ld      b, a
                ld      a, (cam)
                neg
                add     a, b
                ld      (shcol), a
                call    showgo
                ld      hl, flleft
                dec     (hl)
                jr      nz, sfnext
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
                ld      hl, (curleft)
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
                ld      a, (curw)       ; and the block over his right
                add     a, a
                add     a, a
                add     a, a
                ld      e, a
                ld      d, 0
                ld      hl, (curleft)
                add     hl, de
                dec     hl
                jr      cropright
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
bxfwd:          ld      e, a            ; sign extend the offset and add
                ld      d, 0
                or      a
                jp      p, bxpos
                dec     d
bxpos:          ld      hl, (charx)
                add     hl, de
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
                ld      de, BLOCK_PX
                add     hl, de
                jp      tile_flags
ffback:         call    base_x
                ld      de, -BLOCK_PX
                add     hl, de
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
                ld      a, (facing)
                or      a
                jr      nz, afleft      ; behind is the other way round
                jr      afright

abovefront_flags:
                call    base_x
                ld      a, (facing)
                or      a
                jr      z, afleft
afright:        ld      de, BLOCK_PX
                add     hl, de
                jr      arow
afleft:         ld      de, -BLOCK_PX
                add     hl, de
arow:           ld      a, (blocky)
                or      a
                jr      z, ffnone       ; nothing above the top row
                dec     a
                ld      c, a
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

; How far into his own block he stands, in POP's units of two pixels.  It was
; a table of 288; this is the same sum -- the coordinate less `angle`, brought
; into one block's width and halved -- and 288 bytes we did not have.

get_dist:       call    base_x
                ld      de, -ANGLE_PX
                add     hl, de
gdup:           bit     7, h            ; up into the block above zero
                jr      z, gddown
                ld      de, 28
                add     hl, de
                jr      gdup
gddown:         ld      a, h            ; and down into the first one
                or      a
                jr      nz, gdsub
                ld      a, l
                cp      28
                jr      c, gdgot
gdsub:          ld      de, -28
                add     hl, de
                jr      gddown
gdgot:          srl     a               ; two pixels to the unit
                ld      b, a
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
                ld      hl, blocky      ; straight through, keep going.
                inc     (hl)            ; Three is the row under the screen,
                ret                     ; and CUT takes him to it

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

draw_prince:    call    page_canvas     ; the frame table lives there now
                call    frame_entry
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
                call    page_art        ; and the room is wanted again

; The anchor is the leading edge, so the offset differs with facing and is
; kept with the sprite rather than worked out here.

                ld      a, (curoff)     ; signed, and his coordinate is two
                ld      e, a            ; bytes wide
                ld      d, 0
                or      a
                jp      p, shoff
                dec     d
shoff:          ld      hl, (charx)
                add     hl, de
                ld      (curleft), hl   ; CROPCHAR wants the picture's edges
                ld      a, l
                and     7
                ld      (curshift), a
                sra     h               ; signed: he can stand left of the room
                rr      l
                sra     h
                rr      l
                sra     h
                rr      l
                ld      a, l
                ld      b, a            ; the room's byte column; the camera
                ld      a, (cam)        ; says where that is on screen
                neg
                add     a, b

                ld      (rawcol), a

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

; Clip him to the thirty two columns the screen has.  The room is 280 wide
; and the view 256, so he can be half off the side of it -- and a byte column
; outside 0..31 is not off the screen at all, it is the next row along, which
; is where the rubbish on the left came from.  What the left edge cuts off is
; skipped in the source too, so the rest still lines up.

                xor     a
                ld      (spskip), a
                ld      a, (rawcol)
                ld      c, a
                bit     7, a
                jr      z, clipright
                neg                     ; off the left: skip that many bytes
                ld      (spskip), a
                ld      b, a
                ld      a, (neww)
                sub     b
                jr      c, clipnone
                jr      z, clipnone
                ld      (neww), a
                ld      c, 0
clipright:      ld      a, c
                ld      b, a
                ld      a, (neww)
                add     a, b            ; past the right hand edge?
                cp      33
                jr      c, clipset
                ld      a, 32
                sub     b
                jr      c, clipnone
                jr      z, clipnone
                ld      (neww), a
clipset:        ld      a, c
                ld      (newcol), a
                jr      clipdone
clipnone:       xor     a               ; none of him is on screen
                ld      (neww), a
                ld      (newcol), a
clipdone:
                call    crop_char
                call    erase_new
                call    draw_flames     ; background, so before he is drawn

; Only now: everything above reads the room and the tables, and the sprite's
; bank goes over the top of the room.

                call    page_frame

                ld      a, (newh)       ; the calls above have had A
                ld      b, a
                ld      a, (newcol)     ; before HL is loaded: startrows has it
                ld      (linecol), a
                call    startrows
                ld      hl, (curdat)
                ld      a, (newtop)
                ld      (rowy), a
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
drawgo:         ld      a, (neww)       ; wholly off the side of the screen
                or      a
                jr      z, drawskip
                call    line_addr
                ld      bc, work - SCREEN
                add     hl, bc          ; draw into the working copy
                ld      de, mbuf        ; past what the left edge cut off
                ld      a, (spskip)
                add     a, a            ; two bytes to a pixel byte here
                ld      c, a
                ld      b, 0
                ex      de, hl
                add     hl, bc
                ex      de, hl
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

cover_rows:     ld      a, (neww)       ; likewise: djnz would go round
                or      a               ; 256 times for none of him
                ret     z
                ld      a, (newcol)
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

; The room under where he is about to be drawn, put back before he is.
;
; Only two rectangles of the working copy are ever read -- where he was, which
; the erase above has just done, and where he is going, which is this one.
; Everywhere else it holds whatever was there last, and after the view has
; moved that is the room a byte out; walk him into it and the background
; under him comes out shifted.  So both go back from the room, every frame.

erase_new:      ld      hl, newcol

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

; The view has moved and the whole screen is being redrawn from the room --
; six kilobytes, which is longer than the beam takes to cross the screen, so
; it is seen while it happens.  His own bytes therefore go down with the row
; they belong to rather than in a pass of their own: a row is never on screen
; without him, and the tear that is left is the room sliding, nothing more.

                xor     a
                ld      (fullshow), a
                ld      (dirtyh), a
                ld      (rowy), a
                ld      (linecol), a
                call    startrows
                call    roomwin
                ld      (roomp), hl
                ld      b, 192
fsrow:          push    bc
                call    line_addr
                ex      de, hl
                ld      hl, (roomp)
                call    copy32
                push    hl              ; the room, past its thirty two
                ld      hl, (rowptr)
                call    fs_sprite
                pop     hl
                call    nextrow
                pop     bc
                djnz    fsrow
                call    set_attrs       ; the colour slides with the view
                jp      show_flames

; In: HL = the screen address of column zero on this row.  Puts down the part
; of the sprite that falls on it, if any.

fs_sprite:      ld      a, (neww)
                or      a
                ret     z
                ld      a, (rowy)
                ld      b, a
                ld      a, (newtop)
                neg
                add     a, b            ; how far into him this row is
                ld      b, a
                ld      a, (newh)
                cp      b
                ret     c
                ret     z
                ld      a, (newcol)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      d, h
                ld      e, l            ; DE = screen
                ld      bc, work - SCREEN
                add     hl, bc          ; HL = working copy
                ld      a, (neww)
                ld      c, a
                ld      b, 0
                ldir
                ret

; Two rectangles reach the screen, not the box around them: where he was and
; where he is.  The box would take in corners neither of them covers, and the
; working copy is only ever put right under the two.

showpart:       ld      a, (dirtyh)     ; whatever a block redraw changed
                or      a
                jr      z, showold
                ld      hl, dirtycol
                call    show_one
                xor     a
                ld      (dirtyh), a
showold:        ld      a, (oldw)
                or      a
                jr      z, shownew
                ld      hl, oldcol
                call    show_one
shownew:        ld      hl, newcol
                call    show_one
                jp      show_flames

show_one:       ld      de, shcol       ; col, top, width, height, in order
                ld      bc, 4
                ldir

showgo:         ld      a, (shh)
                or      a
                ret     z
                ld      a, (shw)        ; none of him on screen: LDIR would
                or      a               ; read a width of zero as 65536 and
                ret     z               ; take the stack with it
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

; A block that has just been redrawn, from the room to the working copy and
; on to the screen.
;
; Nothing else does this.  The working copy is only ever put right under the
; two rectangles the sprite covers, and only those reach the screen -- so a
; gate opening, an exit door rising or a floor giving way was not seen until
; the view moved or he happened to walk over it.
;
; In: (blockcol) and (dy) say which block, (redh) how deep the band that
; changed is -- POP's loosewipe and platewipe, and the whole block for a gate.

REDWIDE         equ     5               ; twenty eight pixels, however it sits

redshow:        ld      a, (blockcol)   ; the block's leftmost room byte
                add     a, a
                add     a, a
                ld      c, a            ; four
                add     a, a
                add     a, a
                add     a, a            ; thirty two
                sub     c               ; twenty eight pixels to a block
                rrca
                rrca
                rrca
                and     0x1f
                ld      (rdcol), a

                ld      b, a            ; clipped to what the view shows
                ld      a, (cam)
                cp      b
                jr      nc, rsleft
                ld      a, b
rsleft:         ld      (rdstart), a
                ld      c, a
                ld      a, (rdcol)
                add     a, REDWIDE
                ld      b, a
                ld      a, (cam)
                add     a, 32
                cp      b
                jr      nc, rsright
                ld      b, a
rsright:        ld      a, b
                sub     c
                ret     z
                ret     c
                ld      (rdw), a

                ld      a, (rdstart)    ; where that lands on screen
                ld      b, a
                ld      a, (cam)
                neg
                add     a, b
                ld      (linecol), a
                ld      a, (redh)
                ld      b, a
                ld      a, (dy)
                sub     b
                inc     a               ; the band ends on the block's floor
                ld      (rowy), a
                call    startrows
                call    dirty_add       ; and the blit takes it from there
rsrow:          push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, rsskip
                call    line_addr
                ld      (rsscr), hl
                ld      de, work - SCREEN
                add     hl, de
                ld      (rswrk), hl
                ld      a, (rowy)
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (rdstart)
                ld      e, a
                ld      d, 0
                add     hl, de          ; HL = the room's row
                ld      de, (rswrk)
                ld      a, (rdw)
                ld      c, a
                ld      b, 0
                ldir
                jr      rsnext
rsskip:         call    startrows
rsnext:         ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    rsrow
                ret

; The rectangle a block redraw left behind, grown to hold all of them, and
; sent at the top of the next frame -- before his own two, so that he wins.

dirty_add:      ld      a, (dirtyh)
                or      a
                jr      z, dirtyset     ; nothing there yet: take it whole
                ld      a, (dirtycol)   ; else grow it to hold both
                ld      b, a
                ld      a, (linecol)
                cp      b
                jr      nc, dirty1
                ld      b, a
dirty1:         ld      a, (dirtycol)
                ld      c, a
                ld      a, (dirtyw)
                add     a, c            ; the old right hand edge
                ld      c, a
                ld      a, (linecol)
                ld      hl, rdw
                add     a, (hl)
                cp      c
                jr      nc, dirty2
                ld      a, c
dirty2:         sub     b
                ld      (dirtyw), a
                ld      a, b
                ld      (dirtycol), a
                ld      a, (dirtytop)
                ld      b, a
                ld      a, (rowy)
                cp      b
                jr      nc, dirty3
                ld      b, a
dirty3:         ld      a, (dirtytop)
                ld      c, a
                ld      a, (dirtyh)
                add     a, c
                ld      c, a
                ld      a, (rowy)
                ld      hl, redh
                add     a, (hl)
                cp      c
                jr      nc, dirty4
                ld      a, c
dirty4:         sub     b
                ld      (dirtyh), a
                ld      a, b
                ld      (dirtytop), a
                ret

dirtyset:       ld      a, (linecol)
                ld      (dirtycol), a
                ld      a, (rowy)
                ld      (dirtytop), a
                ld      a, (rdw)
                ld      (dirtyw), a
                ld      a, (redh)
                ld      (dirtyh), a
                ret

rdcol:          db      0
rdstart:        db      0
rdw:            db      0
redh:           db      63
rsscr:          dw      0
rswrk:          dw      0
dirtycol:       db      0
dirtytop:       db      0
dirtyw:         db      0
dirtyh:         db      0

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

                include "bg.asm"

; ---------------------------------------------------------------- data



charx:          dw      0
chary:          db      0
facing:         db      0               ; 0 left, 1 right
jarabove:       db      0               ; 1 the row above, -1 his own
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
charcu:         db      0               ; FCharCU, the row his picture is cut at
fchary:         db      0
curleft:        dw      0
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

; show_one and keep_rect copy these four as one record -- col, top, width,
; height, in that order -- so nothing may be put between them.
newcol:         db      0
newtop:         db      0
neww:           db      0
newh:           db      0

oldcol:         db      0
oldtop:         db      0
oldw:           db      0
oldh:           db      0

rawcol:         db      0               ; where his picture wanted to go,
spskip:         db      0               ; and what the left edge cut off

cam:            db      0               ; the view's left edge, in bytes
fullshow:       db      0
masterc:        db      0
coverm:         dw      0
coverb:         dw      0
workp:          dw      0
roomp:          dw      0
rowptr:         dw      0
rndseed:        db      37
fstate:         db      0
flleft:         db      0
flrec:          dw      0
flst:           dw      0
flsrc:          dw      0
flstride:       db      0
flmask:         dw      0
flmbase:        dw      0
flroom:         dw      0
flwork:         dw      0
flrect:         ds      4
flstate:        ds      8
linecol:        db      0
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

cmpspace:       incbin  "cmpspace.bin"
cmpbarr:        incbin  "cmpbarr.bin"
floory:         incbin  "floory.bin"
blocktop:       incbin  "blocktop.bin"
floorband:      incbin  "floorband.bin"
torches:        ds      1 + 6 * 7
flametab:       incbin  "flametab.bin"
flames:         incbin  "flames.bin"
flamemask:      incbin  "flamemask.bin"
foreband:       ds      192
blockof:        incbin  "blockof.bin"
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
