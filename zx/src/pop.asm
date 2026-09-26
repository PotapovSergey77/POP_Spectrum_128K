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

cutfixed        equ     roomblk         ; PlayCut0's pictures: see mkassets
                include "assets.inc"
                include "bg.inc"
MODORG          equ     sprites + SPARE_LEN     ; the control code: see modend

; The background set's own code, in its bank with its pictures: bgovl.asm.
; Its entries, three bytes apart.

ovstart         equ     bgovl + 3       ; the top of a frame, from c1anim
ovpost          equ     bgovl + 6       ; after the frame's moves, c1post
ovset           equ     bgovl + 9       ; the set into the program: newroom
ovflame         equ     bgovl + 12      ; a torch's frame into flbuf
ovattr          equ     bgovl + 15      ; the palace's colours, into imgbuf

; And between the last system variable the 48K ROM's interrupt touches and
; the bottom of the stack, what 48K BASIC kept its channels in: nothing uses
; it now, and twenty of the drawing's bytes live there, which start makes
; nought as the program they came out of had them.  Here, ahead of bg.asm:
; pasmo takes an equ on an equ not yet defined as nought.

LOWVARS         equ     23734

; Below that, system variables the 48K ROM has no use for once BASIC is
; gone -- its interrupt keeps to KSTATE, LAST_K, REPDEL, REPPER, FLAGS, MODE,
; FLAGS2 and FRAMES, and LD-BYTES reads BORDCR -- and many of the fixed
; code's variables live there: from just past FRAMES, and between the ROM's
; own from 0x5C0B, at the addresses they are given where they are declared.
; start makes the lot nought, the ROM's with them, from SYSLOW to LOWVARS'
; end.

SYSLOW          equ     0x5C0B
SYSVARS         equ     23675
SYSVARLEN       equ     59

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
WTLESS_G        equ     1               ; SUBS.S, weightless
WTLESS_TERM     equ     4
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
mwcp:           cp      FRAME_WAIT      ; full, which a frame that overran has
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
                ld      hl, c1anim      ; the trans list first, as NextFrame
                call    c1jp            ; has it, and EnemyAlert
                call    input_step      ; everything down to here starts one
                call    step_seq
                call    firstguard
                call    check_barr
                call    check_floor
                call    do_fall
                call    checkspikes     ; spikes near him spring, and running
                call    checkimpale     ; or jumping on to them is death
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
                ld      hl, c1post      ; the rest of NextFrame that lives
                call    c1jp            ; in CODE1
                call    animmobs
                call    draw_chars      ; and the floor and the front back
                call    page_art        ; over him: see kid_pics
                call    rq_run          ; and the redrawing, as time allows
                call    vw_fill         ; and the view ahead, to the very end
                jp      main

; The background's code comes next, ahead of the rest of the fixed half: it
; is little of what a frame runs, and the low end of the map, up to 0x8000,
; is the memory the ULA holds up.  What a frame spends its time in -- the
; blits, the torches, the rubbing out and the showing -- goes above it.

                include "bg.asm"

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

roomwin:        call    roomrow
                ld      a, (cam)
                ld      e, a
                ld      d, 0
                add     hl, de
                ret

; A = a number.  Out: HL = ten of it, DE = two.

mul10:          ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de
                ret

; A = a room byte column.  Out: A = the screen's, B = the room's.

subcam:         ld      b, a
                ld      a, (cam)
                neg
                add     a, b
                ret

; A = a row.  Out: HL = the room's first byte on it.

roomrow:        call    mul35
                ld      de, room
                add     hl, de
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

repaint:        ld      a, 1
                ld      (gddirty), a
                xor     a
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
; step as he passes 44, 78 and 112 pixels from the left edge of the screen --
; the first past where level one's drop leaves him, so the level opens on
; the room's own left edge; facing left, 16, 64 and 112 from the right.
; They are that far apart so that the next view can be made between them
; even running -- some five frames on the real machine.  The view only ever steps the way he faces, so a
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
                ld      a, (frame)      ; up the stairs he is turned to face
                or      a               ; left, and moved: the view stays put
                ret     z               ; through climbstairs, 217 to 228 and
                cp      217             ; the blank frames after
                jr      c, camgo
                cp      229
                ret     c
camgo:          call    camsched        ; C = where the rule puts the view
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

; A = the camera the rule gives: how many of the three steps, the way he
; faces, he has passed.  In the room's pixels, where each step lands for the
; view it starts from -- 44, 86 and 128 facing right; facing left 264, 208
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
                db      44, 86, 128     ; facing right

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
                call    vwbit           ; the first row's bit, and each next
                ld      d, a            ; row the next one along: a slicer's
vm1:            ld      a, c            ; fifty eight rows were 15000 T
                cp      192             ; worked out one by one
                ret     nc
                ld      a, d
                and     (hl)
                jr      nz, vm2         ; wanted already
                ld      a, d
                or      (hl)
                ld      (hl), a
                push    hl
                ld      hl, vwcnt
                inc     (hl)
                pop     hl
vm2:            inc     c
                rrc     d
                jr      nc, vm3
                inc     hl
vm3:            djnz    vm1
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
; happens, so the view has until then.  And when the view has had nothing
; for VWHUNG frames, VWMIN runs go whatever the clock says: on a machine
; slower than this one a frame had nothing left over, and the view never
; moved at all.  Only then: in a fight a frame's own work runs well into its
; last period, and runs owed every frame made it late.

VWMIN           equ     2
VWHUNG          equ     2
VWBATCH         equ     4

vw_fill:        ld      a, (vwcam)
                inc     a
                ret     z               ; no view in hand
                call    vwdue
vwcp:           cp      FRAME_WAIT
                jr      nc, vwgoal
vwld:           ld      a, FRAME_WAIT - 1
vwgoal:         inc     a
                ld      (vwstop), a
                ld      hl, vwhung      ; gone hungry: runs owed, and
                ld      a, (hl)         ; otherwise none, and only as time
                inc     (hl)            ; allows
                cp      VWHUNG
                sbc     a, a
                cpl
                and     VWMIN
                ld      (vwmin), a
                jr      z, vwtime
vwf1:           ld      a, (vwatt)
                or      a
                jr      nz, vwfatt
                call    vwany
                ret     z               ; ready, and waiting for him
                call    vw_batch
                jr      vwf2
vwfatt:         call    vw_attrs
vwf2:           xor     a
                ld      (vwhung), a
                ld      hl, vwmin       ; the runs it has whatever happens
                dec     (hl)
                jp      p, vwf1
                inc     (hl)
vwtime:         call    vwdue
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
                call    roomrow
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
                jr      page_art

; The room's code back where it runs, from the two banks it is kept in: see
; roomblk.  Only ever with the screen black and the working copy unwritten.

roomrest:       ld      a, BANK_CVS
                call    pageset
                ld      hl, RBAT1
                ld      de, roomblk
                ld      bc, RB1LEN
                ldir
                jr      page_art

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

; CODE1, the canvas bank's own code, from the rest of the program.  c1jp
; goes in at HL with that bank paged, for a caller that pages what it wants
; afterwards; c1call puts back the bank that was in -- the control code's
; own, say.  And c1far is CODE1's way out: a routine of the fixed half at
; HL, which may page what it likes, and the canvas bank back after it.

; CODE1's way into the background set's code (bgovl.asm): by c1far, with
; HL = bgjp and DE = the entry, which returns to c1far.

bgjp:           call    page_bg
                ex      de, hl
                jp      (hl)

; And from the fixed half, DE the entry and HL what it takes: the bank that
; was in, back after it.

bgcall:         ld      a, (nowbank)
                push    af
                call    bgjp
                pop     af
                jr      pageset

c1call:         ld      a, (nowbank)
                push    af
                call    c1jp
                pop     af
                jr      pageset
c1jp:           call    page_pixels
jphl:           jp      (hl)
c1far:          call    jphl
                push    af
                call    page_pixels
                pop     af
                ret

; And the same for the control code, which lives in the canvas bank: HL its
; routine, A whatever that routine takes -- paging has A, so it is kept --
; and the canvas bank back after it.

c1mod:          push    af
                call    page_canvas
                pop     af
                call    jphl
                push    af
                call    page_pixels
                pop     af
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

; En garde a frame is a period longer: the Apple, which draws as fast as it
; can, slows down with two of them fighting, and three periods made the
; fight run away.  The frame's slot -- mainwait, the view and the redraw
; all count it -- is FRAME_WAIT, or one more with his sword out.

input_step:     ld      a, (charsword)
                and     2
                rrca
                add     a, FRAME_WAIT
                ld      (mwcp + 1), a
                ld      (vwcp + 1), a
                dec     a
                ld      (vwld + 1), a
                ld      (rqcp + 1), a
                ld      a, (charlife)   ; PLAYERCTRL: no strength left, no
                or      a               ; life -- once
                jp      p, isalive
                ld      a, (kidstr)
                or      a
                jr      nz, isalive
                ld      (charlife), a
isalive:        call    stun_tick
                call    read_input
                call    facejstk
                call    ctrl
                jr      facejstk

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
ctrlclr:        jr      clrall

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
                jr      z, standing
                cp      48
                jp      z, turning
                cp      50
                jr      c, ctrl0
                cp      53
                jr      c, standing     ; turn 7-8-9 and the crouch
ctrl0:          cp      4
                jp      c, starting     ; run 4-5-6
                cp      67              ; 6502 carry is the other way round:
                jr      c, ctrl4        ; bcc means below, which is jr c here
                cp      70
                jp      c, stjumpup
ctrl4:          cp      15
                jp      c, running      ; run 8-17
                cp      87
                jr      c, ctrl1
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
                ld      a, (btn)        ; button up: a fresh push forward
                or      a               ; runs, before anything else
                jr      nz, stbtn
                ld      a, (clrf)
                or      a
                jp      m, do_startrun
stbtn:          ld      a, (clrb)       ; then, button or not, the same three
                or      a
                jp      m, do_turn
                ld      a, (clru)
                or      a
                jp      m, do_up
                ld      a, (clrd)
                or      a
                jp      m, do_down
                ld      a, (jstkx)      ; and held forward: a run, button up,
                or      a               ; a careful step on a fresh push with
                ret     p               ; it down
                ld      a, (btn)
                or      a
                jr      z, do_startrun
                ld      a, (clrf)
                or      a
                ret     p
                jp      do_stepfwd

; No point starting a run into a wall, or he twitches on the spot.

; DoStartrun.  Very close to a barrier it becomes a careful step instead --
; but not a slicer, which he may run at -- and it clears no flag of its own.

do_startrun:    call    get_fwd_dist
                ld      b, a
                ld      a, (fwdkind)
                cp      1               ; a barrier ahead?
                jr      nz, srgo
                ld      a, (fwdid)
                cp      BG_SLICER
                jr      z, srgo
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
                jp      m, climb_up     ; up: climb
hangbtn:        ld      a, (btn)
                or      a
                jr      z, hangdrop     ; let go of the button, let go of the
                                        ; ledge
                ld      a, (charact)    ; hanging on the side of a block is
                cp      6               ; hanging straight
                jr      z, hangcont
                call    under_flags     ; hanging on the side of a block
                cp      BLK_BLOCK
                ld      a, SQ_HANGSTRAIGHT
                jp      z, jumpseq
hangcont:       call    above_flags     ; the ledge crumbles away -- a loose
                call    cmp_space       ; floor he hangs from falls: he falls
                ret     nz              ; with it
hangdrop:       jp      hang_release    ; in the fixed code: see there

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
                jr      z, crback
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
                cp      BG_FLASK        ; a flask is picked up the same way
                jr      z, swyes
                sub     BG_SWORD
                sub     1
                sbc     a, a
                ret
swyes:          or      a
                ret

mpc0:
                org     mfix0
take_sword:     ld      hl, c1take      ; RemoveObj: see c1take
                call    c1call          ; and the control code's bank back,
                ld      a, 1            ; where jumpseq and step_seq after it
                ld      (clrbtn), a     ; read the sequences: the press is
                ld      a, (takeid)     ; spent
                cp      BG_SWORD
                ld      a, SND_DRINK    ; the CPC's, drinking
                call    nz, addsound
                ld      a, SQ_DRINKPOTION
                jr      nz, tkseq
                ld      a, 0xff         ; the sword is potion -1
                ld      (lastpotion), a
                ld      a, 1
                ld      (gotsword), a
                ld      a, SQ_PICKUPSWORD
tkseq:          call    jumpseq
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

do_up:          call    stairs_up       ; in front of open stairs: up them
                ret     nz
                call    clrall
                ld      (clru), a
                ld      a, (jstkx)
                or      a
                jp      m, do_standjump

                call    above_flags     ; must be clear over his head
                ld      (blockid), a
                call    abovefront_flags
                call    check_ledge
                jr      nz, do_jumphang

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
                jr      do_jumphang

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

do_runjump:     jp      run_jump

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
                ld      c, a            ; which sequence that comes to is
                ld      hl, c1stepseq   ; worked out in CODE1, where there is
                call    c1call          ; room for it -- C in and C out, which
                ld      a, c            ; is all the paging leaves alone
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
                jr      z, sqchx
                cp      SEQ_CHY
                jr      z, sqchy
                cp      SEQ_ACT
                jr      z, sqact
                cp      SEQ_SETFALL
                jp      z, sqsetfall
                cp      SEQ_IFWTLESS
                jp      z, sqwtless
                cp      SEQ_JARU
                jr      z, sqjaru
                cp      SEQ_JARD
                jr      z, sqjard
                cp      SEQ_EFFECT
                jp      z, sqeffect
                cp      SEQ_TAP
                jr      z, sqtap
                cp      SEQ_FIRSTOP     ; nextlevel: GoneUpstairs
                jr      nz, seqloop     ; die: no data
                push    hl
                ld      hl, lvflag      ; inc NextLevel, if there is one
                sla     (hl)            ; (its tune has begun with the
                                        ; climb: see stairs)
                pop     hl
                jr      seqloop

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

; A jump or a hard landing jars the floorboards -- jaru those in the row
; above him, jard those in his own.  TOPCTRL.S acts on it once a frame.

sqjaru:         ld      a, 1
                ld      (jarabove), a
                jr      seqloop
sqjard:         ld      a, 0xff
                ld      (jarabove), a
                jr      seqloop

sqrowup:        push    hl
                ld      hl, blocky
                dec     (hl)
                jr      sqrow

sqrowdn:        push    hl
                ld      hl, blocky
                inc     (hl)
sqrow:          ld      hl, c1addsl     ; the slicers of the row he steps to
                call    c1call
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

