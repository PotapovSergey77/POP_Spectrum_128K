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
; seven pixels to a byte -- so that every piece goes down where POP puts it,
; on a seven pixel boundary, with no shifting: XCO is a byte index there, and
; all four of AND, ORA, STA and XOR are plain byte work.  Twenty eight pixels
; to a block is three and a half Spectrum bytes, so composing in the screen's
; own layout instead would put half the pieces mid-byte and every one of those
; ops would need edge masks.  That canvas lives in a bank of its own; the
; pieces and the tables live in another; and the finished canvas is repacked
; into the room's 35 byte rows at the end.  The repack no longer turns bytes
; round -- the art ships that way -- so it is only closing up the spare bit.
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
                jp      nc, bgrowskip
                ld      hl, bandbot     ; a single block redraw only wants the
                cp      (hl)            ; rows that can have changed; a whole
                jr      z, bgband1      ; room asks for all of them
                jp      nc, bgrowskip
bgband1:        ld      hl, bandtop
                cp      (hl)
                jp      c, bgrowskip
                ld      a, (bgmask)     ; into a mask, or into the picture
                or      a
                jp      nz, bgmaskrow
                ld      a, (bgrow)
                call    canvasrow       ; HL = where that row starts
                jr      bgrowat
bgmaskrow:      ld      a, (bgrow)      ; only the floor bands are kept
                ld      l, a
                ld      h, 0
                ld      de, floorband
                add     hl, de
                ld      a, (hl)
                inc     a
                jp      z, bgrowskip
                dec     a
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; eight
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl          ; thirty two
                add     hl, de          ; and forty
                ld      a, (bgmask)
                dec     a
                ld      de, FLOORCAN
                jr      z, bgmaskr1
                ld      de, HALFCAN
bgmaskr1:       add     hl, de
bgrowat:        ld      a, (xco)
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
                ld      a, (bgmask)
                or      a
                jp      nz, bgbmask
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
                jr      bgbytenext
bgbmask:        ld      a, (bgop)       ; a mask covers what an AND clears,
                or      a                ; what an ORA sets, and the whole
                jr      nz, bgbm1        ; rectangle of an STA
                ld      a, (de)
                cpl
                and     0xfe
                jr      bgbmput
bgbm1:          dec     a
                jr      nz, bgbm2
                ld      a, (de)
                jr      bgbmput
bgbm2:          ld      a, 0xfe
bgbmput:        or      (hl)
                ld      (hl), a
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
                dec     b
                jp      nz, bgrowloop
                ret

bandtop:        db      0               ; the rows a draw may touch
bandbot:        db      191

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

draw_c:         call    checkc
                ret     nc
                call    dodrawc
                jp      mask_b

; checkc: carry set if the C section below and to the left shows at all.

checkc:         ld      a, (objid)
                cp      BG_SPACE
                jr      z, ccyes
                cp      BG_PILLARTOP
                jr      z, ccyes
                cp      BG_PANELWOF
                jr      z, ccyes
                cp      BG_ARCHTOP1     ; carry below it, and those hide it
                ccf
                ret
ccyes:          scf
                ret

dodrawc:        call    page_bg
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
                ret     z
                ld      c, a
                ld      a, (dy)
                ld      (yco), a
                ld      a, c
                ld      c, BG_ORA
                jp      bglay

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

loose_y:        ld      a, (state)      ; getloosey: a floor on its way down
                bit     7, a            ; counts 1..Ffalling and the state is
                jr      nz, ly1         ; the frame; one that is only jarred
                cp      BG_FFALLING + 1 ; has bit 7 and counts in the rest
                ret     c
                ld      a, BG_FFALLING
                ret
ly1:            and     0x7f
                cp      BG_FFALLING + 1
                ret     c
                ld      a, 1            ; past the last frame: back to the
                ret                     ; first, the way POP does it

; drawmb and drawmd, of which only the loose floor is here so far.  Without
; its B section the floor to its right loses its left half.

; drawmc: the only movable C section is the top of a gate's bars, poking up
; into the block above and to the right of it.

draw_mc:        ld      a, (objid)      ; an A section would cover it
                cp      BG_SPACE
                jr      z, dmcok
                cp      BG_PANELWOF
                jr      z, dmcok
                cp      BG_PILLARTOP
                ret     nz
dmcok:          ld      a, (below)
                cp      BG_GATE
                ret     nz

                call    page_bg
                ld      a, (dy)
                ld      (yco), a
                ld      a, (bgtables + T_GATECMASK)
                ld      c, BG_AND       ; a triangle out of the way first
                call    bglay
                call    page_bg
                ld      a, (sbelow)
                cp      GMAXVAL
                jr      c, dmc1
                ld      a, GMAXVAL
dmc1:           rrca                    ; (state / 4) mod 8
                rrca
                and     7
                ld      hl, bgtables + T_GATE8C
                call    bgentry
                ld      c, a
                ld      a, (dy)
                ld      (yco), a
                ld      a, c
                ld      c, BG_ORA
                jp      bglay

draw_mb:        ld      a, (preced)
                cp      BG_GATE
                jp      z, drawgateb
                cp      BG_EXIT
                jp      z, drawexitb
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

; ---------------------------------------------------------------- the gate
;
; A gate's bars hang in the block to its right, so they are drawn as that
; block's movable B section.  The state is how far the gate has risen, four
; pixels to the step, up to GMAXVAL; the foot of the bars is laid at that
; height and eight-line middle pieces are stacked above it to the top of the
; B section, with one of eight part-height shapes to finish.

GMAXVAL         equ     188

; setupdgb: the topmost line of the B section, and where the foot sits.

setupdgb:       ld      a, (dy)
                sub     62
                ld      (blockthr), a
                ld      a, (spreced)
                cp      GMAXVAL
                jr      c, sdgb1
                ld      a, GMAXVAL
sdgb1:          rrca                    ; state / 4, one off the floor
                rrca
                and     0x3f
                inc     a
                ld      c, a
                ld      a, (ay)
                sub     c
                ld      (gatebot), a
                ret

drawgateb:      call    setupdgb
                ld      a, (gatebot)
                add     a, 12
                ld      c, a
                ld      a, (ay)
                cp      c
                jr      c, dgbora
                jr      z, dgbora

                call    page_bg         ; clear of the floor line: stamp it
                ld      a, (gatebot)
                ld      (yco), a
                ld      a, (bgtables + T_GATEBOTSTA)
                ld      c, BG_STA
                call    bglay
                jr      dgbmid

dgbora:         call    restorebot      ; over it, so put the floor back and
                call    page_bg         ; lay the foot on top of that
                ld      a, (gatebot)
                sub     2
                ld      (yco), a
                ld      a, (bgtables + T_GATEBOTORA)
                ld      c, BG_ORA
                call    bglay

