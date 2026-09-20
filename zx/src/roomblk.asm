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
                cp      BG_SWORD
                jp      z, mtsword
                cp      BG_FLASK
                jp      z, mtflask
                cp      BG_TORCH
                jr      nz, mtnext
                ld      a, (mtcol)
                cp      9               ; the last column has no flame
                jr      nc, mtnext

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

; ADDTORCHES puts the swords on the list as well, and TRIGSWORD starts each
; one at a random point of its wait so two never gleam together.  HL is
; still at its byte of roomids, which is the block's own index.

mtsword:        ld      de, roomids
                or      a
                sbc     hl, de
                ld      a, l
                ld      (trloc), a
                ld      a, (roomnum)
                ld      (trscrn), a
                call    trobat
                ld      a, r
                and     0x1f
                ld      (trobst), a
                call    trobsave
                ld      a, 1
                ld      (trdirec), a
                call    addtrob
                jr      mtnext

; TRIGFLASK: a flask on the list, its bubbles from a random frame.

mtflask:        ld      de, roomids
                or      a
                sbc     hl, de
                ld      a, l
                ld      (trloc), a
                ld      a, (roomnum)
                ld      (trscrn), a
                call    trobat
                ld      a, r
                and     7
                ld      c, a
                ld      a, (trobst)
                or      c
                ld      (trobst), a
                call    trobsave
                ld      a, 1
                ld      (trdirec), a
                call    addtrob
                jr      mtnext

mtrow:          db      0
mtcol:          db      0
mtal:           db      0

; And on to the screen, wherever the view has put them.


CPKEEP          equ     64 + (CANVAS_W * 192) % 32  ; cleared by hand

compose:        xor     a               ; no front pieces noted yet
                ld      (nfront), a
                ld      (recfront), a
                inc     a
                ld      (frontok), a
                call    page_pixels     ; a clean canvas first: pushed, a
                ld      (cpsp + 1), sp  ; quarter of the time an LDIR takes.
                ld      sp, CANVAS + CANVAS_W * 192     ; The interrupt may
                ld      hl, 0           ; come while the stack is the canvas:
                ld      b, (CANVAS_W * 192 - CPKEEP) / 32   ; it pushes below
cpfill:         rept    16              ; it, in this bank -- what it pages in
                push    hl              ; for the sound is this one -- and
                endm                    ; what it leaves is cleared in turn;
                djnz    cpfill          ; the last CPKEEP bytes go by hand,
cpsp:           ld      sp, 0           ; so it never reaches under the canvas
                ld      hl, CANVAS
                ld      de, CANVAS + 1
                ld      bc, CPKEEP - 1
                ld      (hl), 0
                ldir

                call    read_room
                call    read_edges

                ld      a, 2
                ld      (blockrow), a
comprow:        ld      a, (blockrow)
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, blockbot
                add     hl, de
                ld      a, (hl)
                ld      (dy), a
                sub     3
                ld      (ay), a

                ld      a, (blockrow)   ; PREV: what the room to the left
                add     a, a            ; hangs over into this one
                ld      l, a
                ld      h, 0
                ld      de, prevblk
                add     hl, de
                ld      a, (hl)
                ld      (preced), a
                inc     hl
                ld      a, (hl)
                ld      (spreced), a
                xor     a
                ld      (blockcol), a
                ld      (xco), a
compcol:        call    setblock
                call    draw_c
                call    draw_mc
                call    draw_b
                call    draw_mb
                call    draw_d
                call    draw_md
                call    draw_a
                call    draw_front
                call    slicerfront

                ld      a, (objid)      ; on to the next block
                ld      (preced), a
                ld      a, (state)
                ld      (spreced), a
                ld      a, (xco)
                add     a, 4
                ld      (xco), a
                ld      hl, blockcol
                inc     (hl)
                ld      a, (hl)
                cp      10
                jr      c, compcol

                ld      hl, blockrow
                ld      a, (hl)
                or      a
                jr      z, cproof
                dec     (hl)
                jr      comprow

; drawfrnt notes the whole rectangle of a front piece as what stands in front
; of him, since a dither he showed through is worse than a few pixels he does
; not.  A slicer's is the exception: with its jaws up the piece is the empty
; middle of the block and nothing else but the plinth at its foot, and sixty
; rows of rectangle rubbed a slab out of him as he walked through an open
; one.  So the entry it has just made is cut back to the rows the picture at
; rest actually has something on -- slicerfrh, out of the piece tables.

slicerfront:    ld      a, (objid)
                cp      BG_SLICER
                ret     nz
                ld      a, (nfront)
                or      a
                ret     z
                dec     a               ; five bytes to an entry
                ld      l, a
                ld      h, 0
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de
                ld      de, frontlist
                add     hl, de
                ld      a, (xco)        ; and it is this block's, not one that
                cp      (hl)            ; was noted and this one lost
                ret     nz
                ld      de, 4
                add     hl, de
                call    page_bg
                ld      a, (bgtables + T_SLICERFRH)
                ld      (hl), a
                ret

