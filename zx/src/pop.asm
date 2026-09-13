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

                org     24320
PAGEPORT        equ     0x7FFD
BANKM           equ     0x5B5C  ; the 128 ROM's copy of it

; The tape's BASIC loader cannot page banks itself -- OUT is the one statement
; this build cannot try out before it ships -- so it calls in here instead.
; Each of these is four bytes, so the loader knows where they are: 24320 for
; the first, then every four, and the last one starts the game.
;
;   10 CLEAR 24575
;   20 LOAD ""CODE : REM the program
;   30 RANDOMIZE USR 24320 : REM page a bank in
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

; Once start has run the stubs are never called again, and the map of the
; rows a view being made still wants -- a bit a row, 24 bytes -- lives over
; the top of the six of them.

vwmap           equ     stubs

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
MODORG          equ     sprites + SPARE_LEN     ; the control code: see modend

SCREEN          equ     16384
FRAMES          equ     23672           ; the ROM's own count of interrupts,
                                        ; kept by the handler at 0x38
; 50Hz interrupt periods per game frame.  The Apple ran the kid at about ten
; a second; three periods is sixteen and two thirds, which is as near as whole
; periods come to the thirty per cent more that plays comfortably.
;
; What is counted is the periods since the frame BEGAN, not the halts after
; its work ended.  Three halts after the work cost ceil(work/period) + 2, so
; the walking frame's 1.6 periods of work bought four -- twelve a second --
; and any frame whose work crossed the next whole period lost a further one.
; Counting from the start spends max(FRAME_WAIT, ceil(work/period)) instead:
; the tall frames -- hanging is fifty five scanlines of him -- have their two
; periods of work inside the same slot as the short ones, so they no longer
; fall off a step, and only a frame that overruns all three lands late.
FRAME_WAIT      equ     3
BLOCK_PX        equ     28
STEP_OFF_FWD    equ     3               ; CTRL.S
STEP_OFF_BACK   equ     8
GCLIMBTHRES     equ     6               ; a gate held from above: CTRL.S
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
;
; start itself runs from where the working copy goes: see the end.

start2:         call    repaint
                call    draw_chars
                call    page_art
                call    hide_floor
                call    hide_behind
                call    hide_guard
                ld      a, (FRAMES)
                ld      (frstart), a
                ei

; ---------------------------------------------------------------- main

; The screen is written the moment the interrupt returns, while the beam is
; still in the border above the room.  Everything else -- rubbing him out,
; reading the keys, running his sequence, drawing him -- happens afterwards,
; into the working copy, and reaches the screen at the top of the next frame.
; A frame's worth of lag, and nothing torn: the beam never catches the blit
; halfway through him.

main:           ld      hl, nohalt      ; the view being made ran right up to
                ld      a, (hl)         ; the interrupt: the frame is due, and
                ld      (hl), 0         ; the beam still in the border
                or      a
                jr      nz, mainrun
                halt                    ; the blit wants the beam still in the
mainwait:       ld      a, (FRAMES)     ; border above the room, so a frame
                ld      hl, frstart     ; always begins on an interrupt -- but
                sub     (hl)            ; on the FIRST one that leaves the slot
                cp      FRAME_WAIT      ; full, which a frame that overran has
                jr      nc, mainrun     ; left behind already
                halt
                jr      mainwait

mainrun:        ld      a, (FRAMES)
                ld      (frstart), a

                call    page_art
                call    show_rect
                call    show_meters     ; over whatever went to the screen
                call    page_art
                call    keep_rect

                call    camera
                call    rq_shows        ; blocks redrawn last frame, to show
                call    page_canvas     ; the sequences live there, and
                call    checkalert      ; EnemyAlert, before either moves
                call    input_step      ; everything down to here starts one
                call    step_seq
                call    firstguard
                call    check_barr
                call    check_floor
                call    do_fall
                call    page_canvas
                call    do_shad         ; and the guard after him
                call    page_canvas
                call    checkstrike
                call    checkstab
                call    cutguard
                call    page_art
                call    nextroom        ; before anything reads his row again
                call    checkpress
                call    shakeloose
                call    animtrans
                call    animmobs
                call    draw_chars
                call    page_art
                call    hide_floor
                call    hide_behind
                call    hide_guard
                call    rq_run          ; and the redrawing, as time allows
                call    vw_fill         ; and the view ahead, to the very end
                jp      main

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

; The end of a room change, and it has to be here rather than in the block
; that builds a room: repaint writes the whole working copy, and those rows
; ARE the bytes that block sits in.  Called from inside it, the repaint went
; over the code that was running and the machine came back up executing room
; pixels -- so the block jumps out to this, and never returns to itself.

nrfinish:       call    repaint
                jp      set_attrs

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
; Ours is 24 pixels short of it, so the view slides, a byte at a time.  The
; screen is taken in thirds and the whole slide is done while he crosses the
; first two of them the way he faces, and by the middle: facing right, a
; step as he passes 16, 64 and 112 pixels from the left edge of the screen;
; facing left, the same from the right.  They are that far apart so that
; the next view can be made between them even running -- some seven frames
; on the real machine.  The view only ever steps the way he faces, so a
; pace to and fro across a step does not set it swinging; when he turns,
; it goes back by the same rule.
;
; A step never repaints the screen shown.  The next view the way he faces is
; made ahead, in the screen not shown, with whatever time frames have left
; over; when he reaches the step it is ready, camera takes it, he is drawn
; for it, and show_rect turns the screens round at the top of the frame
; after.

camera:         xor     a               ; nothing waits for the view yet
                ld      (vwwait), a
                call    camsched        ; C = where the rule puts the view
                ld      c, a
                ld      b, 0            ; B = 1: the step ahead is due now
                ld      a, (facing)
                or      a
                ld      a, (cam)
                jr      z, camfl
                cp      CAM_MAX         ; facing right: a step right, if the
                ret     z               ; room has one, due once the rule is
                inc     a               ; there
                cp      c
                jr      z, camdue
                jr      nc, camwant
camdue:         inc     b
                jr      camwant
camfl:          or      a               ; facing left: a step left
                ret     z
                dec     a
                cp      c
                jr      c, camwant
                inc     b
camwant:        ld      hl, vwcam       ; the view being made?
                cp      (hl)
                jr      z, camready
                ld      (hl), a         ; no: that one, all of it -- and if
                ld      a, b            ; it is wanted now, the queue waits
                ld      (vwwait), a
                jr      vw_all
camready:       dec     b               ; wanted now, and ready?
                ret     nz
                call    vwany
                jr      z, camtake
                ld      a, 1            ; not yet: the queue waits for it
                ld      (vwwait), a
                ret
camtake:
                ld      a, (vwcam)
                ld      (cam), a
                ld      a, 1
                ld      (flipnow), a
                ret

; On the way into a room, straight to where the rule puts it.

camhome:        call    camsched
                ld      (cam), a
                ret

; A = the camera the rule gives: how many of the three steps, the way he
; faces, he has passed.  In the room's pixels, where each step lands for the
; view it starts from -- 16, 72 and 128 facing right; facing left 264, 208
; and 152, passed going down, and the first of those is past the byte.

camsched:       ld      hl, camthr + 3
                ld      a, (facing)
                or      a
                jr      nz, cs1
                ld      hl, camthr
cs1:            ld      de, (charx)
                xor     a
                bit     7, d
                ret     nz              ; left of the room: none
                inc     d
                dec     d
                ld      b, 3
                jr      z, cs2
                ld      a, b            ; right of 255: all three
                ret
cs2:            ld      c, a
                ld      a, e
                cp      (hl)
                ld      a, c
                ret     c
                inc     a
                inc     hl
                djnz    cs2
                ret

camthr:         db      153, 209, 255   ; facing left: from these on, 1 2 3
                db      16, 72, 128     ; facing right

; ---------------------------------------------------------------- a new view
;
; Every row of it wanted afresh, and its colours.

vw_all:         ld      hl, vwmap
                ld      b, 24
va1:            ld      (hl), 0xff
                inc     hl
                djnz    va1
                ld      a, 192
                ld      (vwcnt), a      ; all 192 rows
                ld      (vwatt), a      ; and, not nought, the colours
                ret

; Z: nothing of the view left to do.  The rows are counted as they are
; marked and copied, so the question costs nothing to ask.

vwany:          ld      a, (vwcnt)
                ld      hl, vwatt
                or      (hl)
                ret

; Rows the room has just changed in: the view being made wants them again.
; In: A = the first, B = how many.

vw_mark:        ld      c, a
vm1:            ld      a, c
                cp      192
                jr      nc, vm2
                call    vwbit
                ld      d, a
                and     (hl)
                jr      nz, vm2         ; wanted already
                ld      a, d
                or      (hl)
                ld      (hl), a
                ld      hl, vwcnt
                inc     (hl)
vm2:            inc     c
                djnz    vm1
                ret

; A = a row.  Out: HL = its byte of vwmap, A = its bit.

vwbit:          ld      e, a
                rrca
                rrca
                rrca
                and     0x1f
                ld      hl, vwmap
                add     a, l
                ld      l, a
                jr      nc, vb1
                inc     h
vb1:            ld      a, e
                and     7
                ld      e, a
                ld      a, 0x80
                ret     z
vb2:            rrca
                dec     e
                jr      nz, vb2
                ret

; What is left of a frame after the queue: the view ahead, a run of rows at
; a time, right up to the interrupt the next frame starts on.  A run is short
; enough that the frame can begin the moment it is done, with the beam still
; in the border, instead of waiting at the halt.  That is the third
; interrupt; a frame that has overrun it will start on the next one whatever
; happens, so the view has until then.  And VWMIN runs go whatever the clock
; says: on a machine slower than this one a frame had nothing left over, and
; the view never moved at all.

VWMIN           equ     2
VWBATCH         equ     4

vw_fill:        ld      a, (vwcam)
                inc     a
                ret     z               ; no view in hand
                call    vwdue
                cp      FRAME_WAIT
                jr      nc, vwgoal
                ld      a, FRAME_WAIT - 1
vwgoal:         inc     a
                ld      (vwstop), a
                ld      a, VWMIN
                ld      (vwmin), a
vwf1:           ld      a, (vwatt)
                or      a
                jr      nz, vwfatt
                call    vwany
                ret     z               ; ready, and waiting for him
                call    vw_batch
                jr      vwf2
vwfatt:         call    vw_attrs
vwf2:           ld      hl, vwmin       ; the runs it has whatever happens
                dec     (hl)
                jp      p, vwf1
                inc     (hl)
                call    vwdue
                ld      hl, vwstop
                cp      (hl)
                jr      c, vwf1
                ld      a, 1            ; the frame is due: it starts now
                ld      (nohalt), a
                ret

; A = the interrupts since the frame began.

vwdue:          ld      a, (FRAMES)
                ld      hl, frstart
                sub     (hl)
                ret

; The colours, in the screen not shown.  set_attrs works them out for the
; camera, so for as long as that takes it is the view's.

vw_attrs:       xor     a
                ld      (vwatt), a
                ld      a, (cam)
                push    af
                ld      a, (vwcam)
                ld      (cam), a
                ld      a, (scrsel + 1)
                or      a
                ld      hl, SCREEN + 6144
                jr      nz, vwa1
                ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0xC000 + 6144
vwa1:           call    set_attrs_at
                pop     af
                ld      (cam), a
                jp      page_art

; The next run of rows the view still wants, up to VWBATCH of them together
; so that the search, the two addresses and the paging are paid once for the
; run and the addresses walk from row to row after that: the room's, from
; where the view will stand, into the screen not shown -- through the buffer
; down here when that is bank 7, which wants the window the room is in.  A
; row at a time, with all of that for every one, spent twice what the
; copying did.

