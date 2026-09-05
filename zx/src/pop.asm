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

                include "assets.inc"

SCREEN          equ     16384
BUFW            equ     8               ; widest sprite plus the shift byte
FRAME_WAIT      equ     3               ; 50Hz frames per game frame
BLOCK_PX        equ     28
TILE_GROUND     equ     TILE_FLOOR | TILE_SOLID   ; anything but space
STEP_OFF_FWD    equ     3               ; CTRL.S
STEP_OFF_BACK   equ     8
ACCEL_G         equ     3               ; SUBS.S GRAVITY
TERM_VEL        equ     33
PAGEPORT        equ     0x7FFD
; The room runs from block 0 to block 9, and a character on block b has his
; anchor between 28b+2 and 28b+29.  Only walls should stop him inside that --
; these are just to keep him on the map.
X_MIN           equ     2
X_MAX           equ     253

; ---------------------------------------------------------------- entry

start:          di
                ld      sp, stack
                im      1

                xor     a
                out     (254), a

                call    find_spr        ; which bank the tape put them in
                call    pick_banks      ; and free ones for the rest

                ld      a, (banktab + 1); frames past the first bank
                call    pageset
                ld      bc, SPR2_LEN
                ld      a, b
                or      c
                jr      z, nospr2
                ld      hl, stage_spr2
                ld      de, sprblob
                ldir
nospr2:
                call    page_art
                ld      hl, stage_art
                ld      de, room
                ld      bc, ART_LEN
                ldir

                call    build_fore

                ld      hl, (SIG_ART_AT); a bank that did not arrive leaves a
                ld      de, SIG_ART     ; black screen and nothing to go on
                or      a
                sbc     hl, de
                jp      nz, badload

                ld      hl, room        ; the screen and the working copy both
                ld      de, SCREEN      ; start out as the bare room
                ld      bc, 6912
                ldir
                ld      hl, room        ; the bitmap only: nothing ever writes
                ld      de, work        ; attributes through the working copy
                ld      bc, 6144
                ldir

                include "seqfix.inc"    ; turn sequence offsets into addresses

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
                ld      (seqid), a
                ld      (oldw), a       ; nothing to erase on the first pass
                ld      (pendchx), a
                ld      a, revtab / 256 ; the reversal table's page
                ld      (mrev1 + 1), a
                ld      (mrev2 + 1), a
                ld      hl, seqs + SQ_STAND
                ld      (seqptr), hl

                call    step_seq
                call    draw_prince
                call    page_art
                call    hide_behind
                call    show_rect
                call    keep_rect
                ei

; ---------------------------------------------------------------- main

main:           ld      b, FRAME_WAIT
mainwait:       halt
                djnz    mainwait

                call    page_art
                call    erase_prince
                call    input_step
                call    step_seq
                call    check_floor
                call    do_fall
                call    draw_prince
                call    page_art
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

; The foreground is a handful of rectangles, not six kilobytes: they travel
; on the tape and the mask is painted from them, with the art bank in.

build_fore:     ld      hl, foremask
                ld      de, foremask + 1
                ld      bc, 6143
                ld      (hl), 0
                ldir

                ld      hl, frontrect
                ld      a, (hl)
                inc     hl
                or      a
                ret     z
                ld      b, a
bfrect:         push    bc
                ld      a, (hl)
                ld      (frx0), a
                inc     hl
                ld      a, (hl)
                ld      (frxw), a
                inc     hl
                ld      a, (hl)
                ld      (fry), a
                inc     hl
                ld      a, (hl)
                inc     hl
                ld      b, a
                push    hl
bfrow:          push    bc
                ld      e, 0            ; the row's leftmost byte
                ld      a, (fry)
                call    scraddr
                ld      de, foremask - SCREEN
                add     hl, de
                ld      (frrow), hl
                ld      a, (frx0)
                ld      c, a
                ld      a, (frxw)
                ld      b, a
bfpix:          ld      a, c            ; which byte of the row
                srl     a
                srl     a
                srl     a
                ld      e, a
                ld      d, 0
                ld      hl, (frrow)
                add     hl, de
                ld      a, c            ; and which bit of it
                and     7
                inc     a
                ld      e, 0x80
bfbit:          dec     a
                jr      z, bfset
                srl     e
                jr      bfbit