dgbmid:         ld      a, (gatebot)
                sub     12
                ld      (yco), a
dgbloop:        ld      a, (yco)
                cp      192
                ret     nc
                sub     7               ; a middle piece is eight lines high
                jr      c, dgbtop
                ld      hl, blockthr
                cp      (hl)
                jr      c, dgbtop
                call    page_bg
                ld      a, (bgtables + T_GATEB1)
                ld      c, BG_STA
                call    bglay
                ld      a, (yco)
                sub     8
                ld      (yco), a
                jr      nz, dgbloop

dgbtop:         ld      a, (yco)        ; and what is left at the top
                ld      hl, blockthr
                sub     (hl)
                inc     a
                ret     z
                cp      9
                ret     nc
                dec     a
                ld      c, a
                call    page_bg
                ld      hl, bgtables + T_GATE8B
                ld      a, c
                call    bgentry
                ld      c, BG_STA
                jp      bglay

; The exit: stairs, and a door that rises four pixels to the step the way a
; gate does.  Both stand in the block to the right of the exit tile, one byte
; further in again -- and in the room the prince starts in, that tile is the
; way he came in, so it gets no stairs.

EXITINC         equ     4
EMAXVAL         equ     172

drawexitb:      ld      a, (xco)
                cp      36
                ret     nc              ; it would run off the right hand end
                inc     a
                ld      (xco), a
                call    dxbody
                ld      a, (xco)        ; put XCO back for whatever follows
                dec     a
                ld      (xco), a
                ret

dxbody:         ld      a, (roomnum)
                cp      START_ROOM
                jr      z, dxdoor
                call    page_bg
                ld      a, (ay)
                sub     12
                ld      (yco), a
                ld      a, (bgtables + T_STAIRS)
                ld      c, BG_STA
                call    bglay

dxdoor:         ld      a, (dy)
                sub     67
                ret     c
                cp      192
                ret     nc
                ld      (blockthr), a
                ld      a, (spreced)
                rrca                    ; the door has risen state/4
                rrca
                and     0x3f
                ld      c, a
                ld      a, (ay)
                sub     14
                sub     c
                ld      (yco), a
dxloop:         call    page_bg
                ld      a, (bgtables + T_DOORMASK)
                ld      c, BG_AND
                call    bglay
                call    page_bg
                ld      a, (bgtables + T_DOOR)
                ld      c, BG_ORA
                call    bglay
                ld      a, (yco)
                sub     4
                ld      c, a
                ld      hl, blockthr
                cp      (hl)
                jr      c, dxtop
                ld      a, c
                ld      (yco), a
                jr      dxloop

dxtop:          ld      a, (ay)         ; part of the C section, really
                sub     64
                ret     c
                cp      192
                ret     nc
                ld      (yco), a
                call    page_bg
                ld      a, (bgtables + T_TOPREPAIR)
                ld      c, BG_STA
                jp      bglay

; The foot of the bars crosses the floor line, where a stamp would cut into
; the floor.  Lay the gate block's own B section back down, and its C and A
; sections with it, so the foot can be ORed over unbroken background.

restorebot:     call    page_bg
                ld      a, BG_GATE
                call    tab_pieceby
                call    bgay
                call    page_bg
                ld      a, BG_GATE
                call    tab_pieceb
                ld      c, BG_STA
                call    bglay
                call    checkc
                call    c, dodrawc
                jp      draw_a

blockthr:       db      0
gatebot:        db      0

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
dfgo:           push    bc              ; C is the opacity and bgentry uses it
                call    page_bg         ; which part of it is solid enough
                ld      a, (objid)      ; to stand in front of him
                ld      hl, bgtables + T_FRONTMX
                call    bgentry
                ld      (frbodyx), a
                ld      a, (objid)
                ld      hl, bgtables + T_FRONTMW
                call    bgentry
                ld      (frbodyw), a
                pop     bc
                ld      a, 1
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

                ld      a, (blockrow)   ; the row below, one block to the left
                cp      2
                jr      nz, sbon
                ld      a, (blockcol)   ; the bottom row looks into the room
                add     a, a            ; underneath, read once already
                ld      l, a
                ld      h, 0
                ld      de, belowrow
                add     hl, de
                jr      sbtake

sbon:           ld      a, (blockcol)
                or      a
                jr      nz, sbhere
                ld      a, (blockrow)   ; and column zero into the one to the
                inc     a               ; left, whose row below this is
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, prevblk
                add     hl, de
sbtake:         ld      a, (hl)
                ld      (below), a
                inc     hl
                ld      a, (hl)
                ld      (sbelow), a
                ret

sbhere:         dec     a
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

; getprev and getbelow: what the rooms next door put into this one's edges.
;
; PRECED for column zero is the rightmost column of the room to the left --
; its wall face hangs over into this one, and a gate in its last column draws
; its bars here -- and the bottom row's C sections come out of the room
; underneath.  With no room that way POP puts a solid block; below, floor.

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
                jp      page_art
rebcnone:       ld      a, BG_BLOCK
                ld      (de), a
                inc     de
                xor     a
                ld      (de), a
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
prevblk:        ds      6
belowrow:       ds      20

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

; getobjid1: a plate that is down is not drawn as the piece the blueprint
; names, and whether it is down is in LINKMAP rather than in the blueprint --
; which is why every read of a block goes through here.  In: A = the masked
; id, C = its state.  Out: A and C = what to draw.  The bank has to be in.

subplate:       cp      BG_PRESSPLATE
                jr      z, spdown
                cp      BG_UPRESSPLATE
                ret     nz
                ld      a, c            ; a plate's state is its link index
                ld      (linkindex), a
                call    gettimer
                cp      2
                ld      a, BG_UPRESSPLATE
                ret     c               ; still up
                ld      c, 0
                ld      a, BG_FLOOR     ; pushed down it is just floor
                ret
spdown:         ld      a, c
                ld      (linkindex), a
                call    gettimer
                cp      2
                ld      a, BG_PRESSPLATE
                ret     c
                ld      a, BG_DPRESSPLATE
                ret

; The room's thirty ids and thirty states, out of the blueprint.

read_room:      call    rr_copy
                ld      b, 30           ; and each of them through getobjid1
                ld      hl, roomids
rrsub:          push    bc
                push    hl
                ld      a, (hl)
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
; The canvas holds the room the Apple's way, seven pixels to a byte on a seven
; pixel boundary; the room wants eight to a byte.  Forty bytes
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
cvleft2:        db      0
cvacc:          db      0
cvbuf:          ds      CANVAS_W
; Eight bytes of seven pixels are exactly seven of eight, so the row divides
; into five of these and nothing is left over.  The art is stored with its
; leftmost pixel already in bit 7 -- see bgexport.py -- so all that is left
; here is to close up the gap bit 0 leaves in every byte: each one written is
; the tail of one source byte and the head of the next.  The tail is carried
; in C from the round before, which is why nothing is read twice.
;
; In: HL = eight source bytes, DE = seven to write.  Out: both past them.