vw_batch:       ld      a, (vwrow)      ; the first row still wanted
vbs1:           cp      192
                jr      c, vbs2
                xor     a
vbs2:           ld      (vwrow), a
                call    vwbit
                and     (hl)
                jr      nz, vbs3
                ld      a, (vwrow)
                inc     a
                jr      vbs1
vbs3:           ld      a, (vwrow)      ; it and the rows after it, while
                ld      (vwfirst), a    ; they are wanted too, off the map
                ld      b, 0
vbs4:           ld      a, (vwrow)
                call    vwbit
                ld      d, a
                and     (hl)
                jr      z, vbs5
                ld      a, d
                cpl
                and     (hl)
                ld      (hl), a
                ld      hl, vwcnt
                dec     (hl)
                inc     b
                ld      hl, vwrow
                inc     (hl)
                ld      a, (hl)
                cp      192
                jr      nc, vbs5
                ld      a, b
                cp      VWBATCH
                jr      c, vbs4
vbs5:           ld      a, b
                ld      (vwn), a
                call    page_art
                ld      a, (vwfirst)    ; the room's first row, for the view
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (vwcam)
                add     a, l
                ld      l, a
                jr      nc, vbs6
                inc     h
vbs6:           push    hl
                ld      e, 0
                ld      a, (vwfirst)
                call    scraddr         ; and its line on the screen
                ex      de, hl
                pop     hl
                ld      a, (vwn)
                ld      b, a
                ld      a, (scrsel + 1)
                or      a
                jr      z, vbbounce
vbdirect:       push    bc              ; bank 7 shown: into bank 5, straight
                push    de
                call    copy32
                ld      de, ROOM_BYTES - 32
                add     hl, de
                pop     de
                ex      de, hl
                call    nextline
                ex      de, hl
                pop     bc
                djnz    vbdirect
                ret
vbbounce:       push    de              ; bank 5 shown: the run into the
                ld      de, imgbuf      ; buffer with the room's bank in
vbb1:           push    bc
                call    copy32
                ld      bc, ROOM_BYTES - 32
                add     hl, bc
                pop     bc
                djnz    vbb1
                ld      a, BANK_CANVAS  ; and out of it with bank 7's
                call    pageset
                pop     de
                set     7, d            ; 0x4000 is 0xC000 in bank 7
                ld      hl, imgbuf
                ld      a, (vwn)
                ld      b, a
vbb2:           push    bc
                push    de
                call    copy32
                pop     de
                ex      de, hl
                call    nextline
                ex      de, hl
                pop     bc
                djnz    vbb2
                jp      page_art

; The room's code back where it runs, from the two banks it is kept in: see
; roomblk.  Only ever with the screen black and the working copy unwritten.

roomrest:       ld      a, BANK_CVS
                call    pageset
                ld      hl, RBAT1
                ld      de, roomblk
                ld      bc, RB1LEN
                ldir
                jp      page_art

roombuild:      call    roomrest
                jp      newroom

; Which screen the ULA shows: bank 5, the ordinary one at 0x4000, or bank 7,
; the 128's second.  A new view is made in the one not shown and shown with
; a single OUT, so a scroll is never seen being drawn.  What is kept is what
; the show loop ORs into a screen address's high byte -- 0x80 moves 0x4000 to
; 0xC000, where bank 7 is when it is paged to be written -- and the port's
; bit 3 comes out of that; every page after keeps it.

flip:           ld      a, (scrsel + 1)
                xor     0x80
setvis:         ld      (scrsel + 1), a
                rrca                    ; 0x80 is bit 3, four places down
                rrca
                rrca
                rrca
                or      0x10            ; and the 48K ROM, as always
                ld      (pgbits + 1), a
                ld      a, (nowbank)
                jr      pageset

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
pgbits:         or      0x10            ; another bank can put this one back
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

mfix0:
                org     MODORG              ; into the canvas bank: see MODORG
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

input_step:     ld      a, (kidstr)     ; PLAYERCTRL: no strength left, no life
                or      a
                jr      nz, isalive
                ld      (charlife), a
isalive:        call    read_input
                call    facejstk
                call    ctrl
                jp      facejstk

; GENCTRL.  Falling and being bumped are not under control; otherwise what he
; does next depends on what he is doing now, which CTRL.S reads off CharPosn,
; the frame he was last drawn in.

ctrl:           ld      a, (charlife)   ; dead, and standing: he drops
                or      a
                jp      p, ctrldead
                ld      a, (charact)
                cp      5               ; mid-bump
                jr      z, ctrlclr
                cp      4               ; or falling: not under control, and
                jr      nz, ctrlon      ; forget whatever was pressed
ctrlclr:        jp      clrall

ctrldead:       ld      a, (frame)
                cp      15
                jr      z, ctrldrop
                cp      166
                jr      z, ctrldrop
                cp      158
                jr      z, ctrldrop
                cp      171
                ret     nz
ctrldrop:       ld      a, SQ_DROPDEAD
                jp      jumpseq

ctrlon:         ld      a, (charsword)  ; en garde: FightCtrl
                cp      2
                jp      z, fight_ctrl
                ld      a, (charid)     ; a guard: GuardCtrl
                cp      2
                jp      nc, guard_ctrl
                ld      a, (frame)
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

standing:       ld      a, (clrbtn)     ; a fresh click is "pick it up", and
                or      a               ; CTRL.S asks that first of all
                jp      m, stgrab
stback:         call    kid_engarde     ; an enemy in range: en garde
                ret     nz
                ld      a, (btn)
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
                call    turnseq         ; turn, or draw as he turns
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

crouching:      ld      a, (clrbtn)     ; a fresh click, crouched: this is
                or      a               ; where the thing is actually taken
                jp      m, crgrab
crback:         ld      a, (jstky)      ; still holding down?
                cp      1
                jr      z, crawlmaybe
                ld      a, SQ_STANDUP
                jp      jumpseq
crawlmaybe:     ld      a, (clrf)       ; a fresh push forward, and only
                or      a               ; that one is spent: CTRL.S sets
                ret     p               ; clrF to 1 and leaves the others
                ld      a, 1
                ld      (clrf), a
                ld      a, SQ_CRAWL
                jp      jumpseq

; PickItUp and RemoveObj, for the sword alone: the block he is stooped in
; front of becomes plain floor, the room is told to draw it again, and he
; picks the sword up, brandishes it and puts it away -- pickupsword runs
; into resheathe, so CharSword stays nought and he can still take hold of a
; ledge.  Out: Z when there was no sword there and the crouch goes on as it
; was.

SWORDWIPE       equ     16              ; the gleam's 12 rows: one band, so the
                                        ; queue draws it in one step -- RemoveObj
                                        ; has 35, marked TEMP, and three bands
                                        ; left the sword on the floor in his hand

; TryPickup and PickItUp in CTRL.S, for the sword alone.  Standing, CTRL.S
; asks it only on a fresh click with the button still down -- a click left
; over from a careful step long before is not one.  A sword underfoot sends
; him a block back first, unless there is nothing behind; only the one in
; front is ever taken.  Out of the crouch he takes it; standing he walks up
; to the edge of his own block and stoops, and DoCrouch clears the stick.

stgrab:         ld      a, (btn)
                or      a
                jp      z, stback
                call    try_pickup
                jp      z, stback
                ret

crgrab:         call    try_pickup
                jp      z, crback
                ret

; Out: Z when he does nothing about it.

try_pickup:     call    base_x          ; underfoot?
                call    blockcol_of
                call    sword_at
                jr      z, tpfront
                call    behind_flags
                call    cmp_space
                ret     z               ; nothing to back on to
                ld      a, -14
                call    move_by
tpfront:        call    get_fwd_dist    ; fwdinx: the block he faces
                push    af
                ld      a, (fwdinx)
                call    sword_at
                pop     bc              ; B: how far to its edge
                ret     z
                ld      a, (frame)
                cp      109
                jp      z, take_sword
                ld      a, (fwdkind)    ; PickItUp: up to it, unless he is
                cp      2               ; there
                ld      a, b
                call    nz, move_by
                ld      a, (facing)
                or      a
                ld      a, -2
                call    nz, move_by
                call    do_crouch
                or      1
                ret

; A = a column of his row.  NZ when the sword lies in it.

sword_at:       push    af
                ld      a, (blocky)
                ld      c, a
                pop     af
                call    tile_at
                sub     BG_SWORD
                sub     1
                sbc     a, a
                ret

mpc0:
                org     mfix0
take_sword:     ld      a, (roomnum)
                ld      (trscrn), a
                ld      a, (blocky)     ; ten blocks to the row, as checkpress
                ld      l, a            ; works it out
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de
                ld      a, (fwdinx)
                add     a, l
                ld      (trloc), a

                call    trobat          ; and it is floor from now on
                ld      a, BG_FLOOR
                call    trobtype
                xor     a
                ld      (trobst), a
                call    trobsave

                ld      a, SWORDWIPE    ; the space it stood in, redrawn at
                ld      (redh), a       ; once, as RemoveObj marks it: at the
                ld      a, 1            ; back of the queue it lay there on
                ld      (rqprio), a     ; the floor while he held it
                call    redplate
                xor     a
                ld      (rqprio), a

                ld      a, 1
                ld      (gotsword), a
                call    page_canvas     ; trobat and redplate paged the level
                ld      a, SQ_PICKUPSWORD ; in, and jumpseq and step_seq after
                call    jumpseq         ; it read the sequences from here
                ld      a, 1            ; NZ: the crouch is spent on this
                or      a
                ret

; --------------------------------------------------------------- jumping up
;
; DoJumpup.  A ledge overhead within reach is worth grabbing; up with the
; stick pushed forward is a standing jump instead; otherwise he jumps on the
; spot.  POP also tries a step back first, which comes later.

; The first frames of a jump up.  Forward now -- held or freshly pressed --
; makes it a standing jump instead, which is the other way round of pressing
; the two keys: up first, then the direction.

mfix1:
                org     mpc0              ; into the canvas bank: see MODORG
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

; DoJumphigh.  A barrier close in front is backed away from first, and then
; the block his hands reach decides which jump it is: a ceiling over him and
; he pushes it -- jumpup, the sequence that carries the jar -- while open sky
; gives the plain high jump.  Only highjump was here, so nothing he jumped
; into was ever jarred.

jumphigh:       call    get_fwd_dist
                cp      4
                jr      nc, jhceil
                ld      b, a
                ld      a, (fwdkind)
                dec     a               ; only a barrier is backed away from
                jr      nz, jhceil
                ld      a, b
                sub     3
                call    addcharx

jhceil:         call    base_x          ; where his hands touch: DoJumphigh
                ld      de, ANGLE_PX - 6 ; reads it with getblockx, which
                add     hl, de          ; takes no angle off
                ld      a, (blocky)
                dec     a
                ld      c, a
                call    tile_in_row
                cp      BLK_BLOCK
                jr      z, jhtouch
                call    cmp_space
                jr      nz, jhtouch
                ld      a, SQ_HIGHJUMP  ; no ceiling above
                jp      jumpseq
jhtouch:        ld      a, SQ_JUMPUP    ; touch it, and jar the room above
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

; CHECKLEDGE, as CTRL.S asks it: what he lowers himself into has to be clear
; and what he holds on to solid.  cmp_space calls a solid block clear, so a
; wall at his back passed the test above for a drop -- and he went down
; through the floor.  check_ledge turns a block away first.

                call    behind_flags
                ld      (blockid), a
                call    under_flags
                call    check_ledge
                jr      z, do_crouch
                ld      a, (facing)     ; facing left, a gate underfoot is only
                or      a               ; a ledge once it is up far enough
                jr      nz, dbledge
                call    under_flags
                cp      BG_GATE
                jr      nz, dbledge
                ld      a, (tilestate)
                rrca
                rrca
                and     0x3f
                cp      GCLIMBTHRES
                jr      c, do_crouch