; The last pass of SURE: the bottom row of the room above, D sections alone,
; with Dy at 2 and Ay at -1, so what shows along the top of the screen is the
; underside of its floor -- the ceiling.  The blocks below it are this room's
; own top row, and column zero's comes from the room to the left, which is
; what getbelow would have handed back with scrnBelow pretending to be this
; room.  PRECED starts empty; spreced POP leaves as the last block left it.

cproof:         ld      a, 2
                ld      (dy), a
                ld      a, 0xff
                ld      (ay), a
                xor     a
                ld      (preced), a
                ld      (blockcol), a
                ld      (xco), a

cpcloop:        ld      a, (blockcol)   ; the ceiling block itself
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, aboverow
                add     hl, de
                ld      a, (hl)
                ld      (objid), a
                inc     hl
                ld      a, (hl)
                ld      (state), a

                ld      a, (blockcol)   ; and the one below and to its left
                or      a
                jr      z, cpcprev
                dec     a
                ld      c, a
                ld      b, 0
                call    blockat
                ld      (below), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (sbelow), a
                jr      cpcdraw
cpcprev:        ld      a, (prevblk)
                ld      (below), a
                ld      a, (prevblk + 1)
                ld      (sbelow), a

cpcdraw:        call    draw_c          ; RedDSure: no A section, and nothing
                call    draw_mc         ; movable but the C and D ones
                call    draw_b
                call    draw_d
                call    draw_md
                call    draw_front

                ld      a, (objid)      ; on to the next block
                ld      (preced), a
                ld      a, (state)
                ld      (spreced), a
                ld      a, (xco)
                add     a, 4
                ld      (xco), a
                ld      hl, blockcol
                inc     (hl)
                ld      a, (hl)
                cp      10
                jr      c, cpcloop
                ret

; The block in hand, and the one below and to its left.  getbelow stores the
; row below starting one along, so the C section sees the block down-left.


read_edges:     call    readlinks
                call    page_bg

                ld      de, prevblk     ; blocks 9, 19 and 29 to the left
                ld      a, (links)
                or      a
                jr      z, repnone
                ld      c, 9
                call    edgeblk
                ld      a, (links)
                ld      c, 19
                call    edgeblk
                ld      a, (links)
                ld      c, 29
                call    edgeblk
                jr      rebelow
repnone:        ld      b, 3
repnl:          ld      a, BG_BLOCK
                ld      (de), a
                inc     de
                xor     a
                ld      (de), a
                inc     de
                djnz    repnl

rebelow:        ld      de, belowrow + 2
                ld      a, (links + 3)
                or      a
                jr      z, rebnone
                xor     a
                ld      (edgecol), a
rebl:           ld      a, (edgecol)
                ld      c, a
                ld      a, (links + 3)
                call    edgeblk
                ld      hl, edgecol
                inc     (hl)
                ld      a, (hl)
                cp      9               ; nine of them: the rightmost is the
                jr      c, rebl         ; next room's business
                jr      rebcorn
rebnone:        ld      b, 9
rebnl:          ld      a, BG_FLOOR     ; nothing to fall into
                ld      (de), a
                inc     de
                xor     a
                ld      (de), a
                inc     de
                djnz    rebnl

rebcorn:        ld      de, belowrow    ; and the corner, down and to the left
                ld      a, (links + 3)
                or      a
                jr      z, rebcnone
                call    roomleft
                or      a
                jr      z, rebcnone
                ld      c, 9
                call    edgeblk
                jr      reabove
rebcnone:       ld      a, BG_BLOCK
                ld      (de), a
                inc     de
                xor     a
                ld      (de), a

; And the ceiling: the bottom row of the room above, blocks 20 to 29, whose
; D sections hang into the top of this screen.  Where there is no room up
; there POP lays a row of floorpieces, so the world has a lid wherever it
; ends.

reabove:        ld      de, aboverow
                ld      a, (links + 2)
                or      a
                jr      z, reanone
                ld      a, 20
                ld      (edgecol), a
reabl:          ld      a, (edgecol)
                ld      c, a
                ld      a, (links + 2)
                call    edgeblk
                ld      hl, edgecol
                inc     (hl)
                ld      a, (hl)
                cp      30
                jr      c, reabl
                jp      page_art
reanone:        ld      b, 10
reanl:          ld      a, BG_FLOOR     ; nothing above is a lid all the same
                ld      (de), a
                inc     de
                xor     a
                ld      (de), a
                inc     de
                djnz    reanl
                jp      page_art

; A = a room, C = one of its thirty blocks, DE = where the id and its state
; go.  The background bank has to be in.

edgeblk:        push    de
                dec     a
                ld      l, a
                ld      h, 0
                add     hl, hl          ; thirty bytes to a room
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; thirty two
                or      a
                sbc     hl, de          ; less two
                ld      e, c
                ld      d, 0
                add     hl, de
                ld      de, level
                add     hl, de
                ld      a, (hl)
                and     0x1f
                ld      b, a
                ld      de, 720         ; the states follow the ids
                add     hl, de
                ld      c, (hl)
                ld      a, b
                call    subplate
                pop     de
                ld      (de), a
                inc     de
                ld      a, c
                ld      (de), a
                inc     de
                ret