cv8to7:         ld      c, (hl)         ; the first of the eight

                ld      a, c
                and     0xfe
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                and     0x01
                or      b
                ld      (de), a
                inc     de

                ld      a, c
                add     a, a
                and     0xfc
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                and     0x03
                or      b
                ld      (de), a
                inc     de

                ld      a, c
                add     a, a
                add     a, a
                and     0xf8
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                rlca
                and     0x07
                or      b
                ld      (de), a
                inc     de

                ld      a, c
                add     a, a
                add     a, a
                add     a, a
                and     0xf0
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                rlca
                rlca
                and     0x0f
                or      b
                ld      (de), a
                inc     de

                ld      a, c
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                and     0xe0
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                rlca
                rlca
                rlca
                and     0x1f
                or      b
                ld      (de), a
                inc     de

                ld      a, c
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                and     0xc0
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                rlca
                rlca
                rlca
                rlca
                and     0x3f
                or      b
                ld      (de), a
                inc     de

                ld      a, c
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                add     a, a
                and     0x80
                ld      b, a
                inc     hl
                ld      c, (hl)
                ld      a, c
                rlca
                rlca
                rlca
                rlca
                rlca
                rlca
                rlca
                and     0x7f
                or      b
                ld      (de), a
                inc     de

                inc     hl              ; past the eighth
                ret



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
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; five bytes to an entry
                ld      de, frontlist
                add     hl, de
                ld      a, (xco)        ; where it went, which part of it is
                ld      (hl), a         ; solid, and how tall it is
                inc     hl
                ld      a, (yco)
                ld      (hl), a
                inc     hl
                ld      a, (frbodyx)
                ld      (hl), a
                inc     hl
                ld      a, (frbodyw)
                ld      (hl), a
                inc     hl
                ld      a, (imgh)
                ld      (hl), a
                ld      hl, nfront
                inc     (hl)
                ret

frbodyx:        db      0
frbodyw:        db      0

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

recfront:       db      0
nfront:         db      0
fleft:          db      0
fptr:           dw      0
fmrow:          dw      0
frow:           db      0
frows:          db      0
fx0:            dw      0
fpx:            db      0
frontlist:      ds      MAXFRONT * 4

; ---------------------------------------------------------------- the floor
;
; DRAWFLOOR and DRAWHALF: the floorpieces POP lays back over a character who
; is falling, hanging or climbing.  What they cover is not the pixels they
; light -- an AND covers what it clears and an STA the whole of its rectangle
; -- so the same passes are run again with the pieces going into a mask.
;
; Only the fifteen rows of each floor band are kept, which is where the
; perspective wedge is; floorband already says which row of the mask a
; scanline is, or -1.  Two masks: the whole piece, and the shorter one
; climbing up uses, which leaves the hands on the ledge showing.

FLOORCAN        equ     CANVAS + CANVAS_W * 192
HALFCAN         equ     FLOORCAN + CANVAS_W * 45

; The tiles that have a half piece in the dungeon set.  Anything else falls
; back to the whole floorpiece, exactly as FRAMEADV.S does.

halfpiece:      ld      a, (objid)
                cp      BG_FLOOR
                ret     z
                cp      BG_TORCH
                ret     z
                cp      BG_DPRESSPLATE
                ret     z
                cp      BG_EXIT
                ret

; One block's floorpiece, into whichever mask is in hand.

floorpiece:     ld      a, (preced)     ; drawfloor and drawhalf both begin
                or      a               ; here: the wedge is the near edge of
                ret     nz              ; a floor, and a floor that runs on
                call    page_bg         ; into this one has no near edge
                ld      a, (bgmask)
                dec     a
                jr      z, fpwhole      ; the first mask is the whole piece
                call    halfpiece
                jr      nz, fpwhole
                ld      a, (ay)         ; CUmask and CUpiece, the short one
                ld      c, a
                ld      a, (objid)
                cp      BG_DPRESSPLATE
                ld      a, c
                jr      nz, fpcu
                inc     a               ; POP's own quick trick for a plate
fpcu:           ld      (yco), a
                ld      a, (bgtables + T_CUMASK)
                ld      c, BG_AND
                call    bglay
                call    page_bg
                ld      a, (ay)
                ld      (yco), a
                ld      a, (bgtables + T_CUPIECE)
                ld      c, BG_ORA
                call    bglay
                jp      draw_d

fpwhole:        ld      a, (objid)      ; addamask, then adda
                call    tab_maska
                or      a
                jr      z, fpa
                ld      c, a
                ld      a, (ay)
                ld      (yco), a
                ld      a, c
                ld      c, BG_AND
                call    bglay
                call    page_bg
fpa:            ld      a, (objid)
                cp      BG_LOOSE
                jr      nz, fppiece
                call    loose_y
                ld      hl, bgtables + T_LOOSEA
                call    bgentry
                jr      fpgo
fppiece:        call    tab_piecea
fpgo:           or      a
                jr      z, fpd
                ld      c, a
                ld      a, (objid)
                push    bc
                call    tab_pieceay
                call    bgay
                pop     bc
                ld      a, c
                ld      c, BG_ORA
                call    bglay
                call    page_bg
fpd:            jp      draw_d

; Both masks, made and repacked.

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

onemask:        ld      (bgmask), a
                call    page_canvas
                dec     a
                ld      hl, FLOORCAN
                jr      z, om1
                ld      hl, HALFCAN
om1:            ld      d, h
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

; Forty five rows of forty Apple bytes into forty five of thirty five.

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
bgmask:         db      0

; ---------------------------------------------------------------- next room
;
; A level is twenty four rooms and the blueprint says which is which way: the
; four bytes at MAP are the room to the left, to the right, above and below,
; and a zero means there is nothing there.  Walking off an edge takes him to
; the room on that side, and everything about the new one -- its picture, its
; three masks, its torches -- is made on the way in.

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

; He is at one end of the room or the other, and there is a room that way.

nextroom:       jp      cutchar

; The rooms stack 189 scanlines apart -- the bottom of the row below the
; screen against the bottom of the top row of the next one -- so falling
; through takes that off his height and puts him on the top row.

; CUT in AUTO.S: three block rows and 189 scanlines, whichever way he went.

nrup:           ld      a, (links + 2)
                or      a
                ret     z
                ld      (roomnum), a
                ld      a, (chary)
                add     a, 189
                ld      (chary), a
                ld      a, (blocky)
                add     a, 3
                ld      (blocky), a
                jp      nrgo