dbledge:        call    get_dist        ; line him up with it
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

; GETFWDDIST in COLL.S.  A careful step stops at the edge of the block it is
; on when what lies ahead is not to be trodden on: empty space, of course,
; but a floor that is already loose as well -- step on to that and it gives
; way under you.  A plate, a sword or a flask stop him short too, unless he
; is already at the edge, in which case he steps across.

get_fwd_dist:   call    cd_edges        ; his edges, then GetBaseBlock
                call    base_x
                call    blockcol_of
                ld      (fwdbx), a
                ld      a, (blocky)     ; a barrier in the block underfoot
                ld      c, a
                ld      a, (fwdbx)
                call    tile_at
                ld      (fwdid), a
                call    cmp_barr
                jr      z, fwdnext
                ld      a, (fwdbx)
                call    dbarr
                bit     7, a
                jr      z, fwdtobarr
fwdnext:        ld      a, (facing)     ; or in the one in front
                or      a
                ld      a, (fwdbx)
                jr      z, fwdl
                inc     a
                inc     a
fwdl:           dec     a
                ld      (fwdinx), a
                ld      a, (blocky)
                ld      c, a
                ld      a, (fwdinx)
                call    tile_at
                ld      (fwdid), a
                cp      BG_PANELWOF     ; facing right it is only the end of
                jr      nz, fwd99       ; this block
                ld      a, (facing)
                or      a
                jr      nz, fwdedge
fwd99:          ld      a, (fwdid)
                call    cmp_barr
                jr      z, fwdnobarr
                ld      a, (fwdinx)
                call    dbarr
                bit     7, a
                jr      z, fwdtobarr
fwdnobarr:      ld      a, (fwdid)
                ld      c, a
                cp      BG_LOOSE        ; it would give way under him
                jr      z, fwdedge
                cp      BG_PRESSPLATE
                jr      z, fwdshort
                cp      BG_UPRESSPLATE
                jr      z, fwdshort
                cp      BG_SWORD
                jr      z, fwdshort
                cp      BG_FLASK
                jr      z, fwdshort
                ld      a, c
                call    cmp_space
                jr      nz, fwdclear
fwdedge:        xor     a               ; an edge: stop at the end of this one
                ld      (fwdkind), a
                jp      get_dist
fwdshort:       call    get_dist        ; already at the edge: step across
                or      a
                jr      z, fwdclear
                push    af
                xor     a
                ld      (fwdkind), a
                pop     af
                ret
fwdclear:       ld      a, 2
                ld      (fwdkind), a
                ld      a, 11           ; POP's own natural step
                ret
fwdtobarr:      cp      14              ; more than a step away: a whole one
                jr      nc, fwdclear
                ld      c, a
                ld      a, 1
                ld      (fwdkind), a
                ld      a, c
                ret

; DBARR: from his leading edge to the barrier in the block at column A, just
; read -- negative if the barrier is behind him.  A gate counts only while it
; is down.

dbarr:          ld      (dbcol), a
                ld      a, (fwdid)
                cp      BG_GATE
                jr      nz, dbok
                call    gatebarr
                jr      nc, dbclr
dbok:           ld      a, (dbcol)
                call    edge140
                ld      (cbedge), a
                ld      a, (fwdid)
                call    cmp_barr
                jr      z, dbclr
                ld      (cccode), a
                ld      a, (facing)
                or      a
                jr      z, dbleft
                call    leftbar         ; facing right: up to its left edge
                ld      hl, cdright
                sub     (hl)
                ret
dbleft:         call    rightbar        ; facing left: back to its right edge
                ld      c, a
                ld      a, (cdleft)
                sub     c
                ret
dbclr:          ld      a, 0xff
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

mpc1:
                org     mfix1
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

mfix2:
                org     mpc1              ; into the canvas bank: see MODORG
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
                jp      z, sqtap
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

; A footstep, a smack against a wall, or a tap for nothing but that: each
; of them is heard, and wakes a guard.

sqtap:          ld      a, (hl)
                inc     hl
                cp      3
                jp      nc, seqloop
                ld      a, 1
                ld      (alertguard), a
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

; ---------------------------------------------------------------- CHECKBARR
;
; COLL.S.  A barrier is not something he is inside of but an edge he has just
; crossed.  Every frame both edges of each barrier within reach -- on his own
; row, the one below and the one above -- are set against both edges of his
; picture, and a collision is a nybble that was clear last frame and is set
; in this one.  Standing flush against a wall is therefore no collision at
; all, which is what lets a careful step end right up against it.
;
; The comparisons are made in POP's own coordinates, 140 to the screen with
; ScrnLeft on the left, so they are the 6502's byte for byte.

SCRNLEFT        equ     58
ANGLE140        equ     7
THINNER         equ     3
F_THIN          equ     0x20
OOFVEL          equ     22
DEATHVEL        equ     33              ; and past this one he does not get up

check_barr:     ld      a, 0xff         ; no collision yet
                ld      (collidel), a
                ld      (collider), a
                ld      a, (charact)
                cp      7               ; turning: out of reach of walls
                ret     z

                call    cd_edges

                ld      a, (blocky)
                ld      (bythis), a
                call    initcdbufs
                ld      a, (bythis)
                ld      (bylast), a

                ld      a, (cdright)    ; the last block in range, and one on
                call    blockxp
                add     a, 2
                cp      11
                jr      c, cbend
                ld      a, 11
cbend:          ld      (endrange), a
                ld      a, (cdleft)     ; and the first
                call    blockxp
                dec     a
                ld      (begrange), a

                ld      a, (bythis)     ; this row
                ld      hl, cdthis
                ld      de, snthis
                call    getcdata
                ld      a, (bythis)     ; the one below
                inc     a
                ld      hl, cdbelow
                ld      de, snbelow
                call    getcdata
                ld      a, (bythis)     ; and the one above
                dec     a
                ld      hl, cdabove
                ld      de, snabove
                call    getcdata

                ld      c, 9            ; a nybble gone from clear to set
crloop:         ld      hl, snlast
                ld      b, 0
                add     hl, bc
                push    hl
                ld      de, snthis - snlast
                add     hl, de
                ld      a, (hl)
                pop     hl
                bit     7, a
                jr      nz, cbno        ; nothing there this frame
                cp      (hl)
                jr      nz, cbno        ; or it is not the room it was
                ld      de, cdlast - snlast
                add     hl, de
                ld      d, (hl)
                ld      a, l
                add     a, cdthis - cdlast
                ld      l, a
                jr      nc, cbl1
                inc     h
cbl1:           ld      e, (hl)
                ld      a, d
                and     0x0f
                jr      nz, cbnol
                ld      a, e
                and     0x0f
                jr      z, cbnol
                ld      a, c            ; into the left edge of a barrier
                ld      (collidel), a
cbnol:          ld      a, d
                and     0xf0
                jr      nz, cbno
                ld      a, e
                and     0xf0
                jr      z, cbno
                ld      a, c            ; into the right edge of one
                ld      (collider), a
cbno:           dec     c
                jp      p, crloop

; COLLISIONS: act on what was found -- but not while he hangs, or climbs up
; on to a ledge, where the wall is what he has hold of.

                ld      a, (charact)
                cp      2
                ret     z
                cp      6
                ret     z
                ld      a, (frame)
                cp      135
                jr      c, cl2
                cp      149
                ret     c
cl2:            ld      a, (collidel)
                bit     7, a
                jr      z, leftcoll
                ld      a, (collider)
                bit     7, a
                ret     nz

; RIGHTCOLL and LEFTCOLL: an edge only counts when he faces it.  A = how far
; in he has gone, measured from the barrier to his own edge.

rightcoll:      ld      (collx), a
                ld      a, (facing)
                or      a
                ret     nz
                ld      a, (collx)
                call    checkcoll1
                ret     nc
                call    rightbar
                ld      hl, cdleft
                sub     (hl)
                ld      c, 0
                jr      collide

leftcoll:       ld      (collx), a
                ld      a, (facing)
                or      a
                ret     z
                ld      a, (collx)
                call    checkcoll1
                ret     nc
                call    leftbar
                ld      hl, cdright
                sub     (hl)
                ld      c, 0xff

; COLLIDE.  He is put back out by exactly as far as he went in, and then it
; is a bump: soft on the ground, hard out of a jump or a fall, and bumpfall
; with nothing under him.  A bump is not under his control, which is what
; stops him walking straight back into the wall.

collide:        ld      e, a
                ld      a, c
                ld      (collface), a
                ld      a, (frame)
                cp      177             ; impaled: let it be
                ret     z
                ld      a, e
                call    movex

                call    ccread          ; in mid air or on the ground?
                ld      b, a
                ld      a, (collface)
                or      a
                ld      a, b
                jr      z, clfacel
                cp      BG_BLOCK        ; a solid block has no floor to stand
                jr      nz, clspace     ; on: look at the one before it
                ld      hl, tempbx
                dec     (hl)
                jr      clagain
clfacel:        cp      BG_PANELWOF
                jr      z, clnext
                cp      BG_PANELWIF
                jr      z, clnext
                cp      BG_BLOCK
                jr      nz, clspace
clnext:         ld      hl, tempbx
                inc     (hl)
                ld      a, (tempscrn)   ; the null screen's block ten is his
                or      a               ; own room's block nought
                jr      nz, clagain
                ld      a, (hl)
                cp      10
                jr      nz, clagain
                ld      (hl), 0
                ld      a, (roomnum)
                ld      (tempscrn), a
clagain:        call    ccread
clspace:        call    cmp_space
                jr      nz, groundbump

airbump:        ld      a, -4           ; four back off the wall
                call    addcharx
                ld      a, (charact)
                cp      4               ; falling already: that is all
                ret     z
                ld      a, SQ_BUMPFALL
                jr      bumpseq

groundbump:     ld      a, (blocky)
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, floory
                add     hl, de
                ld      a, (hl)
                ld      b, a
                ld      hl, chary
                sub     (hl)
                cp      15              ; well above the floor: that is air
                jr      nc, airbump
                ld      a, b
                ld      (chary), a
                ld      a, (yvel)
                cp      OOFVEL
                jr      c, gbok
                ld      a, -5           ; coming down hard: checkfloor has him
                jp      addcharx
gbok:           xor     a
                ld      (yvel), a
                ld      a, (frame)      ; out of a standing jump, a running
                cp      24              ; jump or a fall the bump is hard
                jr      z, gbhard
                cp      25
                jr      z, gbhard
                cp      40
                jr      c, gbsoft
                cp      43
                jr      c, gbhard
                cp      102
                jr      c, gbsoft
                cp      107
                jr      c, gbhard
gbsoft:         ld      a, SQ_BUMP
                jr      bumpseq
gbhard:         ld      a, SQ_HARDBUMP
bumpseq:        call    jumpseq         ; and straight into its first frame,
                jp      step_seq        ; as animchar does

; CHECKCOLL for the block in slot A, as CHECKCOLL1 finds it: carry if it
; stops him -- a flask never does, a gate only while it is low enough -- with
; the block's left edge, as the room on screen has it, in cbedge.

checkcoll1:     ld      (tempbx), a
                ld      l, a
                ld      h, 0
                ld      de, snthis
                add     hl, de
                ld      a, (hl)
                ld      (tempscrn), a
                ld      a, (blocky)     ; the row, brought into 0..2
                or      a
                jp      p, ck2
                add     a, 3
                jr      ck1
ck2:            cp      3
                jr      c, ck1
                sub     3