; A = a room.  Out: A = the room to its left.  The bank has to be in.

roomleft:       push    de              ; the caller is holding a destination
                dec     a
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl          ; four bytes to a room
                ld      de, level + 1952
                add     hl, de
                ld      a, (hl)
                pop     de
                ret

edgecol:        db      0

read_room:      call    rr_copy
                ld      b, 30           ; and each of them through getobjid1
                ld      hl, roomids
rrsub:          push    bc
                push    hl
                ld      a, (hl)
                and     0x1f            ; getobjid1 works on the id alone, and
                                        ; a blueprint byte carries three bits
                                        ; of modifier above it -- unmasked, no
                                        ; plate was ever substituted here, so a
                                        ; room entered with one held down drew
                                        ; it standing up
                ld      de, 30
                add     hl, de
                ld      c, (hl)
                call    subplate
                pop     hl
                ld      (hl), a
                push    hl
                ld      de, 30
                add     hl, de
                ld      (hl), c
                pop     hl
                inc     hl
                pop     bc
                djnz    rrsub
                ret

rr_copy:        call    page_bg
                ld      a, (roomnum)
                dec     a
                ld      l, a            ; thirty bytes to a room
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l            ; two
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; thirty two
                or      a
                sbc     hl, de          ; less two
                ld      de, level
                add     hl, de
                ld      de, roomids
                ld      bc, 30
                push    hl
                ldir
                pop     hl
                ld      de, 720
                add     hl, de
                ld      de, roomids + 30
                ld      bc, 30
                ldir
                ld      hl, roomids     ; spikes anywhere in it?  checkspikes
                ld      b, 30           ; and checkimpale look no further when
rsspk:          ld      a, (hl)         ; there are none
                and     0x1f
                cp      BG_SPIKES
                jr      z, rsspk1       ; A = BG_SPIKES: not nought
                inc     hl
                djnz    rsspk
                xor     a
rsspk1:         ld      (spkroom), a
                ret

; ---------------------------------------------------------------- storage


convert:        xor     a
                ld      (cvrow), a
                ld      a, 192
                ld      (cvleft), a
cvline:         call    page_pixels
                ld      a, (cvrow)
                call    canvasrow
                ld      de, cvbuf
                ld      bc, CANVAS_W
                ldir

                call    page_art
                ld      a, (cvrow)
                call    mul35
                ld      de, room
                add     hl, de
                ex      de, hl          ; DE = the room's row
                ld      hl, cvbuf
                ld      b, 5            ; forty in, thirty five out
cvgroup:        push    bc
                call    cv8to7
                pop     bc
                djnz    cvgroup

                ld      hl, cvrow
                inc     (hl)
                ld      hl, cvleft
                dec     (hl)
                jr      nz, cvline
                ret

; A room, start to finish: the blocks laid into the canvas, then repacked.

newroom:        ld      hl, CANVAS      ; the whole canvas: see rbwipe
                ld      (cvbasep), hl
                ld      a, (pristok)    ; the level as it began is in the
                or      a               ; canvas, which the room is about to
                jr      z, nrp1         ; take: into the working copy, which
                call    page_pixels     ; the repaint after takes in turn
                ld      hl, PRISTINE
                ld      de, work        ; (the working copy)
                ld      bc, PRISTLEN
                ldir
nrp1:           call    compose
                call    convert
                call    build_fore
                call    floormasks
                call    maketorches
                ld      a, BANK_CVS     ; and this code put by again, in the
                call    pageset         ; canvas bank past the slice: the
                ld      hl, roomblk     ; canvas was all the room's while it
                ld      de, RBAT1       ; was built, and roomrest brings it
                ld      bc, RB1LEN      ; back from there for the next
                ldir
                ld      a, (pristok)    ; and the level as it began back
                or      a
                jr      z, nrp2
                ld      hl, work
                ld      de, PRISTINE
                ld      bc, PRISTLEN
                ldir
nrp2:           jp      page_art

; The level as it begins, into the canvas past the room's code (PRISTINE),
; for a death to begin it again from: LoadLevelX in RESTART.  lvback puts it
; back.  A page at a time through imgbuf, the two being in different banks.

lvkeep:         ld      a, 1
                ld      (pristok), a
                ld      a, (maxkidstr)  ; and origstrength
                ld      (origstr), a
                xor     a               ; a level begins short of its
                ld      (milestone), a  ; milestone
                ld      hl, level
                ld      de, PRISTINE
                ld      bc, BANK_BG * 256 + BANK_CVS
                jr      lvcopy
lvback:         ld      hl, PRISTINE
                ld      de, level
                ld      bc, BANK_CVS * 256 + BANK_BG