nrdown:         ld      a, (links + 3)
                or      a
                ret     z
                ld      (roomnum), a
                ld      a, (chary)
                sub     189
                ld      (chary), a
                ld      a, (blocky)
                sub     3
                ld      (blocky), a
                jp      nrgo

; CUTCHAR in AUTO.S.  A cut is not a matter of getting near the edge: the
; picture itself has to have left the screen, by four of POP's units -- eight
; pixels -- past the side he is walking off.  Which edge counts depends on
; which way he faces, because the far one is still on screen.
;
; ScrnLeft is 58 and ScrnRight 197 in POP's 140 wide space, so LeftCutEdge
; and RightCutEdge come out at -8 and 286 in the room's own 280.

CUTLEFTX        equ     -8
CUTRIGHTX       equ     286

; The vertical cut is not "his block row has changed", it is how far his
; coordinate has gone past the screen -- TopCutEdge and BotCutEdge in AUTO.S,
; ten pixels above the top and twenty four below the bottom.  Cutting on the
; row instead took the screen away the instant the floor let go, so the fall
; was never seen at all.

TOPCUTPL        equ     10
TOPCUTMI        equ     240             ; ScrnTop - 16, as a byte
BOTCUT          equ     215             ; ScrnBottom + 24

cutchar:        ld      a, (charact)    ; falling: only the bottom counts
                cp      3
                jr      z, ccnotup
                cp      4
                jr      z, ccnotup
                cp      5
                jr      z, ccnotup
                ld      a, (chary)
                cp      TOPCUTPL
                jp      c, nrup
                cp      TOPCUTMI
                jp      nc, nrup
ccnotup:        ld      a, (chary)
                cp      BOTCUT
                jp      nc, nrdown

                ld      a, (charact)    ; not while he turns
                cp      7
                ret     z
                ld      a, (frame)      ; nor part way through a stand up, a
                cp      110             ; climb, or a sword stroke
                jr      c, cc1
                cp      120
                ret     c
cc1:            cp      135
                jr      c, cc2
                cp      163
                ret     c
                cp      166
                jr      c, cc2
                cp      169
                ret     c

cc2:            call    char_edges
                ld      a, (facing)
                or      a
                jr      nz, ccright

                ld      hl, (edgel)     ; facing left: his left edge decides
                ld      de, CUTLEFTX + 1
                call    cmp16
                jp      c, nrleft
                ld      hl, (edgel)
                ld      de, 280
                call    cmp16
                jp      nc, nrright
                ret

ccright:        ld      hl, (edger)     ; facing right: his right one
                ld      de, CUTRIGHTX
                call    cmp16
                jr      c, ccnotr
                call    panelahead      ; a panel across the way blocks the
                jp      nc, nrright     ; view, and POP does not cut through it
ccnotr:         ld      hl, (edger)
                ld      de, 0
                call    cmp16
                jp      c, nrleft
                ret

; Carry set if the last block of his row is a panel.

panelahead:     ld      a, (blocky)
                cp      3
                ccf
                ret     nc
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten blocks to the row
                ld      de, roomids + 9
                add     hl, de
                ld      a, (hl)
                cp      BG_PANELWIF
                scf
                ret     z
                cp      BG_PANELWOF
                scf
                ret     z
                or      a
                ret

; HL - DE as signed numbers.  Out: carry set if HL is the smaller.

cmp16:          or      a
                sbc     hl, de
                ld      a, h
                rlca
                ret

; GETEDGES: where his picture actually starts and ends, which is what a cut
; is measured against.  The frame table says how wide it is and how far the
; anchor sits from its leading edge.

char_edges:     call    page_canvas
                call    frame_entry
                ld      a, (hl)
                ld      c, a            ; width in bytes
                inc     hl
                inc     hl              ; past the height
                ld      a, (facing)
                or      a
                jr      z, ce1
                inc     hl
ce1:            ld      a, (hl)         ; the anchor offset, signed
                ld      b, a            ; page_art leaves the bank number in
                call    page_art        ; A, which is where the 22 came from
                ld      a, b
                ld      e, a
                ld      d, 0
                or      a
                jp      p, ce2
                dec     d
ce2:            ld      hl, (charx)
                add     hl, de
                ld      (edgel), hl
                ld      a, c            ; seven pixels to an Apple byte, not
                add     a, a            ; eight: the picture is narrower than
                add     a, a            ; the buffer it is stored in
                add     a, a
                sub     c
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (edger), hl
                ret

edgel:          dw      0
edger:          dw      0

; CUT: a whole screen's width sideways, three block rows and 189 scanlines up
; or down.

nrleft:         ld      a, (links)
                or      a
                ret     z
                ld      (roomnum), a
                ld      hl, (charx)
                ld      de, 280
                add     hl, de
                ld      (charx), hl
                jp      nrgo
nrright:        ld      a, (links + 1)
                or      a
                ret     z
                ld      (roomnum), a
                ld      hl, (charx)
                ld      de, -280
                add     hl, de
                ld      (charx), hl

nrgo:           call    newroom         ; the room and everything about it
                call    readlinks
                call    camhome         ; the view is already where he is
                xor     a
                ld      (oldw), a
                call    repaint
                call    set_attrs
                ret

links:          ds      4

; ---------------------------------------------------------------- one block
;
; RedBlockSure for a single block, which is what a loose floor, a gate or a
; pressplate wants while the game is running: they change one block and the
; room has to follow without being built again.
;
; The block's own four columns of the canvas are wiped and its five passes
; run again -- everything that writes into those columns belongs to this
; block, since drawc and drawb draw the piece to the LEFT but at the current
; block's column -- and then the bytes that changed are repacked.
;
; In: (blockrow), (blockcol).

redblock:       ld      a, (blockrow)
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, blockbot
                add     hl, de
                ld      a, (hl)
                ld      (dy), a
                sub     3
                ld      (ay), a

                ld      a, (blockcol)   ; the piece to its left, for drawc
                or      a               ; and drawb
                jr      nz, rbleft
                ld      a, (blockrow)   ; column zero takes it from the room
                add     a, a            ; to the left, the way compose does
                ld      l, a
                ld      h, 0
                ld      de, prevblk
                add     hl, de
                ld      a, (hl)
                ld      (preced), a
                inc     hl
                ld      a, (hl)
                ld      (spreced), a
                jr      rbwipe
rbleft:         dec     a
                ld      c, a
                ld      a, (blockrow)
                ld      b, a
                call    blockat
                ld      hl, (blockptr)
                ld      a, (hl)
                and     0x1f
                ld      (preced), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (spreced), a

                ld      a, (redh)       ; the band, for the wipe, the five
                ld      b, a            ; passes and the repack alike -- what
                ld      a, (dy)         ; falls outside it is redrawn exactly
                ld      (bandbot), a    ; as it was, so leaving it alone is
                sub     b               ; the same picture for a third of the
                inc     a               ; work
                ld      (bandtop), a