bfset:          ld      a, (hl)
                or      e
                ld      (hl), a
                inc     c
                djnz    bfpix
                ld      hl, fry
                inc     (hl)
                pop     bc
                djnz    bfrow
                pop     hl
                pop     bc
                djnz    bfrect
                ret

frx0:           db      0
frxw:           db      0
fry:            db      0
frrow:          dw      0

; The tape loaded the sprites through the window at 0xC000, into whichever
; bank the loader had paged there -- bank 0 on a machine that has just been
; reset, but there is no need to take that on trust.  Page each bank in turn
; and look for the signature the sprites end with.

find_spr:       ld      c, 0
fsloop:         ld      a, c
                call    pageset
                ld      hl, (SPR_SIG_AT)
                ld      de, SIG_SPR
                or      a
                sbc     hl, de
                jr      z, fsfound
                inc     c
                ld      a, c
                cp      8
                jr      c, fsloop
                jr      badload
fsfound:        ld      a, c
                ld      (banktab), a
                ret

; The rest of the sprites and the room need banks of their own.  Take them
; from the uncontended ones, skipping whichever the tape happened to use.

pick_banks:     ld      hl, bankcand
                ld      de, banktab + 1
                ld      b, 2
pbloop:         ld      a, (hl)
                inc     hl
                ld      c, a
                ld      a, (banktab)
                cp      c               ; that is where the tape put the first
                jr      z, pbloop
                ld      a, c
                ld      (de), a
                inc     de
                djnz    pbloop
                ret

bankcand:       db      6, 4, 1

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
                push    bc              ; what the handler at 0x38 is
                ld      bc, PAGEPORT
                out     (c), a
                pop     bc              ; find_spr counts banks in C
                ret

; [0] where the tape left the first bank of sprites, [1] the rest of them,
; [2] the room and its mask.
banktab:        db      0, 0, 0
artbank         equ     banktab + 2

; ---------------------------------------------------------------- input
;
; Cursor left is key 5, row F7FE bit 4; cursor right is key 8, row EFFE
; bit 2.  Out: A = 0 none, 1 left, 2 right.

read_keys:      ld      bc, 0xF7FE
                in      a, (c)
                bit     4, a
                jr      nz, keyright
                ld      a, 1
                ret
keyright:       ld      bc, 0xEFFE
                in      a, (c)
                bit     2, a
                jr      nz, keynone
                ld      a, 2
                ret
keynone:        xor     a
                ret

; Cursor up is key 7, row EFFE bit 3.  Out: NZ if it is down.

read_up:        ld      bc, 0xEFFE
                in      a, (c)
                cpl
                and     8
                ret

; Caps shift is row FEFE bit 0.  POP calls it the button; held with a
; direction it turns a run into a single careful step.

read_shift:     ld      bc, 0xFEFE
                in      a, (c)
                cpl
                and     1
                ret

; Cursor down is key 6, the same half row, bit 4.

read_down:      ld      bc, 0xEFFE
                in      a, (c)
                cpl
                and     16
                ret

; Standing and running listen to the keys; turning, stopping and turning on
; the run play out to their end, as they do in the original.

; A run that has run out of floor or hit a wall skids to a halt.

input_step:     ld      a, (charact)
                cp      2               ; hanging: up climbs, down lets go
                jp      z, fromhang
                cp      6
                jp      z, fromhang
                cp      3               ; no steering in the air
                ret     z
                cp      4
                ret     z
                ld      a, (seqid)
                cp      ID_CROUCH
                jp      z, fromcrouch
                ld      a, (blocked)
                or      a
                jp      z, inputkeys
                ld      a, (seqid)
                cp      ID_RUNCYC
                jp      z, tostopnow
                cp      ID_STARTRUN
                jp      nz, inputkeys
tostopnow:      ld      hl, seqs + SQ_RUNSTOP
                jp      setseq

fromhang:       call    read_up
                jr      z, fhdrop
                ld      hl, seqs + SQ_CLIMBUP
                jp      setseq
fhdrop:         call    read_down
                ret     z
                ld      hl, seqs + SQ_HANGDROP
                jp      setseq

; CTRL.S stands him up the moment down is let go, which is why a short fall
; leaves him crouched for a breath and then upright without being asked.