sqsetfall:      ld      a, (hl)         ; how fast along, and how fast down
                inc     hl
                ld      (xvel), a
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
                cp      1               ; a footstep, or the smack of a wall
                push    af
                ld      a, SND_FOOTSTEP
                call    z, addsound
                pop     af
                cp      2
                ld      a, SND_SMACKWALL
                call    z, addsound
                ld      a, 1
                ld      (alertguard), a
                jp      seqloop

; ifwtless: a goto while he is weightless, two bytes skipped otherwise.

sqwtless:       ld      a, (weightless)
                or      a
                jp      nz, sqgoto
                jr      sqskip2

; effect 1: POTIONEFFECT, whatever he has just drunk.

sqeffect:       ld      a, (hl)
                inc     hl
                dec     a
                jp      nz, seqloop
                push    hl
                ld      hl, potion_effect       ; in CODE1
                call    c1call
                pop     hl
                jp      seqloop

sqskip2:        inc     hl
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

airbump:        ld      a, SND_SMACKWALL ; BumpSound
                call    addsound
                ld      a, -4           ; four back off the wall
                call    addcharx
                ld      a, (charact)
                cp      4               ; falling already: he rebounds off
                ld      a, 0            ; the wall and drops
                jr      nz, abfall
                ld      (xvel), a
                ret
abfall:         ld      a, SQ_BUMPFALL
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
                cp      BG_SLICER       ; a slicer is in his way only while
                jr      nz, cknotsl     ; its jaws are shut -- and COLL.S
                ld      a, (tilestate)  ; asks it without masking the blood
                cp      SLICEREXT       ; off: a smeared one never bars
                jr      nz, ccno
                jr      ckyes
cknotsl:        cp      BG_MIRROR       ; a mirror: see ckmirr
                jp      z, ckmirr
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

; COLL.S's :mirror.  A mirror bars the way -- but to the kid on a running
; jump, from its right: he goes through, and his reflection comes to life,
; createshad, which REFLECTION acts on (bgovl.asm).  SMASHMIRROR's spec
; nothing reads, and is not kept.  From checkcoll1, in the module, and back.

ckmirr:         ld      a, (charid)
                or      a
                jr      nz, ckmyes
                ld      a, (frame)      ; frames 39 to 43
                sub     39
                cp      5
                jr      nc, ckmyes
                ld      a, (facing)     ; facing left
                or      a
                jr      nz, ckmyes
                dec     a
                ld      (createshad), a
                jp      ccno
ckmyes:         jp      ckyes

createshad:     db      0               ; 0xFF: the reflection comes to life
shadkey:        db      0               ; the shadow's JSTKX: see bgovl.asm
lastkidstr:     db      0               ; hurt_flash's: here, where the
                                        ; mirror's CreateShad can set it

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
                call    mul10           ; ten tiles to the row
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

blockcol_of:    ld      de, 2 * BLOCK_PX - ANGLE_PX     ; GETBLOCKXP takes
                add     hl, de          ; `angle` off first; two blocks on,
                bit     7, h            ; so as not to be negative -- and
                jr      z, bcpos        ; further left than that is two off
                ld      hl, 0
bcpos:          srl     h               ; a quarter, then a seventh: times
                rr      l               ; 147 and over 1024, which is exact
                srl     h               ; this far.  Taking off a block at a
                rr      l               ; time was 460 T a call, and a frame
                ld      a, l            ; makes a dozen or more
                ld      h, 0
                add     hl, hl
                ld      e, a
                ld      d, 0
                add     hl, de          ; three
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, de          ; nine
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, de          ; 147
                ld      a, h
                rrca
                rrca
                and     0x3f
                sub     2
                ld      b, a            ; B too, not C: the caller keeps the
                ret                     ; row there, and tile_in_row wants it

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

tirroom         equ     SYSVARS + 0
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

flvis:          call    subcam          ; the screen column
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
                call    gs_flame
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
                ld      hl, flames      ; the frames are the same for both:
                ld      (flsrc), hl     ; ovflame moves them for the mask

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
flgot:          ld      de, ovflame     ; the flames are in the background
                call    bgcall          ; bank and the room they go over is
                                        ; in the art bank, so the one frame
                                        ; wanted is brought across first
                ld      a, (flrect)     ; how much of it is in view
                call    flvis
                or      a
                ret     z

; The flame's three bytes of mask are the same on every one of its rows, so
; they go into the three ANDs below; its pixels are walked in the alternate
; HL, what the view cut off each row skipped with the alternate BC, and the
; room and the working copy are worked out at its top row and walked from
; there in HL and DE.  With all four kept in memory and every row's
; addresses worked out afresh, two torches were a fifth of a frame; with the
; two walked in memory and nextline called, still a tenth.

                ld      (flwid + 1), a  ; the bytes the view shows
                ld      b, a
                cp      3               ; the room goes a byte on after each
                jr      c, flst1        ; but the third: 35 less that, a row
                dec     a
flst1:          neg
                add     a, ROOM_BYTES
                ld      (flstep + 1), a
                ld      a, (flrect + 2)
                sub     b               ; and those it cut off, past each row
                exx
                ld      c, a
                ld      b, 0
                ld      hl, flbuf
                exx
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
                ld      a, (flrect)     ; the working copy, the camera saying
                call    subcam          ; where that lands
                ld      e, a
                ld      a, (flrect + 1)
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de
                push    hl
                ld      a, (flrect + 1) ; and the room at its top row
                call    roomrow
                ld      a, (flrect)
                ld      e, a
                ld      d, 0
                add     hl, de
                pop     de
                ld      a, (flrect + 3)
                ld      b, a
flrow:          push    de
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
                add     hl, bc
                exx
                ld      a, l            ; the room a row down
flstep:         add     a, 0            ; patched
                ld      l, a
                jr      nc, fl1
                inc     h
fl1:            pop     de              ; and the working copy a line down,
                inc     d               ; as nextline does it
                ld      a, d
                and     7
                jr      z, flnl
fldn:           djnz    flrow
                ret
flnl:           ld      a, e
                add     a, 32
                ld      e, a
                jr      c, fldn
                ld      a, d
                sub     8
                ld      d, a
                jr      fldn


; Colour, which the Spectrum keeps in cells of eight pixels by eight.  The
; map is the room's width and the camera slides over it in whole cells, so
; the window is simply copied out -- again when the view moves.

set_attrs:      ld      hl, SCREEN + 6144
set_attrs_at:   ld      a, 1            ; the meters' colours go with it
                ld      (meterdirty), a
                ld      (atbase), hl    ; or the other screen's, for a view
                ld      d, h            ; being made in it
                ld      e, l
                inc     de
                ld      bc, 767
saink:          ld      (hl), INK_ROOM  ; the set's: newroom puts it here
                ldir
saflask:        call    flask_attrs     ; or palattr, the palace's first

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
                call    subcam
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

; And the colour of a flask's potion in the one cell its bubbles keep to: red
; for the two that give strength, green for weightlessness, blue for the
; rest.  flask_ma puts them in cell row 5 of the block row, 4 for a tall
; bottle -- which potion five's is not -- and in the cell that starts at room pixel 28 col + 16 -- + 12 in
; an odd column, where the flask is five pixels further back.

; HL = a rectangle that gets bigger, DE = one to take in.  An empty one takes
; the other as it is.

box_two:        push    hl
                inc     de
                inc     de
                ld      a, (de)
                dec     de
                dec     de
                or      a
                jr      z, btdone       ; nothing to take in
                inc     hl
                inc     hl
                ld      a, (hl)
                dec     hl
                dec     hl
                or      a
                jr      nz, btboth
                ex      de, hl
                ld      bc, 4
                ldir
btdone:         pop     hl
                ret
btboth:         ex      de, hl          ; union4 grows DE
                call    union4
                pop     hl
                ret

dmsrc           equ     SYSVARS + 1
dmcol           equ     SYSVARS + 3
dmtop           equ     SYSVARS + 4
dmw             equ     SYSVARS + 5
dmrect:         ds      4
meterdirty:     db      1               ; something went over the meters
dmslot:         dw      0
mbold:          ds      8               ; where each is drawn now
mbshow:         ds      8               ; and that with where it was


; DrawFF in FRAMEADV.S, for every MOB in the room on screen: a loose floor on
; its way down, laid over the room with its own mask -- the loose floor's A,
; D and B sections, composed at build time -- its foot on moby and its left
; edge at mobx Apple bytes, which lands on a byte or four pixels into one.
; Where they were last frame has been put back already; where they are now
; is shown next frame together with it, as mbshow.  The room goes back under
; the whole of that box before the picture goes down: it takes in what lies
; between the two -- the rows a fast one dropped past, or the gap between two
; of them when one has gone and the other has moved up a slot -- and the
; working copy there is whatever it held before the view last moved.

MOBROWS         equ     FF_H

draw_mobs:      ld      hl, mbold       ; last frame's, to be shown with this
                ld      de, mbshow
                ld      bc, 8
                ldir
                xor     a
                ld      (mbold + 2), a  ; and nothing drawn yet this frame
                ld      (mbold + 6), a
                ld      a, (nummob)
                or      a
                ret     z
                ld      b, a
                ld      c, 0
                ld      hl, mbold       ; a rectangle each: two far apart in
dmloop:         push    bc              ; one box was most of the screen to
                ld      (dmslot), hl    ; put back, cover and show -- for the
                call    mobload         ; first two of this room: the others
                call    draw_mob        ; are elsewhere, and three falling in
                ld      hl, (dmslot)    ; one room were more than two slots
                inc     hl
                inc     hl
                ld      a, (hl)
                dec     hl
                dec     hl
                or      a
                jr      z, dmsame
                ld      de, 4
                add     hl, de
                ld      a, l
                cp      (mbold + 8) & 0xff
                jr      z, dmfull
dmsame:         pop     bc
                inc     c
                djnz    dmloop
                ret
dmfull:         pop     bc
                ret

draw_mob:       ld      a, (mobvel)
                inc     a
                ret     z               ; gone
                ld      a, (mobroom)
                ld      hl, roomnum
                cp      (hl)
                ret     nz
                ld      a, (mobx)       ; seven pixels an Apple byte
                ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                or      a
                sbc     hl, de
                ld      a, l
                and     7
                ld      de, FF_AT0
                ld      b, FF_W
                jr      z, dmshift
                ld      de, FF_AT4
                ld      b, FF_W4
dmshift:        ld      (dmsrc), de
                srl     h
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      a, (cam)
                ld      c, a
                ld      a, l
                sub     c
                ld      (dmcol), a      ; its first byte on the screen, signed
                ld      a, b
                ld      (dmw), a
                ld      a, (moby)
                sub     MOBROWS - 1
                ld      (dmtop), a
                ld      a, (dmcol)      ; and its rectangle, B wide, the
                                        ; columns clipped to the screen's
                bit     7, a
                jr      z, dmright
                add     a, b            ; off the left: what is left of it
                ret     m
                ret     z
                ld      b, a
                xor     a
dmright:        ld      c, a
                add     a, b
                sub     32
                jr      c, dmfits
                ld      d, a            ; past the right: that much less
                ld      a, b
                sub     d
                ret     c
                ret     z
                ld      b, a
dmfits:         ld      hl, dmrect
                ld      (hl), c
                inc     hl
                ld      a, (dmtop)
                ld      (hl), a
                inc     hl
                ld      (hl), b
                inc     hl
                ld      (hl), MOBROWS
                call    page_art        ; the room back under it and where it
                ld      hl, (dmslot)    ; was, as one, first: after the view
                ld      de, mbshow - mbold      ; has moved, what the working
                add     hl, de          ; copy holds there is the old view
                ld      de, dmrect
                call    box_two         ; which keeps HL
                call    eraseset
                ld      a, FF_BLOB
                ld      (curbank), a
                call    page_frame
                ld      a, (dmrect)     ; what the left edge cut off, a mask
                ld      hl, dmcol       ; and a byte of the piece a column:
                sub     (hl)            ; from there on every row is laid
                add     a, a            ; whole, as far as the rectangle
                ld      e, a            ; goes, with nothing asked a byte
                ld      d, 0
                ld      hl, (dmsrc)
                add     hl, de
                ld      (dmsrc), hl
                ld      a, (dmtop)
                ld      b, MOBROWS
                ld      c, a            ; C = the row in hand
dmrow:          push    bc
                ld      a, c
                cp      192
                jr      nc, dmnext      ; off the top or the foot
                ld      a, (dmrect)
                ld      e, a
                ld      a, c
                call    scraddr
                ld      bc, work - SCREEN
                add     hl, bc          ; its first column in the working copy
                ld      a, (dmrect + 2)
                ld      b, a
                ld      de, (dmsrc)
dmbyte:         ld      a, (de)         ; the mask: the room shows through
                and     (hl)
                inc     de
                ex      de, hl
                or      (hl)            ; and the piece
                ex      de, hl
                ld      (hl), a
                inc     hl
                inc     de
                djnz    dmbyte
dmnext:         ld      hl, (dmsrc)     ; a row on
                ld      a, (dmw)
                add     a, a
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (dmsrc), hl
                pop     bc
                inc     c
                djnz    dmrow

                ld      hl, (dmslot)    ; and where it is now
                ld      de, dmrect
                jp      box_two


; The colours of the screen that is shown, worked out again.

shown_attrs:    call    page_canvas     ; bank 7, in case it is that one
                ld      a, (scrsel + 1) ; 0x5800, or 0xD800 for bank 7
                or      0x58
                ld      h, a
                ld      l, 0
                jp      set_attrs_at


INK_POTRED      equ     0x42
INK_POTGREEN    equ     0x44
INK_POTBLUE     equ     0x41

flask_attrs:    ld      hl, roomids
                ld      bc, 0           ; B = the block row, C = the column
fatile:         ld      a, (hl)
                and     0x1f
                cp      BG_FLASK
                jr      nz, fanext
                push    hl
                push    bc
                ld      de, 30
                add     hl, de
                ld      a, (hl)         ; the potion
                rlca
                rlca
                rlca
                and     7
                jr      z, faout        ; empty: no bubbles
                ld      de, INK_POTRED * 256 + 4
                cp      2               ; the tall bottle a cell row higher
                jr      z, faink        ; than the short one --
                jr      c, fashort      ; refresh: the short bottle
                ld      d, INK_POTGREEN
                cp      3
                jr      z, faink
                ld      d, INK_POTBLUE
                cp      5               ; and five's is the short one too
                jr      nz, faink
fashort:        inc     e
faink:          ld      a, b            ; eight cell rows a block row
                add     a, a
                add     a, a
                add     a, a
                add     a, e
                ld      l, a            ; thirty two cells to the row
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                ld      a, c            ; (28 col + 16 or 12) / 8, less the
                add     a, a            ; camera
                add     a, a
                bit     0, c
                jr      z, faeven
                sub     4