ck1:            ld      (tempby), a
                call    ccread
                cp      BG_FLASK
                jr      z, ccno
                ld      c, a
                call    cmp_barr
                ld      (cccode), a
                ld      a, c
                cp      BG_GATE
                jr      nz, ckyes
                call    gatebarr        ; tilestate is the gate's own
                jr      nc, ccno
ckyes:          ld      a, (tempbx)
                call    edge140
                ld      c, a
                ld      a, (tempscrn)   ; AdjustScrn: the rooms either side
                ld      hl, links       ; are a screen's width away
                cp      (hl)
                jr      nz, ccnl
                ld      a, c
                sub     140
                jr      ccedge
ccnl:           inc     hl
                cp      (hl)
                ld      a, c
                jr      nz, ccedge
                add     a, 140
ccedge:         ld      (cbedge), a
                scf
                ret
ccno:           or      a
                ret

ccread:         ld      a, (tempby)     ; the block in tempscrn, tempbx, tempby
                ld      c, a
                ld      a, (tempbx)
                ld      b, a
                ld      a, (tempscrn)
                jp      blk_in

; GETCDATA: one row's blocks, begrange to endrange, into a CD buffer and an
; SN one.  In: A = the row, HL = the CD buffer, DE = the SN buffer.  The
; slot is the block's column in its own room, as RDBLOCK hands it back.

getcdata:       ld      (cbrow), a
                ld      (cbcd), hl
                ld      (cbsn), de
                ld      a, (begrange)
                ld      (cbidx), a
gcloop:         ld      a, (cbidx)
                call    edge140
                ld      (cbedge), a
                ld      a, (cbrow)
                ld      c, a
                ld      a, (cbidx)
                call    tile_at
                call    cmp_barr
                ld      c, 0            ; no barrier: neither edge is near him
                jr      z, gcput
                ld      (cccode), a
                call    leftbar
                ld      hl, cdright
                cp      (hl)
                jr      nc, gcr         ; its left edge is at or past his right
                ld      c, 0x0f
gcr:            call    rightbar
                ld      hl, cdleft
                cp      (hl)
                jr      c, gcput        ; its right edge is at or short of his
                jr      z, gcput        ; left
                ld      a, c
                or      0xf0
                ld      c, a
gcput:          ld      a, (tempbx)
                ld      e, a
                ld      d, 0
                ld      hl, (cbcd)
                add     hl, de
                ld      (hl), c
                ld      hl, (cbsn)
                add     hl, de
                ld      a, (tempscrn)
                ld      (hl), a
                ld      a, (cbidx)
                inc     a
                ld      (cbidx), a
                ld      hl, endrange
                cp      (hl)
                jr      nz, gcloop
                ret

; GETLEFTBAR and GETRIGHTBAR, for the barrier code in cccode and the block
; edge in cbedge.

leftbar:        ld      a, (cccode)
                ld      e, a
                ld      d, 0
                ld      hl, barl
                add     hl, de
                ld      a, (cbedge)
                add     a, (hl)
                ret

rightbar:       ld      a, (cccode)
                ld      e, a
                ld      d, 0
                ld      hl, barr
                add     hl, de
                ld      a, (cbedge)
                add     a, 13
                sub     (hl)
                ret

; A = a column.  Out: A = its left edge, 140 wide, with angle added.

edge140:        ld      b, a
                add     a, a
                add     a, b
                add     a, a
                add     a, b
                add     a, a            ; fourteen a block
                add     a, SCRNLEFT + ANGLE140
                ret

; GETBLOCKXP for a 140 wide A: the column, signed.

blockxp:        sub     SCRNLEFT        ; back to room pixels, 280 wide
                ld      l, a
                sbc     a, a
                ld      h, a
                add     hl, hl
                jp      blockcol_of

; INITCDBUFS: last frame's data is this frame's -- or, if he has changed row,
; the row above's or the row below's, which is where his row was.

initcdbufs:     ld      a, (bythis)
                ld      hl, bylast
                cp      (hl)
                jr      z, icthis
                add     a, 3
                cp      (hl)
                jr      z, icthis
                sub     6
                cp      (hl)
                jr      z, icthis
                ld      a, (bythis)
                inc     a
                cp      (hl)
                jr      z, icabove
                sub     3
                cp      (hl)
                jr      z, icabove
                ld      hl, snbelow
                jr      iccopy
icabove:        ld      hl, snabove
                jr      iccopy
icthis:         ld      hl, snthis
iccopy:         push    hl
                ld      de, snlast
                ld      bc, 10
                ldir
                pop     hl
                ld      de, cdlast - snlast
                add     hl, de
                ld      de, cdlast
                ld      bc, 10
                ldir
                ld      hl, snthis      ; and nothing yet this frame
                ld      b, 30
icff:           ld      (hl), 0xff
                inc     hl
                djnz    icff
                ret

; GETEDGES' collision edges: his picture's left and right, 140 wide, and
; three pixels in from each on a frame that is marked thin.

cd_edges:       ld      a, (nowbank)
                push    af
                call    char_edges      ; edgel -- and the art is left in
                call    page_canvas
                call    frame_entry
                ld      a, (hl)         ; the width in Apple bytes
                ld      c, a
                add     a, a
                add     a, a
                add     a, a
                sub     c               ; Mult7, in half pixels
                inc     a
                srl     a               ; imwidth
                ld      c, a
                ld      hl, (edgel)
                sra     h
                rr      l
                ld      a, l
                add     a, SCRNLEFT
                ld      (cdleft), a
                add     a, c
                ld      (cdright), a
                call    frame_check
                and     F_THIN
                jr      z, cdok
                ld      a, (cdleft)
                add     a, THINNER
                ld      (cdleft), a
                ld      a, (cdright)
                sub     THINNER
                ld      (cdright), a
cdok:           pop     af
                jp      pageset

; ADDCHARX, with + the way he faces; and plain CharX += A.  Both take POP's
; 140 wide A, and his coordinate is twice that.

addcharx:       ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      nz, movex
                neg
movex:          ld      l, a
                add     a, a
                sbc     a, a
                ld      h, a
                add     hl, hl
                ld      de, (charx)
                add     hl, de
                ld      (charx), hl
                ret


; HL = a room x, which may be off either end.  Out: A = the tile's flags
; there, zero off the room.

tile_flags:     ld      a, (blocky)
                ld      c, a
                jp      tile_in_row

mpc2:
                org     mfix2
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

mfix3:
                org     mpc2              ; into the canvas bank: see MODORG
cmp_barr:       ld      l, a
                ld      h, 0
                ld      de, cmpbarr
                add     hl, de
                ld      a, (hl)
                or      a
                ret

; GATEBARR? in COLL.S.  The bars have risen state/4, and six pixels of margin
; go on top of that; against that stands imheight, the height of the picture
; he is drawn as.  Carry if the gate stops him.

GATEMARGIN      equ     6

gatebarr:       ld      a, (nowbank)    ; the frame table is in the canvas
                push    af              ; bank and this is called from both
                call    page_canvas     ; sides of the paging
                call    frame_entry
                inc     hl
                ld      a, (hl)
                ld      c, a
                pop     af
                call    pageset
                ld      a, (tilestate)
                rrca
                rrca
                and     0x3f
                add     a, GATEMARGIN
                cp      c
                ret

; In: A = a screen x, C = a block row.  Out: A = that tile's flags.  The row
; is free here, which tile_flags cannot afford -- it runs inside movetry.

mpc3:
                org     mfix3
tile_in_row:    call    blockcol_of
tile_at:        ld      b, a            ; B = the column, C = the row, both
                or      a               ; signed: a block off the screen is
                jp      m, tirfar       ; not empty, it belongs to the room
                cp      10              ; next door
                jr      nc, tirfar
                ld      a, c
                cp      3
                jr      nc, tirfar

                ld      a, b            ; the common case: this room, whose
                ld      (tempbx), a     ; thirty are already in hand
                ld      a, (roomnum)
                ld      (tempscrn), a
                ld      a, c
                ld      l, a
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
                ld      b, a            ; the state travels with it: a gate's
                ld      de, 30          ; height is the whole of whether it
                add     hl, de          ; bars him
                ld      a, (hl)
                ld      (tilestate), a
                ld      a, b
                ret

; HL = a room x.  Out: A = the block column, signed, -2 to 11.  The table
; runs from -64 to 319 so an index just off either side still resolves.

blockcol_of:    ld      de, -ANGLE_PX   ; GETBLOCKXP takes `angle` off first
                add     hl, de
                ld      b, 0            ; B, not C: the caller keeps the row
bcup:           bit     7, h            ; there, and tile_in_row wants it
                jr      z, bcdown
                ld      de, 28
                add     hl, de
                dec     b
                jr      bcup
bcdown:         ld      a, h            ; then down a block at a time
                or      a
                jr      nz, bcsub
                ld      a, l
                cp      28
                jr      c, bcgot
bcsub:          ld      de, -28
                add     hl, de
                inc     b
                jr      bcdown
bcgot:          ld      a, b
                ret

; The handler of RDBLOCK in CTRLSUBS.S.  A block index outside the screen
; belongs to the room next door; a room that is not there at all reads as
; solid block, never as space -- otherwise the edge of the world is a step
; into thin air, and he falls through it for ever.

tirfar:         ld      a, (roomnum)
blk_in:         ld      (tirroom), a    ; A = the room to read it in
                ld      a, (nowbank)
                push    af
                call    page_bg
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

tirgot:         ld      a, b            ; RDBLOCK's tempblockx and tempscrn
                ld      (tempbx), a
                ld      a, (tirroom)
                ld      (tempscrn), a
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
                ld      b, a
                ld      a, c
                ld      (tilestate), a
                ld      a, b
tirdone:        ld      c, a
                pop     af
                call    pageset
                ld      a, c
                ret
tirnull:        xor     a
                ld      (tilestate), a
                ld      a, BLK_BLOCK    ; nothing that way is a solid wall
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

; A = the room byte a flame starts at.  Out: A = how many of its three bytes
; the view shows.  A torch in column eight has its flame at room bytes 32 to
; 34, which with the view at the left of the room is past the end of a
; screen row -- and the Spectrum's next byte along is the start of a row
; eight lines further down, so the flame came out again at the left edge.

flvis:          ld      b, a
                ld      a, (cam)
                neg
                add     a, b            ; the screen column
                cp      32
                jr      nc, flvnone
                neg
                add     a, 32           ; what is left of the row
                cp      3
                ret     c
                ld      a, 3
                ret
flvnone:        xor     a
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
flgot:          ld      a, (nowbank)    ; the flames are in the background
                push    af              ; bank and the room they go over is
                call    page_bg         ; in the art bank, so the one frame
                ld      de, flbuf       ; wanted is brought across first
                ld      bc, FLAME_BYTES
                ldir
                pop     af
                call    pageset
                ld      hl, flbuf
                ld      (flsrc), hl

                ld      a, (flrect)     ; how much of it is in view
                call    flvis
                or      a
                ret     z

; The flame's three bytes of mask are the same on every one of its rows, so
; they go into the three ANDs below; its pixels are walked in the alternate
; HL, and the room and the working copy are worked out at its top row and
; walked from there.  With all four kept in memory and every row's
; addresses worked out afresh, two torches were a fifth of a frame.

                ld      (flwid + 1), a  ; the bytes the view shows
                ld      b, a
                ld      a, (flrect + 2)
                sub     b
                ld      (flskp + 1), a  ; and those it cut off, past each row
                ld      hl, (flmbase)
                ld      a, (hl)         ; what the room keeps: not the mask
                cpl
                ld      (flm0 + 1), a
                inc     hl
                ld      a, (hl)
                cpl
                ld      (flm1 + 1), a
                inc     hl
                ld      a, (hl)
                cpl
                ld      (flm2 + 1), a
                ld      a, (flrect + 1) ; the room at its top row
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (flrect)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (flroom), hl
                ld      a, (flrect)     ; and the working copy, the camera
                ld      b, a            ; saying where that lands
                ld      a, (cam)
                neg
                add     a, b
                ld      e, a
                ld      a, (flrect + 1)
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de
                ld      (flwork), hl
                ld      hl, flbuf
                exx
                ld      a, (flrect + 3)
                ld      b, a