rbwipe:         ld      a, (blockcol)   ; four bytes to a block
                add     a, a
                add     a, a
                ld      (xco), a
                call    page_canvas
                ld      a, (dy)
                ld      (rbrow), a
                ld      a, (redh)
                ld      b, a
rbwipe1:        push    bc
                ld      a, (rbrow)
                cp      192
                jr      nc, rbwipe2
                call    canvasrow
                ld      a, (xco)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
                inc     hl
                ld      (hl), 0
rbwipe2:        ld      hl, rbrow
                dec     (hl)
                pop     bc
                djnz    rbwipe1

                call    setblock        ; and lay it down again
                call    draw_c
                call    draw_mc
                call    draw_b
                call    draw_mb
                call    draw_d
                call    draw_md
                call    draw_a
                call    draw_front

; The groups of eight Apple bytes that cover it, repacked into the room.  A
; block starts on a multiple of four, so it is either the first half of a
; group or the second, and one group either side takes in whatever a piece
; spilled.

                ld      a, (blockcol)   ; the one group of eight Apple bytes
                srl     a               ; that holds the block: four bytes to
                ld      (rbgroup), a    ; a block, eight to a group, so it is
                                        ; always the column halved
                ld      a, (redh)       ; only the band that changed goes
                ld      b, a            ; back into the room: the rest of the
                ld      a, (dy)         ; block was redrawn the same as it was
                sub     b
                inc     a
                jr      nc, rbtop
                xor     a
rbtop:          ld      (rbrow), a
                ld      a, (redh)
                ld      (rbleftn), a
rbline:         ld      a, (rbrow)
                cp      192
                jr      nc, rbnext

                call    page_canvas
                ld      a, (rbrow)
                call    canvasrow
                ld      a, (rbgroup)    ; eight bytes to a group
                add     a, a
                add     a, a
                add     a, a
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      de, cvbuf
                ld      bc, 8
                ld      a, (redwide)
                or      a
                jr      z, rbone
                ld      c, 16
rbone:          ldir

                call    page_art
                ld      a, (rbrow)
                call    mul35
                ld      de, room
                add     hl, de
                ld      a, (rbgroup)    ; seven bytes out to a group
                ld      c, a
                add     a, a
                add     a, a
                add     a, a
                sub     c
                ld      e, a
                ld      d, 0
                add     hl, de
                ex      de, hl
                ld      hl, cvbuf
                call    cv8to7
                ld      a, (redwide)    ; a piece that reaches past its own
                or      a               ; block wants the next group too
                jr      z, rbnext
                call    cv8to7

rbnext:         ld      hl, rbrow
                inc     (hl)
                ld      hl, rbleftn
                dec     (hl)
                jp      nz, rbline
                xor     a               ; the next whole room wants them all
                ld      (bandtop), a
                ld      a, 191
                ld      (bandbot), a
                call    redshow         ; and on to the screen
                xor     a
                ld      (redwide), a
                ret

redwide:        db      0

rbrow:          db      0
rbleftn:        db      0
rbgroup:        db      0

; ------------------------------------------------------- gates and pressplates
;
; MOVER.S.  Standing on a pressplate puts it down for a count and triggers
; whatever the level says it is wired to; a gate so triggered rises, waits at
; the top and comes back down, and a plate under a raised gate lets it fall.
; The wiring is two tables in the blueprint: LINKLOC holds a block and two
; bits of a room number, LINKMAP the other three bits and the plate's count,
; and a flag in LINKLOC ends the chain, so one plate can work several gates.
;
; Everything part way through an animation is on the trans list along with the
; room it is in, because a gate goes on opening after the view has left that
; room.  That is also why an object's state lives in the blueprint rather than
; in the room's own copy of it: the copy is only what is being drawn.

MAXTR           equ     6
PPTIMER         equ     5
; How deep a redraw each of them reaches.  POP's loosewipe is 31, but that is
; an erase height that has to take a character with it; what actually changes
; between a loose floor's frames is fifteen rows up from Dy, measured over all
; ten of the falling states and all four of the wiggling ones.  A gate's bars
; fill the whole B section, so that one keeps the lot.
LOOSEWIPE       equ     16
PLATEWIPE       equ     16
GATETIMER       equ     238
MAXGATEVEL      equ     8
LINKLOC         equ     level + 1440
LINKMAP         equ     level + 1696

; A = a room (1..24), C = one of its thirty blocks.  Out: HL = its type byte
; in the blueprint; its state is 720 further on.  The bank has to be in.

bluepos:        dec     a
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
                ret

; The object the trans list is pointing at.  Out: A = its id, (trobst) = its
; state, (blueptr) on its type byte.  Leaves the background bank in.

trobat:         call    page_bg
                ld      a, (trloc)
                ld      c, a
                ld      a, (trscrn)
                call    bluepos
                ld      (blueptr), hl
                ld      de, 720
                add     hl, de
                ld      a, (hl)
                ld      (trobst), a
                ld      hl, (blueptr)
                ld      a, (hl)
                and     0x1f
                ret

; Put (trobst) back, and into the room's own copy if that room is the one on
; screen -- the drawing reads the copy, not the blueprint.

trobsave:       call    page_bg
                ld      hl, (blueptr)
                ld      de, 720
                add     hl, de
                ld      a, (trobst)
                ld      (hl), a
                call    onscreen
                ret     nz
                ld      hl, (blueptr)
                ld      a, (hl)
                and     0x1f
                push    af
                ld      a, (trobst)
                ld      c, a
                pop     af
                call    subplate
                ld      b, a
                ld      a, (trloc)
                ld      l, a
                ld      h, 0
                ld      de, roomids
                add     hl, de
                ld      (hl), b
                ld      de, 30
                add     hl, de
                ld      (hl), c
                ret

; A = a new id for it, the same two places.

trobtype:       ld      c, a
                call    page_bg
                ld      hl, (blueptr)
                ld      (hl), c
                call    onscreen
                ret     nz
                ld      a, (trloc)
                ld      l, a
                ld      h, 0
                ld      de, roomids
                add     hl, de
                ld      (hl), c
                ret

onscreen:       ld      a, (trscrn)     ; Z if this object is in the room the
                ld      hl, roomnum     ; view is showing
                cp      (hl)
                ret

; LINKLOC and LINKMAP, one entry per link, indexed by (linkindex).

llocat:         ld      a, (linkindex)
                ld      l, a
                ld      h, 0
                ld      de, LINKLOC
                add     hl, de
                ret

