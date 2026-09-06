; ---------------------------------------------------------------- background
;
; RedBlockSure and the passes under it, out of FRAMEADV.S.  Up to now a room
; was composed on the host and shipped as a bitmap, which is fine for one room
; and impossible for a level: twenty four of them would be 161K.  POP draws a
; room out of its image tables when you walk into it, and so does this.  The
; same machinery is what a loose floor, a gate or a pressplate wants, since
; those redraw a block while the game runs.
;
; A room is composed in the Apple's own layout -- 40 bytes to a scanline,
; seven pixels to a byte, bit 0 leftmost -- so that every piece goes down
; where POP puts it, on a seven pixel boundary, with no shifting.  That canvas
; lives in a bank of its own; the pieces and the tables live in another; and
; the finished canvas is repacked into the room's 35 byte rows at the end.
;
; The two banks are never wanted at the same moment.  A piece is read from the
; background bank into a buffer down here, and then laid into the canvas with
; the canvas bank in.

CANVAS_W        equ     40
APPLE_PX        equ     CANVAS_W * 7

BG_AND          equ     0               ; the four ways a piece goes down
BG_ORA          equ     1
BG_STA          equ     2
BG_XOR          equ     3

page_bg:        ld      a, BANK_BG
                jp      pageset

page_canvas:    ld      a, BANK_CANVAS
                jp      pageset

; ---------------------------------------------------------------- the tables
;
; BGDATA.S, one array to a piece id, thirty entries each.  In: A = the piece
; id, HL = the array.  Out: A = its entry.

bgentry:        ld      e, a
                ld      d, 0
                add     hl, de
                ld      a, (hl)
                ret

; The arrays themselves are in the background bank, which has to be in.

tab_maska:      ld      hl, bgtables + T_MASKA
                jr      bgentry
tab_maskb:      ld      hl, bgtables + T_MASKB
                jr      bgentry
tab_piecea:     ld      hl, bgtables + T_PIECEA
                jr      bgentry
tab_pieceay:    ld      hl, bgtables + T_PIECEAY
                jr      bgentry
tab_pieceb:     ld      hl, bgtables + T_PIECEB
                jr      bgentry
tab_pieceby:    ld      hl, bgtables + T_PIECEBY
                jr      bgentry
tab_piecec:     ld      hl, bgtables + T_PIECEC
                jr      bgentry
tab_pieced:     ld      hl, bgtables + T_PIECED
                jr      bgentry
tab_fronti:     ld      hl, bgtables + T_FRONTI
                jr      bgentry
tab_fronty:     ld      hl, bgtables + T_FRONTY
                jr      bgentry
tab_frontx:     ld      hl, bgtables + T_FRONTX
                jr      bgentry

; ---------------------------------------------------------------- one piece
;
; setbgimg: bit 7 of the image number picks the second table, the rest is the
; index.  The record is width in bytes, height in scanlines, then the bytes,
; BOTTOM row first, which is the order FASTLAY walks them in.
;
; In: (imgnum), (xco) in bytes, (yco) the bottom scanline, (bgop).

bgdraw:         ld      a, (imgnum)
                or      a
                ret     z
                call    page_bg
                ld      a, (imgnum)     ; paging has had A

                ld      hl, bgtab1      ; which table
                bit     7, a
                jr      z, bgd1
                ld      hl, bgtab2
bgd1:           and     0x7f
                ret     z
                ld      c, a
                ld      a, (hl)         ; how many it holds
                cp      c
                ret     c
                push    hl
                ld      a, c
                dec     a
                ld      e, a
                ld      d, 0
                add     hl, de
                add     hl, de
                inc     hl              ; past the count
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                pop     hl
                ld      a, d            ; nothing there
                or      e
                ret     z
                add     hl, de

                ld      a, (hl)         ; width, height, and the bytes
                ld      (imgw), a
                ld      c, a
                inc     hl
                ld      a, (hl)
                ld      (imgh), a
                inc     hl
                push    hl
                call    frontrec        ; a front piece is worth remembering
                pop     hl
                ld      a, (imgh)       ; which has had A
                ld      b, a
                push    hl
                ld      h, 0            ; how many bytes that is
                ld      l, 0
                ld      d, 0
                ld      e, c