lvcopy:         ld      a, 9            ; the blueprint: 2304 bytes
lvc1:           push    af
                ld      a, b
                call    pageset
                push    bc
                push    de
                ld      de, imgbuf
                ld      bc, 256
                ldir
                pop     de
                pop     bc
                ld      a, c
                call    pageset
                push    bc
                push    hl
                ld      hl, imgbuf
                ld      bc, 256
                ldir
                pop     hl
                pop     bc
                pop     af
                dec     a
                jr      nz, lvc1
                jp      page_art

cvrow:          db      0
cvleft:         db      0

build_fore:     call    page_art
                ld      hl, foreband
                ld      de, foreband + 1
                ld      bc, 191
                ld      (hl), 0xff
                ldir

                ld      a, (nfront)
                or      a
                ret     z
                ld      (fleft), a
                ld      hl, frontlist
                ld      (fptr), hl
bfmark:         call    frontrect       ; B = top row, C = how many
bfmark1:        ld      a, b
                cp      192
                jr      nc, bfmark2
                ld      l, a
                ld      h, 0
                ld      de, foreband
                add     hl, de
                ld      (hl), 0
bfmark2:        inc     b
                dec     c
                jr      nz, bfmark1
                ld      hl, fleft
                dec     (hl)
                jr      nz, bfmark

                ld      hl, foreband    ; number the rows that are marked
                ld      b, 192
                ld      c, 0
bfnum:          ld      a, (hl)
                inc     a
                jr      z, bfnum1
                ld      a, c            ; as many as the mask has room for:
                cp      FORE_ROWS       ; any past those go without
                ld      a, 0xff
                jr      nc, bfnum2
                ld      a, c
                inc     c
bfnum2:         ld      (hl), a
bfnum1:         inc     hl
                djnz    bfnum

                ld      a, c            ; and clear that much of the mask
                or      a
                ret     z
                call    mul35
                call    zerofill


                ld      a, (nfront)     ; then paint the rectangles into it
                ld      (fleft), a
                ld      hl, frontlist
                ld      (fptr), hl
bfpaint:        call    frontrect
                ld      a, b
                ld      (frow), a
                ld      a, c
                ld      (frows), a
                ld      hl, (fx0)       ; the byte it starts in
                srl     h
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      a, l
                ld      (fcol), a
                ld      a, (fx0)        ; and the bits of that byte
                and     7
                ld      b, a
                ld      a, 0xff
                inc     b
bfsh1:          dec     b
                jr      z, bfsh2
                srl     a
                jr      bfsh1
bfsh2:          ld      (fmask0), a     ; the first byte's mask

                ld      hl, (fx0)       ; the last pixel of it, which for a
                ld      a, (fpx)        ; piece at the right hand end of the
                ld      e, a            ; room does not fit in eight bits
                ld      d, 0
                add     hl, de
                dec     hl
                ld      a, l
                and     7               ; bits down to that one stay
                ld      d, a
                ld      a, 7
                sub     d
                ld      d, a
                ld      a, 0xff
                inc     d
bfsh3:          dec     d
                jr      z, bfsh4
                add     a, a
                jr      bfsh3
bfsh4:          ld      (fmask1), a     ; the last byte's mask
                srl     h               ; and how many bytes on it is
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      a, (fcol)
                ld      b, a
                ld      a, l
                sub     b
                ld      (fspan), a

; All of that is the rectangle's and the same on every row of it: worked
; out once, and each row only finds its place in the mask and paints.

                ld      hl, 0           ; no row of it placed yet
                ld      (fmrow), hl
bfrow:          ld      a, (frow)
                cp      192
                jr      nc, bfrownext
                ld      hl, (fmrow)     ; the row after one placed: every
                ld      a, h            ; row of a rectangle is marked, so
                or      l               ; it is the next row of the mask
                jr      z, bfplace
                ld      de, ROOM_BYTES
                add     hl, de
                ld      de, foremask + FORE_ROWS * ROOM_BYTES
                or      a               ; unless that is past the rows the
                sbc     hl, de          ; mask has room for
                add     hl, de
                jr      c, bfat
                jr      bfrownext
bfplace:        ld      a, (frow)
                ld      l, a
                ld      h, 0
                ld      de, foreband
                add     hl, de
                ld      a, (hl)
                inc     a
                jr      z, bfrownext
                dec     a
                call    mul35
                ld      de, foremask
                add     hl, de
                ld      a, (fcol)
                ld      e, a
                ld      d, 0
                add     hl, de
bfat:           ld      (fmrow), hl
                ld      a, (fmask1)
                ld      d, a
                ld      a, (fmask0)
                ld      c, a
                ld      a, (fspan)
                or      a
                jr      nz, bfwide
                ld      a, c            ; all in the one byte
                and     d
                or      (hl)
                ld      (hl), a
                jr      bfrownext
bfwide:         ld      b, a            ; the first, then the whole ones
                ld      a, c
                or      (hl)
                ld      (hl), a
                inc     hl
                dec     b
                jr      z, bflast
bfmid:          ld      (hl), 0xff
                inc     hl
                djnz    bfmid