flrow:          push    bc
                ld      de, (flwork)
                ld      hl, (flroom)
flwid:          ld      c, 0            ; patched: the bytes shown
flm0:           ld      a, 0xff         ; patched: what the room keeps
                and     (hl)
                exx
                or      (hl)            ; and the flame's own pixels
                inc     hl
                exx
                ld      (de), a
                inc     hl
                inc     e               ; a screen row never crosses a page
                dec     c
                jr      z, flrend
flm1:           ld      a, 0xff
                and     (hl)
                exx
                or      (hl)
                inc     hl
                exx
                ld      (de), a
                inc     hl
                inc     e
                dec     c
                jr      z, flrend
flm2:           ld      a, 0xff
                and     (hl)
                exx
                or      (hl)
                inc     hl
                exx
                ld      (de), a
flrend:         exx                     ; past what the view cut off
flskp:          ld      bc, 0           ; patched
                add     hl, bc
                exx
                ld      hl, (flroom)    ; and a row down, in the room and in
                ld      de, ROOM_BYTES  ; the working copy
                add     hl, de
                ld      (flroom), hl
                ld      hl, (flwork)
                call    nextline
                ld      (flwork), hl
                pop     bc
                djnz    flrow
                ret

flvw:           db      0               ; the flame's bytes that are in view

; Colour, which the Spectrum keeps in cells of eight pixels by eight.  The
; map is the room's width and the camera slides over it in whole cells, so
; the window is simply copied out -- again when the view moves.

set_attrs:      ld      hl, SCREEN + 6144
set_attrs_at:   ld      (atbase), hl    ; or the other screen's, for a view
                ld      d, h            ; being made in it
                ld      e, l
                inc     de
                ld      bc, 767
                ld      (hl), INK_ROOM
                ldir

                ld      a, (torches)    ; and red where a torch burns
                or      a
                ret     z
                ld      (flleft), a
                ld      hl, torches + 1
                ld      (flrec), hl
; Colour where a torch burns: the cells its flame actually reaches, as
; mkassets works them out from the flame's own pixels -- a cross for an odd
; column, two cells by three for an even one -- not the three by three box
; the flame is drawn in, which turned the wall around it the same colour.

sanext:         ld      hl, (flrec)
                ld      a, (hl)         ; its column, less the camera
                ld      b, a
                ld      a, (cam)
                neg
                add     a, b
                ld      (sacol), a
                inc     hl
                ld      a, (hl)         ; the top of it, in cells
                ld      c, a
                srl     a
                srl     a
                srl     a
                ld      (sarow), a
                inc     hl              ; past the width, the height and the
                inc     hl              ; size of a frame
                inc     hl
                inc     hl
                ld      a, (hl)         ; the frame offset says which shift
                inc     hl
                or      (hl)
                inc     hl
                ld      (flrec), hl
                ld      hl, flcells
                jr      z, sash
                ld      de, 6
                add     hl, de
sash:           ld      a, c            ; and the top which block row: 4, 67
                cp      67              ; or 130
                jr      c, sarw
                inc     hl
                inc     hl
                cp      130
                jr      c, sarw
                inc     hl
                inc     hl
sarw:           ld      e, (hl)
                inc     hl
                ld      d, (hl)         ; DE = the nine cells, top left first

                ld      a, (sarow)
                ld      b, 3
sarr:           push    bc
                push    af
                ld      a, 3            ; which of the flame's three rows of
                sub     b               ; cells this is, and so its colour
                ld      hl, flcolour
                add     a, l
                ld      l, a
                jr      nc, sarc
                inc     h
sarc:           ld      a, (hl)
                ld      (sacolr), a
                pop     af
                push    af
                ld      l, a            ; thirty two cells to the row
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                ld      bc, (atbase)
                add     hl, bc
                ld      a, (sacol)
                ld      c, a
                ld      b, 3
sacc:           srl     d               ; this cell's bit
                rr      e
                jr      nc, sacskip
                ld      a, c
                cp      32              ; past the right of the view
                jr      nc, sacskip
                push    hl
                add     a, l
                ld      l, a
                jr      nc, sac1
                inc     h
sac1:           ld      a, (sacolr)
                ld      (hl), a
                pop     hl
sacskip:        inc     c
                djnz    sacc
                pop     af
                inc     a
                pop     bc
                djnz    sarr

                ld      hl, flleft
                dec     (hl)
                jp      nz, sanext
                ret

sacol:          db      0
sarow:          db      0
sacolr:         db      0               ; this row's colour
flcolour:       db      INK_FLAME_TOP, INK_FLAME_MID, INK_FLAME_LOW
flcells:        dw      FLCELLS0, FLCELLS1, FLCELLS2  ; shift three
                dw      FLCELLS3, FLCELLS4, FLCELLS5  ; shift seven

; Where a room's torches are.  FRAMEADV.S draws a flame as the B section of
; the block to the torch's RIGHT, one byte in and 43 scanlines above that
; block's A section, so it lands at room pixel 28*col + 35 -- three off a
; byte boundary on an even column and seven on an odd one, which is why two
; shifts of the flame are enough for a whole level.

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
                ld      a, (shcol)      ; only what is in view: showgo does
                call    flvis           ; nothing with a width of none
                ld      (shw), a
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

base_x:         ld      a, (nowbank)    ; the frame tables are in the canvas
                push    af              ; bank, and this is asked from both
                call    page_canvas     ; sides of the paging
                call    frame_index
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
                pop     af              ; and the bank it found
                jp      pageset

; A = the Fcheck byte of the frame he is on, from either side of the paging.

frame_check:    ld      a, (nowbank)
                push    af
                call    page_canvas
                call    frame_index
                ld      de, fcheck
                add     hl, de
                ld      c, (hl)
                pop     af
                call    pageset
                ld      a, c
                ret

; Out: A = the flags of the tile he is standing on.

mfix4:
                org     mpc3              ; into the canvas bank: see MODORG
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
mpc4:
                org     mfix4
ffnone:         xor     a
                ret

mfix5:
                org     mpc4              ; into the canvas bank: see MODORG
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
arow:           ld      a, (blocky)     ; row -1 is the bottom row of the room
                dec     a               ; above, which RDBLOCK's handler goes
                ld      c, a            ; and reads there: GETABOVE asks for it
                jp      tile_in_row     ; the same way from any row

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
                call    frame_index     ; does this frame look for floor?
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
                ld      (charsword), a  ; so that he can grab on
                ld      a, (frame)
                cp      150
                jr      c, cfstep
                cp      180
                jr      nc, cfstep
                call    fightfall_seq   ; from a fighting stance
                jp      jumpseq
cfstep:         ld      a, SQ_STEPFALL
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

; The landing, out of CTRL.S: under OofVelocity he takes it on his feet, a
; storey and a half costs him a life, and past DeathVelocity nothing is left
; to save.  The speed has to be read before it is cleared.

hit_floor:      call    floor_plane
                ld      (chary), a
                ld      a, (yvel)
                ld      b, a
                xor     a
                ld      (yvel), a
                inc     a
                ld      (charact), a
                ld      a, b
                ld      b, SQ_SOFTLAND
                cp      OOFVEL
                jr      c, hfsoft
                cp      DEATHVEL
                jr      nc, hfhard
                ld      a, (charid)     ; guards cannot survive two storeys
                cp      2
                jr      nc, hfhard
                ld      a, 1            ; a storey and a half: one life
                call    decstr
                ld      b, SQ_MEDLAND
                jr      nz, hfland
hfhard:         ld      a, 100          ; POP spends more than he can have
                call    decstr
                ld      b, SQ_HARDLAND
hfland:         ld      a, b
                jp      jumpseq
hfsoft:         ld      a, (charid)     ; a guard always lands en garde, and
                cp      2               ; so does the kid who was
                jr      nc, hfeng
                ld      a, (charsword)
                cp      2
                jr      nz, hfland
hfeng:          ld      a, 2
                ld      (charsword), a
                ld      b, SQ_LANDENGARDE
                jr      hfland

; DECSTR in MISC.S.  A = what to take off him.  Out: Z when that was the last
; of it and he dies.  POP keeps the change in ChgKidStr so the meter can be
; redrawn from it; there is nothing drawing a meter here yet.

mpc5:
                org     mfix5
decstr:         ld      hl, kidstr      ; the kid's, or his opponent's
                ld      b, a
                ld      a, (charid)
                or      a
                ld      a, b
                jr      z, dsgot
                ld      hl, oppstr
dsgot:          cp      (hl)
                jr      c, dsleft
                ld      (hl), 0
                xor     a
                ret
dsleft:         ld      b, a
                ld      a, (hl)
                sub     b
                ld      (hl), a
                ret

; ---------------------------------------------------------------- frames
;
; Out: HL = table entry for the current frame and facing.
;      Entry: width, height, xoff, blob offset (2).

frame_entry:    call    frame_index
                ld      d, h
                ld      e, l
                add     hl, hl          ; six bytes each
                add     hl, de
                add     hl, hl
                ld      de, sprites
                add     hl, de
                ret

; USEALTSETS in CTRLSUBS.S.  Out: HL = where the frame he is on stands in
; every table indexed by frame.  A guard is drawn in ALTSET1 for 150 to 189
; -- himself, out of chtable4 -- and falls in its 172 to 176 for 102 to 106;
; the rest of what he does is done in the kid's own frames.

frame_index:    ld      a, (frame)
                ld      l, a
                ld      h, 0
                ld      a, (charid)
                or      a
                ret     z
                ld      a, l
                cp      102
                ret     c
                cp      107
                jr      nc, fialt
                add     a, 70
fialt:          cp      150
                ret     c
                cp      190
                ret     nc
                ld      l, a
                ld      de, ALT_BASE - 150
                add     hl, de
                ret

; ---------------------------------------------------------------- draw

; He is one picture and the sword in his hand another, as SETUPSWORD adds
; it.  The frame's rectangle -- what is rubbed out, covered by the front and
; shown -- is the two of them together; each is then laid down with a clip
; of its own.  CROPCHAR reads his own picture, so it goes before the sword.

; The two passes are apart so that a second character can go between them:
; see draw_chars.

dp_rect:        call    body_rec
                call    dp_place
                call    crop_char
                ld      hl, newcol
                ld      de, rbody
                ld      bc, 4
                ldir
                call    sword_rec
                jp      z, dp_clip
                call    dp_place
                call    dp_union
                jp      dp_clip

dp_pics:        ld      hl, newcol
                ld      de, runion
                ld      bc, 4
                ldir
                call    body_rec
                call    dp_image
                call    sword_rec
                call    nz, dp_image
                ld      hl, runion
                ld      de, newcol
                ld      bc, 4
                ldir
                ret

; In: HL = where the body puts a thing and DE = where the sword does, each
; with its size two bytes on.  Out: A = where the two together begin and
; B = how far they run.  Either may be off an edge, and a place gone round
; past 255 compares wrongly by value -- so they are compared by difference,
; which is small.

span:           ld      c, (hl)
                ld      a, (de)
                sub     c
                jp      p, spnear
                ld      a, (de)
                ld      c, a
spnear:         ld      a, (hl)
                inc     hl
                inc     hl
                add     a, (hl)
                ld      b, a
                ld      a, (de)
                inc     de
                inc     de
                ex      de, hl
                add     a, (hl)
                sub     b
                jp      m, spfar
                add     a, b
                ld      b, a