faeven:         add     a, 16
                rrca
                rrca
                rrca
                and     0x1f
                add     a, c
                add     a, c
                add     a, c
                ld      e, a
                ld      a, (cam)
                ld      b, a
                ld      a, e
                sub     b
                cp      32
                jr      nc, faout       ; not in the view
                ld      c, a
                ld      b, 0
                add     hl, bc
                ld      bc, (atbase)
                add     hl, bc
                ld      (hl), d
faout:          pop     bc
                pop     hl
fanext:         inc     hl
                inc     c
                ld      a, c
                cp      10
                jr      c, fatile
                ld      c, 0
                inc     b
                ld      a, b
                cp      3
                jr      c, fatile
                ret

sacol           equ     SYSVARS + 6
sarow           equ     SYSVARS + 7
sacolr          equ     SYSVARS + 8     ; this row's colour
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
                call    subcam
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
                ld      a, (frame)      ; climbing the stairs: the door
                cp      224
                jr      c, crnostairs
                cp      229
                jp      c, stairs_crop
crnostairs:

                ld      a, (newtop)     ; topej -- the row his picture starts
                call    get_blocky
                cp      3               ; a top over the screen is a line
                jr      nz, crrow       ; past 191 to GETBLOCKY: it is the
                ld      a, 0xff         ; row above, climbing through a hole
crrow:          ld      (croprow), a    ; in the ceiling, not the room below

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
                jr      tile_flags

; Out: A = the flags of the block one along, the way he faces or the way he
; came -- GETINFRONT and GETBEHIND.  Off the map reads as space, which is
; what it looks like.

front_flags:    ld      a, (facing)
                or      a
                jr      z, ffback
fffwd:          call    base_x
                ld      de, BLOCK_PX
                add     hl, de
                jr      tile_flags
ffback:         call    base_x
                ld      de, -BLOCK_PX
                add     hl, de
                jr      tile_flags
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
dist_hl:        ld      de, -ANGLE_PX
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

; The climb up the stairs, and GoneUpstairs's tune with it: as he begins
; to go in rather than once he is through, as the user asked.

stairseq:       ld      a, SONG_UPSTAIRS
                ld      c, 25
                call    cue_song
                ld      a, SQ_CLIMBSTAIRS
                jp      jumpseq

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
                jp      z, cf_air
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
                ld      hl, c1addsl     ; startfall: the slicers of the row
                call    c1call          ; he is falling to
                ld      a, 3
                ld      (charact), a
                xor     a
                ld      (yvel), a
                ld      (charsword), a  ; so that he can grab on
                jp      start_fall

; GRAVITY and ADDFALL, then the floor plane test of `falling`.  stepfall
; carries its own chy for the first four frames and gravity only takes over
; at the setfall, which is why the velocity is left alone until then.

do_fall:        ld      a, (charact)
                cp      4               ; only a free fall has weight: the
                ret     nz              ; four frames of stepfall carry their
                ld      bc, ACCEL_G + 256 * (TERM_VEL + 1) ; own chy
                ld      a, (weightless)
                or      a
                jr      z, dfgrav
                ld      bc, WTLESS_G + 256 * (WTLESS_TERM + 1)
dfgrav:         ld      a, (yvel)
                add     a, c
                cp      b
                jr      c, fallvel
                ld      a, b
                dec     a
fallvel:        ld      (yvel), a
                ld      b, a
                ld      a, (chary)
                add     a, b
                ld      (chary), a
                ld      a, (xvel)       ; ADDFALL: and along, as the jump or
                call    move_by         ; the fall set him going
fallplane:      call    floor_plane
                ld      b, a
                ld      a, (chary)
                cp      b
                jp      c, fall_on      ; not down to the plane yet: grab?
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
                call    land_spikes     ; on to spikes that are out: impaled
                ret     nz
                ld      hl, c1addsl     ; and the slicers of the row he lands
                call    c1call          ; on start
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
                push    af              ; anything harder is a splat
                ld      a, SND_SPLAT
                call    addsound
                pop     af
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
hfland:         ld      a, b            ; and into its first frame at once,
                call    jumpseq         ; as :doland's animchar does: a frame
                jp      step_seq        ; of daylight between the two let the
                                        ; control code have a dead man on the
                                        ; ground and stand him up again
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

; ---------------------------------------------------------------- grabbing
;
; fallon in CTRL.S: falling, the button down, not yet down to the floor
; plane and slow enough to hold on, he reaches eight units forward for a
; ledge above and in front -- and gets it, if there is one: square on the
; block, at the floor line, hanging, and stunned a moment so that he cannot
; climb straight on up.

GRABREACH       equ     -8
GRABSPEED       equ     32
GRABLEAD        equ     25
STUNTIME        equ     12

fall_on:        ld      a, (btn)
                or      a
                ret     z
                ld      a, (charlife)   ; & is he alive?
                or      a
                ret     p
                ld      a, (yvel)
                cp      GRABSPEED
                ret     nc              ; falling too fast
                call    floor_plane
                ld      b, a
                ld      a, (chary)
                add     a, GRABLEAD
                cp      b
                ret     c               ; not within grabbing range yet
                ld      hl, (charx)
                ld      (fosave), hl
                ld      a, GRABREACH
                call    move_by
                call    above_flags     ; can he grab the ledge?
                ld      (blockid), a
                call    abovefront_flags
                call    check_ledge
                jr      nz, fograb
                ld      hl, (fosave)    ; no
                ld      (charx), hl
                ret
fograb:         call    get_dist        ; square on the block
                call    move_by
                call    floor_plane
                ld      (chary), a
                xor     a
                ld      (yvel), a
                ld      a, STUNTIME
                ld      (stunned), a
                ld      a, SQ_FALLHANG
                call    jumpseq
                jp      step_seq

; CHECKFLOOR: the first frames of a fall off a ledge are in the air too, and
; he can catch hold in those.  A = 3.

cf_air:         ld      a, (frame)
                cp      102
                ret     c
                cp      106
                ret     nc
                jr      fall_on

; PLAYERCTRL counts the stun down.

stun_tick:      ld      hl, stunned
                ld      a, (hl)
                or      a
                ret     z
                dec     (hl)
                ret

; hanging's :climbup in CTRL.S.  A gate over him is climbed only facing
; right, or when it is raised far enough to get past; otherwise he tries and
; falls back.  Stunned from catching the ledge, he cannot climb at all.

climb_up:       ld      a, (stunned)
                or      a
                jp      nz, hangbtn
                call    clrall
                ld      (clru), a
                ld      (clrbtn), a
                call    above_flags
                cp      BG_MIRROR       ; a mirror or a slicer over him can
                jr      z, culeft       ; be climbed only facing left
                cp      BG_SLICER
                jr      nz, cunotsl
culeft:         ld      a, (facing)
                or      a
                jr      z, cusucceed
                ld      a, SQ_CLIMBFAIL
                jp      jumpseq
cunotsl:        cp      BG_GATE
                jr      nz, cusucceed
                ld      a, (facing)
                or      a
                jr      nz, cusucceed
                ld      a, (tilestate)
                rrca
                rrca
                and     0x3f
                cp      GCLIMBTHRES
                ld      a, SQ_CLIMBFAIL
                jp      c, jumpseq
cusucceed:      ld      a, SQ_CLIMBUP
                jp      jumpseq

; DoRunjump in CTRL.S: the jump is calibrated so the foot pushes off at the
; edge.  Where the floor ends within a block of where four more units would
; put him, he waits for it; close enough -- up to eight units short, two over
; -- he is moved there and jumps.  No edge in sight, he jumps as he is.

RJCHANGE        equ     4
RJLOOKAHEAD     equ     1
RJLEADDIST      equ     14
RJMAXFUJBAK     equ     8
RJMAXFUJFWD     equ     2

run_jump:       ld      a, (frame)
                cp      7
                ret     c               ; must be in full run
                ld      hl, (charx)
                ld      (fosave), hl
                ld      a, RJCHANGE     ; where he will be
                call    move_by
                ld      hl, (charx)
                call    blockcol_of
                ld      (rjcol), a
                xor     a
                ld      (rjblocks), a
rjloop:         ld      a, (facing)     ; the next block along
                or      a
                ld      a, (rjcol)
                jr      nz, rjright
                dec     a
                dec     a
rjright:        inc     a
                ld      (rjcol), a
                ld      a, (blocky)
                ld      c, a
                ld      a, (rjcol)
                call    tile_at
                cp      BG_SPIKES
                jr      z, rjedge
                call    cmp_space
                jr      z, rjedge
                ld      hl, rjblocks
                inc     (hl)
                ld      a, (hl)
                cp      RJLOOKAHEAD + 1
                jr      c, rjloop
                ld      hl, (fosave)    ; no edge in sight: jump anyway
                ld      (charx), hl
                jr      rjgo
rjedge:         ld      hl, (charx)     ; units to the end of the floor
                call    dist_hl
                ld      b, a
                ld      a, (rjblocks)
                add     a, a
                ld      c, a
                add     a, a
                add     a, a
                sub     c               ; fourteen a block
                add     a, b
                sub     RJLEADDIST
                ld      hl, (fosave)
                ld      (charx), hl
                cp      -RJMAXFUJBAK
                jr      nc, rjfudge     ; move back a little and jump
                cp      RJMAXFUJFWD
                jr      c, rjfudge      ; move forward a little and jump
                cp      0x80
                ret     c               ; still too far: wait for the next frame
                ld      a, -3           ; too late: he will miss the edge, but
rjfudge:        add     a, RJCHANGE     ; let it look good
                call    move_by
rjgo:           call    clrall
                ld      (clru), a
                ld      a, SQ_RUNJUMP
                jp      jumpseq

; STARTFALL in CTRL.S: the fall is chosen by the frame he went over the edge
; in -- out of a step, a run, a standing or a running jump, a drop from a
; ledge or a fighting stance -- and each carries him on at its own speed.
; Out: A = the sequence.

fall_seq:       ld      a, (frame)
                cp      9               ; run-12
                ld      b, SQ_STEPFALL
                jr      z, fsgot
                cp      13              ; run-16
                ld      b, SQ_STEPFALL2
                jr      z, fsgot
                cp      26              ; standjump-19
                ld      b, SQ_JUMPFALL
                jr      z, fsgot
                cp      44              ; runjump-11
                ld      b, SQ_RJUMPFALL
                jr      z, fsgot
                cp      81
                jr      c, fsfight
                cp      86
                jr      nc, fsfight
                ld      a, 5            ; a hang dropped from
                call    move_by
                ld      a, SQ_STEPFALL2
                ret
fsfight:        cp      150
                jr      c, fsstep
                cp      180
                jp      c, fightfall_seq ; from a fighting stance
fsstep:         ld      b, SQ_STEPFALL
fsgot:          ld      a, b
                ret

; The rest of STARTFALL: a frame into the fall straight away, so that next
; frame's control finds him falling and not in the frame he left the floor in;
; then, where that has put him into a wall, out of it -- or, falling at a
; wall ahead, a unit back from it (CDpatch), or out of a running jump too
; close to the edge, down the wall in the patch fall.

start_fall:     ld      a, (frame)      ; the frame the fall replaces
                ld      (sfframe), a
                call    fall_seq
                call    jumpseq
                call    step_seq        ; advance one frame into the fall
                call    under_flags
                call    cmp_wall
                jp      z, inside_block
                call    front_flags
                call    cmp_wall
                ret     nz
                ld      a, (sfframe)
                cp      44              ; running jump?
                jr      nz, sfpatchx
                call    get_dist
                cp      6
                jr      nc, sfpatchx
                ld      a, SQ_PATCHFALL
                call    jumpseq
                jp      step_seq
sfpatchx:       ld      a, -1
                jp      move_by


; CMPWALL: Z when the block is a wall to him -- a solid block, or facing left
; a panel's wall side.

cmp_wall:       cp      BLK_BLOCK
                ret     z
                ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                ret     nz
                cp      BG_PANELWIF
                ret     z
                cp      BG_PANELWOF
                ret

sfframe         equ     SYSVARS + 9
fosave          equ     SYSVARS + 10
rjcol           equ     SYSVARS + 12
rjblocks:       db      0
stunned:        db      0

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
                ld      a, (charid)     ; the kid and the shadow: his own
                cp      2
                ret     c
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
                call    subcam          ; the room's byte column, on screen

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
                ld      a, (clipl)      ; the left edge: the screen's, or
                ld      e, a            ; CROPCHAR's FCharCL, a mirror's
                ld      a, (newcol)
                ld      c, a
                sub     e               ; signed, as the column is
                jp      p, clipright
                neg                     ; off the left: skip that many bytes
                ld      (spskip), a
                ld      b, a
                ld      a, (neww)
                sub     b
                jr      c, clipnone
                jr      z, clipnone
                ld      (neww), a
                ld      c, e
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
                ld      a, (charid)     ; the shadow: every other line of
                dec     a               ; him left out, the room showing
                ld      a, 0            ; through -- the Apple lays him
                jr      nz, dpsolid     ; EORed, which one colour cannot
                inc     a               ; tell from the kid
dpsolid:        ld      (dfodd + 1), a
                call    dfsetup

                call    page_frame

                ld      a, (newh)       ; the calls above have had A
                or      a               ; and no rows is not 256 of them
                ret     z
                ld      b, a
                ld      a, (newtop)
                ld      c, a            ; C = the row in hand
                ld      hl, (curdat)    ; HL = its pairs
                ld      a, (dfstep + 1)
                ld      e, a
                ld      d, 0

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
dpgo:           ld      a, (clipb)      ; and none below the foot of it, or
                ld      d, a            ; of the mirror's frame
                ld      a, c
                add     a, b
                jr      c, dpcut
                dec     a
                cp      d
                jr      c, dpfit
dpcut:          ld      a, d
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
                ld      c, b            ; the rows, in C, which the row
                exx                     ; routines leave alone; and in the
                ld      c, REVTAB / 256 ; alternate C the page of the table
                exx                     ; that turns a byte about

; A row: the routine dfsetup chose lays it, then the pairs go a row on and
; the working copy a line down.  All a row asks of itself -- what the left
; edge cut off, how many bytes, whether the last one spills onto the screen
; -- dfsetup has patched into the routine once for the picture; they were a
; third of every row's time asked afresh.

drawrow:        ld      a, h            ; the line's parity
dfodd:          and     0               ; patched: 1 for the shadow
                jr      nz, drskip
                push    de
                push    hl