bgdsize:        add     hl, de
                djnz    bgdsize
                ld      b, h
                ld      c, l
                pop     hl
                ld      de, imgbuf
                ldir

                call    page_canvas

; FASTLAY: the first stored row lands on YCO and the rest climb.

                ld      a, (yco)
                ld      (bgrow), a
                ld      hl, imgbuf
                ld      (bgsrc), hl
                ld      a, (imgh)
                ld      b, a
bgrowloop:      push    bc
                ld      a, (bgrow)
                cp      192
                jr      nc, bgrowskip
                call    canvasrow       ; HL = where that row starts
                ld      a, (xco)
                cp      CANVAS_W
                jr      nc, bgrowskip
                ld      e, a
                ld      d, 0
                add     hl, de          ; HL = canvas
                ld      de, (bgsrc)     ; DE = the piece
                ld      a, (imgw)
                ld      b, a
                ld      a, (xco)
                ld      c, a
bgbyte:         ld      a, c            ; anything past the row is dropped
                cp      CANVAS_W
                jr      nc, bgbytenext
                ld      a, (bgop)
                or      a
                jr      nz, bgb1
                ld      a, (de)         ; and
                and     (hl)
                jr      bgbput
bgb1:           dec     a
                jr      nz, bgb2
                ld      a, (de)         ; ora
                or      (hl)
                jr      bgbput
bgb2:           dec     a
                jr      nz, bgb3
                ld      a, (de)         ; sta
                jr      bgbput
bgb3:           ld      a, (de)         ; xor
                xor     (hl)
bgbput:         ld      (hl), a
bgbytenext:     inc     hl
                inc     de
                inc     c
                djnz    bgbyte
                ld      (bgsrc), de
                jr      bgrowdown
bgrowskip:      ld      hl, (bgsrc)     ; off the screen, but the source moves
                ld      a, (imgw)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (bgsrc), hl
bgrowdown:      ld      hl, bgrow
                dec     (hl)
                pop     bc
                djnz    bgrowloop
                ret

; A = a scanline.  Out: HL = where its forty bytes start in the canvas.

canvasrow:      ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; eight
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl          ; thirty two
                add     hl, de          ; and forty
                ld      de, CANVAS
                add     hl, de
                ret

; Set the piece up and lay it: A = image, (xco)/(yco) already set, C = the op.

bglay:          ld      (imgnum), a
                ld      a, c
                ld      (bgop), a
                jp      bgdraw

; ---------------------------------------------------------------- sections
;
; The five passes of RedBlockSure, one for one with FRAMEADV.S.  The block in
; hand is described by the bytes at the end of this file: its own id and
; state, the id and state of the block to its left, and of the one below and
; to its left.

; drawc: the C section of the piece below and to the left.

draw_c:         ld      a, (objid)      ; only some pieces show it
                cp      BG_SPACE
                jr      z, dcok
                cp      BG_PILLARTOP
                jr      z, dcok
                cp      BG_PANELWOF
                jr      z, dcok
                cp      BG_ARCHTOP1
                jr      nc, dcok
                ret                     ; and no mask either: drawc is done
dcok:           call    page_bg
                ld      a, (below)
                cp      BG_BLOCK
                jr      nz, dcpiece
                ld      a, (sbelow)     ; a solid block has its own C
                cp      BG_NUMBLOX
                jr      c, dcblock
                xor     a
dcblock:        ld      hl, bgtables + T_BLOCKC
                call    bgentry
                jr      dcgo
dcpiece:        call    tab_piecec
                ld      c, a
                ld      a, (bgtables + T_PANELC0)
                cp      c
                ld      a, c
                jr      nz, dcgo
                ld      a, (bgtables + T_NUMPANS)
                ld      c, a
                ld      a, (sbelow)     ; a panel, of which there are three
                cp      c
                ret     nc
                ld      hl, bgtables + T_PANELC
                call    bgentry