spfar:          ld      a, b
                sub     c
                ld      b, a
                ld      a, c
                ret

dp_union:       ld      hl, rbody
                ld      de, newcol
                call    span
                ld      (newcol), a
                ld      a, b
                ld      (neww), a
                ld      hl, rbody + 1
                ld      de, newtop
                call    span
                ld      (newtop), a
                ld      a, b
                ld      (newh), a
                ret

; SETUPSWORD in CTRLSUBS.S.  Sheathing, frames 229 to 237, the sword is seen
; whatever CharSword says; otherwise only while he has it out.  The export
; has folded its offset in with his, so a pose is a frame's record and the
; sword's Fdy after it.  Out: NZ with its picture loaded, Z when none.

sword_rec:      call    page_canvas
                ld      a, (charid)     ; a live guard's is always seen
                cp      2
                jr      nz, srkid
                ld      a, (charlife)
                or      a
                jp      m, srpose
srkid:          ld      a, (frame)
                cp      229
                jr      c, srheld
                cp      238
                jr      c, srpose
srheld:         ld      a, (charsword)
                or      a
                jr      z, srnone
srpose:         call    frame_index
                ld      de, fswd
                add     hl, de
                ld      a, (hl)
                or      a
                jr      z, srnone
                dec     a               ; seven bytes a pose
                ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                or      a
                sbc     hl, de
                ld      de, swposes
                add     hl, de
                push    hl
                ld      de, 6
                add     hl, de
                ld      a, (hl)
                pop     hl
                call    dp_load
                or      1
                ret
srnone:         call    page_art
                xor     a
                ret

body_rec:       call    page_canvas     ; the frame table lives there now
                call    frame_index     ; and Fdy with it, wanted after the
                ld      de, fdy         ; room has been paged back in
                add     hl, de
                ld      a, (hl)
                push    af
                call    frame_entry
                pop     af

; HL = a picture's record -- width, height, the two anchors, the blob -- and
; A = its Fdy.  Into cur*, and the room paged back in.

dp_load:        ld      (curfdy), a
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
                jp      page_art        ; and the room is wanted again

; The anchor is the leading edge, so the offset differs with facing and is
; kept with the sprite rather than worked out here.

dp_place:       ld      a, (curoff)     ; signed, and his coordinate is two
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

                ld      (newcol), a     ; unclipped: dp_clip clips it

; SETUPCHAR: the picture sits at CharY + Fdy, not at CharY.  Every frame of a
; sequence has its own, and that is what carries him up and down within it.

                ld      a, (curfdy)     ; read while the canvas bank was in
                ld      b, a
                ld      a, (chary)
                add     a, b
                ld      (fchary), a
                ld      b, a            ; top row = that, less the height
                ld      a, (curh)
                ld      c, a
                ld      a, b
                sub     c
                inc     a
                ld      (newtop), a

                ld      a, (curw)       ; the shift needs one byte more
                inc     a
                ld      (neww), a
                ld      a, (curh)
                ld      (newh), a
                ret

; Clip him to the thirty two columns the screen has.  The room is 280 wide
; and the view 256, so he can be half off the side of it -- and a byte column
; outside 0..31 is not off the screen at all, it is the next row along, which
; is where the rubbish on the left came from.  What the left edge cuts off is
; skipped in the source too, so the rest still lines up.

dp_clip:        xor     a
                ld      (spskip), a
                ld      a, (newcol)
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
clipdone:       ret

; One picture: placed, clipped, and laid down row by row.  Only now does the
; sprite's bank go over the top of the room.

dp_image:       call    dp_place
                call    dp_clip
                ld      a, (neww)       ; none of it on the screen
                or      a
                ret     z
                call    dfsetup

                call    page_frame

                ld      a, (newh)       ; the calls above have had A
                or      a               ; and no rows is not 256 of them
                ret     z
                ld      b, a
                ld      a, (newtop)
                ld      c, a            ; C = the row in hand
                ld      hl, (curdat)    ; HL = its pairs
                ld      de, (dfrowlen)

; The rows above the screen, and those above the floor that cuts him off,
; are passed over first; then the rows are walked with their addresses in
; hand, the screen's a line down each time and the pairs a row on.  Working
; each one out afresh, and asking both questions of every row, was costing
; more than the bytes themselves once there were two of them fighting.

dpskip:         ld      a, c
                cp      192
                jr      nc, dpnext      ; above the top of the screen
                ld      a, (charcu)
                cp      c
                jr      c, dpgo
                jr      z, dpgo
dpnext:         add     hl, de
                inc     c
                djnz    dpskip
                ret
dpgo:           ld      a, c            ; and none below the foot of it
                add     a, b
                jr      c, dpcut
                cp      193
                jr      c, dpfit
dpcut:          ld      a, 192
                sub     c
                ld      b, a
dpfit:          push    hl
                push    bc
                ld      a, (newcol)
                ld      e, a
                ld      a, c
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de          ; HL = the working copy
                pop     bc
                pop     de
                push    hl
                ld      hl, (dfsrc)     ; DE = the first pair wanted
                add     hl, de
                ex      de, hl
                pop     hl
drawrow:        push    bc
                push    de
                push    hl
dfcall:         call    0               ; dfleft or dfmirror
                pop     hl
                pop     de
                ld      bc, (dfrowlen)  ; on to the next row of pairs
                ex      de, hl
                add     hl, bc
                ex      de, hl
                call    nextline
                pop     bc
                djnz    drawrow
                ret

; A row of him goes straight from its (mask, data) pairs into the working
; copy: each byte through the shift's two tables, the part that stays OR'd
; with what spilled from the pair before, and laid down there and then.  It
; used to go through two buffers and three passes first -- copied aside,
; turned about when he faces right, shifted into (mask, data) pairs, and
; only then blitted -- and that was half of all a frame did.
;
; The alternate registers carry what a row needs from pair to pair: D and E
; the pages of the two tables, B and C what the mask and the data spilled.
;
; The edges come out of CROPCHAR's clipping: spskip bytes cut off at the
; left, neww bytes shown.  Worked out once a frame --
;   dfsrc    how far into a row the first byte to read is
;   dfcnt    how many whole bytes are laid down
;   dfspill  whether the byte the last one spills into is on the screen
; A byte the left edge cut off still spills into the first byte shown, so
; with spskip set the row starts one byte early and reads it for that alone.

dfsetup:        ld      a, (neww)
                ld      c, a
                ld      a, (curw)
                ld      b, a
                ld      (dfrowlen), a
                ld      d, 0
                ld      a, (spskip)
                ld      e, a
                add     a, c            ; skip + shown = pairs + 1: the spill
                dec     a               ; byte is on the screen
                cp      b
                ld      a, c
                jr      nz, dfnospill
                dec     a
                inc     d
dfnospill:      ld      (dfcnt), a
                ld      a, d
                ld      (dfspill), a
                ld      a, e            ; the pair read first, counted from
                or      a               ; the left of the picture as shown:
                jr      nz, dfskip1     ; the one before the first shown
                inc     a
dfskip1:        ld      e, a
                ld      a, (facing)
                or      a
                jr      nz, dfsetm
                ld      a, e            ; facing left, rows run as stored
                dec     a
                ld      hl, dfleft
                ld      bc, dfleft0
                jr      dfset
dfsetm:         ld      a, b            ; facing right, from the end of the
                sub     e               ; row back
                ld      hl, dfmirror
                ld      bc, dfmirror0
dfset:          ld      (dfsrc), a
                ld      a, (curshift)   ; no shift: the loops that need no
                or      a               ; tables
                jr      nz, dfshift
                ld      h, b
                ld      l, c
dfshift:        ld      (dfcall + 1), hl
                rrca                    ; and the tables' pages, for good:
                dec     a               ; two, four and six only
                ld      c, a
                exx
                add     a, shifthi / 256
                ld      d, a
                exx
                ld      a, c
                exx
                add     a, shiftlo / 256
                ld      e, a
                exx
                ret

; No shift at all: the byte is the byte, and nothing spills.

dfleft0:        ld      a, (spskip)
                or      a
                jr      z, dfl0go
                inc     de              ; the byte cut off spills nothing
dfl0go:         ld      a, (dfcnt)
                or      a
                ret     z
                ld      b, a
dfl0pair:       ld      a, (de)
                inc     de
                or      (hl)
                ld      (hl), a
                inc     l
                djnz    dfl0pair
                ret

dfmirror0:      ld      a, (spskip)
                or      a
                jr      z, dfm0go
                dec     de
dfm0go:         ld      a, (dfcnt)
                or      a
                ret     z
                ld      b, a
                exx
                ld      h, revtab / 256
                exx
dfm0pair:       ld      a, (de)
                dec     de
                exx
                ld      l, a
                ld      a, (hl)
                exx
                or      (hl)
                ld      (hl), a
                inc     l
                djnz    dfm0pair
                ret

; In: DE = the first pair to read, HL = where its byte goes.

dfleft:         ld      a, (spskip)
                or      a
                jr      nz, dflcut
                exx                     ; nothing cut off: nothing spilled in
                ld      b, 0
                exx
                jr      dflgo
dflcut:         ld      a, (de)         ; the byte cut off, for its spill
                inc     de
                exx
                ld      l, a
                ld      h, e
                ld      b, (hl)
                exx
dflgo:          ld      a, (dfcnt)
                or      a
                jr      z, dfend
                ld      b, a
dflpair:        ld      a, (de)         ; the byte, and only it: the mask is
                inc     de              ; its complement and the blit is an OR
                exx
                ld      l, a
                ld      h, d
                ld      a, (hl)         ; what stays in this byte
                or      b               ; and what came over from the left
                ld      h, e
                ld      b, (hl)         ; what goes over to the right
                exx
                or      (hl)            ; the room keeps every bit he has not
                ld      (hl), a
                inc     l               ; a screen row never crosses a page
                djnz    dflpair
                jr      dfend

; Facing right: the pairs from the end of the row back, and every byte with
; its bits turned about on the way to the shift.

dfmirror:       ld      a, (spskip)
                or      a
                jr      nz, dfmcut
                exx
                ld      b, 0
                exx
                jr      dfmgo
dfmcut:         ld      a, (de)
                dec     de
                exx
                ld      l, a
                ld      h, revtab / 256
                ld      l, (hl)
                ld      h, e
                ld      b, (hl)
                exx
dfmgo:          ld      a, (dfcnt)
                or      a
                jr      z, dfend
                ld      b, a
dfmpair:        ld      a, (de)
                dec     de
                exx
                ld      l, a
                ld      h, revtab / 256
                ld      l, (hl)
                ld      h, d
                ld      a, (hl)
                or      b
                ld      h, e
                ld      b, (hl)
                exx
                or      (hl)
                ld      (hl), a
                inc     l
                djnz    dfmpair

; The byte the last one spills into: what came over, laid on the room the
; same way.  The spill lives in the alternate B, the screen address in the
; main HL -- and A is A in both sets.

dfend:          ld      a, (dfspill)
                or      a
                ret     z
                exx
                ld      a, b
                exx
                or      (hl)
                ld      (hl), a
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

; Putting the foreground back over him is hide_behind, with the fight.

; Walk the sprite's rows and lay the mask's own pixels back over him.  Three
; things line up on each row: the mask, the room the mask picks out of, and
; the working copy he was drawn into.

cover_rows:     ld      a, (neww)       ; likewise: djnz would go round
                or      a               ; 256 times for none of him
                ret     z
                ld      a, (newcol)     ; first: mastercol has B, which is
                call    mastercol       ; about to be the rows
                ld      (masterc), a
                ld      a, (newh)
                or      a
                ret     z
                ld      b, a
                ld      a, (newtop)
                call    cliprows        ; C = his first row on the screen
                ret     c
                ld      a, c
                ld      (rowy), a