fromcrouch:     call    read_down
                ret     nz
                ld      hl, seqs + SQ_STANDUP
                jp      setseq

inputkeys:      call    read_keys
                ld      b, a
                ld      a, (seqid)
                cp      ID_STAND
                jp      z, fromstand
                cp      ID_STARTRUN
                jp      z, fromrun
                cp      ID_RUNCYC
                jp      z, fromrun
                ret

; Down, standing.  Facing a cliff and close to it, he steps off it; with his
; BACK to one and close to that, he lowers himself over it; otherwise he
; crouches.  Straight out of CTRL.S, and the way round it goes matters: you
; climb down backwards, holding the ledge you were standing on.

fromstand:      push    bc
                call    read_down
                pop     bc
                jr      z, fsnodown

                call    front_flags
                and     TILE_GROUND
                jr      nz, fdback      ; no cliff in front of him
                call    get_dist
                cp      STEP_OFF_FWD
                jr      nc, fdback      ; not close enough to the edge
                ld      a, 5            ; step off it; the fall follows
                jp      move_by

fdback:         call    behind_flags
                and     TILE_GROUND
                jr      nz, tostoop     ; no cliff behind him either
                call    get_dist
                cp      STEP_OFF_BACK
                jr      c, tostoop      ; not backed up to the edge
                call    under_flags     ; and there has to be a ledge to hold
                and     TILE_FLOOR
                jr      z, tostoop
                call    get_dist        ; line him up with it
                sub     9
                call    move_by
                ld      hl, seqs + SQ_CLIMBDOWN
                jp      setseq

tostoop:        ld      hl, seqs + SQ_STOOP
                jp      setseq

fsnodown:       ld      a, b
                or      a
                ret     z
                dec     a               ; 0 = left, 1 = right
                ld      c, a
                ld      a, (facing)
                cp      c
                jr      z, facingit
                ld      hl, seqs + SQ_TURN
                jp      setseq

facingit:       push    bc
                call    read_shift
                pop     bc
                jp      z, tostartrun
                ; fall through: a careful step

; GETFWDDIST in COLL.S.  A wall or a drop ahead means he steps up to the edge
; of his own block and no further; anything he can walk on means a full step.
; POP keeps fourteen sequences so the step always ends where it should.

do_step:        call    front_flags
                ld      c, a
                and     TILE_SOLID
                jr      nz, stepedge
                ld      a, c
                and     TILE_FLOOR
                jr      z, stepedge
                ld      a, 14
                jr      stepgo
stepedge:       call    get_dist
stepgo:         or      a
                ret     z               ; already there: nothing to step
                dec     a
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, steptab
                add     hl, de
                ld      a, (hl)
                inc     hl
                ld      h, (hl)
                ld      l, a
                jp      setseq
; No point starting a run into a wall or off the edge, or he twitches on the
; spot: stand still instead.

tostartrun:     ld      a, (charx)
                ld      b, a
                ld      a, (facing)
                or      a
                ld      a, b
                jr      nz, trright
                sub     BLOCK_PX
                jr      trtest
trright:        add     a, BLOCK_PX
trtest:         call    tile_flags
                bit     1, a
                ret     nz
                bit     0, a
                ret     z
                ld      hl, seqs + SQ_STARTRUN
                jp      setseq

fromrun:        ld      a, b
                or      a
                jr      z, torunstop
                dec     a
                ld      c, a
                ld      a, (facing)
                cp      c
                ret     z
                ld      hl, seqs + SQ_RUNTURN
                jp      setseq
torunstop:      ld      hl, seqs + SQ_RUNSTOP
setseq:         ld      (seqptr), hl
                xor     a               ; a new sequence starts from a stop
                ld      (pendchx), a
                ret

; ---------------------------------------------------------------- sequence
;
; Read byte code until a frame comes out, which is this game frame's picture.
;
; The chx written beside a frame in SEQTABLE.S belongs to the step out of it,
; not into it: the interpreter stops on the frame byte and only moves on the
; next pass.  That matters at an about face, where the move and the turn have
; to happen together for the anchor swapping ends to cancel out.

step_seq:       ld      a, (pendchx)
                or      a
                jr      z, seqnopend
                call    move_by
                xor     a
                ld      (pendchx), a