lmapat:         ld      a, (linkindex)
                ld      l, a
                ld      h, 0
                ld      de, LINKMAP
                add     hl, de
                ret

gettimer:       call    lmapat
                ld      a, (hl)
                and     0x1f
                ret

chgtimer:       and     0x1f            ; in: A = the new count
                ld      c, a
                call    lmapat
                ld      a, (hl)
                and     0xe0
                or      c
                ld      (hl), a
                ret

getloc:         call    llocat
                ld      a, (hl)
                and     0x1f
                ret

getlast:        call    llocat
                ld      a, (hl)
                and     0x80
                ret

getscrn:        call    llocat          ; two bits of the room here, three in
                ld      a, (hl)         ; the map
                and     0x60
                rrca
                rrca
                ld      c, a
                call    lmapat
                ld      a, (hl)
                and     0xe0
                add     a, c
                rrca
                rrca
                rrca
                and     0x1f
                ret

; ---- the list itself ----
;
; Is (trloc, trscrn) on it already?  Out: carry set and C = where.

searchtrob:     ld      a, (numtrans)
                or      a
                ret     z
                ld      b, a
                ld      c, 0
sto1:           push    bc
                ld      a, c
                ld      l, a
                ld      h, 0
                ld      de, trlocs
                add     hl, de
                ld      a, (trloc)
                cp      (hl)
                jr      nz, sto2
                ld      de, trscrns - trlocs
                add     hl, de
                ld      a, (trscrn)
                cp      (hl)
                jr      nz, sto2
                pop     bc
                scf
                ret
sto2:           pop     bc
                inc     c
                djnz    sto1
                or      a
                ret

; In: trdirec, trloc, trscrn.  Already listed means only a change of direction.

addtrob:        call    searchtrob
                jr      c, atchange
                ld      a, (numtrans)
                cp      MAXTR
                ret     nc              ; too many at once: the trigger fails
                ld      c, a
                inc     a
                ld      (numtrans), a
                ld      a, c
                ld      l, a
                ld      h, 0
                ld      de, trlocs
                add     hl, de
                ld      a, (trloc)
                ld      (hl), a
                ld      de, trscrns - trlocs
                add     hl, de
                ld      a, (trscrn)
                ld      (hl), a
atdirec:        ld      de, trdirecs - trscrns
                add     hl, de
                ld      a, (trdirec)
                ld      (hl), a
                ret
atchange:       ld      a, c
                ld      l, a
                ld      h, 0
                ld      de, trscrns
                add     hl, de
                jr      atdirec

stopobj:        ld      a, 0xff
                ld      (trdirec), a
                ret

; C = an entry.  Load it into the three the routines work on, or save the
; direction back into it.

trload:         ld      l, c
                ld      h, 0
                ld      de, trlocs
                add     hl, de
                ld      a, (hl)
                ld      (trloc), a
                ld      de, trscrns - trlocs
                add     hl, de
                ld      a, (hl)
                ld      (trscrn), a
                ld      de, trdirecs - trscrns
                add     hl, de
                ld      a, (hl)
                ld      (trdirec), a
                ret

trdsave:        ld      l, c
                ld      h, 0
                ld      de, trdirecs
                add     hl, de
                ld      a, (trdirec)
                ld      (hl), a
                ret

; ---- what puts things on it ----
;
; CHECKPRESS in CTRL.S: on the ground with his foot on the floor, whatever is
; under it is read, and a plate is pushed or a loose floor broken.

checkpress:     ld      a, (frame)      ; hanging from a plate presses it
                cp      87              ; just as well as standing on it
                jr      c, cpnothang
                cp      100
                jr      c, cphang       ; 87..99, hanging from a jump
                cp      135
                jr      c, cpnothang
                cp      141
                jr      c, cphang       ; 135..140, climbing up or down
cpnothang:      ld      a, (charact)
                cp      7               ; turning
                jr      z, cpground
                cp      5               ; bumped
                jr      z, cpground
                cp      2
                ret     nc
cpground:       ld      a, (frame)
                cp      79              ; jumping up to touch the ceiling
                jr      z, cpceil
                ld      l, a            ; is his foot on the floor at all
                ld      h, 0
                ld      de, fcheck
                add     hl, de
                ld      a, (hl)
                and     F_CHECK
                ret     z
                xor     a               ; the block he stands on
                jr      cpwhere
cpceil:         ld      a, 2            ; and up there, only a floor counts
                jr      cpwhere
cphang:         ld      a, 1            ; the block he has hold of
cpwhere:        ld      (cpabove), a
                call    base_x          ; and which block it is on
                call    blockcol_of
                cp      10
                ret     nc              ; -2..-1 come back as 254..255
                ld      c, a
                ld      a, (blocky)
                ld      b, a
                ld      a, (cpabove)
                or      a
                jr      z, cprow
                dec     b
cprow:          ld      a, b
                cp      3
                ret     nc              ; and off the screen is nothing
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten blocks to the row
                ld      a, l
                add     a, c
                ld      (trloc), a
                ld      a, (roomnum)
                ld      (trscrn), a

                call    trobat
                ld      b, a
                ld      a, (cpabove)
                cp      2
                ld      a, b
                jr      z, cploose      ; touching the ceiling breaks a floor
                cp      BG_UPRESSPLATE  ; but pushes nothing
                jp      z, pushpp
                cp      BG_PRESSPLATE
                jp      z, pushpp
cploose:        cp      BG_LOOSE
                ret     nz

; BREAKLOOSE: it only starts once, and then animfloor has it.

breakloose:     ld      a, (trobst)
                or      a
                ret     nz
                ld      a, 1
                ld      (trobst), a
                call    trobsave
                xor     a               ; down
                ld      (trdirec), a
                call    addtrob
                ld      a, LOOSEWIPE
                ld      (redh), a
                jp      redplate

; SHAKELOOSE in TOPCTRL.S and SHAKEM in MOVER.S.  A loose floor that is only
; jarred wiggles for a few frames and settles again: its state carries bit 7
; and counts in the low bits, which is how getloosey tells the two apart.

WIGGLETIME      equ     4

shakeloose:     ld      a, (jarabove)
                or      a
                ret     z
                ld      b, a
                xor     a
                ld      (jarabove), a
                ld      a, (blocky)
                bit     7, b
                jr      nz, slrow       ; jard: the row he is on
                dec     a               ; jaru: the one above it
slrow:          cp      3
                ret     nc
                ld      (slrow2), a
                ld      a, (roomnum)
                ld      (trscrn), a
                ld      a, 9
                ld      (slcol), a
slloop:         ld      a, (slrow2)
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl
                add     hl, de          ; ten blocks to the row
                ld      a, (slcol)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      a, l
                ld      (trloc), a
                call    trobat
                cp      BG_LOOSE
                call    z, shakeit
                ld      hl, slcol
                ld      a, (hl)
                or      a
                ret     z
                dec     (hl)
                jr      slloop