dcgo:           or      a
                jr      z, mask_b
                ld      c, a
                ld      a, (dy)
                ld      (yco), a
                ld      a, c
                ld      c, BG_ORA
                call    bglay

mask_b:         call    page_bg
                ld      a, (preced)
                call    tab_maskb
                or      a
                ret     z
                ld      c, a
                ld      a, (dy)
                ld      (yco), a
                ld      a, c
                ld      c, BG_AND
                jp      bglay

; drawb: the B section of the piece to the left.

draw_b:         ld      a, (objid)
                cp      BG_BLOCK
                ret     z               ; hidden by a solid block
                call    page_bg
                ld      a, (preced)
                cp      BG_SPACE
                jr      z, dbspace
                cp      BG_FLOOR
                jr      z, dbfloor
                cp      BG_BLOCK
                jr      z, dbblock

                call    tab_pieceb
                or      a
                ret     z
                ld      c, a
                ld      a, (bgtables + T_PANELB0)
                cp      c
                jr      z, dbpanel
                ld      a, (preced)     ; anything else goes at its own height
                push    bc
                call    tab_pieceby
                call    bgay
                pop     bc
                ld      a, c
                ld      c, BG_ORA
                jp      bglay
dbpanel:        ld      a, (bgtables + T_NUMPANS)
                ld      c, a
                ld      a, (spreced)
                cp      c
                ret     nc
                ld      hl, bgtables + T_PANELB
                call    bgentry
                ld      c, a
                ld      a, (preced)
                push    bc
                call    tab_pieceby
                call    bgay
                pop     bc
                ld      a, c
                ld      c, BG_ORA
                jp      bglay

dbspace:        ld      a, (bgtables + T_NUMBPANS)
                inc     a
                ld      c, a
                ld      a, (spreced)
                cp      c
                ret     nc
                ld      a, (spreced)
                ld      hl, bgtables + T_SPACEB
                call    bgentry
                ld      b, a
                ld      a, (spreced)
                ld      hl, bgtables + T_SPACEBY
                call    bgentry
                ld      c, b
                jr      dbput

dbfloor:        ld      a, (bgtables + T_NUMBPANS)
                inc     a
                ld      c, a
                ld      a, (spreced)
                cp      c
                jr      c, dbfl1
                xor     a
dbfl1:          ld      c, a
                ld      hl, bgtables + T_FLOORB
                call    bgentry
                ld      b, a
                ld      a, c
                ld      hl, bgtables + T_FLOORBY
                call    bgentry
                ld      c, b
                jr      dbput

dbblock:        ld      a, (spreced)
                cp      BG_NUMBLOX
                jr      c, dbbl1
                xor     a
dbbl1:          ld      hl, bgtables + T_BLOCKB
                call    bgentry
                ld      b, a
                ld      a, (preced)
                call    tab_pieceby
                ld      c, b

dbput:          push    bc              ; A = the offset from Ay, C = image
                call    bgay
                pop     bc
                ld      a, c
                or      a
                ret     z
                ld      c, BG_ORA
                jp      bglay

; A = a signed offset from Ay; sets (yco).

bgay:           ld      c, a
                ld      a, (ay)
                add     a, c
                ld      (yco), a
                ret

; drawd: the block's own top surface.

draw_d:         call    page_bg
                ld      a, (dy)
                ld      (yco), a
                ld      a, (objid)
                cp      BG_BLOCK
                jr      nz, ddpiece
                ld      a, (state)
                cp      BG_NUMBLOX
                jr      c, dd1
                xor     a
dd1:            ld      hl, bgtables + T_BLOCKD
                call    bgentry
                ld      c, BG_STA
                jp      bglay
ddpiece:        ld      c, BG_STA
                cp      BG_PANELWOF
                jr      nz, dd2
                ld      c, BG_ORA
dd2:            push    bc
                ld      a, (objid)
                call    tab_pieced
                pop     bc
                jp      bglay

; drawa: the front face, with the mask that keeps it out of its neighbour.