dfcall:         call    0               ; patched: the row's routine
                pop     hl
                pop     de
drskip:         ld      a, e
dfstep:         add     a, 0            ; patched: a row of pairs
                ld      e, a
                jr      nc, dr1
                inc     d
dr1:            inc     h               ; a line down, as nextline does it
                ld      a, h
                and     7
                jr      z, drnext
drdn:           dec     c
                jr      nz, drawrow
                ret
drnext:         ld      a, l
                add     a, 32
                ld      l, a
                jr      c, drdn
                ld      a, h
                sub     8
                ld      h, a
                jr      drdn

; A row of him goes straight from its (mask, data) pairs into the working
; copy: each byte through the shift's two tables, the part that stays OR'd
; with what spilled from the pair before, and laid down there and then.  It
; used to go through two buffers and three passes first -- copied aside,
; turned about when he faces right, shifted into (mask, data) pairs, and
; only then blitted -- and that was half of all a frame did.
;
; The alternate registers carry what a row needs from pair to pair: D and E
; the pages of the two tables, B what the data spilled, C the page of REVTAB.
;
; The edges come out of CROPCHAR's clipping: spskip bytes cut off at the
; left, neww bytes shown.  Worked out once a picture --
;   dfsrc    how far into a row the first byte to read is
;   the count of whole bytes laid down, into the four routines
;   whether the byte the last one spills into is on the screen, into dfend
; A byte the left edge cut off still spills into the first byte shown, so
; with spskip set the row starts one byte early and reads it for that alone.
; With nothing but that byte on the screen the picture is not drawn at all:
; a few pixels at the edge, for a frame.

dfsetup:        ld      a, (neww)
                ld      c, a
                ld      a, (curw)
                ld      b, a
                ld      (dfstep + 1), a
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
dfnospill:      or      a
                jr      nz, dfsome
                pop     hl              ; none whole: out of dp_image too
                ret
dfsome:         ld      (dfl0n + 1), a
                ld      (dfm0n + 1), a
                ld      (dfln + 1), a
                ld      (dfmn + 1), a
                ld      a, d            ; the spill: nop to lay it, ret not to
                dec     a
                and     0xc9
                ld      (dfend), a
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
                ld      bc, dfleft0 + 1
                jr      dfset
dfsetm:         ld      a, b            ; facing right, from the end of the
                sub     e               ; row back
                ld      hl, dfmirror
                ld      bc, dfmirror0 + 1
dfset:          ld      (dfsrc), a
                ld      a, (spskip)     ; a byte cut off: the routines that
                or      a               ; read it, or step past it
                jr      z, dfcut0
                dec     bc
                ld      a, (facing)
                or      a
                ld      hl, dflcut
                jr      z, dfcut0
                ld      hl, dfmcut
dfcut0:         ld      a, (curshift)   ; no shift: the loops that need no
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

; No shift at all: the byte is the byte, and nothing spills.  The first
; instruction steps past a byte the left edge cut off; dfsetup calls the one
; after it when there is none.

dfleft0:        inc     de
dfl0n:          ld      b, 0            ; patched: the bytes laid
dfl0pair:       ld      a, (de)
                inc     de
                or      (hl)
                ld      (hl), a
                inc     l
                djnz    dfl0pair
                ret

dfmirror0:      dec     de
dfm0n:          ld      b, 0            ; patched
                exx
                ld      h, REVTAB / 256
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

; In: DE = the first pair to read, HL = where its byte goes.  dflcut and
; dfmcut read the byte cut off for its spill first.

dflcut:         ld      a, (de)
                inc     de
                exx
                ld      l, a
                ld      h, e
                ld      b, (hl)
                exx
                jr      dfln
dfleft:         exx                     ; nothing cut off: nothing spilled in
                ld      b, 0
                exx
dfln:           ld      b, 0            ; patched: the bytes laid
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

dfmcut:         ld      a, (de)
                dec     de
                exx
                ld      l, a
                ld      h, c
                ld      l, (hl)
                ld      h, e
                ld      b, (hl)
                exx
                jr      dfmn
dfmirror:       exx
                ld      b, 0
                exx
dfmn:           ld      b, 0            ; patched
dfmpair:        ld      a, (de)
                dec     de
                exx
                ld      l, a
                ld      h, c            ; REVTAB
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
; same way -- or, patched to a ret, not on the screen.  The spill lives in
; the alternate B, the screen address in the main HL, and A is A in both.

dfend:          nop                     ; patched: ret with no spill shown
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
                jr      cover_rows

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
; The room back over a rectangle of the working copy: HL = col, top, width,
; height.

eraseset:       ld      de, ercol       ; col, top, width, height, in order
                ld      bc, 4
                ldir

                ld      a, (erw)
                or      a
                ret     z
                call    chainat         ; the row's copy, and past it the room
                ld      (ercall + 1), hl        ; a row on: 35 less the width
                neg
                add     a, ROOM_BYTES
                ld      (erskip + 1), a
                ld      a, (erh)
                or      a
                ret     z
                ld      b, a
                ld      a, (ertop)
                call    cliprows
                ret     c
                push    bc              ; B = rows, C = the first
                ld      a, (ercol)      ; the working copy's
                ld      e, a
                ld      a, c
                call    scraddr
                ld      de, work - SCREEN
                add     hl, de
                ex      (sp), hl
                push    hl
                ld      a, l            ; the room's row, under the view
                call    roomrow
                ld      a, (ercol)
                call    mastercol
                ld      e, a
                ld      d, 0
                add     hl, de
                pop     bc
                pop     de

; A row: DE the working copy, HL the room.  LDI counts in BC, and C starts
; each row at 255 so that B, the rows, is never touched.  Walking the room
; and the working copy on in place, instead of pushing and popping them and
; calling nextline, and the LDIs instead of LDIR, took a third off a row.

eraserow:       push    de
                ld      c, 255
ercall:         call    copy32          ; patched: the last (erw) of them
                ld      a, l
erskip:         add     a, 0            ; patched: 35 less the width
                ld      l, a
                jr      nc, er1
                inc     h
er1:            pop     de              ; the working copy a line down, as
                inc     d               ; nextline does it
                ld      a, d
                and     7
                jr      z, ernext
erdn:           djnz    eraserow
                ret
ernext:         ld      a, e
                add     a, 32
                ld      e, a
                jr      c, erdn
                ld      a, d
                sub     8
                ld      d, a
                jr      erdn

; A guard standing still -- waiting for him en garde, or dead -- is the same
; picture in the same place frame after frame, and rubbing him out, drawing
; him and putting the floor and the front back over him was a third of a
; frame for nothing: it slowed the prince down all the way across a guard's
; room.  He is left as he is when his rectangle and everything his picture
; comes from are as they were when he was last drawn -- where he is, the
; frame, the way he faces, where his feet are cut -- and nothing else is
; drawn over his box this frame: the prince's box, a torch, a floor falling,
; a block redrawn, the whole working copy laid again.  His box is then
; emptied, so that nothing rubs him out and nothing shows him.

gdlast          equ     LOWVARS + LOWVARLEN     ; charx, chary, facing,
                                        ; frame; charcu and his rectangle: ten,
                                        ; up to the deepest the stack goes
gdskip          equ     0x5C6F          ; 1: left as he is this frame
kidskip         equ     SYSVARS + 58    ; and the prince: see kid_still
gddirty         equ     0x5C70          ; something wrote over him
spkroom         equ     0x5C71          ; the room has spikes: see roomblk

; draw_chars' ways in.  The guard's picture has the floor and the front put
; back over it straight after, while he is still the character in hand --
; one exchange of the two records less, and the prince, drawn after, is put
; right the same way over his own.

kid_pics:       ld      a, (kidskip)    ; the prince's the same, last
                jr      gdpics1
gd_pics:        ld      a, (gdskip)
gdpics1:        or      a
                ret     nz
                call    dp_pics
                call    page_art
                call    hide_floor
                jp      hide_behind

gd_still:       ld      hl, gdskip
                ld      (hl), 0
                ld      a, (gdhere)
                or      a
                ret     z
                ld      hl, charx + OP  ; as when last drawn -- and this frame's
                ld      de, gdlast      ; kept, whatever the answer
                ld      bc, 5 * 256
                call    gs_cmp
                ld      hl, charcu + OP ; and his rectangle
                ld      b, 5
                call    gs_cmp
                ld      a, c
                ld      hl, gddirty
                or      (hl)
                ld      (hl), b
                ld      hl, mbold + 2   ; nothing falling, nor anything that
                or      (hl)            ; fell last frame to rub out
                ld      hl, mbold + 6
                or      (hl)
                ld      hl, nummob
                or      (hl)
                ld      de, boxcol      ; and not the prince's box: a torch
                jr      nz, gsmove      ; over him gs_flame sees to
                call    gs_meet
                jr      c, gsjoin
gsstill:        ld      hl, gdskip
                inc     (hl)
gsempty:        xor     a
                ld      (boxw + OP), a
                ret

; Drawn again, and the prince's box meets him: the two boxes are one, rubbed
; out and shown once -- in a fight they are much the same place, and the
; rows the two have in common went to the screen twice.

gsmove:         call    gs_meet
                ret     nc
gsjoin:         ld      hl, boxcol + OP
                ld      de, boxcol
                call    union4
                jr      gsempty

; A torch just drawn over a guard left as he is: he goes down again on top
; of it, as he would have -- only the torch's rectangle has changed, and that
; is shown with the torch.

gs_flame:       ld      a, (gdskip)
                or      a
                ret     z
                ld      a, (cam)        ; its rectangle on the screen
                ld      c, a
                ld      a, (flrect)
                sub     c
                ld      (flrect), a
                ld      de, flrect
                call    gs_meet
                ret     nc
                xor     a
                ld      (gdskip), a
                ret

; B bytes at HL against the copy at DE, which takes them: C gathers what
; differs.

gs_cmp:         ld      a, (de)
                xor     (hl)
                or      c
                ld      c, a
                ld      a, (hl)
                ld      (de), a
                inc     hl
                inc     de
                djnz    gs_cmp
                ret

; DE = a rectangle.  Out: carry if it meets the guard -- his rectangle,
; which is his box while he is still, and stays whole when the box is emptied.

gs_meet:        ld      a, (neww + OP)  ; none of him in view: nothing meets
                or      a               ; him, carry clear
                ret     z
                ld      hl, newcol + OP
                call    ov1             ; the columns
                ret     nc
                inc     hl              ; and the rows
                inc     de

; Along one of them: A and B meet where either starts inside the other --
; the differences taken round, so that a top above the screen (192 and up)
; still compares.

ov1:            ld      a, (de)
                sub     (hl)
                inc     hl
                inc     hl
                cp      (hl)
                dec     hl
                dec     hl
                ret     c
                ld      a, (hl)
                ex      de, hl
                sub     (hl)
                inc     hl
                inc     hl
                cp      (hl)
                dec     hl
                dec     hl
                ex      de, hl
                ret

; For hide_behind: from the front list's entry at HL, B of them left, on to
; the first whose rows meet the character's, with B counting it.  Out: Z
; when there is none.  Most are wholly above or below him, and turning them
; away here, two bytes and a sum each, saved asking the whole question of
; every one: rows meet where his bottom less its top, round, is less than
; the two heights less one.

hbseek:         ld      a, (newtop)
                ld      d, a
                ld      a, (newh)
                dec     a
                ld      e, a
hbs1:           ld      a, b
                or      a
                ret     z
                inc     hl
                ld      a, (hl)         ; its bottom row
                sub     d               ; less his top, round
                ld      c, a
                inc     hl
                inc     hl
                inc     hl
                ld      a, (hl)         ; its height, and his less one
                dec     hl
                dec     hl
                dec     hl
                dec     hl
                add     a, e
                cp      c
                jr      z, hbs2
                ret     nc              ; they meet: NZ
hbs2:           ld      a, 5
                add     a, l
                ld      l, a
                jr      nc, hbs3
                inc     h
hbs3:           dec     b
                jr      hbs1

; A = a width of 1 to 32.  Out: HL = the place in copy32 that copies that
; many, A still the width.

chainat:        ld      l, a
                add     a, a
                neg
                add     a, (copy32 + 64) & 255
                ld      h, a
                ld      a, l
                ld      l, h
                ld      h, (copy32 + 64) / 256
                ret     c
                dec     h
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
                xor     a               ; what fell was put down for the view
                ld      (mbshow + 2), a ; gone: the new one never had it
                ld      (mbshow + 6), a
                inc     a               ; and nor had it the meters
                ld      (meterdirty), a
shnoflip:
                ld      a, (fullshow)
                or      a
                jr      z, showmine

; The view has moved and the whole screen is being redrawn from the room --
; six kilobytes, which is longer than the beam takes to cross the screen, so
; it is seen while it happens.  His own bytes therefore go down with the row
; they belong to rather than in a pass of their own: a row is never on screen
; without him, and the tear that is left is the room sliding, nothing more.

                ld      (meterdirty), a ; A is not nought here: the meters too
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
showold:        ld      hl, mbshow      ; what falls, where it was and is
                call    show_one
                ld      hl, mbshow + 4
                call    show_one
                ld      hl, boxcol      ; where each was and is, as one: see
                call    show_one        ; draw_chars
                ld      hl, boxcol + OP
                call    show_one
                jp      show_flames

show_one:       ld      de, shcol       ; col, top, width, height, in order
                ld      bc, 4
                ldir

showgo:         ld      a, (shw)        ; none of him on screen
                or      a
                ret     z
                call    chainat
                ld      (shcall + 1), hl
                ld      (shwid + 1), a
                ld      a, (shh)
                or      a
                ret     z
                ld      b, a            ; B is the row count, not the width
                ld      a, (shtop)
                call    cliprows
                ret     c
                ld      a, c            ; down into the meters' row: they
                add     a, b            ; want putting back over it
                cp      METERTOP + 1
                jr      c, shabove
                ld      a, 1
                ld      (meterdirty), a
shabove:        ld      a, (shcol)
                ld      e, a
                ld      a, c
                call    scraddr
                ld      a, h            ; DE = the screen shown: 0x80 up when
scrsel:         or      0               ; that is bank 7
                ld      d, a
                ld      e, l
                ld      a, h            ; HL = working copy, the same place
                add     a, (work - SCREEN) / 256        ; a whole number
                ld      h, a                            ; of thirds up

; A row, as eraserow does one: the two addresses share their low byte, and
; the working copy's line within its cell is the screen's.  A screen row
; never crosses a page, but the address past its last byte does.

showrow:        ld      c, 255
shcall:         call    copy32          ; patched
                ld      a, e