shakeit:        ld      a, (trobst)     ; already going, or on its way down
                or      a
                ret     nz
                ld      a, 0x80
                ld      (trobst), a
                call    trobsave
                ld      a, 1
                ld      (trdirec), a
                call    addtrob
                ld      a, LOOSEWIPE
                ld      (redh), a
                jp      redplate

slrow2:         db      0
slcol:          db      0
cpabove:        db      0

; PUSHPP: the plate's own state is its index into the link tables.

pushpp:         ld      (pptype), a
                ld      a, (trobst)
                ld      (linkindex), a
                call    gettimer
                cp      31
                ret     z               ; this one is down for good
                cp      2
                jr      nc, ppagain     ; down already: restart the count
                ld      a, PPTIMER
                call    chgtimer
                ld      a, 1
                ld      (trdirec), a
                call    addtrob
                call    trobsave        ; so the copy shows it pushed down
                ld      a, PLATEWIPE
                ld      (redh), a
                call    redplate
                jp      trigger
ppagain:        ld      a, PPTIMER
                call    chgtimer
                jp      trigger

; And what the plate is wired to.  The chain runs on until an entry has the
; last flag set.

trigger:        call    page_bg
trigl:          call    llocat
                ld      a, (hl)
                cp      0xff
                ret     z               ; wired to nothing
                call    getloc
                ld      (trloc), a
                call    getscrn
                ld      (trscrn), a
                call    trobat
                call    trigobj
                ld      a, (trdirec)
                and     0x80
                jr      nz, trignext    ; the trigger failed
                call    addtrob
trignext:       call    page_bg
                call    getlast
                ld      c, a
                ld      hl, linkindex
                inc     (hl)
                ld      a, c
                or      a
                jr      z, trigl
                ret

trigobj:        cp      BG_GATE
                jr      z, triggate
                cp      BG_EXIT
                ret     nz
                ld      a, (trobst)     ; an exit only ever opens
                or      a
                jp      nz, stopobj
                ld      a, 1
                ld      (trdirec), a
                ret

; A plate lowers a gate, one that springs back up raises it, and rubble --
; a plate crushed under a falling slab -- opens it and jams it there.

triggate:       ld      a, (pptype)
                cp      BG_UPRESSPLATE
                jr      z, tgraise
                cp      BG_RUBBLE
                jr      z, tgjam

                ld      a, (trobst)     ; down, unless it is down already
                or      a
                jp      z, stopobj
                ld      a, 3            ; down fast
                ld      (trdirec), a
                ret

tgjam:          ld      a, 2
                ld      (trdirec), a
                ld      a, (trobst)
                cp      GMAXVAL
                ret     c
                ld      a, 0xff         ; at the top already: jam it there
                ld      (trobst), a
                call    trobsave
                jp      stopobj

tgraise:        ld      a, 1
                ld      (trdirec), a
                ld      a, (trobst)
                cp      0xff
                jp      z, stopobj      ; jammed open
                cp      GMAXVAL
                ret     c
                ld      a, GATETIMER    ; up already: start the wait again
                ld      (trobst), a
                call    trobsave
                jp      stopobj

; ---- one step of everything on the list ----

animtrans:      ld      a, (numtrans)
                or      a
                ret     z
                ld      b, a
                ld      c, 0
antl:           push    bc
                call    trload
                call    animobj
                pop     bc
                push    bc
                call    trdsave
                pop     bc
                inc     c
                djnz    antl

; and drop whatever has stopped, closing the list up over it

                xor     a
                ld      (tcsrc), a
                ld      (tcdst), a
tcl:            ld      a, (tcsrc)
                ld      hl, numtrans
                cp      (hl)
                jr      nc, tcdone
                ld      l, a
                ld      h, 0
                ld      de, trdirecs
                add     hl, de
                ld      a, (hl)
                cp      0xff
                jr      z, tcskip
                ld      a, (tcsrc)
                ld      c, a
                call    trload
                ld      a, (tcdst)
                ld      c, a
                call    trstore
                ld      hl, tcdst
                inc     (hl)
tcskip:         ld      hl, tcsrc
                inc     (hl)
                jr      tcl
tcdone:         ld      a, (tcdst)
                ld      (numtrans), a
                ret

trstore:        ld      l, c
                ld      h, 0
                ld      de, trlocs
                add     hl, de
                ld      a, (trloc)
                ld      (hl), a
                ld      de, trscrns - trlocs
                add     hl, de
                ld      a, (trscrn)
                ld      (hl), a
                ld      de, trdirecs - trscrns
                add     hl, de
                ld      a, (trdirec)
                ld      (hl), a
                ret

; The object in hand: work out what it is, move it on, put the state back and
; only then redraw, because the drawing reads the room's copy of the state.

animobj:        xor     a               ; nothing wants redrawing yet -- and
                ld      (redwant), a    ; this has to be before the dispatch,
                call    trobat          ; which jumps past anything after it
                ld      (aoid), a
                cp      BG_GATE
                jr      z, aogate
                cp      BG_UPRESSPLATE
                jr      z, aoplate
                cp      BG_PRESSPLATE
                jr      z, aoplate
                cp      BG_LOOSE
                jr      z, aofloor
                cp      BG_EXIT
                jr      z, aoexit
                cp      BG_SPACE
                jr      z, aodone       ; the floor that was here has gone
                jp      stopobj         ; none of these: off the list

; The bars are drawn at state/4, clamped, so most of a gate's life changes
; nothing to look at: fifty frames waiting at the top with the state above
; GMAXVAL, and a descent of one unit a frame that moves them every fourth.
; Redrawing all of that was the slowdown that lasted until he left the room.

aogate:         ld      a, (trobst)
                call    gatedrawn
                ld      (agwas), a
                call    animgate
                ld      a, (trobst)
                call    gatedrawn
                ld      hl, agwas
                cp      (hl)
                jr      nz, aodone
                xor     a               ; the bars are where they were
                ld      (redwant), a
                jr      aodone

gatedrawn:      cp      GMAXVAL
                jr      c, gdr1
                ld      a, GMAXVAL
gdr1:           rrca
                rrca
                and     0x3f
                ret

agwas:          db      0
aoplate:        call    animplate
                jr      aodone
aoexit:         call    animexit
                jr      aodone
aofloor:        call    animfloor

aodone:         call    trobsave
                ld      a, (redwant)    ; a plate that is only counting down
                or      a               ; looks no different from one that is
                ret     z               ; not, and a redraw is not cheap
                ld      a, (aoid)
                cp      BG_GATE
                jp      z, redgate
                cp      BG_EXIT
                jp      z, redright
                jp      redplate