draw_a:         call    page_bg
                ld      a, (preced)
                cp      BG_ARCHTOP1
                jr      nz, dachk
                ld      a, (objid)
                cp      BG_PANELWOF
                jr      nz, damain
                call    tab_pieceay
                call    bgay
                ld      a, (bgtables + T_ARCHPANEL)
                ld      c, BG_ORA
                jp      bglay
dachk:          cp      BG_PANELWIF
                jr      z, damask
                cp      BG_PANELWOF
                jr      z, damask
                cp      BG_PILLARTOP
                jr      z, damask
                cp      BG_BLOCK
                jr      nz, damain
damask:         ld      a, (objid)
                call    tab_maska
                or      a
                jr      z, damain
                ld      c, a
                ld      a, (ay)
                ld      (yco), a
                ld      a, c
                ld      c, BG_AND
                call    bglay
                call    page_bg

damain:         ld      a, (objid)
                cp      BG_LOOSE
                jr      nz, dapiece
                call    loose_y
                ld      hl, bgtables + T_LOOSEA
                call    bgentry
                jr      dago
dapiece:        call    tab_piecea
dago:           or      a
                ret     z
                ld      c, a
                ld      a, (objid)
                push    bc
                call    tab_pieceay
                call    bgay
                pop     bc
                ld      a, c
                ld      c, BG_ORA
                jp      bglay

; getloosey: at rest a loose floor draws exactly like a solid one.

loose_y:        ld      a, (state)
                bit     7, a
                jr      nz, ly1
                xor     a
                ret
ly1:            and     0x7f
                cp      BG_FFALLING + 1
                ret     c
                ld      a, BG_FFALLING
                ret

; drawmb and drawmd, of which only the loose floor is here so far.  Without
; its B section the floor to its right loses its left half.

draw_mb:        ld      a, (preced)
                cp      BG_LOOSE
                ret     nz
                call    page_bg
                ld      a, (state)      ; loose_y wants the left one's state
                push    af
                ld      a, (spreced)
                ld      (state), a
                call    loose_y
                ld      hl, bgtables + T_LOOSEBY
                call    bgentry
                call    bgay
                pop     af
                ld      (state), a
                ld      a, (bgtables + T_LOOSEB)
                ld      c, BG_ORA
                jp      bglay

draw_md:        ld      a, (objid)
                cp      BG_LOOSE
                ret     nz
                call    page_bg
                call    loose_y
                ld      hl, bgtables + T_LOOSED
                call    bgentry
                ld      c, a
                ld      a, (dy)
                ld      (yco), a
                ld      a, c
                ld      c, BG_STA
                jp      bglay

; drawfrnt: what goes over the characters.  Stamped rather than ORed for the
; posts and the arches, so the neighbour's B section does not show through.

draw_front:     call    page_bg
                ld      a, (objid)
                call    tab_fronti
                or      a
                ret     z
                ld      (frimg), a
                ld      a, (objid)
                call    tab_frontx
                ld      c, a
                ld      a, (xco)
                add     a, c
                ld      (xco), a
                ld      a, (objid)
                call    tab_fronty
                call    bgay
                ld      c, BG_ORA
                ld      a, (objid)
                cp      BG_POSTS
                jr      z, dfsta
                cp      BG_ARCHTOP2
                jr      c, dfgo
dfsta:          ld      c, BG_STA
dfgo:           ld      a, 1
                ld      (recfront), a
                ld      a, (frimg)
                call    bglay
                xor     a
                ld      (recfront), a
                call    page_bg         ; put the column back for the next one
                ld      a, (objid)
                call    tab_frontx
                ld      c, a
                ld      a, (xco)
                sub     c
                ld      (xco), a
                ret

; ---------------------------------------------------------------- a room
;
; Three rows of ten blocks, left to right and bottom to top, exactly as the
; screen redraw of FRAMEADV.S walks them.

compose:        xor     a               ; no front pieces noted yet
                ld      (nfront), a
                ld      (recfront), a
                call    page_canvas     ; a clean canvas first
                ld      hl, CANVAS
                ld      de, CANVAS + 1
                ld      bc, CANVAS_W * 192 - 1
                ld      (hl), 0
                ldir

                call    read_room

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

                xor     a               ; PREV: nothing to the left yet
                ld      (preced), a
                ld      (spreced), a
                ld      (blockcol), a
                ld      (xco), a
