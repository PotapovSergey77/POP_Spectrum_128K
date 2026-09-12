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


compose:        xor     a               ; no front pieces noted yet
                ld      (nfront), a
                ld      (recfront), a
                inc     a
                ld      (frontok), a
                call    page_pixels     ; a clean canvas first
                ld      hl, CANVAS
                ld      de, CANVAS + 1
                ld      bc, CANVAS_W * 192 - 1
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
                ld      hl, (blockptr)
                ld      a, (hl)
                and     0x1f
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

newroom:        call    compose
                call    convert
                call    build_fore
                call    floormasks
                call    maketorches
                jp      page_art

; build_fore below is written but not called yet: the rectangles it collects
; are right -- the row index it makes matches the one baked on the host, row
; for row -- but something paints rows it should not, so the mask that
; travels is still the baked one until that is found.

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
                jp      nz, bfmark

                ld      hl, foreband    ; number the rows that are marked
                ld      b, 192
                ld      c, 0
bfnum:          ld      a, (hl)
                inc     a
                jr      z, bfnum1
                ld      (hl), c
                inc     c
bfnum1:         inc     hl
                djnz    bfnum

                ld      a, c            ; and clear that much of the mask
                or      a
                ret     z
                call    mul35
                ld      b, h
                ld      c, l
                dec     bc
                ld      hl, foremask
                ld      de, foremask + 1
                ld      (hl), 0
                ldir

                ld      a, (nfront)     ; then paint the rectangles into it
                ld      (fleft), a
                ld      hl, frontlist
                ld      (fptr), hl
bfpaint:        call    frontrect
                ld      a, b
                ld      (frow), a
                ld      a, c
                ld      (frows), a
bfrow:          ld      a, (frow)
                cp      192
                jp      nc, bfrownext
                ld      l, a
                ld      h, 0
                ld      de, foreband
                add     hl, de
                ld      a, (hl)
                inc     a
                jp      z, bfrownext
                dec     a
                call    mul35
                ld      de, foremask
                add     hl, de
                ld      (fmrow), hl
                ld      hl, (fx0)       ; the byte it starts in
                srl     h
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ex      de, hl
                ld      hl, (fmrow)
                add     hl, de
                ld      a, (fx0)        ; and the bits of that byte
                and     7
                ld      b, a
                ld      a, 0xff
                inc     b
bfsh1:          dec     b
                jr      z, bfsh2
                srl     a
                jr      bfsh1
bfsh2:          ld      c, a            ; C = the first byte's mask

                push    hl              ; the last pixel of it, which for a
                ld      hl, (fx0)       ; piece at the right hand end of the
                ld      a, (fpx)        ; room does not fit in eight bits
                ld      e, a
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
bfsh4:          ld      d, a            ; D = the last byte's mask
                srl     h               ; and B = which byte that is
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      b, l
                pop     hl

                push    hl              ; how many bytes it spans, without
                ld      hl, (fx0)       ; losing the row it is writing to
                srl     h
                rr      l
                srl     h
                rr      l
                srl     h
                rr      l
                ld      e, l
                pop     hl
                ld      a, b
                sub     e
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
                jp      nz, bfrow
                ld      hl, fleft
                dec     (hl)
                jp      nz, bfpaint
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
                call    page_canvas
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
pmrow:          call    page_canvas
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
                call    camhome         ; the view is already where he is
                xor     a
                ld      (oldw), a
                jp      nrfinish        ; and out of this block first: the
                                        ; repaint goes straight over it

; He is at one end of the room or the other, and there is a room that way.