bflast:         ld      a, d
                or      (hl)
                ld      (hl), a
bfrownext:      ld      hl, frow
                inc     (hl)
                ld      hl, frows
                dec     (hl)
                jr      nz, bfrow
                ld      hl, fleft
                dec     (hl)
                jp      nz, bfpaint
                ret

; HL bytes of the foreground mask from its start made nought, eight to a
; round and the few over them first.

zerofill:       ld      a, l
                and     7
                ld      c, a            ; the few over eights
                srl     h
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l               ; HL = how many eights
                ex      de, hl
                ld      hl, foremask
                xor     a
                inc     c
                jr      zfodd1
zfodd:          ld      (hl), a
                inc     hl
zfodd1:         dec     c
                jr      nz, zfodd
                inc     e               ; DE eights: counted as E within D
                dec     e
                jr      z, zfouter
                inc     d
zfouter:        ld      b, e
zfloop:         rept    8
                ld      (hl), a
                inc     hl
                endm
                djnz    zfloop
                dec     d
                jr      nz, zfloop
                ret

; The next note, unpacked: B = its top row, C = how many, (fx0) = its first
; pixel and (fpx) = how many of those.

frontrect:      ld      hl, (fptr)
                ld      a, (hl)         ; the byte column it went at, times
                inc     hl              ; seven -- which does not fit in a
                push    hl              ; byte at the right hand end of the
                ld      l, a            ; room, and used to wrap
                ld      h, 0
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                or      a
                sbc     hl, de
                ex      de, hl
                pop     hl
                ld      b, (hl)         ; the bottom row
                inc     hl
                ld      a, (hl)         ; where its body starts within it
                inc     hl
                ld      c, a
                ld      a, e
                add     a, c
                ld      e, a
                jr      nc, frx1
                inc     d
frx1:           ld      (fx0), de
                ld      a, (hl)         ; and how wide the body is
                inc     hl
                ld      (fpx), a
                ld      c, (hl)         ; and the height
                inc     hl
                ld      (fptr), hl
                ld      a, b            ; the top of it
                sub     c
                inc     a
                ld      b, a
                ret


fleft:          db      0
fptr:           dw      0
fmrow:          dw      0
frow:           db      0
frows:          db      0
fx0:            dw      0
fpx:            db      0
fcol:           db      0
fmask0:         db      0
fmask1:         db      0
fspan:          db      0

floormasks:     ld      a, 1
                call    onemask
                ld      hl, FLOORCAN
                ld      (cvsrc2), hl
                ld      hl, floormask
                ld      (cvdst2), hl
                call    packmask

                ld      a, 2
                call    onemask
                ld      hl, HALFCAN
                ld      (cvsrc2), hl
                ld      hl, halfmask
                ld      (cvdst2), hl
                call    packmask

                xor     a
                ld      (bgmask), a
                ret

; A = which mask.  Runs the floorpiece pass over every block of the room.

onemask:        ld      (bgmask), a     ; which canvas, before paging: pageset
                dec     a               ; hands back the port value in A, and
                ld      hl, FLOORCAN    ; asking afterwards cleared HALFCAN
                jr      z, om1          ; twice and FLOORCAN never -- so the
                ld      hl, HALFCAN     ; floor mask kept the ink of every room
om1:            push    hl              ; visited before this one
                call    page_pixels
                pop     hl
                ld      d, h
                ld      e, l
                inc     de
                ld      bc, CANVAS_W * 45 - 1
                ld      (hl), 0
                ldir

                ld      a, 2
                ld      (blockrow), a
omrow:          ld      a, (blockrow)
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, blockbot
                add     hl, de
                ld      a, (hl)
                ld      (dy), a
                sub     3
                ld      (ay), a
                ld      a, (blockrow)   ; PREV, the same as compose has it
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, prevblk
                add     hl, de
                ld      a, (hl)
                ld      (preced), a
                inc     hl
                ld      a, (hl)
                ld      (spreced), a
                xor     a
                ld      (blockcol), a
                ld      (xco), a
omcol:          call    setblock
                call    floorpiece
                ld      a, (objid)
                ld      (preced), a
                ld      a, (state)
                ld      (spreced), a
                ld      a, (xco)
                add     a, 4
                ld      (xco), a
                ld      hl, blockcol
                inc     (hl)
                ld      a, (hl)
                cp      10
                jr      c, omcol
                ld      hl, blockrow
                ld      a, (hl)
                or      a
                ret     z
                dec     (hl)
                jr      omrow

; One block's floorpiece, made again in both masks.
;
; The masks are made when the room is entered, but a floor that gives way
; changes them: the wedge is a floor's near edge and exists only where the
; block to the left is empty space, which the block right of a collapsed
; floor now has.  DRAWFLOOR runs off the blueprint every frame on the Apple
; and never has this to think about; here the two blocks that change are done
; again, on redblock's pattern and with its invariant -- a piece keeps to its
; own four columns.  A block's wedge lies in its own band, so only fifteen of
; the forty five rows are touched.
;
; In: (blockrow), (blockcol).