compcol:        call    setblock
                call    draw_c
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
                ret     z
                dec     (hl)
                jr      comprow

; The block in hand, and the one below and to its left.  getbelow stores the
; row below starting one along, so the C section sees the block down-left.

setblock:       ld      a, (blockrow)
                ld      b, a
                ld      a, (blockcol)
                ld      c, a
                call    blockat
                ld      hl, (blockptr)
                ld      a, (hl)
                and     0x1f            ; getobjid: the id is the low five bits
                ld      (objid), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (state), a

                xor     a               ; the row below, one block to the left
                ld      (below), a
                ld      (sbelow), a
                ld      a, (blockrow)
                cp      2
                ret     z
                ld      a, (blockcol)
                or      a
                ret     z
                dec     a
                ld      c, a
                ld      a, (blockrow)
                inc     a
                ld      b, a
                call    blockat
                ld      hl, (blockptr)
                ld      a, (hl)
                and     0x1f
                ld      (below), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (sbelow), a
                ret

; B = row, C = column.  Out: (blockptr) = where that block's id sits.

blockat:        ld      a, b
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten to the row
                ld      e, c
                ld      d, 0
                add     hl, de
                ld      de, roomids
                add     hl, de
                ld      (blockptr), hl
                ret

; The room's thirty ids and thirty states, out of the blueprint.

read_room:      call    page_bg
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

imgnum:         db      0
imgw:           db      0
imgh:           db      0
xco:            db      0
yco:            db      0
bgop:           db      0
bgrow:          db      0
bgsrc:          dw      0
frimg:          db      0
objid:          db      0
state:          db      0
preced:         db      0
spreced:        db      0
below:          db      0
sbelow:         db      0
dy:             db      0
ay:             db      0
blockrow:       db      0
blockcol:       db      0
blockptr:       dw      0
roomnum:        db      1
blockbot:       db      2, 65, 128, 191, 254
roomids:        ds      60              ; thirty ids, then thirty states
imgbuf:         ds      384             ; the largest piece is 378 bytes

; ---------------------------------------------------------------- repack
;
; The canvas holds the room the Apple's way, seven pixels to a byte with bit 0
; leftmost; the room wants eight to a byte with bit 7 leftmost.  Forty bytes
; in, thirty five out, and the two banks are never in together, so a row goes
; through a buffer down here.

convert:        xor     a
                ld      (cvrow), a
                ld      a, 192
                ld      (cvleft), a
cvline:         call    page_canvas
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
                jp      build_fore

; build_fore below is written but not called yet: the rectangles it collects
; are right -- the row index it makes matches the one baked on the host, row
; for row -- but something paints rows it should not, so the mask that
; travels is still the baked one until that is found.

cvrow:          db      0
cvleft:         db      0
cvleft2:        db      0
cvacc:          db      0
cvbuf:          ds      CANVAS_W
; Eight bytes of seven pixels are exactly seven of eight, so the row divides
; into five of these and nothing is left over.  Reversing first puts the
; leftmost pixel in bit 7, where the Spectrum wants it, and then each output
; byte is the tail of one source byte and the head of the next.
;
; In: HL = eight source bytes, DE = seven to write.  Out: both past them.