seqnopend:      ld      hl, (seqptr)
seqloop:        ld      a, (hl)
                inc     hl
                cp      SEQ_GOTO
                jr      nz, seqnogoto
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ex      de, hl
                jr      seqloop
seqnogoto:      cp      SEQ_FACE
                jr      nz, seqnoface
                push    hl
                ld      a, (facing)
                xor     1
                ld      (facing), a
                pop     hl
                jr      seqloop
seqnoface:      cp      SEQ_CHY
                jr      nz, seqnochy
                ld      a, (hl)
                inc     hl
                push    hl
                ld      hl, chary
                add     a, (hl)
                ld      (hl), a
                pop     hl
                jr      seqloop
seqnochy:       cp      SEQ_ACT
                jr      nz, seqnoact
                ld      a, (hl)
                inc     hl
                ld      (charact), a
                jr      seqloop
seqnoact:       cp      SEQ_UP
                jr      nz, seqnoup
                push    hl
                ld      hl, blocky
                dec     (hl)
                call    set_row
                pop     hl
                jr      seqloop
seqnoup:        cp      SEQ_DOWN
                jr      nz, seqnodown
                push    hl
                ld      hl, blocky
                inc     (hl)
                call    set_row
                pop     hl
                jr      seqloop
seqnodown:      cp      SEQ_SETFALL
                jr      nz, seqnosetf
                inc     hl              ; the X velocity, which we do not use
                ld      a, (hl)
                inc     hl
                ld      (yvel), a
                jr      seqloop
seqnosetf:      cp      SEQ_CHX
                jr      nz, seqnoid
                ld      a, (hl)
                inc     hl
                push    hl
                call    move_by
                pop     hl
                jr      seqloop
seqnoid:        cp      SEQ_ID
                jr      nz, seqframe
                ld      a, (hl)
                inc     hl
                ld      (seqid), a
                jr      seqloop
seqframe:       ld      (frame), a
                ld      a, (hl)
                inc     hl
                ld      (pendchx), a
                ld      (seqptr), hl
                ret

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
; The prince may only stand where there is floor, and never inside a wall.
; blockof turns a screen pixel into a block column and tiles says what is in
; it, both built offline from the room's BLUETYPE.

; A step that runs into something does not simply fail: he goes as far as
; he can and stops there, so he ends up against the wall rather than a
; whole stride short of it.

movestore:      ld      c, l            ; C = where he would end up
                ld      a, l
                ld      (wanted), a
movetry:        ld      a, c
                call    check_spot
                jr      nz, moveok
                ld      a, (charx)      ; back off a pixel towards himself
                cp      c
                jr      z, moveblocked
                jr      c, movedec
                inc     c
                jr      movetry
movedec:        dec     c
                jr      movetry
moveok:         ld      a, c
                ld      (charx), a
                ld      hl, wanted      ; a shortened step still counts as
                cp      (hl)            ; running into something
                jr      nz, moveblocked
                xor     a
                ld      (blocked), a
                ret
moveblocked:    ld      a, 1
                ld      (blocked), a
                ret

; A = a screen x.  Out: NZ if he may stand there.
;
; Only a wall stops him.  Running out of floor does not: that is what makes
; him fall, and check_floor deals with it.  A wall stands at the back of its
; own tile, and the block lookup already accounts for the perspective, so no
; fudge is needed here -- he stops with the brick drawn over his shoulder.

check_spot:     call    tile_flags
                and     TILE_SOLID
                jr      nz, spotno
                ld      a, 1            ; `and` above left the flags saying
                or      a               ; "wall", so say "clear" for the
                ret                     ; caller's jr nz
spotno:         xor     a
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

; Out: A = the flags of the tile he is standing on.

under_flags:    ld      a, (charx)
                jr      tile_flags

; Out: A = the flags of the block one along, the way he faces or the way he
; came -- GETINFRONT and GETBEHIND.  Off the map reads as space, which is
; what it looks like.

front_flags:    ld      a, (facing)
                or      a
                jr      z, ffback
fffwd:          ld      a, (charx)
                add     a, BLOCK_PX
                jr      c, ffnone
                jr      tile_flags
ffback:         ld      a, (charx)
                sub     BLOCK_PX
                jr      c, ffnone
                jr      tile_flags