packmask:       ld      a, 45
                ld      (cvleft), a
pmrow:          call    page_pixels
                ld      hl, (cvsrc2)
                ld      de, cvbuf
                ld      bc, CANVAS_W
                ldir
                ld      (cvsrc2), hl

                call    page_art
                ld      de, (cvdst2)
                ld      hl, cvbuf
                ld      b, 5
pmgroup:        push    bc
                call    cv8to7
                pop     bc
                djnz    pmgroup
                ld      (cvdst2), de

                ld      hl, cvleft
                dec     (hl)
                jr      nz, pmrow
                ret

cvsrc2:         dw      0
cvdst2:         dw      0

readlinks:      call    page_bg
                ld      a, (roomnum)
                dec     a
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl          ; four bytes to a room
                ld      de, level + 1952
                add     hl, de
                ld      de, links
                ld      bc, 4
                ldir
                jp      page_art

; CUT in AUTO.S: a whole screen's width sideways, three block rows and 189
; scanlines up or down.  The stubs in the fixed half of the map say which way
; he went and put this block back before they come here.

nrcut:          ld      a, (nrwhich)    ; the stub has the room already: all
                or      a               ; that is left is where he lands in it
                jr      z, nrcup
                dec     a
                jr      z, nrcdown
                dec     a
                jr      z, nrcleft
                dec     a
                jr      nz, levelgo

                ld      hl, (charx)     ; right
                ld      de, -280
                add     hl, de
                ld      (charx), hl
                jr      nrcgo

nrcleft:        ld      hl, (charx)
                ld      de, 280
                add     hl, de
                ld      (charx), hl
                jr      nrcgo

nrcup:          ld      a, (chary)
                add     a, 189
                ld      (chary), a
                ld      a, (blocky)
                add     a, 3
                ld      (blocky), a
                jr      nrcgo

nrcdown:        ld      a, (chary)
                sub     189
                ld      (chary), a
                ld      a, (blocky)
                sub     3
                ld      (blocky), a

; Building a room takes the best part of a second, and a frozen picture of the
; room he has just left reads as the game having stopped.  Black says it is
; working, and the new room arrives whole when it is ready.

nrcgo:          xor     a               ; nothing of the last room's still
                ld      (rqn), a        ; to be drawn, nor to be shown, nor
                ld      (rqsn), a       ; a view of it made
                ld      (flipnow), a
                dec     a
                ld      (vwcam), a
                ld      hl, SCREEN
                ld      de, SCREEN + 1
                ld      bc, 6143
                ld      (hl), 0
                ldir
                xor     a               ; and that black shown, whichever
                call    setvis          ; screen was
                call    newroom         ; this block is already back, so the
                call    readlinks       ; room itself is all that is left
                ld      hl, c1addsl     ; ADDSLICERS in CUT: walking into a
                call    c1call          ; room starts the slicers of the row
                                        ; he walks in on, the same as stepping
                                        ; up or down one does.  Without it a
                                        ; slicer woke only for the side he
                                        ; happened to arrive at falling
                call    camhome         ; the view is already where he is
                call    add_guard       ; and the new room's guard stands up
                xor     a
                ld      (oldw), a
                ld      (mbold + 2), a  ; nothing falling drawn in it yet
                ld      (mbold + 6), a
                ld      (mbshow + 2), a
                ld      (mbshow + 6), a
                jp      nrfinish        ; and out of this block first: the
                                        ; repaint goes straight over it

; LoadNextLevel and RESTART in TOPCTRL.S, as far as this game has them --
; nextroom has let the tune he went up to play out -- the screen black, the next blueprint off the tape over this one -- the disk's
; LoadLevelX -- and the level set going: nothing moving or falling, nobody
; following him, the exit he came in by open and coming down behind him
; (ENTRANCE), and he stands at KidStartBlock with the sword he has, all his
; strength, and the turn STARTKID starts him with.  The room itself is the
; room change's to build.

levelgo:        xor     a
                ld      (gdkeep), a
                ld      (numtrans), a
                ld      (nummob), a
                ld      (exitopen), a
                ld      (charsword), a
                ld      (yvel), a
                ld      (xvel), a
                ld      (jarabove), a
                ld      (weightless), a
                ld      (offguard), a
                ld      (droppedout), a
                ld      (heroic), a
                ld      (enemyalert), a
                ld      (stunned), a
                ld      (oppstr), a
                ld      hl, SCREEN      ; black while the tape turns
                ld      de, SCREEN + 1
                ld      bc, 6143
                ld      (hl), a
                ldir
                call    setvis
                ld      a, (lvflag)     ; a death: RESTART, the level as it
                cp      3               ; began, and the strength he began it
                jr      z, lgagain      ; with
                call    page_pixels     ; the next level off the tape: the
                call    c1start         ; player told to start it, and to
                ld      a, (curlev)     ; stop it again once it has loaded
                or      a               ; (c1stop) -- and before level two
                jr      nz, lgnocut     ; the princess's room, which comes
                ld      hl, 0xC000      ; first on the tape, into the art