cv8to7:         ld      (cvdst), de     ; where the seven are to go
                ex      de, hl          ; DE = the eight, HL free for the table
                ld      h, revtab / 256
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 0), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 1), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 2), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 3), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 4), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 5), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 6), a
                inc     de
                ld      a, (de)
                ld      l, a
                ld      a, (hl)
                ld      (cvrev + 7), a
                inc     de
                ex      de, hl          ; HL past the eight
                ld      de, (cvdst)     ; and the seven where they were

                ld      a, (cvrev + 0)
                and     0xfe
                ld      c, a
                ld      a, (cvrev + 1)
                rlca
                and     0x01
                or      c
                ld      (de), a
                inc     de

                ld      a, (cvrev + 1)
                add     a, a
                and     0xfc
                ld      c, a
                ld      a, (cvrev + 2)
                rlca
                rlca
                and     0x03
                or      c
                ld      (de), a
                inc     de

                ld      a, (cvrev + 2)
                add     a, a
                add     a, a
                and     0xf8
                ld      c, a
                ld      a, (cvrev + 3)
                rlca
                rlca
                rlca
                and     0x07
                or      c
                ld      (de), a
                inc     de

                ld      a, (cvrev + 3)
                add     a, a
                add     a, a
                add     a, a
                and     0xf0
                ld      c, a
                ld      a, (cvrev + 4)
                rlca
                rlca
                rlca
                rlca
                and     0x0f
                or      c
                ld      (de), a
                inc     de

                ld      a, (cvrev + 4)
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                and     0xe0
                ld      c, a
                ld      a, (cvrev + 5)
                rlca
                rlca
                rlca
                rlca
                rlca
                and     0x1f
                or      c
                ld      (de), a
                inc     de

                ld      a, (cvrev + 5)
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                and     0xc0
                ld      c, a
                ld      a, (cvrev + 6)
                rlca
                rlca
                rlca
                rlca
                rlca
                rlca
                and     0x3f
                or      c
                ld      (de), a
                inc     de

                ld      a, (cvrev + 6)
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                and     0x80
                ld      c, a
                ld      a, (cvrev + 7)
                rrca
                and     0x7f
                or      c
                ld      (de), a
                inc     de
                ret

cvdst:          dw      0
cvrev:          ds      8


; ---------------------------------------------------------------- the mask
;
; What the foreground covers.  POP draws the front pieces after the
; characters, which is what lets a wall or a post stand in front of the
; prince; here they go down with the room and their rectangles are put back
; over him afterwards.  The whole rectangle counts, not just the lit pixels,
; or he shows through the gaps in the dither.
;
; The pieces are noted as they are drawn and the mask is painted from the
; notes, because painting wants the art bank and drawing wants the canvas.
; Twenty five is the most any room of the level has; a hundred and eighty
; rows is the most any of them covers, which is what the mask holds.

MAXFRONT        equ     28

frontrec:       ld      a, (recfront)
                or      a
                ret     z
                ld      a, (nfront)
                cp      MAXFRONT
                ret     nc
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      de, frontlist
                add     hl, de
                ld      a, (xco)        ; where it went and how big it is
                ld      (hl), a
                inc     hl
                ld      a, (yco)
                ld      (hl), a
                inc     hl
                ld      a, (imgw)
                ld      (hl), a
                inc     hl
                ld      a, (imgh)
                ld      (hl), a
                ld      hl, nfront
                inc     (hl)
                ret

; Which rows the mask has anything on, and where each of them sits in it.

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
                ld      a, (fx0)        ; the byte it starts in
                srl     a
                srl     a
                srl     a
                ld      e, a
                ld      d, 0
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
                ld      a, (fx0)        ; piece at the right hand end of the
                ld      l, a            ; room does not fit in eight bits
                ld      h, 0
                ld      a, (fpx)
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

                ld      a, (fx0)        ; how many bytes it spans
                srl     a
                srl     a
                srl     a
                ld      e, a
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
                ld      a, (hl)         ; the byte column it went at
                inc     hl
                ld      c, a
                add     a, a            ; times seven
                add     a, a
                add     a, a
                sub     c
                ld      (fx0), a
                ld      b, (hl)         ; the bottom row
                inc     hl
                ld      a, (hl)         ; the width, in bytes of seven
                inc     hl
                ld      c, a
                add     a, a
                add     a, a
                add     a, a
                sub     c
                ld      (fpx), a
                ld      c, (hl)         ; and the height
                inc     hl
                ld      (fptr), hl
                ld      a, b            ; the top of it
                sub     c
                inc     a
                ld      b, a
                ret

recfront:       db      0
nfront:         db      0
fleft:          db      0
fptr:           dw      0
fmrow:          dw      0
frow:           db      0
frows:          db      0
fx0:            db      0
fpx:            db      0
frontlist:      ds      MAXFRONT * 4