ffnone:         xor     a
                ret

behind_flags:   ld      a, (facing)
                or      a
                jr      z, fffwd
                jr      ffback

; GETDIST: how far he is from the edge of his own block, in POP's units of
; two pixels, measured the way he faces.  Standing in the middle of a block
; is offset 7, so seven units to the edge behind and six to the one ahead.

get_dist:       ld      a, (charx)
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
                call    under_flags
                and     TILE_GROUND
                ret     nz
                ld      hl, blocky
                inc     (hl)
                call    set_row
                ld      a, 3
                ld      (charact), a
                xor     a
                ld      (yvel), a
                ld      hl, seqs + SQ_STEPFALL
                ld      (seqptr), hl
                xor     a
                ld      (pendchx), a
                ret

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
                and     TILE_GROUND
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
                ld      (pendchx), a
                ld      a, 1
                ld      (charact), a
                ld      hl, seqs + SQ_SOFTLAND
                ld      (seqptr), hl
                ret

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
                call    page_frame

; The anchor is the leading edge, so the offset differs with facing and is
; kept with the sprite rather than worked out here.

                ld      a, (charx)
                ld      b, a
                ld      a, (curoff)
                add     a, b
                ld      b, a
                and     7
                ld      (curshift), a
                ld      a, b
                rra
                rra
                rra
                and     31
                ld      (newcol), a

                ld      a, (chary)      ; top row = CharY - height + 1
                ld      b, a
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

                ld      b, a
                ld      hl, (curdat)
                ld      a, (newtop)
                ld      (rowy), a

drawrow:        push    bc
                call    build_row       ; HL walks over the source row
                push    hl
                ld      a, (rowy)
                cp      192
                jr      nc, drawskip
                ld      c, a
                ld      a, (newcol)
                ld      e, a
                ld      a, c
                call    scraddr
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

; Put the foreground back over the prince.  foremask has a bit per pixel,
; set where a front piece covers, and it sits at the same offsets as the
; screen, so one lookup gives both the mask and the room byte to restore.

hide_behind:    ld      a, (newh)
                ld      b, a
                ld      a, (newtop)
                ld      (rowy), a