cut1len:        ld      de, 0           ; bank: its length is build.sh's
                ld      a, BANK_ART
                call    tapeblk
lgnocut:        call    tapeload
                call    page_bg         ; and the character set it carries,
                ld      hl, (level + LV_HEAD + 6)       ; if it is not the
                ld      a, h            ; one the tape started with
                or      l
                jr      z, lgnochs
                ex      de, hl
                ld      hl, 0xC000      ; into the art bank, whose room is
                ld      a, BANK_ART     ; built again after this
                call    tapeblk
                call    chset_put
lgnochs:        call    page_pixels
                call    c1stop
                ld      a, (curlev)     ; PlayCut1: see cut1.asm
                or      a
                jr      nz, lgwent
                call    page_art
                call    0xC000
lgwent:         ld      hl, curlev      ; kept as it begins
                inc     (hl)
                call    lvkeep
                jr      lghead
lgagain:        call    lvback
                ld      a, (origstr)
                ld      (maxkidstr), a

lghead:         call    page_bg         ; where he starts, and whether a
                ld      hl, level + LV_HEAD     ; level comes after this one
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      (charx), de
                ld      a, (hl)
                ld      (chary), a
                inc     hl
                ld      a, (hl)
                ld      (blocky), a
                inc     hl
                ld      a, (hl)
                ld      (facing), a
                inc     hl
                ld      a, (hl)
                ld      (lvflag), a
                ld      a, (level + LV_KIDSCRN)
                ld      (roomnum), a

                ld      a, (curlev)     ; STARTKID's :special3: past level
                cp      2               ; three's first gate he begins again
                jr      nz, lgnomile    ; just inside it, and the loose floor
                ld      a, (milestone)  ; he broke on the way is gone
                or      a
                jr      z, lgnomile
                ld      hl, MS3_X
                ld      (charx), hl
                ld      a, MS3_Y
                ld      (chary), a
                ld      a, MS3_ROW
                ld      (blocky), a
                ld      a, MS3_FACE
                ld      (facing), a
                ld      a, MS3_ROOM
                ld      (roomnum), a
                ld      a, MS3_LOOSE
                ld      (trloc), a
                ld      a, MS3_LOOSESCRN
                ld      (trscrn), a
                call    trobat
                ld      a, BG_SPACE
                call    trobtype
                call    page_bg
lgnomile:
                ld      a, (roomnum)    ; the room he starts in: the milestone
                                        ; above reads curlev and the flag into
                                        ; A, and the ENTRANCE below used to
                                        ; take what LV_KIDSCRN had left there
                ld      c, a            ; ENTRANCE: the exit in his room, open,
                dec     a               ; and coming down fast -- CLOSEEXIT
                ld      l, a
                ld      h, 0
                add     hl, hl          ; thirty to a room
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                or      a
                sbc     hl, de
                ld      de, level + 29
                add     hl, de
                ld      b, 30
lgexit:         ld      a, (hl)
                and     0x1f
                cp      BG_EXIT
                jr      z, lgclose
                dec     hl
                djnz    lgexit
                jr      lgkid
lgclose:        ld      de, 720         ; its state, all the way open
                add     hl, de
                ld      (hl), EMAXVAL
                dec     b
                ld      a, b
                ld      (trloc), a
                ld      a, c
                ld      (trscrn), a
                ld      a, 3
                ld      (trdirec), a
                call    addtrob

lgkid:          ld      a, 0xff         ; STARTKID
                ld      (charlife), a
                ld      a, 1
                ld      (gotsword), a
                ld      (charact), a
                ld      a, (maxkidstr)
                ld      (kidstr), a
                ld      a, 1
                ld      (meterdirty), a
                ld      a, (curlev)     ; level one's :special1: no sword yet,
                or      a               ; the gate by the way in slams and he
                ld      b, SQ_TURN      ; drops in
                jr      nz, lgseq
                ld      (gotsword), a
                ld      a, 5
                ld      (trscrn), a
                ld      a, 2
                ld      (trloc), a
                call    trobat
                call    pushpp
                ld      b, SQ_STEPFALL
lgseq:          push    bc
                call    page_canvas
                pop     af
                call    jumpseq
                call    page_canvas
                call    step_seq
                jp      nrcgo

; rdch4 in MASTER.S: the fourth character table the level carries, when its
; opponent is not the one the tape started with.  The block is in the art
; bank at 0xC000 -- a count of pieces, each one's bank, where it goes and
; how long it is, and then the bytes of them all.  Two banks are never in
; together, so every piece goes through the working copy, a chunk at a time.

CHSBUF          equ     work
CHSCHUNK        equ     2048

chset_put:      ld      a, BANK_ART
                call    pageset
                ld      hl, 0xC000
                ld      a, (hl)
                ld      (chsleft), a
                or      a
                ret     z
                inc     hl
                ld      (chshdr), hl
                ld      d, 0
                ld      e, a            ; five bytes an entry, and the bytes
                add     hl, de          ; themselves past the lot of them
                add     hl, de
                add     hl, de
                add     hl, de
                add     hl, de
                ld      (chssrc), hl