shwid:          sub     0               ; patched: the width
                ld      e, a
                ld      l, a
                jr      nc, shsame      ; a box out to column 31: past its
                dec     h               ; last byte the LDIs carried into
                dec     d               ; the next page
shsame:         inc     h
                inc     d
                ld      a, h
                and     7
                jr      z, shnext
shdn:           djnz    showrow
                ret
shnext:         ld      a, l
                add     a, 32
                ld      l, a
                ld      e, a
                jr      c, shdn
                ld      a, h
                sub     8
                ld      h, a
                ld      a, d
                sub     8
                ld      d, a
                jr      shdn

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
                call    subcam
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
                call    roomrow         ; here on, not multiplied out afresh
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

rsroomp         equ     SYSVARS + 13

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

dirty_add:      ld      a, 1            ; the guard drawn afresh: see gd_still
                ld      (gddirty), a
                ld      a, (dirtyn)
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

rdcol           equ     SYSVARS + 15
rdstart         equ     SYSVARS + 16
rdw             equ     SYSVARS + 17
redh:           db      63
dirtyn          equ     SYSVARS + 18    ; rectangles waiting for the blit

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
xvel:           db      0               ; CharXVel: along, in a free fall
clipl:          db      0               ; FCharCL: the first screen column
                                        ; he shows in -- a mirror's edge
clipb:          db      192             ; and the line his picture stops
                                        ; above: the screen's foot, or the
                                        ; mirror's frame under a reflection
CHRECLEN        equ     $ - chrec
oprec:          ds      CHRECLEN
OP              equ     oprec - chrec

jarabove        equ     SYSVARS + 19    ; 1 the row above, -1 his own
jstkx:          db      0
jstky:          db      0
btn:            db      0
clrf:           db      0
clrb:           db      0
clru:           db      0
clrd:           db      0
clrbtn:         db      0
atemp           equ     0x5C21
fwdkind         equ     0x5C22
blockid         equ     0x5C23
fchary:         db      0
curleft         equ     0x5C24
croprow         equ     0x5C26
croptop         equ     0x5C27
kidstr:         db      3               ; initmaxstr in TOPCTRL.S

curw            equ     0x5C28
curh            equ     0x5C29
curoff          equ     0x5C2A
curshift        equ     0x5C2B
curdat          equ     0x5C2C
curbank         equ     0x5C2E
curent          equ     0x5C2F
rowy:           db      0

spskip          equ     0x5C31          ; and what the left edge cut off
frstart:        db      0               ; the interrupt this frame began on
tilestate       equ     0x5C32          ; the state of the tile last read
gotsword:       db      START_SWORD               ; he has picked the sword up: CTRL.S
                                        ; asks it before he may draw on anyone
rbody:          ds      4               ; where his own picture goes
runion:         ds      4               ; and the frame's, with the sword
curfdy          equ     0x5C33          ; SETUPCHAR's Fdy for this frame
collidel        equ     0x5C34          ; CHECKBARR and its helpers
collider        equ     0x5C35
collx           equ     0x5C36
collface        equ     0x5C37
bythis          equ     0x5C38
bylast:         db      0
begrange        equ     0x5C39
endrange:       db      0
cdleft:         db      0               ; CDLeftEj and CDRightEj, 140 wide
cdright:        db      0
cbrow           equ     0x5C3A
cbidx           equ     0x5C42
cbedge          equ     0x5C43          ; blockedge
cccode          equ     0x5C44          ; the barrier code in hand
cbcd            equ     0x5C45
cbsn            equ     0x5C49
tempbx          equ     0x5C47          ; RDBLOCK's tempblockx, tempblocky
tempby          equ     0x5C4B          ; and tempscrn
tempscrn        equ     0x5C4C
dbcol           equ     0x5C4D
fwdbx           equ     0x5C4E          ; CharBlockX, the block in front, and
fwdinx          equ     0x5C4F          ; what is in it
fwdid           equ     0x5C50
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
vwfirst         equ     0x5C51          ; the run in hand: its first row
vwn             equ     0x5C52          ; and how many
flipnow:        db      0               ; show it at the top of the next frame
nohalt:         db      0               ; the fill ran up to the interrupt
vwwait          equ     0x5C53          ; a step is due: the queue waits
vwstop:         db      0               ; the one it runs up to
vwmin:          db      0               ; rows still owed it this frame
vwhung:         db      0               ; frames since it last had a run
atbase          equ     0x5C54          ; the colours set_attrs writes
masterc         equ     0x5C56
coverm          equ     0x5C57
covm            equ     0x5C59          ; cover_rows' three: the mask's row,
covr            equ     0x5C5B          ; the room's and the working copy's,
covw            equ     0x5C5D          ; and which row of the mask that is
covi            equ     0x5C5F
coverb          equ     SYSVARS + 20
roomp           equ     SYSVARS + 22
rowptr          equ     SYSVARS + 24
rndseed:        db      37
fstate          equ     SYSVARS + 26
flleft          equ     0x5C60
flrec           equ     0x5C61
flst            equ     0x5C63
flsrc           equ     0x5C65
flstride        equ     0x5C67
flmbase         equ     0x5C68
flrect:         ds      4
linecol:        db      0
ercol:          db      0
ertop:          db      0
erw:            db      0
erh:            db      0
shcol:          db      0
shtop:          db      0
shw:            db      0
shh:            db      0

dfsrc:          dw      0               ; bookkeeping: see dfsetup


; UPDATEGUARD for the room below, which ADDGUARD will raise him in again:
; a fresh start, and he is gone from this one.

skel_down:      ld      a, SND_SPLAT
                call    addsound
                ld      a, (nowbank)
                push    af
                call    page_bg
                ld      a, SKELLAND
                ld      de, 0
                call    gd_field_in
                ld      (hl), SKELLANDBLK
                ld      a, SKELLAND
                ld      de, GDX
                call    gd_field_in
                ld      (hl), SKELLANDX
                ld      a, SKELLAND
                ld      de, GDFACE
                call    gd_field_in
                ld      (hl), 0         ; facing right
                ld      a, SKELLAND
                ld      de, GDPROG
                call    gd_field_in
                ld      a, (guardprog)
                ld      (hl), a
                ld      a, SKELLAND
                ld      de, GDSEQH
                call    gd_field_in
                ld      (hl), 0         ; alive: ADDGUARD starts him afresh
                pop     af
                call    pageset
                jp      gd_gone

; The guard's program, AUTO.S: his column of its tables, which c1gprob copies
; out of CODE1 whenever he is given one -- the tables are only ever read for
; the guard in the room.

GP_STRIKE       equ     0
GP_RESTRIKE     equ     1
GP_BLOCK        equ     2
GP_IMPBLOCK     equ     3
GP_ADV          equ     4
GP_REFRACT      equ     5
gprob:          ds      6

cmpspace:       incbin  "cmpspace.bin"
cmpbarr:        incbin  "cmpbarr.bin"
floory:         incbin  "floory.bin"
blocktop:       incbin  "blocktop.bin"
floorband:      incbin  "floorband.bin"
torches:        ds      1 + 4 * 7       ; seven bytes a torch, and no room
                                        ; of the fifteen has more than four
flametab:       incbin  "flametab.bin"
flamemask:      incbin  "flamemask.bin"
                ds      (($ + 255) / 256 * 256) - $
shifthi:        incbin  "shifthi.bin"
shiftlo:        incbin  "shiftlo.bin"
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

; ---------------------------------------------------------------- CODE1
;
; What works on the canvas bank with it paged in, and on nothing else but
; the fixed half of the map, lives in that bank: past the canvas, where a
; room being built never writes.  Assembled in place, cut out of pop.bin by
; build.sh and put on the end of the art bank's tape block, past the titles'
; music (C1ART), and put in place by start.

c1fix:
                org     CODE1

; The band's groups, imgbuf's seven room bytes (or fourteen) a row, back
; into the slice as the canvas had them.

c1unpack:       ld      a, (rbgroup)
                add     a, a
                add     a, a
                add     a, a
                ld      e, a
                ld      d, 0
                ld      hl, SLICE
                add     hl, de
                ex      de, hl          ; DE = the slice at the group
                ld      hl, imgbuf
                ld      a, (rbh)
                ld      b, a
                ld      a, (fmode)
                or      a
                jr      z, cufull
                ld      a, (blockcol)
                rra
                jr      c, cuodd
                inc     hl              ; an even block is the first half: the
                inc     hl              ; second, from the fourth room byte
                inc     hl
                inc     de
                inc     de
                inc     de
                inc     de
cue1:           push    bc              ; unp_hi has B
                ld      c, (hl)
                inc     hl
                call    unp_hi
                pop     bc
                inc     hl              ; seven on to the next row's fourth
                inc     hl
                inc     hl
                ld      a, e            ; and forty less the four laid
                add     a, CANVAS_W - 4
                ld      e, a
                jr      nc, cue2
                inc     d
cue2:           djnz    cue1
                ret
cuodd:          push    bc              ; an odd one the second: the first,
                push    de              ; and the next group whole if a piece
                call    unp_lo          ; runs on into it
                inc     hl
                inc     hl
                inc     hl
                ld      a, (rbwide)
                or      a
                jr      z, cuo1
                inc     de
                inc     de
                inc     de
                inc     de
                call    unp8
cuo1:           pop     de
                ex      de, hl
                ld      bc, CANVAS_W
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    cuodd
                ret
cufull:         push    bc
                push    de
                call    unp8
                ld      a, (rbwide)
                or      a
                call    nz, unp8
                pop     de
                ex      de, hl
                ld      bc, CANVAS_W
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    cufull
                ret

; cv8to7 turned about: seven room bytes at HL, eight pixels each, into eight
; canvas bytes at DE, seven pixels each in bits 7 to 1.  Both move on.

unp8:           call    unp_lo
                jr      unp_hi
unp_lo:         ld      c, (hl)         ; nought: bits 7..1 of the first
                ld      a, c
                and     0xfe
                ld      (de), a
                inc     de
                inc     hl
                ld      a, c            ; one: bit 0 of it, 7..2 of the next
                rrca
                and     0x80
                ld      b, a
                ld      c, (hl)
                ld      a, c
                rrca
                and     0x7e
                or      b
                ld      (de), a
                inc     de
                inc     hl
                ld      a, c            ; two
                rrca
                rrca
                and     0xc0
                ld      b, a
                ld      c, (hl)
                ld      a, c
                rrca
                rrca
                and     0x3e
                or      b
                ld      (de), a
                inc     de
                inc     hl
                ld      a, c            ; three
                rrca
                rrca
                rrca
                and     0xe0
                ld      b, a
                ld      c, (hl)
                ld      a, c
                rrca
                rrca
                rrca
                and     0x1e
                or      b
                ld      (de), a
                inc     de
                inc     hl
                ret                     ; C = the fourth room byte, HL past it
unp_hi:         ld      a, c            ; four
                rrca
                rrca
                rrca
                rrca
                and     0xf0
                ld      b, a
                ld      c, (hl)
                ld      a, c
                rrca
                rrca
                rrca
                rrca
                and     0x0e
                or      b
                ld      (de), a
                inc     de
                inc     hl
                ld      a, c            ; five
                rlca
                rlca
                rlca
                and     0xf8
                ld      b, a
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                rlca
                and     0x06
                or      b
                ld      (de), a
                inc     de
                inc     hl
                ld      a, c            ; six
                rlca
                rlca
                and     0xfc
                ld      b, a
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                and     0x02
                or      b
                ld      (de), a
                inc     de
                inc     hl
                ld      a, c            ; seven: the last one's 6..0
                rlca
                and     0xfe
                ld      (de), a
                inc     de
                ret

; The block's own four columns of the band, wiped.

c1wipe:         ld      a, (xco)
                ld      e, a
                ld      d, 0
                ld      hl, SLICE
                add     hl, de
                ld      a, (rbh)
                ld      b, a
                ld      de, CANVAS_W - 3
cw1:            ld      (hl), 0
                inc     hl
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
                add     hl, de
                djnz    cw1
                ret

; B rows of the band's group or groups, HL on in the slice, out to imgbuf
; at DE for the repacking.

c1copy:         push    bc
                push    hl
                ld      bc, 8
                ld      a, (rbwide)
                or      a
                jr      z, c1c1
                ld      c, 16
c1c1:           ldir
                pop     hl
                ld      c, CANVAS_W
                add     hl, bc
                pop     bc
                djnz    c1copy
                ret

; The floor mask's four columns for its band, wiped for maskone.

c1mowipe:       call    mocanrow
                ld      b, 15
cmw1:           ld      (hl), 0
                inc     hl
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
                ld      de, CANVAS_W - 3
                add     hl, de
                djnz    cmw1
                ret

; The rest of ctrlplayer's :dead in TOPCTRL.S, once he has fallen for good:
; CharLife counted up to deadenough, and then the level begun again --
; RESTART, by way of the room change: lvflag 3, which nextroom and levelgo
; take from there -- as soon as the tune for his death is heard out, or at
; once for ENTER or SPACE, which cut it short.  No "Press button to
; continue": nothing waits to be told.

DEADENOUGH      equ     4               ; TOPCTRL.S

c1dead:         ld      hl, charlife
                ld      a, (hl)
                cp      DEADENOUGH
                jr      nc, cd1
                inc     (hl)
                jp      page_art
cd1:            ld      a, 0xbf         ; ENTER, and not the button with it:
                in      a, (254)        ; SPACE is pressed as he dies as often
                rra                     ; as not, and the song never played
                call    nc, ststop
                ld      a, (sfxtimer)
                or      a
                jp      nz, page_art
                ld      a, 3
                ld      (lvflag), a
                jp      page_art

; The tape, while a level changes: a line of the ROM's letters across the
; middle of the black screen asks for it to be started, and once the level
; is in, stopped -- for a few seconds, or until ENTER or SPACE.

c1start:        ld      hl, msgstart
                jr      tapemsg
c1stop:         ld      hl, msgstop
                call    tapemsg
                ld      b, 150
c1sw:           halt
                ld      a, 0x3f
                in      a, (254)
                rra
                ret     nc
                djnz    c1sw
                ret

; HL = the column, then the text, nought at its end.

tapemsg:        ld      a, (hl)
                inc     hl
                add     a, 0x60         ; cell row 11: the middle third's
                ld      e, a            ; fourth
                ld      d, 0x48
tm1:            ld      a, (hl)
                or      a
                ret     z
                push    hl
                push    de
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl
                ld      bc, 0x3C00      ; the ROM's letters, space at 0x3D00
                add     hl, bc
                ld      b, 8