; The room and the working copy are worked out at his first row and walked
; from there, a row at a time, and so is the mask, from one row of it to the
; next: a front piece is tall, and its rows follow on.  Worked out afresh for
; every row they cost more than laying the mask down did.

                ld      a, c
                call    mul35
                ld      de, room
                call    covercol
                ld      (covr), hl
                ld      a, (newcol)
                ld      e, a
                ld      a, c
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de
                ld      (covw), hl
                ld      a, 0xfe         ; no row of the mask in hand yet
                ld      (covi), a

coverrow:       push    bc
                ld      a, (rowy)
                ld      l, a
                ld      h, 0
                ld      de, (coverb)
                add     hl, de
                ld      a, (hl)         ; the mask's row for this line, or -1
                cp      0xff
                jr      z, covernxt     ; the mask has nothing on this one
                ld      c, a
                ld      a, (covi)       ; the one after the last: a step on
                inc     a
                cp      c
                ld      a, c
                ld      (covi), a
                ld      hl, (covm)
                ld      de, ROOM_BYTES
                add     hl, de
                jr      z, covmask
                call    mul35           ; or worked out, the first of a run
                ld      de, (coverm)
                call    covercol
covmask:        ld      (covm), hl
                ld      hl, (covw)      ; the working copy, into the
                push    hl              ; alternate DE
                exx
                pop     de
                exx
                ld      hl, (covm)      ; the mask
                ld      de, (covr)      ; the room
                ld      a, (neww)
                ld      b, a
                call    cover_apply
covernxt:       ld      hl, (covr)      ; a row down, in the room and in the
                ld      de, ROOM_BYTES  ; working copy
                add     hl, de
                ld      (covr), hl
                ld      hl, (covw)
                call    nextline
                ld      (covw), hl
                ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    coverrow
                ret

covercol:       add     hl, de          ; HL = a row, DE its base: the byte
                ld      a, (masterc)    ; under his left edge
                ld      e, a
                ld      d, 0
                add     hl, de
                ret

; In: HL = mask, DE = room, the alternate DE = working copy, B = bytes.
; Where the mask has a bit the room's goes in, and elsewhere his stays:
; work ^ ((work ^ room) & mask).

cover_apply:    ld      a, (hl)
                or      a
                jr      z, covernext
                ld      a, (de)
                exx
                ex      de, hl
                xor     (hl)
                exx
                and     (hl)
                exx
                xor     (hl)
                ld      (hl), a
                ex      de, hl
                exx
covernext:      inc     hl
                inc     de
                exx
                inc     e               ; a screen row never crosses a page
                exx
                djnz    cover_apply
                ret

; ---------------------------------------------------------------- erase
;
; Put the room back over where the sprite was, in the working copy.

erase_prince:   ld      hl, oldcol + OP ; the guard where he was, then the kid
                call    eraseset
                ld      hl, oldcol
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
                ld      (erwid + 1), a
                ld      a, (erh)
                or      a
                ret     z
                ld      b, a
                ld      a, (ertop)
                call    cliprows
                ret     c
                call    rowcount
                ld      a, c            ; the room's row, under the view
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (ercol)
                call    mastercol
                ld      e, a
                ld      d, 0
                add     hl, de
                push    hl
                ld      a, (ercol)      ; and the working copy's
                ld      e, a
                ld      a, c
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de
                ex      de, hl
                pop     hl
eraserow:       push    hl
                push    de
                ld      b, 0
erwid:          ld      c, 0            ; patched with the width
                ldir
                pop     hl              ; the working copy walks as the screen
                call    nextline        ; does: it is the screen, moved up
                ex      de, hl
                pop     hl
                ld      bc, ROOM_BYTES
                add     hl, bc
                exx
                dec     b
                exx
                jr      nz, eraserow
                ret

; The rows of a rectangle that are on the screen.  A top of 192 or more is
; above it -- he is drawn from his feet up, and his head can be over the
; top -- and a band can run past the foot of it.
;
; In: A = the top row, B = rows.  Out: carry when none are on it; otherwise
; C = the first on it, B = how many.

cliprows:       cp      192
                jr      c, crbot
                neg                     ; this many above the screen
                cp      b
                ccf
                ret     c
                ld      c, a
                ld      a, b
                sub     c
                ld      b, a
                xor     a
crbot:          ld      c, a
                add     a, b
                jr      c, crcut
                cp      193
                jr      c, crfit
crcut:          ld      a, 192
                sub     c
                ld      b, a
crfit:          or      a
                ret

; The row count goes into the alternate B, which the tight loops count on,
; so that the whole of BC is theirs for LDIR.

rowcount:       ld      a, b
                exx
                ld      b, a
                exx
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

show_rect:      ld      hl, flipnow     ; the view made behind is ready:
                ld      a, (hl)         ; turned round now, while the beam is
                ld      (hl), 0         ; still in the border -- and the
                or      a               ; screen that goes behind is no view
                jr      z, shnoflip     ; at all any more
                call    flip
                ld      a, 0xff
                ld      (vwcam), a
shnoflip:
                ld      a, (fullshow)
                or      a
                jr      z, showmine

; The view has moved and the whole screen is being redrawn from the room --
; six kilobytes, which is longer than the beam takes to cross the screen, so
; it is seen while it happens.  His own bytes therefore go down with the row
; they belong to rather than in a pass of their own: a row is never on screen
; without him, and the tear that is left is the room sliding, nothing more.

                xor     a
                ld      (fullshow), a
                ld      (dirtyn), a
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
                ld      de, newcol
                call    fs_sprite
                ld      hl, (rowptr)
                ld      de, newcol + OP
                call    fs_sprite
                pop     hl
                call    nextrow
                pop     bc
                djnz    fsrow
                call    set_attrs       ; the colour slides with the view
                ld      a, 0xff         ; painted into bank 5, so bank 5 is
                ld      (vwcam), a      ; the one to show -- and a view being
                xor     a               ; made anywhere is made over
                call    setvis
                jp      show_flames

; The rectangles go to whichever screen is shown, bank 7 paged in case it is.

showmine:       ld      a, BANK_CANVAS
                call    pageset
                call    showpart
                jp      page_art

; In: HL = the screen address of column zero on this row.  Puts down the part
; of the sprite that falls on it, if any.

; DE = the rectangle: col, top, width, height.

fs_sprite:      ld      a, (de)
                ld      c, a            ; C = col
                inc     de
                ld      a, (de)
                ld      b, a            ; B = top
                inc     de
                ld      a, (de)
                or      a
                ret     z
                push    af              ; the width
                inc     de
                ld      a, (rowy)
                sub     b               ; how far into him this row is
                ld      b, a
                ld      a, (de)
                cp      b
                jr      c, fsnone
                jr      z, fsnone
                ld      e, c
                ld      d, 0
                add     hl, de
                ld      d, h
                ld      e, l            ; DE = screen
                ld      bc, work - SCREEN
                add     hl, bc          ; HL = working copy
                pop     af
                ld      c, a
                ld      b, 0
                ldir
                ret
fsnone:         pop     af
                ret

; Two rectangles reach the screen, not the box around them: where he was and
; where he is.  The box would take in corners neither of them covers, and the
; working copy is only ever put right under the two.

showpart:       ld      a, (dirtyn)     ; whatever the block redraws changed,
                or      a               ; a rectangle at a time
                jr      z, showold
                ld      b, a
                ld      hl, dirtyq
showdq:         push    bc
                push    hl
                call    show_one
                pop     hl
                ld      de, 4
                add     hl, de
                pop     bc
                djnz    showdq
                xor     a
                ld      (dirtyn), a
showold:        ld      hl, boxcol      ; where each was and is, as one: see
                call    show_one        ; draw_chars
                ld      hl, boxcol + OP
                call    show_one
                jp      show_flames

show_one:       ld      de, shcol       ; col, top, width, height, in order
                ld      bc, 4
                ldir

showgo:         ld      a, (shw)        ; none of him on screen: LDIR would
                or      a               ; read a width of zero as 65536 and
                ret     z               ; take the stack with it
                ld      (shwid + 1), a
                ld      a, (shh)
                or      a
                ret     z
                ld      b, a            ; B is the row count, not the width
                ld      a, (shtop)
                call    cliprows
                ret     c
                call    rowcount
                ld      a, (shcol)
                ld      e, a
                ld      a, c
                call    scraddr
showrow:        push    hl
                ld      a, h            ; DE = the screen shown: 0x80 up when
scrsel:         or      0               ; that is bank 7
                ld      d, a
                ld      e, l
                ld      a, h            ; HL = working copy, the same place
                add     a, (work - SCREEN) / 256        ; a whole number
                ld      h, a                            ; of pages up
                ld      b, 0
shwid:          ld      c, 0            ; patched with the width
                ldir
                pop     hl
                call    nextline
                exx
                dec     b
                exx
                jr      nz, showrow
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
                ld      a, (rdcol)      ; five bytes for a block, nine when
                add     a, REDWIDE      ; the piece reaches past it
                ld      b, a
                ld      a, (redwide)
                or      a
                jr      z, rswide1
                ld      a, b
                add     a, 4
                ld      b, a
rswide1:
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
                push    bc
                ld      a, (rowy)       ; the room's row, stepped by 35 from
                call    mul35           ; here on rather than multiplied out
                ld      de, room        ; for every one
                add     hl, de
                ld      a, (rdstart)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (rsroomp), hl
                pop     bc
rsrow:          push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, rsskip
                call    line_addr
                ld      de, work - SCREEN
                add     hl, de
                ex      de, hl          ; DE = the working copy
                ld      hl, (rsroomp)   ; HL = the room
                ld      a, (rdw)
                ld      c, a
                ld      b, 0
                ldir
                jr      rsnext
rsskip:         call    startrows
rsnext:         ld      hl, (rsroomp)
                ld      de, 35
                add     hl, de
                ld      (rsroomp), hl
                ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    rsrow
                ret

rsroomp:        dw      0

; The rectangle a block redraw left behind, queued for the top of the next
; frame -- before his own two, so that he wins.  One rectangle each, never
; the box around them: the working copy is only right under the rectangles
; themselves, and after the view has moved everything else in it is the room
; a byte out.  The box round a gate at one end and a plate at the other sent
; all of that to the screen, beside and above the plate, and it stayed there.
; Growing the box used B, too, which redshow is counting its rows in.
;
; Out: BC as it was.

DIRTYMAX        equ     6

dirty_add:      ld      a, (dirtyn)
                cp      DIRTYMAX
                jr      c, dirtyset
                ld      a, 1            ; more than a frame ever has: the whole
                ld      (fullshow), a   ; screen comes from the room instead
                ret

dirtyset:       ld      l, a            ; four bytes to a rectangle, in the
                inc     a               ; order show_one takes them
                ld      (dirtyn), a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      de, dirtyq
                add     hl, de
                ld      a, (linecol)
                ld      (hl), a
                inc     hl
                ld      a, (rowy)
                ld      (hl), a
                inc     hl
                ld      a, (rdw)
                ld      (hl), a
                inc     hl
                ld      a, (redh)
                ld      (hl), a
                ret

rdcol:          db      0
rdstart:        db      0
rdw:            db      0
redh:           db      63
dirtyn:         db      0               ; rectangles waiting for the blit

; Remember where the sprite went, so the next frame can rub it out.

keep_rect:      ld      hl, newcol
                ld      de, oldcol
                ld      bc, 4
                ldir
                ld      hl, newcol + OP ; and the guard's
                ld      de, oldcol + OP
                ld      c, 4
                ldir
                ret