chsone:         ld      a, BANK_ART
                call    pageset
                ld      hl, (chshdr)
                ld      a, (hl)
                ld      (chsbank), a
                inc     hl
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ld      (chsdst), de
                inc     hl
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      (chshdr), hl
                ld      (chslen), de
chspart:        ld      hl, (chslen)
                ld      a, h
                or      l
                jr      z, chsnext
                ld      de, CHSCHUNK
                or      a
                sbc     hl, de
                jr      nc, chsbig
                ld      de, (chslen)
                ld      hl, 0
chsbig:         ld      (chslen), hl
                push    de              ; DE = how many bytes this round
                ld      a, BANK_ART
                call    pageset
                ld      hl, (chssrc)
                ld      de, CHSBUF
                pop     bc
                push    bc
                ldir
                ld      (chssrc), hl
                ld      a, (chsbank)
                call    pageset
                ld      hl, CHSBUF
                ld      de, (chsdst)
                pop     bc
                ldir
                ld      (chsdst), de
                jr      chspart
chsnext:        ld      hl, chsleft
                dec     (hl)
                jr      nz, chsone
                ret

chsleft:        db      0
chsbank:        db      0
chshdr:         dw      0
chssrc:         dw      0
chsdst:         dw      0
chslen:         dw      0

; LD-BYTES in the 48K ROM, which is what is paged: the blueprint and its head
; into the background bank, or the princess's room into the art bank.  Until it loads -- a tape not playing is waited
; for, and one that went wrong is tried again.  The border it leaves is
; BASIC's, and the game's is black.

tapeload:       ld      hl, level
                ld      de, LEVEL_LEN
                ld      a, BANK_BG

; A block, whichever: HL where, DE how long, A the bank.

tapeblk:        call    pageset
tbagain:        push    hl
                push    de
                push    hl
                pop     ix
                ld      a, 0xff
                scf
                call    0x0556
                pop     de
                pop     hl
                jr      nc, tbagain
tbdone:         xor     a
                out     (254), a
                ret

; On the way into a room, straight to where the rule puts it.

camhome:        call    camsched
                ld      (cam), a
                ret

; He is at one end of the room or the other, and there is a room that way.

; ADDGUARD, which only the building of a room -- and the start, before the
; first repaint -- ever reaches, so it lives in this block.

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
                ld      a, (curlev)     ; level three's guard is the
                cp      2               ; skeleton
                ld      a, 2
                jr      nz, agid
                ld      a, 4
agid:           ld      (charid), a
                ld      de, GDSEQH
                call    gd_field
                ld      a, (hl)
                or      a
                jr      nz, agseq
                ld      a, (charid)     ; 0 is a fresh start: a guard stands
                cp      4               ; on the alert, the skeleton lands
                ld      b, SQ_ALERTSTAND        ; en garde
                ld      a, 0
                jr      nz, agsword
                ld      b, SQ_LANDENGARDE
                ld      a, 2
agsword:        ld      (charsword), a
                push    bc
                call    page_canvas
                pop     af
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
                ld      b, 13           ; and his rectangles, and CharXVel
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

; CUTCHECK in AUTO.S: the kid is going into room A the way C says -- 0 up,
; 1 down, 2 left, 3 right.  A live guard en garde close to that side goes
; with him, unless a live guard is waiting in the new room; anyone else is
; left behind and written back into his own.  Only a room change reaches it,
; so it lives in this block, which nrcall puts back first.

leave_room:     ld      (lrroom), a
                ld      a, c
                ld      (lrdir), a
                cp      2               ; milestone3 in AUTO.S: going left
                jr      nz, lrnomile    ; out of the room right of level
                ld      a, (curlev)     ; three's first gate, he begins
                cp      2               ; again from there
                jr      nz, lrnomile
                ld      a, (roomnum)
                cp      MS3_SCRN
                jr      nz, lrnomile
                ld      a, 1
                ld      (milestone), a
                ld      a, (maxkidstr)
                ld      (origstr), a
lrnomile:       ld      a, (gdhere)
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
                jr      z, lrleave
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
                jr      nz, lrleave
                ld      de, -280
                jr      lrsideways
lrleft:         ld      hl, (charx + OP) ; left: ShadX under 256 - ScrnWidth - 25
                ld      de, -2 * (256 - 140 - 25 - SCRNLEFT)
                add     hl, de
                bit     7, h
                jr      z, lrleave
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
                jr      update_guard

lrroom:         db      0
lrdir:          db      0

; gdkeep is not here, where it used to be.  This block is put back in its
; bank by newroom, which runs BEFORE add_guard clears the flag, so a guard
; who once came along left it set in the bank for good -- and from then on
; add_guard took the "he is already here" way out in every room of the level
; and no guard was ever made again.  It lives beside gdhere now.

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