hiderow:        push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, hideskip
                ld      a, (newcol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      (hideadr), hl
                ld      a, (neww)
                ld      (hidecnt), a
hidecol:        ld      hl, (hideadr)
                ld      de, foremask - SCREEN
                add     hl, de
                ld      a, (hl)         ; which pixels here are covered
                or      a
                jr      z, hidenext
                ld      (hidebits), a
                ld      hl, (hideadr)
                ld      d, h
                ld      e, l
                ld      bc, room - SCREEN
                add     hl, bc          ; HL = room
                ex      de, hl
                ld      bc, work - SCREEN
                add     hl, bc
                ex      de, hl          ; HL = room, DE = working copy
                ld      a, (hidebits)
                ld      c, a
                ld      a, (hl)
                and     c               ; the foreground's own pixels
                ld      b, a
                ld      a, c
                cpl
                ex      de, hl
                and     (hl)            ; what the prince may keep
                or      b
                ld      (hl), a
hidenext:       ld      hl, hideadr
                inc     (hl)
                ld      hl, hidecnt
                dec     (hl)
                jr      nz, hidecol
hideskip:       ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    hiderow
                ret

; ---------------------------------------------------------------- erase
;
; Put the room back over where the sprite was, in the working copy.

erase_prince:   ld      a, (oldw)
                or      a
                ret     z
                ld      a, (oldh)
                ld      b, a
                ld      a, (oldtop)
                ld      (rowy), a
eraserow:       push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, eraseskip
                ld      a, (oldcol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      d, h
                ld      e, l
                ld      bc, room - SCREEN
                add     hl, bc          ; HL = room
                ex      de, hl
                ld      bc, work - SCREEN
                add     hl, bc
                ex      de, hl          ; HL = room, DE = working copy
                ld      a, (oldw)
                ld      c, a
                ld      b, 0
                ldir
eraseskip:      ld      hl, rowy
                inc     (hl)
                pop     bc
                djnz    eraserow
                ret

; ---------------------------------------------------------------- show
;
; Copy the rectangle covering both the old and the new sprite from the
; working copy to the screen.  This is the only moment the screen changes.

show_rect:      ld      a, (oldw)
                or      a
                jr      nz, showunion
                ld      a, (newcol)     ; nothing old: just the new box
                ld      (shcol), a
                ld      a, (neww)
                ld      (shw), a
                ld      a, (newtop)
                ld      (shtop), a
                ld      a, (newh)
                ld      (shh), a
                jr      showgo

showunion:      ld      a, (oldcol)     ; leftmost of the two
                ld      b, a
                ld      a, (newcol)
                cp      b
                jr      c, showcol
                ld      a, b
showcol:        ld      (shcol), a

                ld      a, (oldcol)     ; rightmost end of the two
                ld      b, a
                ld      a, (oldw)
                add     a, b
                ld      c, a
                ld      a, (newcol)
                ld      b, a
                ld      a, (neww)
                add     a, b
                cp      c
                jr      nc, showend
                ld      a, c
showend:        ld      b, a
                ld      a, (shcol)
                neg
                add     a, b
                ld      (shw), a

                ld      a, (oldtop)     ; topmost of the two
                ld      b, a
                ld      a, (newtop)
                cp      b
                jr      c, showtop
                ld      a, b
showtop:        ld      (shtop), a

                ld      a, (oldtop)     ; lowest bottom of the two
                ld      b, a
                ld      a, (oldh)
                add     a, b
                ld      c, a
                ld      a, (newtop)
                ld      b, a
                ld      a, (newh)
                add     a, b
                cp      c
                jr      nc, showbot
                ld      a, c
showbot:        ld      b, a
                ld      a, (shtop)
                neg
                add     a, b
                ld      (shh), a

showgo:         ld      a, (shh)
                or      a
                ret     z
                ld      b, a
                ld      a, (shtop)
                ld      (rowy), a
showrow:        push    bc
                ld      a, (rowy)
                cp      192
                jr      nc, showskip
                ld      a, (shcol)
                ld      e, a
                ld      a, (rowy)
                call    scraddr
                ld      d, h
                ld      e, l            ; DE = screen
                ld      bc, work - SCREEN
                add     hl, bc          ; HL = working copy
                ld      a, (shw)
                ld      c, a
                ld      b, 0
                ldir
showskip:       ld      hl, rowy
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

scraddr:        ld      b, a
                and     %00000111
                ld      h, a
                ld      a, b
                rrca
                rrca
                rrca
                and     %00011000
                or      h
                or      %01000000
                ld      h, a
                ld      a, b
                and     %00111000
                rlca
                rlca
                add     a, e
                ld      l, a
                ret

; ---------------------------------------------------------------- data

steptab:        dw      seqs + SQ_STEP1,  seqs + SQ_STEP2
                dw      seqs + SQ_STEP3,  seqs + SQ_STEP4
                dw      seqs + SQ_STEP5,  seqs + SQ_STEP6
                dw      seqs + SQ_STEP7,  seqs + SQ_STEP8
                dw      seqs + SQ_STEP9,  seqs + SQ_STEP10
                dw      seqs + SQ_STEP11, seqs + SQ_STEP12
                dw      seqs + SQ_STEP13, seqs + SQ_STEP14


charx:          db      0
chary:          db      0
facing:         db      0               ; 0 left, 1 right
frame:          db      0
seqid:          db      0
seqptr:         dw      0
pendchx:        db      0
blocked:        db      0
blocky:         db      0
tilerow:        dw      0
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

hideadr:        dw      0
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
tiles:          incbin  "tiles.bin"
floory:         incbin  "floory.bin"
blockof:        incbin  "blockof.bin"
distof:         incbin  "distof.bin"
frontrect:      incbin  "frontrect.bin"
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

work            equ     codeend

stage_art:      incbin  "bank_art.bin"
stage_end:
ART_LEN         equ     stage_end - stage_art

stage_spr2:     incbin  "bank_spr2.bin"         ; frames past the first bank
spr2_end:
SPR2_LEN        equ     spr2_end - stage_spr2

                ds      0xC000 - $              ; the sprites load in a bank
stage_spr:      incbin  "bank_spr.bin"
spr_end:
SPR_SIG_AT      equ     spr_end - 2

                end     start