tm2:            ld      a, (hl)
                ld      (de), a
                inc     hl
                inc     d
                djnz    tm2
                pop     de
                ld      d, 0x59         ; and its cell grey, whatever the
                ld      a, 7            ; room before left in it (the user's
                ld      (de), a         ; colour for these two lines)
                ld      d, 0x48
                pop     hl
                inc     hl
                inc     e
                jr      tm1

msgstart:       db      9, "START THE TAPE", 0
msgstop:        db      9, "STOP THE TAPE ", 0

; ------------------------------------------------------------- a test key
;
; Q takes him to the next level, for testing: the stairs do no more than put
; lvflag at 2, and nextroom takes it from there -- the tune, the black screen,
; the tape and STARTKID in the new level's own room.  So it is armed only when
; the flag says a level follows this one on the tape (1), never over a death's
; restart (3), and only on the frame the key goes down: held, it would carry
; him through the level after as well.

KEYROW_QT       equ     0xFBFE          ; Q is bit 0 of the Q-to-T half row

nextlevkey:     ld      bc, KEYROW_QT
                in      a, (c)
                cpl
                and     1
                ld      hl, qdown
                cp      (hl)
                ld      (hl), a
                ret     z               ; as it was
                or      a
                ret     z               ; and it was let go
                ld      a, (lvflag)
                cp      1
                ret     nz              ; the last level, or he is dead
                inc     a
                ld      (lvflag), a
                ret

qdown           equ     SYSVARS + 33    ; the key as it was last frame

; NextFrame in TOPCTRL.S, the parts of it this port keeps here, from the main
; loop by c1jp.  animtrans and bonesrise come first, ahead of the kid, as they
; do in NextFrame: what the trans list moves this frame is what he meets this
; frame.  Run after him, as it was, a slicer triggered by his step had moved
; on a frame before he could see it, and the jaws that barred him were the
; ones of the frame before.  Then checkalert, before either of them moves,
; and the canvas bank left in for the control code.

c1anim:         ld      de, ovstart     ; the set's own first: a reflection
                ld      hl, bgjp        ; out of the way of the frame's moves
                call    c1far
                ld      hl, animtrans
                call    c1far
                call    bonesrise
                ld      a, (charid + OP)        ; CHECKALERT leaves out the
                dec     a                       ; shadowman but on level 12:
                ld      hl, checkalert  ; the sequences are in the canvas bank
                call    nz, c1mod
                jp      page_canvas

; The prince standing still is the same picture in the same place frame
; after frame, and rubbing him out, drawing him, putting the floor and the
; front back over him and showing him was a quarter of a frame -- which the
; redraw queue wanted, so that a gate went up a step in four frames.  He is
; left as he is, as a still guard is (gd_still), when where he is, his frame,
; the way he faces, where he is cut and his rectangle are as when he was last
; drawn, and nothing goes over his box this frame: no floor falling, no
; guard drawn afresh, no block put back, no flame, no view turned round.
; His box is then emptied, so nothing rubs him out and nothing shows him,
; and kid_pics does not draw him.  From draw_chars by c1call, the guard's
; question first, as rect_still had it.

kid_still:      ld      hl, newcol      ; the box round where he is and was
                call    rect_box
                call    gd_still
                xor     a
                ld      (kidskip), a
                ld      hl, charx       ; as when last drawn, and this frame's
                ld      de, kidlast     ; kept whatever the answer
                ld      bc, 5 * 256
                call    gs_cmp
                ld      hl, charcu
                ld      b, 5
                call    gs_cmp
                ld      a, c
                ld      hl, mbold + 2   ; nothing falling
                or      (hl)
                ld      hl, mbold + 6
                or      (hl)
                ld      hl, nummob
                or      (hl)
                ld      hl, flipnow     ; nor the view turning round
                or      (hl)
                ld      hl, fullshow
                or      (hl)
                ret     nz
                ld      a, (gdhere)     ; the guard drawn afresh over him
                or      a
                jr      z, ksgd
                ld      a, (gdskip)
                or      a
                jr      nz, ksgd
                ld      de, boxcol
                call    gs_meet
                ret     c
ksgd:           ld      a, (dirtyn)     ; a block put back over him
                or      a
                jr      z, ksfl
                ld      b, a
                ld      de, dirtyq
ksdq:           call    ksmeet
                ret     c
                inc     de
                inc     de
                inc     de
                inc     de
                djnz    ksdq
ksfl:           ld      a, (torches)    ; a flame laid over him
                or      a
                jr      z, ksyes
                ld      b, a
                ld      hl, torches + 1
ksfl1:          push    hl
                ld      de, ksrect      ; its rectangle on the screen
                ld      a, (hl)
                push    bc
                call    subcam
                pop     bc
                ld      (de), a
                inc     hl
                inc     de
                push    bc
                ldi
                ldi
                ldi
                pop     bc
                ld      de, ksrect
                call    ksmeet
                pop     hl
                ret     c
                ld      de, 7
                add     hl, de
                djnz    ksfl1
ksyes:          ld      hl, kidskip
                inc     (hl)
                xor     a
                ld      (boxw), a
                ret

; DE = a rectangle.  Out: carry if it meets his box.  DE and HL as they were.

ksmeet:         ld      hl, boxcol
                inc     de
                inc     de
                ld      a, (de)
                dec     de
                dec     de
                or      a
                ret     z
                call    ov1
                ret     nc
                inc     hl
                inc     de
                call    ov1
                dec     de
                ret

ksrect:         ds      4
kidlast:        ds      10