; ---------------------------------------------------------------- helpers
;
; A = scanline, E = byte column.  Out: HL = screen address.

; In: A = a scanline, E = a byte column.  Out: HL = the screen address.
; Worked out, not looked up: each pass asks for its first row only and
; walks the rest with nextline, and the table was 384 bytes of the map.

scraddr:        ld      l, a            ; 010 t t l l l -- the third, and the
                and     0x07            ; line within the character row
                or      0x40
                ld      h, a
                ld      a, l
                rra
                rra
                rra
                and     0x18
                or      h
                ld      h, a
                ld      a, l            ; r r r c c c c c -- the character
                rla                     ; row, and the column
                rla
                and     0xe0
                add     a, e
                ld      l, a
                ret

                include "bg.asm"

; ---------------------------------------------------------------- data



; POP's Char: the character in hand -- the kid, or the guard while his turn
; runs -- and Op, the other one, laid out byte for byte the same.  LoadShadwOp
; and SaveShadwOp are then one exchange of the two, and every routine written
; for the kid works on the guard unchanged; what one asks of the other is at
; its own field plus OP.  The rectangles he is drawn in and rubbed out of go
; with him: show_one and keep_rect copy them four bytes at a time -- col, top,
; width, height, in that order -- so nothing may be put between them.  A byte
; slipped into the middle of the old rectangle once sent the blitter a garbage
; height.

chrec:
charx:          dw      0
chary:          db      0
facing:         db      0               ; 0 left, 1 right
frame:          db      0
seqptr:         dw      0
blocky:         db      0
yvel:           db      0
charact:        db      1
charsword:      db      0               ; CharSword: 2 with it out, en garde
charid:         db      0               ; CharID: 0 the kid, 2 a guard
charlife:       db      0xff            ; CharLife: negative while he lives
charcu:         db      0               ; FCharCU, the row his picture is cut at
newcol:         db      0
newtop:         db      0
neww:           db      0
newh:           db      0
oldcol:         db      0
oldtop:         db      0
oldw:           db      0
oldh:           db      0
boxcol:         db      0               ; the two of them together: rubbed out
boxtop:         db      0               ; as one, and shown as one
boxw:           db      0
boxh:           db      0
CHRECLEN        equ     $ - chrec
oprec:          ds      CHRECLEN
OP              equ     oprec - chrec

jarabove:       db      0               ; 1 the row above, -1 his own
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
fchary:         db      0
curleft:        dw      0
croprow:        db      0
croptop:        db      0
kidstr:         db      3               ; initmaxstr in TOPCTRL.S
wanted:         db      0

curw:           db      0
curh:           db      0
curoff:         db      0
curshift:       db      0
curdat:         dw      0
curbank:        db      0
curent:         dw      0
rowy:           db      0

rawcol:         db      0               ; where his picture wanted to go,
spskip:         db      0               ; and what the left edge cut off
frstart:        db      0               ; the interrupt this frame began on
tilestate:      db      0               ; the state of the tile last read
gotsword:       db      START_SWORD               ; he has picked the sword up: CTRL.S
                                        ; asks it before he may draw on anyone
rbody:          ds      4               ; where his own picture goes
runion:         ds      4               ; and the frame's, with the sword
curfdy:         db      0               ; SETUPCHAR's Fdy for this frame
collidel:       db      0               ; CHECKBARR and its helpers
collider:       db      0
collx:          db      0
collface:       db      0
bythis:         db      0
bylast:         db      0
begrange:       db      0
endrange:       db      0
cdleft:         db      0               ; CDLeftEj and CDRightEj, 140 wide
cdright:        db      0
cbrow:          db      0
cbidx:          db      0
cbedge:         db      0               ; blockedge
cccode:         db      0               ; the barrier code in hand
cbcd:           dw      0
cbsn:           dw      0
tempbx:         db      0               ; RDBLOCK's tempblockx, tempblocky
tempby:         db      0               ; and tempscrn
tempscrn:       db      0
dbcol:          db      0
fwdbx:          db      0               ; CharBlockX, the block in front, and
fwdinx:         db      0               ; what is in it
fwdid:          db      0
barl:           db      0, 12, 2, 0, 0  ; BarL and BarR, 140 wide
barr:           db      0, 0, 9, 11, 0
snlast:         db      255, 255, 255, 255, 255, 255, 255, 255, 255, 255
snthis:         db      255, 255, 255, 255, 255, 255, 255, 255, 255, 255
snabove:        db      255, 255, 255, 255, 255, 255, 255, 255, 255, 255
snbelow:        db      255, 255, 255, 255, 255, 255, 255, 255, 255, 255

cam:            db      0               ; the view's left edge, in bytes
fullshow:       db      0
vwcam:          db      0xff            ; the view being made, or none
vwatt:          db      0               ; its colours still to do
vwrow:          db      0               ; where to look for its next row
vwcnt:          db      0               ; how many rows it still wants
vwfirst:        db      0               ; the run in hand: its first row
vwn:            db      0               ; and how many
flipnow:        db      0               ; show it at the top of the next frame
nohalt:         db      0               ; the fill ran up to the interrupt
vwwait:         db      0               ; a step is due: the queue waits
vwstop:         db      0               ; the one it runs up to
vwmin:          db      0               ; rows still owed it this frame
atbase:         dw      0               ; the colours set_attrs writes
masterc:        db      0
coverm:         dw      0
covm:           dw      0               ; cover_rows' three: the mask's row,
covr:           dw      0               ; the room's and the working copy's,
covw:           dw      0               ; and which row of the mask that is
covi:           db      0
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

dfrow:          dw      0               ; the fused row's pair, and its
dfrowlen:       dw      0               ; bookkeeping: see dfsetup
dfsrc:          dw      0
dfcnt:          db      0
dfspill:        db      0

                ds      64
stack:

cmpspace:       incbin  "cmpspace.bin"
cmpbarr:        incbin  "cmpbarr.bin"
floory:         incbin  "floory.bin"
blocktop:       incbin  "blocktop.bin"
floorband:      incbin  "floorband.bin"
torches:        ds      1 + 6 * 7
flametab:       incbin  "flametab.bin"
flamemask:      incbin  "flamemask.bin"
                ds      (($ + 255) / 256 * 256) - $
shifthi:        incbin  "shifthi.bin"
shiftlo:        incbin  "shiftlo.bin"
revtab:         incbin  "revtab.bin"
codeend:

; ---------------------------------------------------------------- the fight
;
; The working copy ends 0x800 short of the window, and nothing below the
; window has ever been written there -- the room build runs up to 0xB2A0 at
; most.  The guard and the fight go in it, assembled in place and carried on
; the tape after a gap: see build.sh.

HICODE          equ     (codeend + 0x7FF) / 0x800 * 0x800 + 6144
hifix:
                org     HICODE
                include "fight.asm"
hiend:
                org     hifix

; ---------------------------------------------------------------- start
;
; What runs once, before the working copy is first written, sits where the
; working copy goes: it comes in with the program and the first repaint goes
; over it, so the fixed half of the map keeps its room for the game.

start:          di
                ld      sp, stack
                im      1

                xor     a
                out     (254), a

                call    check_banks     ; before anything is written

                ld      a, BANK_CANVAS  ; the frame table and the sequences
                call    pageset         ; came in at the window, where the
                ld      hl, 0xC000 + SPAREALL - 1       ; second screen goes:
                ld      de, sprites + SPAREALL - 1      ; up past it they go,
                ld      bc, SPAREALL                    ; last byte first, as
                lddr                                    ; the two overlap

                ld      a, BANK_CVS     ; and the code that builds a room put
                call    pageset         ; by, for the rooms after this one:
                ld      hl, roomblk     ; past the canvas and its masks
                ld      de, RBAT1
                ld      bc, RB1LEN
                ldir
                call    page_art
                call    newroom         ; and the room is composed, not loaded
                call    readlinks
                call    set_attrs

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
                call    camhome         ; and the view where he is, not adrift
                call    page_canvas
                ld      a, SQ_STAND
                call    jumpseq
                call    page_canvas
                call    step_seq
                call    add_guard       ; and whoever keeps the room
                call    page_art
                jp      start2

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

initend:

; ---------------------------------------------------------------- a room
;
; The code only the building of a room reaches -- composing it, repacking
; it, the masks, the torches, the links -- is wanted only while a room is
; being built, which happens behind the black screen with the working copy
; not yet written.  So it is assembled where the working copy goes, comes in
; with the program, is put by in two banks at startup, and roomrest puts it
; back each time a room is entered; the repaint after goes over it.  Twelve
; hundred bytes of the fixed half of the map are the game's again.

roomblk:
                include "roomblk.asm"
roomend:

; The two banks it is kept in, and how much of it each one holds.  The
; lengths are the block's own, not what is free past the tables: roomrest
; copies exactly these back over the working copy, and the canvas moved down
; when the sprites lost their masks, which would have made the second of
; them nine kilobytes of whatever lies beyond.

RBAT1           equ     HALFCAN + CANVAS_W * 45 ; past the canvas and masks

; The control code -- GENCTRL and all it calls, the sequence interpreter and
; the checks for walls and floors -- runs only while the canvas bank is in,
; for the sequences and the frame tables, so that is where it lives: past the
; tables, in the room the masks left.  It is assembled here, in place, between
; the org pairs round each piece, cut out of pop.bin by build.sh and carried
; up with the tables.  What it calls outside restores the bank it found.

modend          equ     mpc6
MODLEN          equ     modend - MODORG
SPAREALL        equ     SPARE_LEN + MODLEN
RB1LEN          equ     roomend - roomblk

; ----------------------------------------------------------- under the load
;
; Between the system variables and org lies the tape's BASIC loader: the
; program, its variables, and the stack CLEAR left it.  All of it is wanted
; until the last RANDOMIZE USR -- the stubs return into BASIC so it can load
; the next bank -- and none of it after: start takes the stack with its first
; instruction and never goes back.  So the buffers that hold nothing at load
; time live down there instead of in the image, and the image is that much
; smaller.  Nothing here is read before the game begins, and nothing here is
; loaded from the tape.
;
; The ROM's interrupt handler keeps the frame counter and scans the keyboard
; in the system variables below, which is why the block stops short of them.
;
; Order matters in two places: aboverow is read from -2, which is the tail of
; belowrow, and the four cd* are walked ten bytes apart.

LOWBUF          equ     24320 - 490     ; the block ends just under org

frontlist       equ     LOWBUF                      ; five bytes an entry, as
roomids         equ     frontlist + MAXFRONT * 5    ; frontrec writes them
flbuf           equ     roomids + 60                ; thirty ids, then states
rqq             equ     flbuf + FLAME_BYTES         ; one frame of a flame
rqs             equ     rqq + 4 * RQMAX             ; row, column, band, wide
cvbuf           equ     rqs + 4 * RQSMAX
dirtyq          equ     cvbuf + CANVAS_W            ; col, top, width, height
belowrow        equ     dirtyq + 4 * DIRTYMAX
aboverow        equ     belowrow + 20               ; the ceiling: the bottom
moblist         equ     aboverow + 20               ; row of the room above
flstate         equ     moblist + MOBLEN * MAXMOB
cdlast          equ     flstate + 8                 ; each ten on from the
cdthis          equ     cdlast + 10                 ; one before
cdabove         equ     cdthis + 10
cdbelow         equ     cdabove + 10
LOWTOP          equ     cdbelow + 10

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

;
; The erase walks it with nextline, which steps a screen address from one
; scanline to the next, and that holds for the copy only if it sits a whole
; number of eight pages above the screen: on a 2K boundary, then -- A800,
; with the code ending before it.  A page short of that, every eighth row of
; the erase went down on the wrong line.

work            equ     (codeend + 0x7FF) / 0x800 * 0x800

                end     start