redwant:        db      0

; A gate rises four pixels a frame, waits at the top while GATETIMER counts
; down through the states above GMAXVAL, and then falls under gatevel.

animgate:       ld      a, 1
                ld      (redwant), a
                ld      a, 63           ; the bars fill the whole B section
                ld      (redh), a
                ld      a, (trdirec)
                and     0x80
                ret     nz              ; stopped: only the redraw is left
                ld      a, (trdirec)
                cp      3
                jr      nc, agfast

                ld      a, (trobst)
                cp      0xff
                jp      z, stopobj      ; jammed open
                ld      c, a
                ld      a, (trdirec)
                ld      l, a
                ld      h, 0
                ld      de, gateinc
                add     hl, de
                ld      a, c
                add     a, (hl)
                ld      (trobst), a

                ld      a, (trdirec)
                or      a
                jr      z, agdown
                ld      a, (trobst)     ; going up
                cp      GMAXVAL
                ret     c
                ld      a, (trdirec)    ; at the top: jam, or wait and fall
                cp      2
                jr      c, agwait
                ld      a, 0xff
                ld      (trobst), a
                jp      stopobj
agwait:         ld      a, GATETIMER
                ld      (trobst), a
                xor     a
                ld      (trdirec), a
                ret

agdown:         ld      a, (trobst)     ; all the way down is the end of it
                or      a
                ret     nz
                jp      stopobj

agfast:         ld      a, (trdirec)    ; trdirec is an index into gatevel
                cp      MAXGATEVEL
                jr      nc, agf1
                inc     a
                ld      (trdirec), a
agf1:           ld      l, a
                ld      h, 0
                ld      de, gatevel
                add     hl, de
                ld      a, (trobst)
                sub     (hl)
                ld      (trobst), a
                ret     z
                ret     nc
                xor     a               ; it hit the floor
                ld      (trobst), a
                jp      stopobj

; The exit door only ever opens, and stops when it is all the way up.

animexit:       ld      a, 1
                ld      (redwant), a
                ld      a, 63
                ld      (redh), a
                ld      a, (trdirec)
                and     0x80
                ret     nz
                ld      a, (trobst)
                add     a, EXITINC
                ld      (trobst), a
                cp      EMAXVAL
                ret     c
                ld      a, 1            ; open for good: the way out of here
                ld      (exitopen), a
                jp      stopobj

exitopen:       db      0

; A plate stays down while its count runs out, and the count is in LINKMAP.

animplate:      ld      a, (trdirec)
                and     0x80
                ret     nz
                ld      a, (trobst)
                ld      (linkindex), a
                call    page_bg
                call    gettimer
                dec     a
                push    af
                call    chgtimer
                pop     af
                cp      2
                ret     nc              ; the count stops at one
                ld      a, 1            ; and only now does it look different
                ld      (redwant), a
                ld      a, PLATEWIPE
                ld      (redh), a
                jp      stopobj

; A loose floor shakes for Ffalling frames and then is not there any more.

animfloor:      ld      a, 1            ; it shakes every frame
                ld      (redwant), a
                ld      a, LOOSEWIPE
                ld      (redh), a
                ld      a, (trdirec)
                and     0x80
                ret     nz
                ld      a, (trobst)
                inc     a
                ld      (trobst), a
                bit     7, a
                jr      nz, afwiggle
                cp      BG_FFALLING
                ret     c
                ld      a, BG_SPACE     ; time it went
                call    trobtype
                xor     a
                ld      (trobst), a
                ld      hl, aoid        ; and it is space that gets redrawn
                ld      (hl), a
                jp      stopobj

afwiggle:       cp      0x80 + WIGGLETIME
                ret     c
                xor     a               ; jarred, not broken: it settles
                ld      (trobst), a
                jp      stopobj

; ---- putting the change on the screen ----
;
; Only if the object is in the room the view is showing.  A plate or a floor
; takes its own block and the one to its right, whose B section it is; a gate
; takes the block to its right, where the bars hang, and the one above that,
; where the top of them pokes through.

redplate:       call    onscreen
                ret     nz
                call    trrowcol
                call    page_art
                call    redblock
                ld      a, (blockcol)
                cp      9
                ret     nc
                inc     a
                ld      (blockcol), a
                jp      redblock

; The exit's stairs and door are all in the block to its right.

redright:       call    onscreen
                ret     nz
                call    trrowcol
                ld      a, (blockcol)
                cp      9
                ret     nc
                inc     a
                ld      (blockcol), a
                ld      a, 1            ; the door is forty two pixels wide
                ld      (redwide), a    ; and stands a byte in, so it reaches
                call    page_art        ; into the block after this one
                jp      redblock

; CHECKRIGHT in CTRLSUBS.S marks the block to the right, and that block may
; be in the room next door -- which is where four of level one's five gates
; keep their bars.  Asking whether the GATE's room is on screen was therefore
; the wrong question: the room to watch is the one the bars are drawn in.

redgate:        call    trrowcol
                ld      a, (blockcol)
                cp      9
                jr      nc, rgnext      ; the bars hang in the next room along
                inc     a
                ld      (blockcol), a
                call    onscreen
                ret     nz
                jr      rgdraw

rgnext:         call    page_bg         ; the room to its right, if there is
                ld      a, (trscrn)     ; one, and if that is the one we see
                dec     a
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      de, level + 1952 + 1
                add     hl, de
                ld      a, (hl)
                ld      b, a            ; page_art hands back the bank number
                call    page_art        ; in A, so the answer goes aside
                ld      a, b
                or      a
                ret     z
                ld      hl, roomnum
                cp      (hl)
                ret     nz
                xor     a               ; its leftmost column
                ld      (blockcol), a

rgdraw:         call    page_art
                call    redblock
                ld      a, (blockrow)
                or      a
                ret     z
                dec     a
                ld      (blockrow), a
                jp      redblock

trrowcol:       ld      a, (trloc)      ; thirty blocks, ten to the row
                ld      c, 0
trrc1:          cp      10
                jr      c, trrc2
                sub     10
                inc     c
                jr      trrc1
trrc2:          ld      (blockcol), a
                ld      a, c
                ld      (blockrow), a
                ret

numtrans:       db      0
trlocs:         ds      MAXTR
trscrns:        ds      MAXTR
trdirecs:       ds      MAXTR
trloc:          db      0
trscrn:         db      0
trdirec:        db      0
trobst:         db      0
aoid:           db      0
linkindex:      db      0
pptype:         db      0
blueptr:        dw      0
tcsrc:          db      0
tcdst:          db      0
gateinc:        db      -1, 4, 4
gatevel:        db      0, 0, 0, 20, 40, 60, 80, 100, 120