; And after the two of them have moved: CHECKSLICE (DoKid's last), the
; sounds, the slicers' pictures brought up to their states, and kid_death
; last, as its way out may page the art bank in.

c1post:         call    nextlevkey      ; a test key first of all
                call    checkslice
                call    addsfx
                call    sl_sync
                ld      de, ovpost      ; and the set's: level four's mirror,
                ld      hl, bgjp        ; his reflection in it and the
                call    c1far           ; shadow that comes out of it

; When he has died and stopped moving, the death song: heroic if he fell in a
; fight.  CharLife goes past nought so it is asked for once.

kid_death:      ld      a, (charlife)
                or      a
                jr      z, kdnow
                ret     m               ; alive
                jp      c1dead          ; dead a while
kdnow:          ld      a, (frame)
                cp      185
                jr      z, kddead
                cp      177
                jr      z, kddead
                cp      178
                ret     nz
kddead:         ld      a, 1
                ld      (charlife), a
                ld      a, (heroic)
                or      a
                ld      a, SONG_ACCID
                jr      z, kdsong
                ld      a, SONG_HEROIC
kdsong:         ld      c, 255
                jp      cue_song

; ADDSFX in TOPCTRL.S: a strike that is blocked rings.

addsfx:         ld      a, (frame)
                cp      167             ; blocked strike
                ld      a, SND_SWORDCLASH1
                jp      z, addsound
                ld      a, (gdhere)
                or      a
                ret     z
                ld      a, (frame + OP)
                cp      167
                ret     nz
                ld      a, SND_SWORDCLASH2
                jp      addsound

; POTIONEFFECT in MISC.S, on the effect in the sequence the kid drinks in.
; lastpotion is what RemoveObj left: -1 the sword, 1 a refresh of one point,
; 2 one more point for good, 3 weightlessness, 5 poison.  The lightning is
; the Apple's whole screen gone to one colour for a frame; the border here.
; The upside down potion, 4, is not done: the screen cannot turn over.

potion_effect:  ld      a, (charid)
                or      a
                ret     nz
                ld      a, (lastpotion)
                or      a
                ret     z
                inc     a
                jr      nz, penotsword
                ld      a, SONG_SWORD
                ld      c, 25
                call    cue_song
                ld      a, 1            ; the sword: three green flashes
                ld      (gotsword), a
                ld      bc, GREEN * 256 + 3
                jr      peflash
penotsword:     dec     a
                cp      1
                jr      nz, pe2
                ld      a, (maxkidstr)  ; a point back, if one is missing
                ld      hl, kidstr
                cp      (hl)
                ret     z
                inc     (hl)
                ld      a, SONG_SHORTPOT
                ld      c, 25
                call    cue_song
                ld      bc, RED * 256 + 2
                jr      peflash
pe2:            cp      2
                jr      nz, pe3
                ld      a, (maxkidstr)  ; BOOSTMETER, then RECHARGEMETER
                cp      MAXKIDMETER
                jr      nc, pe2full
                inc     a
                ld      (maxkidstr), a
pe2full:        ld      (kidstr), a
                ld      a, SONG_POTION
                ld      c, 25
                call    cue_song
                ld      bc, RED * 256 + 5
                jr      peflash
pe3:            cp      3
                jr      nz, pe5
                ld      a, 200          ; wtlesstimer
                ld      (weightless), a
                ld      a, SONG_SHORTPOT
                ld      c, 25
                jp      cue_song
pe5:            cp      5
                ret     nz
                ld      a, SND_SPLAT
                call    addsound
                ld      hl, kidstr      ; yecch: a point off
                ld      a, (hl)
                or      a
                ret     z
                dec     (hl)
                ret
peflash:        ld      a, b
                ld      (lightcolor), a
                ld      a, c
                ld      (lightning), a
                ret

; RemoveObj in CTRL.S, for take_sword: the block in front of him, whichever
; it holds -- the sword, or a flask whose potion is the top three bits of
; its state -- is floor from now on, and the space it stood in is redrawn
; at once, as RemoveObj marks it: a flask's bubbles are a band higher.

c1take:         ld      a, (roomnum)
                ld      (trscrn), a
                ld      a, (blocky)     ; ten blocks to the row, as checkpress
                call    mul10           ; works it out
                ld      a, (fwdinx)
                add     a, l
                ld      (trloc), a

                ld      hl, trobat      ; which it is
                call    c1far
                ld      (takeid), a
                ld      a, (trobst)
                rlca
                rlca
                rlca
                and     7
                ld      (lastpotion), a
                ld      a, BG_FLOOR     ; and it is floor from now on
                ld      hl, trobtype
                call    c1far
                xor     a
                ld      (trobst), a
                ld      hl, trobsave
                call    c1far

                ld      a, (takeid)
                cp      BG_SWORD
                ld      a, SWORDWIPE
                jr      z, tkwipe
                ld      a, FLASKWIPE
tkwipe:         ld      (redh), a
                ld      a, 1            ; back of the queue it lay there on
                ld      (rqprio), a     ; the floor while he held it
                ld      hl, redplate
                call    c1far
                xor     a
                ld      (rqprio), a
                ld      hl, ao_masks    ; and its floor masks, a flask's not
                call    c1far           ; being a floor's
                call    unfront         ; and the bottle is not in front of
                                        ; him any more
                ld      hl, shown_attrs ; and a flask's colour goes with it,
                call    c1far           ; from a view being made as well
                ld      a, (vwcam)
                inc     a
                ld      (vwatt), a
                ret

; A thing taken off block (blockcol, blockrow): its front piece -- the bottle
; -- comes off the front list, height nought, so nothing is laid back over
; him where it stood.  Its entry is the one whose column is the block's and
; whose foot is within the block's floor line.

unfront:        call    trrowcol        ; the redraws moved blockcol on
                ld      a, (nfront)
                or      a
                ret     z
                ld      b, a
                ld      a, (blockcol)
                add     a, a
                add     a, a
                ld      c, a            ; C = the block's own byte column
                ld      a, (blockrow)
                inc     a
                ld      e, a
                ld      d, 0
                ld      hl, blockbot
                add     hl, de
                ld      d, (hl)         ; D = its floor line
                ld      hl, frontlist
ufloop:         ld      a, (hl)
                sub     c
                cp      4
                jr      nc, ufnext
                inc     hl
                ld      a, d
                sub     (hl)
                dec     hl
                cp      9
                jr      nc, ufnext
                push    hl
                inc     hl
                inc     hl
                inc     hl
                inc     hl
                ld      (hl), 0
                pop     hl
ufnext:         inc     hl
                inc     hl
                inc     hl
                inc     hl
                inc     hl
                djnz    ufloop
                ret

; ---------------------------------------------------------------- slicers
;
; ANIMSLICER in MOVER.S, off animobj's dispatch: the jaws go round their
; frames for ever while he is in the room and on their row, and the moment
; they are retracted with him gone -- or dead, unless they are the pair that
; cut him -- the slicer comes off the trans list.  A = its id, as trobat
; read it, gone with the paging: aoid has it.
;
; One step a frame and slicetimer steps round, as MOVER.S has it, and
; nothing waits: the picture is sl_sync's, which keeps up with the state in
; the frame the state is reached.  It used to be a block redraw through the
; queue, four frames of bands a picture, and the state held still until the
; picture was in -- so the jaws chopped at a pace of the queue's and not the
; Apple's, later than he triggered them and further apart.

SLICERSYNC      equ     3               ; frames between one and the next

aoslicer:       ld      a, (aoid)
                cp      BG_SLICER
                jp      nz, stopobj     ; none of animobj's: off the list
                ld      a, (trdirec)
                or      a
                jp      m, asdone       ; stopped: nothing moves
                ld      a, (trobst)     ; the next frame, round and round,
                ld      b, a            ; the blood kept
                and     0x7f
                inc     a
                cp      SLICETIMER + 1
                jr      c, as1
                ld      a, 1
as1:            ld      c, a
                ld      a, b
                and     0x80
                or      c
                ld      (trobst), a
                ld      a, c
                cp      SLICEREXT       ; the jaws meeting
                jr      nz, as2
                ld      a, SND_SLICER   ; the CPC's, for JawsClash
                call    addsound
as2:            ld      a, (trscrn)     ; his room?
                ld      hl, roomnum
                cp      (hl)
                jr      nz, asoff
                ld      a, (trloc)      ; and his row?
                ld      b, 0xff
asrow:          inc     b
                sub     10
                jr      nc, asrow
                ld      a, (blocky)
                cp      b
                jr      nz, asoff
                ld      a, (charlife)
                or      a
                jp      m, asdone       ; he is alive: on it chops
                ld      a, (trobst)     ; dead, and the slicers that did not
                and     0x80            ; cut him stop
                jr      nz, asdone
asoff:          ld      a, (trobst)     ; retracted, it comes off the list
                and     0x7f
                cp      SLICERRET
                jr      c, asdone
                call    stopobj

; The state goes back, and nothing is queued: sl_sync draws it.

asdone:         xor     a
                ld      (redwant), a
                ld      hl, aodone
                jp      c1far

; The pictures.  A slicer has two, the jaws open and the jaws shut (see
; slicer_x), and the shut one smeared once it has cut.  They are made with
; the room, in the canvas -- the block's own passes run again over its band,
; the way a block redraw runs them -- and kept as what each changes of the
; open one: SLROWS rows of the four room bytes the block's twenty eight
; pixels lie in.  A picture is then those bits flipped in the room and the
; block shown, 55000 T or so, where a block redraw is 237000.
;
; The room is always built with them open, and slshow says what each shows.
; A slice changes the picture twice, the jaws shutting at slicerExt and
; opening the frame after -- the one frame they are shut on the Apple too --
; and three times if the blood is spilt while they are shut.

SLMAX           equ     3               ; the most any room of POP's has
SLROWS          equ     58              ; the rows the jaws, their front and
SLTOP           equ     62              ; the smear change: the first is
SLTILE          equ     4 * SLROWS      ; SLTOP up from the floor line
SLTILES         equ     PRISTINE + PRISTLEN     ; two to a slicer, in the
SLEND           equ     SLTILES + 2 * SLTILE * SLMAX    ; canvas bank
SLTEMP          equ     MASKCAN         ; and where they are made, while
                                        ; the room is built: see sl_make

slnum:          db      0               ; how many the room has
slloc:          ds      SLMAX           ; their blocks
slshow:         ds      SLMAX           ; and the picture each shows
slslot:         db      0

; A = a state.  Out: A = what it shows -- nought open, 1 shut, 2 shut and
; smeared -- as slicer_x draws it.

slpic:          ld      c, a
                and     0x7f
                cp      SLICEREXT
                ld      a, 0
                ret     nz
                ld      a, c
                rlca
                and     1
                inc     a
                ret

; Every frame, once the slicers and the characters have moved: a slicer whose
; picture is not its state's is brought up to it -- in the room, the working
; copy and a view being made -- before he is drawn, so the front goes over
; him in the frame the jaws shut.

sl_sync:        ld      a, (slnum)
                or      a
                ret     z
                ld      b, a
                ld      c, 0
ssloop:         push    bc
                ld      a, c
                ld      (slslot), a
                ld      hl, slloc
                call    slat
                ld      e, (hl)
                ld      d, 0
                ld      hl, roomids + 30
                add     hl, de
                ld      a, (hl)         ; its state, as the room has it
                call    slpic
                ld      hl, slshow
                call    slat
                cp      (hl)
                call    nz, slturn
                pop     bc
                inc     c
                djnz    ssloop
                ret

; HL = a table, (slslot) = the slot.  Out: HL on its entry.  A kept.

slat:           push    af
                ld      a, (slslot)
                add     a, l
                ld      l, a
                jr      nc, sla1
                inc     h
sla1:           pop     af
                ret

; HL = its slshow, A = the picture it is to show.  The whole change goes in
; one pass: to open, the old picture's bits; from open, the new one's;
; between shut and smeared, both.

slturn:         ld      c, (hl)
                ld      (hl), a
                or      a
                jr      nz, slt1
                ld      a, c            ; back to open: the old one's
                ld      c, 0
slt1:           push    bc
                call    sltile
                ld      de, imgbuf
                ld      bc, SLTILE
                ldir
                pop     bc
                ld      a, c            ; and the other's, if both are shut
                call    slxorin
                ld      hl, slloc
                call    slat
                ld      a, (hl)
                ld      (trloc), a
                call    trrowcol        ; its row and column
                ld      a, (blockrow)
                ld      hl, blockbot + 1
                add     a, l
                ld      l, a
                ld      a, (hl)
                sub     SLTOP + 1 - SLROWS      ; redshow's band: SLROWS
                ld      (dy), a                 ; rows ending at the last
                sub     SLROWS - 1              ; that changes
                push    af
                call    roomrow
                ld      a, (blockcol)   ; seven room bytes to two blocks
                ld      c, a
                add     a, a
                add     a, a
                add     a, a
                sub     c
                srl     a
                ld      e, a
                ld      d, 0
                add     hl, de
                ex      de, hl          ; DE = the tile's first room byte
                ld      a, (redh)
                push    af
                ld      a, SLROWS
                ld      (redh), a
                xor     a
                ld      (redwide), a
                ld      hl, slxor       ; flipped, and shown
                call    c1far
                pop     af
                ld      (redh), a
                pop     af              ; and a view being made wants them
                ld      b, SLROWS
                jp      vw_mark

; A = a picture, shut or smeared.  Out: HL = its tile, two to a slot.

sltile:         ld      b, a
                ld      a, (slslot)
                add     a, a
                add     a, b
                ld      b, a            ; the tiles before it, and one
                ld      hl, SLTILES - SLTILE
                ld      de, SLTILE
sxi1:           add     hl, de
                djnz    sxi1
                ret

; A = a picture: its tile, if it has one, flipped into imgbuf.

slxorin:        or      a
                ret     z
                call    sltile
                ld      de, imgbuf
                ld      bc, SLTILE
sxi2:           ld      a, (de)
                xor     (hl)
                ld      (de), a
                inc     hl
                inc     de
                dec     bc
                ld      a, b
                or      c
                jr      nz, sxi2
                ret

; The room's slicers and their pictures, called by newroom between compose
; and convert, with the whole canvas there.  For each, the block's band is
; wiped and the passes that are the same whatever the jaws do -- C, B, D and
; their moving parts -- run again over it once, as a block redraw runs them;
; then A and the front for each picture over a copy of that.  Its change
; from the open one is taken in the canvas's own bytes, where the rest of the
; group is nought, and packed the way convert packs a row: the packing only
; moves bits about, so it packs a change as well as a picture.  The changes
; wait in SLTEMP, past CODE1, where the floor masks go later, and sl_keep
; puts them in SLTILES once convert has done with the canvas they lie over.
;
; The room is built with the jaws open.  Compose drew them as the state had
; them: open, that is the open picture, and the canvas goes back to it after.

SLBAND          equ     SLTOP + 1               ; the block's band, its rows
SLORIG          equ     SLTEMP + 2 * SLTILE * SLMAX     ; the open picture,
SLCOMMON        equ     SLORIG + 4 * SLBAND     ; and the passes before A,
                                                ; four canvas bytes a row

sl_make:        xor     a
                ld      (slnum), a
                ld      c, a            ; the block
slm1:           ld      hl, roomids
                ld      b, 0
                add     hl, bc
                ld      a, (hl)
                and     0x1f
                cp      BG_SLICER
                jr      nz, slm2
                ld      a, (slnum)
                cp      SLMAX
                ret     nc
                ld      (slslot), a
                inc     a
                ld      (slnum), a
                push    bc
                ld      a, c
                ld      hl, slloc
                call    slat
                ld      (hl), a
                ld      hl, slshow
                call    slat
                ld      (hl), 0
                ld      (trloc), a
                call    slmake1
                pop     bc
slm2:           inc     c
                ld      a, c
                cp      30
                jr      c, slm1
                ret

; The slot (slslot), at block (trloc).

slmake1:        call    trrowcol
                ld      a, (trloc)
                ld      e, a
                ld      d, 0
                ld      hl, roomids + 30
                add     hl, de
                ld      (sltarg), hl
                ld      a, (hl)
                push    af              ; its state, put back after
                call    rb_setup        ; dy, xco and the blocks beside it
                ld      a, (dy)
                ld      (bandbot), a
                sub     SLTOP
                ld      (bandtop), a
                call    canvasrow
                ld      a, (xco)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (slcan), hl     ; the block's first byte in the band
                ld      de, SLORIG      ; as compose left it
                call    slsave
                ld      hl, (slcan)     ; wiped, and what does not move
                ld      b, SLBAND
                ld      de, CANVAS_W - 3
sk1:            xor     a
                ld      (hl), a
                inc     hl
                ld      (hl), a
                inc     hl
                ld      (hl), a
                inc     hl
                ld      (hl), a
                add     hl, de
                djnz    sk1
                ld      hl, slpasses
sk2:            ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      a, d
                or      e
                jr      z, sk3
                push    hl
                ex      de, hl
                call    c1far
                pop     hl
                jr      sk2
sk3:            ld      de, SLCOMMON
                call    slsave
                pop     af
                push    af
                call    slpic
                or      a
                jr      z, sk5
                xor     a               ; not open: the open picture drawn,
                call    slpaint         ; for the others to be taken from
                ld      de, SLORIG
                call    slsave
sk5:            ld      a, (slslot)     ; two changes to a slot
                add     a, a
                ld      b, a
                ld      hl, SLTEMP - SLTILE
                ld      de, SLTILE
                inc     b
sk4:            add     hl, de
                djnz    sk4
                ld      (slrows), hl
                ld      a, SLICEREXT
                call    slpaint
                call    slchange
                ld      a, SLICEREXT + 0x80
                call    slpaint
                call    slchange
                ld      hl, SLORIG      ; and the canvas back to open
                ld      de, (slcan)
                call    slback
                pop     af
                ld      hl, (sltarg)
                ld      (hl), a
                jp      rbband0

; A = a state: the block's band as the passes before A left it, and A and
; the front laid over it for that state.

slpaint:        ld      hl, (sltarg)
                ld      (hl), a
                ld      hl, SLCOMMON
                ld      de, (slcan)
                call    slback
                ld      hl, setblock    ; the state, as the passes read it
                call    c1far
                ld      hl, draw_a
                call    c1far
                ld      hl, draw_front
                jp      c1far

; The four bytes of the block down its band: out of the canvas to DE
; (slsave), or from HL back into it at DE (slback).

slsave:         ld      hl, (slcan)
                ld      b, SLBAND
ss1:            push    bc
                ld      bc, 4
                ldir
                ld      bc, CANVAS_W - 4
                add     hl, bc
                pop     bc
                djnz    ss1
                ret

slback:         ld      b, SLBAND
sb1:            push    bc
                ld      bc, 4
                ldir
                ex      de, hl
                ld      bc, CANVAS_W - 4
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    sb1
                ret

; The canvas's picture against the open one, row by row down the tile: the
; bits that differ, set in the block's half of a group whose other half is
; nought, packed, and the room bytes the block lies in kept at (slrows),
; which moves on to the next tile.

slchange:       ld      hl, (slcan)
                ld      (slcp), hl
                ld      hl, SLORIG
                ld      (slop), hl
                ld      hl, cvbuf       ; the group: nought, and only the
                ld      b, 8            ; block's half of it written after
                xor     a
sc1:            ld      (hl), a
                inc     hl
                djnz    sc1
                ld      hl, cvbuf       ; an odd block is its second half,
                ld      de, cvbuf + 8   ; and packed from its fourth byte
                ld      a, (blockcol)
                rrca
                jr      nc, sc2
                ld      hl, cvbuf + 4
                ld      de, cvbuf + 11
sc2:            ld      (slgh), hl
                ld      (slgo), de
                ld      b, SLROWS
sc3:            push    bc
                ld      hl, (slop)
                ld      bc, (slcp)
                ld      de, (slgh)
                rept    4
                ld      a, (bc)
                xor     (hl)
                ld      (de), a
                inc     bc
                inc     hl
                inc     de
                endm
                ld      (slop), hl
                ld      hl, CANVAS_W - 4
                add     hl, bc
                ld      (slcp), hl
                ld      hl, cvbuf       ; packed
                ld      de, cvbuf + 8
                call    cv8to7
                ld      hl, (slgo)
                ld      de, (slrows)
                ldi
                ldi
                ldi
                ldi
                ld      (slrows), de
                pop     bc
                djnz    sc3
                ret

slpasses:       dw      setblock, draw_c, draw_mc, draw_b, draw_mb
                dw      draw_d, draw_md, 0

sltarg:         dw      0               ; the block's state in roomids
slcan:          dw      0
slcp:           dw      0
slop:           dw      0
slgh:           dw      0               ; the block's half of the group
slgo:           dw      0               ; and of it packed
slrows:         dw      0

; After convert: the changes into SLTILES, where sl_sync reads them.

sl_keep:        ld      hl, SLTEMP
                ld      de, SLTILES
                ld      bc, 2 * SLTILE * SLMAX
                ldir
                ret

; bgdraw's BG_MASK, POP's mask opacity (MASKTAB in HRTABLES.S), which
; maddfore lays a flask's bottle with: each pixel of the piece clears itself
; and its neighbour either side, and then goes in.  Without it the floor's dither behind ran into the bottle, and the
; handle and the bands of the tall one showed or not by which column it
; stood in.  It is here, in CODE1, because bgdraw lays with the canvas
; bank in: DE = the piece's row, HL = the canvas, B = how many bytes.

bgpmask:        ld      c, 0            ; the halo the byte before spills
bpk1:           push    bc              ; B bytes left, C that halo
                ld      a, (de)
                ld      b, a            ; B = its pixels, bits 7 to 1
                add     a, a            ; each one's left neighbour
                or      b
                or      c
                ld      c, a
                ld      a, b            ; and right: pixel six's lands on
                srl     a               ; the spare bit
                or      c
                ld      c, a            ; C = the halo
                cpl
                or      1               ; the canvas's spare bit alone
                and     (hl)
                or      b
                ld      (hl), a
                ld      a, c            ; pixel six's right neighbour is the
                rrca                    ; next byte's pixel 0
                and     0x80
                inc     hl
                inc     de
                pop     bc
                ld      c, a
                djnz    bpk1
                jp      bgrowskip

; ADDSLICERS in SUBS.S: every slicer on the row the character is on starts
; chopping -- the first at once, each of the rest slicersync frames behind
; it -- and one already in mid-slice is left alone.  His room is the one on
; screen, so its thirty blocks are in hand.

c1addsl:        ld      a, (blocky)
                cp      3
                ret     nc
                call    mul10           ; ten blocks to the row
                ld      a, l
                ld      (sltrloc), a
                ld      de, roomids
                add     hl, de
                ld      a, SLICETIMER
                ld      (slstate), a
                ld      b, 10
asl1:           ld      a, (hl)
                and     0x1f
                cp      BG_SLICER
                jr      nz, aslnext
                push    hl
                push    bc
                ld      de, 30
                add     hl, de
                ld      a, (hl)         ; its state, as the room has it
                ld      c, a
                and     0x7f
                jr      z, aslok
                cp      SLICERRET
                jr      c, aslskip      ; in mid-slice: leave it alone
aslok:          ld      a, c            ; the blood it carries, and the frame
                and     0x80            ; this one starts at
                ld      hl, slstate
                or      (hl)
                call    trig_slicer
                ld      hl, slstate     ; getnextstate: the next one starts
                ld      a, (hl)         ; slicersync frames along
                sub     SLICERSYNC
                cp      SLICERRET
                jr      nc, aslsync
                add     a, SLICETIMER + 1 - SLICERRET
aslsync:        ld      (hl), a
aslskip:        pop     bc
                pop     hl
aslnext:        inc     hl
                ld      a, (sltrloc)
                inc     a
                ld      (sltrloc), a
                djnz    asl1
                ret

; TRIGSLICER in MOVER.S: A = the state it starts at, (sltrloc) = its block
; in the room on screen.

trig_slicer:    push    af
                ld      a, (sltrloc)
                ld      (trloc), a
                ld      a, (roomnum)
                ld      (trscrn), a
                ld      hl, trobat
                call    c1far
                pop     af
                ld      (trobst), a
                ld      hl, trobsave
                call    c1far
                ld      a, 1
                ld      (trdirec), a
                ld      hl, addtrob
                jp      c1far

; CHECKSLICE in COLL.S: the blocks his picture overlaps this frame, out of
; the collision buffer -- 0xff is a barrier he is inside -- and a slicer
; among them with its jaws shut cuts him in half.
;
; CHECKSLICE2, the same for a guard, is not here: no guard of this level
; ever stands on a slicer's row.

checkslice:     ld      a, (blocky)     ; tempblocky
                ld      (csrow), a
                ld      b, 9
cksl1:          ld      hl, cdthis
                ld      e, b
                ld      d, 0
                add     hl, de
                ld      a, (hl)
                inc     a
                jr      nz, cksl2       ; not over a barrier there
                ld      hl, snthis
                add     hl, de
                ld      a, (hl)         ; the room that block is in
                push    bc
                ld      c, a
                ld      a, (csrow)
                ld      e, a
                ld      a, c
                ld      c, e
                call    blk_in          ; B the column, C the row
                cp      BG_SLICER
                jr      nz, cksl3
                ld      a, (tilestate)
                and     0x7f
                cp      SLICEREXT       ; shut?
                jr      nz, cksl3
                pop     bc
                jr      c1slice
cksl3:          pop     bc
cksl2:          dec     b
                jp      p, cksl1
                ret

; Slice: the blood stays on the jaws, and he is put square on them, at the
; floor, and cut in half.  One that has him already leaves him alone.

c1slice:        ld      a, (tempbx)     ; its block, in its own room
                ld      (sltrloc), a
                ld      a, (csrow)
                call    mul10
                ld      a, (sltrloc)
                add     a, l
                ld      (trloc), a
                ld      a, (tempscrn)
                ld      (trscrn), a
                ld      hl, trobat
                call    c1far
                ld      a, (trobst)
                or      0x80
                ld      (trobst), a
                ld      hl, trobsave
                call    c1far
                ld      a, (frame)
                cp      178
                ret     z
                ld      a, (tempbx)     ; its left edge, seven units in
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                sbc     hl, de          ; twenty eight pixels to the block
                ld      de, 14
                add     hl, de
                ld      (charx), hl
                ld      a, 8            ; and eight the way he faces
                ld      hl, move_by
                call    c1mod
                ld      hl, floor_plane
                call    c1mod
                ld      (chary), a
                ld      a, 100
                call    decstr
                ld      a, SND_SPLAT
                call    addsound
                ld      a, SQ_HALVE
                ld      hl, bumpseq     ; jumpseq, then animchar
                jp      c1mod

csrow:          db      0
slstate:        db      0
sltrloc:        db      0


; ---------------------------------------------------------------- the bones
;
; BONESRISE in MISC.S: on level three, with the exit open and nobody else in
; the room, the skeleton lying in screen one gets up as the kid comes level
; with it.  The bones are a piece of the background until then; they become
; floor, that block and the one to its right are redrawn, and what stands up
; is a guard of the kid's own making -- CharID 4, program two, three points
; of strength he can never be made to lose.

bonesrise:      ld      a, (curlev)     ; level three
                cp      2
                ret     nz
                ld      a, (gdhere)     ; and nobody in the room yet
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
                ld      hl, trobat      ; what lies there
                call    c1far
                push    af
                ld      a, BG_FLOOR     ; floor from now on, and the block
                ld      hl, trobtype    ; and the one right of it redrawn --
                call    c1far           ; markred and markwipe, 24 rows deep
                ld      a, 24
                ld      (redh), a
                ld      hl, redplate
                call    c1far
                pop     af
                cp      BG_BONES
                ret     nz

                call    swapchar        ; he is made in Char, as POP makes
                ld      a, SKELY        ; him
                ld      (blocky), a
                ld      hl, floor_plane
                call    c1mod
                ld      (chary), a
                ld      hl, SKELX * BLOCK_PX + BLOCK_PX ; getblockej + angle
                ld      (charx), hl                     ; + 7
                xor     a
                ld      (facing), a     ; POP's -1, left
                ld      a, SQ_ARISE
                ld      hl, bumpseq     ; jumpseq, then animchar
                call    c1mod
                ld      a, SKELPROG
                ld      (guardprog), a
                call    c1gprob
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

; ------------------------------------------------------------ careful step
;
; The rest of DoStepfwd in CTRL.S, which the control code has no room for.
; In and out: (stepwant) -- in, how far GETFWDDIST says he may go; out, the
; sequence to start.
;
; Nothing left to step is not the end of it.  A barrier ahead -- a mirror,
; or a slicer -- he steps THROUGH, which is the only way past a slicer with
; its jaws up, and without this one stopped him dead like a chasm.  An edge
; he toes first and steps off only at a second press; CharRepeat, how long
; the last step was, is what tells the two presses apart.

c1stepseq:      ld      a, c
                or      a
                jr      z, cssnone
cssgo:          ld      (charrepeat), a
                dec     a
                add     a, SQ_STEP1
                ld      c, a
                ret
cssnone:        ld      a, (fwdkind)
                dec     a
                jr      z, cssthru      ; a barrier: straight through it
                ld      hl, charrepeat
                ld      a, (hl)
                or      a
                jr      z, cssthru      ; the second press: off the edge
                ld      (hl), 0         ; the first: toe it
                ld      c, SQ_TESTFOOT
                ret
cssthru:        ld      a, 11           ; POP's own natural step
                jr      cssgo

charrepeat      equ     SYSVARS + 34    ; CharRepeat: DoStepfwd's alone

; The guards' programs, AUTO.S, and the column of them for (guardprog) into
; gprob, where the fight reads it: add_guard and bonesrise come here as they
; give a guard his program.

c1gprob:        ld      a, (guardprog)
                ld      e, a
                ld      d, 0
                ld      hl, strikeprob
                add     hl, de
                ld      de, gprob
                ld      b, 6
cgp1:           ld      a, (hl)
                ld      (de), a
                inc     de
                ld      a, l            ; the next table, twelve on
                add     a, 12
                ld      l, a
                adc     a, h
                sub     l
                ld      h, a
                djnz    cgp1
                ret

; The shadow's keys, from do_shad's autoctrl by c1call: the command his
; level's code (bgovl.asm) has left in shadkey, AUTOPLAYBACK's -- 1 DoFwd,
; 2 DoBack, 6 DoPress; any other is nothing, DoRelease having let go of
; everything already.

c1shad:         ld      a, (shadkey)
                ld      hl, clrf
                dec     a
                jr      z, csfwd
                inc     hl              ; clrb
                dec     a
                jr      z, csback
                sub     4
                ret     nz
                dec     a
                ld      (clrbtn), a
                ld      (btn), a
                ret
csfwd:          dec     a
                ld      (hl), a
                ld      (jstkx), a
                ret
csback:         dec     a
                ld      (hl), a
                ld      a, 1
                ld      (jstkx), a
                ret

;               strike  0   1   2   3   4   5   6   7   8   9   10  11
strikeprob:     db      75, 100, 75, 75, 75, 50, 100, 220, 0, 60, 40, 60
restrikeprob:   db      0, 0, 0, 5, 5, 175, 20, 10, 0, 255, 255, 150
blockprob:      db      0, 150, 150, 200, 200, 255, 200, 250, 0, 255, 255, 255
impblockprob:   db      0, 75, 75, 100, 100, 145, 100, 250, 0, 145, 255, 175
advprob:        db      255, 200, 200, 200, 255, 255, 200, 0, 0, 255, 100, 100
refractimer:    db      20, 20, 20, 20, 10, 10, 10, 10, 0, 10, 0, 0

c1end:
                org     c1fix
C1LEN           equ     c1end - CODE1

; ---------------------------------------------------------------- start
;
; What runs once, before the working copy is first written, sits where the
; working copy goes: it comes in with the program and the first repaint goes
; over it, so the fixed half of the map keeps its room for the game.

start:          di
                ld      sp, stack

                ld      hl, SYSLOW      ; the variables under the loader,
                ld      de, SYSLOW + 1  ; nought
                ld      bc, LOWVARS + LOWVARLEN - SYSLOW - 1
                ld      (hl), 0
                ldir

                ld      hl, REVTAB      ; the bit reversal table, where it
revt1:          ld      a, l            ; lives from now on: each byte's bits
                ld      b, 8            ; the other way round
revt2:          rra
                rl      c
                djnz    revt2
                ld      (hl), c
                inc     l
                jr      nz, revt1

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
                call    pageset         ; by where the titles leave it alone,
                ld      hl, roomblk     ; swapped with what the tape left
                ld      de, RBINTRO     ; there: the credits over the splash,
                ld      bc, RB1LEN      ; which the titles show from where the
rbswap:         ld      a, (de)         ; room's code was
                ldi
                dec     hl
                ld      (hl), a
                inc     hl
                jp      pe, rbswap

                ld      hl, isrbanks    ; the interrupt's way in, at the top
                ld      b, 6            ; of every bank that is ever paged
stubbank:       push    bc
                ld      a, (hl)
                inc     hl
                push    hl
                call    pageset
                ld      hl, isrstub
                ld      de, 0x10000 - ISRSTUBLEN
                ld      bc, ISRSTUBLEN
                ldir
                pop     hl
                pop     bc
                djnz    stubbank
                ld      a, ISRPAGE
                ld      i, a
                im      2
                ld      a, BANK_ART     ; the titles' music is theirs
                ld      (sfxbank), a
                ld      a, POP_START    ; the titles, before the game begins
                or      a               ; -- a tape started elsewhere, for a
                call    nz, intro       ; test, goes straight in
                call    ststop          ; and the game's sounds its own
                ld      a, BANK_CVS
                ld      (sfxbank), a
                call    page_art        ; the canvas bank's code, from the art
                ld      hl, C1ART       ; bank by way of where the room's code
                ld      de, roomblk     ; goes, which is free until it is put
                ld      bc, C1LEN       ; back
                ldir
                ld      hl, 0xC000 + 2  ; and the titles are gone from the art
                                        ; bank: the room is composed into a bank of
                ld      de, 0xC000 + 3  ; noughts, past the signature and up
                ld      bc, 0x4000 - 2 - ISRSTUBLEN - 1 ; to the interrupt's
                ld      (hl), 0         ; way in
                ldir
                ld      a, BANK_CVS     ; the canvas bank's code in, and the
                call    pageset         ; room's back, the princess's band
                ld      hl, roomblk     ; having been there
                ld      de, CODE1
                ld      bc, C1LEN
                ldir
                ld      hl, RBINTRO
                ld      de, roomblk
                ld      bc, RB1LEN
                ldir
                call    newroom         ; and the room is composed, not loaded:
                call    lvkeep          ; the level as it begins, kept
                                        ; its code put back first, the
                                        ; princess's band having been there
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
                ld      a, START_FACE
                ld      (facing), a
                ld      a, POP_START    ; STARTKID's level one: he drops in
                or      a               ; out of the gate, which slams
                ld      a, SQ_STAND
                jr      z, stseq
                ld      a, 5            ; pushpp on the plate at screen 5,
                ld      (trscrn), a     ; block 2 -- the gate by the way in
                ld      a, 2
                ld      (trloc), a
                call    trobat
                call    pushpp
                call    page_canvas
                ld      a, SQ_STEPFALL
stseq:          call    jumpseq
                call    page_canvas
                call    step_seq
                ld      hl, c1addsl     ; the slicers of the row he starts on,
                call    c1call          ; as CUT starts those of a room walked
                call    add_guard       ; into -- and whoever keeps the room
                ld      a, START_ROOM - KIDSTART_SCRN
                or      a
                ld      a, SONG_DANGER  ; the level begins: "Danger", CUESONG
                jr      nz, stnosong    ; waiting 25 frames for the gate and
                ld      (songpend), a   ; the drop
                ld      a, 25 * FRAME_WAIT
                ld      (songwait), a
stnosong:
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
                jr      nz, badload
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
                jr      nz, badload
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

isrbanks:       db      BANK_SPR1, BANK_SPR2, BANK_SPR3, BANK_BG, BANK_ART
                db      BANK_CANVAS

                include "intro.asm"

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

SLICE           equ     CANVAS          ; a redraw's band: see rbwipe
SLICE_LEN       equ     16 * CANVAS_W   ; RQBAND rows at most
RBAT1           equ     SLICE + SLICE_LEN       ; in the canvas, past the slice
RBROOM          equ     3275            ; the room's code at most: RBINTRO's
PRISTINE        equ     RBAT1 + RBROOM  ; the level as it began: see lvkeep
PRISTLEN        equ     2304
pristok         equ     0x5C77          ; there is one to keep
sfxbank         equ     0x5CD4          ; where the sounds are: see page_sfx
curlev          equ     0x5C75          ; the level, less one
origstr         equ     0x5C76          ; MaxKidStr as the level began
milestone       equ     0x5C6B          ; level three's, passed
cvbasep         equ     0x5C72          ; the canvas as a redraw sees it: two
fmode           equ     0x5C74          ; rb_fetch's A

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
stack           equ     LOWBUF          ; and the stack under that, 64 bytes
LOWSTACK        equ     stack - 64     ; of it down to here

; 128 BASIC's own variables and the printer buffer at 5B00 are nothing to the
; 48K ROM the game runs with, and BASIC is gone: a page of RAM for a table
; that only needs to be on a page of its own, copied there by start.

REVTAB          equ     0x5B00

frontlist       equ     LOWBUF                      ; five bytes an entry, as
roomids         equ     frontlist + MAXFRONT * 5    ; frontrec writes them
flbuf           equ     roomids + 60                ; thirty ids, then states
rqq             equ     flbuf + FLAME_BYTES         ; one frame of a flame
rqs             equ     rqq + 4 * RQMAX             ; row, column, band, wide
cvbuf           equ     rqs + 4 * RQSMAX
dirtyq          equ     cvbuf + CANVAS_W            ; col, top, width, height
belowrow        equ     dirtyq + 4 * DIRTYMAX
aboverow        equ     belowrow + 20               ; the ceiling: the bottom
flstate         equ     aboverow + 20               ; row of the room above
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
