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
BG_MASK         equ     3               ; POP's mask: a pixel's halo cleared

page_bg:        ld      a, BANK_BG
                jp      pageset

page_canvas:    ld      a, BANK_CANVAS
                jp      pageset

; The canvas's own pixels are not in the canvas bank: the second screen took
; the bottom of it, and they went to the bank the last sprites leave half
; empty -- and the two floorpiece masks with them, so that the canvas bank
; keeps only what the control code reads while it runs.

page_pixels:    ld      a, BANK_CVS
                jp      pageset

; Whichever bgdraw is laying into -- the picture or one of the masks, which
; are in the one bank now.

page_target     equ     page_pixels

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
; Which of its rows land in the band.  The first stored row goes down on
; YCO and the rest climb, so row k is on line YCO - k: the rows below the
; band -- or below the screen -- are k < YCO - bottom, those above it
; k > YCO - top.  Only the rows between are brought across and walked; the
; rest used to be copied, and every one of them tested, for nothing.

                push    hl              ; the piece's bytes
                ld      a, (yco)        ; POP's YCO is signed, and the rows
                cp      192             ; climb from it: a bottom row above
                jp      nc, bgdnone     ; the screen puts none of it down --
                                        ; the ceiling row draws at Ay = -1
                ld      a, (bandbot)
                cp      192
                jr      c, bgdhi
                ld      a, 191
bgdhi:          ld      b, a
                ld      a, (yco)
                sub     b
                jr      nc, bgdk0
                xor     a
bgdk0:          ld      c, a            ; C = the first row that lands, k0
                ld      a, (bandtop)
                ld      b, a
                ld      a, (yco)
                sub     b               ; YCO - top: the last one, k1
                jp      c, bgdnone      ; it all sits above the band
                ld      b, a
                ld      a, (imgh)
                dec     a
                cp      b
                jr      nc, bgdk1
                ld      b, a            ; or the piece's own last row
bgdk1:          ld      a, b
                sub     c
                jp      c, bgdnone      ; it all sits below the band
                inc     a
                ld      (bgn), a        ; how many rows land
                ld      a, (yco)
                sub     c
                ld      (bgrow), a      ; and the line the first goes on
                ld      a, (imgw)       ; past the rows that do not
                ld      e, a
                ld      a, c
                call    mul8
                pop     de
                add     hl, de
                push    hl
                ld      a, (imgw)       ; and the ones that do, across
                ld      e, a
                ld      a, (bgn)
                call    mul8
                ld      b, h
                ld      c, l
                pop     hl
                ld      de, imgbuf
                ldir
                call    bg_shift

                call    page_target

                ld      a, (bgmask)     ; which of the seven ways to lay a
                or      a               ; byte down.  It is the same one for
                ld      hl, bgpict      ; every byte of the piece, and asking
                jr      z, bgdtab       ; twice a byte was the single biggest
                ld      hl, bgmasks     ; cost in a block redraw
bgdtab:         ld      a, (bgop)
                cp      3
                jr      c, bgdop
                ld      a, 3
bgdop:          add     a, a
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                ld      (bginner + 1), de

; FASTLAY: the first stored row lands on YCO and the rest climb -- from the
; first of them that lands, now.

                ld      a, (bgrow)
                call    canvasrow       ; the rows are walked one at a time, so
                ld      (bgcanp), hl    ; the address steps by forty instead of
                ld      hl, imgbuf      ; being multiplied out for each of them
                ld      (bgsrc), hl
                ld      a, (bgn)
                ld      b, a
bgrowloop:      push    bc
                ld      a, (bgmask)     ; into a mask, or into the picture
                or      a
                jr      nz, bgmaskrow
                ld      hl, (bgcanp)    ; where that row starts
                jr      bgrowat
bgmaskrow:      ld      a, (bgrow)      ; only the floor bands are kept
                ld      l, a
                ld      h, 0
                ld      de, floorband
                add     hl, de
                ld      a, (hl)
                inc     a
                jr      z, bgrowskip
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
                ld      a, (imgw)       ; how many of its bytes the row can
                add     a, e            ; hold: the same answer for all of
                cp      CANVAS_W + 1    ; them, so it is worked out once
                ld      a, (imgw)
                jr      c, bgfits
                ld      a, CANVAS_W
                sub     e
bgfits:         or      a
                jr      z, bgrowskip    ; none of it lands on the row
                ld      b, a
                ld      de, (bgsrc)     ; DE = the piece
bginner:        jp      bgpand          ; whichever way this piece is laid

bgpand:         ld      a, (de)
                and     (hl)
                ld      (hl), a
                inc     hl
                inc     de
                djnz    bgpand
                jr      bgrowskip

bgpora:         ld      a, (de)
                or      (hl)
                ld      (hl), a
                inc     hl
                inc     de
                djnz    bgpora
                jr      bgrowskip

bgpsta:         ld      a, (de)
                ld      (hl), a
                inc     hl
                inc     de
                djnz    bgpsta
                jr      bgrowskip

bgmand:         ld      a, (de)         ; a mask covers what an AND clears,
                cpl                     ; what an ORA sets, and the whole
                and     0xfe            ; rectangle of an STA
                or      (hl)
                ld      (hl), a
                inc     hl
                inc     de
                djnz    bgmand
                jr      bgrowskip

bgmsta:         ld      a, 0xfe
                or      (hl)
                ld      (hl), a
                inc     hl
                inc     de
                djnz    bgmsta

bgrowskip:      ld      hl, (bgsrc)     ; the source moves on by the whole
                ld      a, (imgw)
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (bgsrc), hl
bgrowdown:      ld      hl, (bgcanp)    ; a row up is forty bytes back
                ld      de, -CANVAS_W
                add     hl, de
                ld      (bgcanp), hl
                ld      hl, bgrow
                dec     (hl)
                pop     bc
                dec     b
                jp      nz, bgrowloop
                ret

; Out here, not in the loops' way: bgmsta, the last of them, runs on into
; bgrowskip, and with this in between a mask's first row was its only one.

bgdnone:        pop     hl              ; none of it lands -- and the canvas
                jp      page_target     ; is left in, as the full way leaves
                                        ; it: the callers draw on after


bgcanp          equ     SYSVARS + 27    ; the canvas row the draw is on
bgn             equ     SYSVARS + 29    ; how many of the piece's rows land

; HL = A * E, both unsigned bytes.

mul8:           ld      hl, 0
                ld      d, h
                ld      b, 8
mul8l:          add     hl, hl
                rla
                jr      nc, mul8n
                add     hl, de
mul8n:          djnz    mul8l
                ret

bgpict:         dw      bgpand, bgpora, bgpsta, bgpmask
bgmasks:        dw      bgmand, bgpora, bgmsta, bgmsta

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
                ld      de, (cvbasep)   ; the canvas, or a redraw's slice as
                add     hl, de          ; if it were the canvas from its top
                ret                     ; row: see rbwipe

; Set the piece up and lay it: A = image, (xco)/(yco) already set, C = the op.

bglay:          ld      (imgnum), a
                ld      a, (bgshift)    ; a shift is for this piece alone
                ld      (bgsh), a
                xor     a
                ld      (bgshift), a
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
                jr      mask_b

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
                jr      bglay

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
                jp      z, dbblock

                call    tab_pieceb
                or      a
                jp      z, dbstripe
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
                call    bglay
                jp      dbstripe
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

dbstripe:       call    page_bg         ; and the palace adds a stripe on the
                ld      a, (preced)     ; wall, 32 lines up from Ay: DRAWB's
                ld      hl, bgtables + T_BSTRIPE        ; :stripe, BGset1 1
                call    bgentry         ; alone -- the dungeon's bstripe is
                or      a               ; noughts
                ret     z
                ld      c, a
                ld      a, (ay)
                sub     32
                ld      (yco), a
                ld      a, c
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
                jr      nz, danotloose
                call    loose_y
                ld      hl, bgtables + T_LOOSEA
                call    bgentry
                jr      dago
danotloose:     cp      BG_FLASK        ; the bottle, and drawflaska's bubbles
                jr      nz, danotflask  ; over it
                call    dapiece
                jp      flask_ma
danotflask:     cp      BG_SPIKES       ; drawspikea over the piece
                jr      nz, danotspikes
                call    dapiece
                jp      spike_ma
danotspikes:    cp      BG_SLICER       ; drawslicera, and piecea has
                jp      z, slicer_ma    ; nothing for it
                cp      BG_SWORD        ; drawsworda: its own picture, and
                jr      nz, dapiece     ; piecea has none for it
                call    sword_gleam
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

; DRAWSWORDA in FRAMEADV.S.  The sword on the ground is no piece of the
; background -- piecea has a nought where its picture would be -- but a
; picture of its own laid over the floor, and it gleams: state 1 is the
; bright one, every other state the plain.  Out: A = the image.

SWORDGLEAM0     equ     0x99
SWORDGLEAM1     equ     0xb3

sword_gleam:    ld      a, (state)
                dec     a
                ld      a, SWORDGLEAM1
                ret     z
                ld      a, SWORDGLEAM0
                ret

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
                jr      z, drawgateb
                cp      BG_SPIKES
                jp      z, spike_mb
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
; further in again -- and in the level's start room, KidStartScrn, that tile
; is the way he came in, so it gets no stairs.  Without them nothing wipes
; the rows the door leaves as it rises: POP never opens that one.

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

dxbody:         ld      a, (dxonly)     ; the top slat alone: the stairs are
                or      a               ; far below those rows, and so is
                jr      nz, dxdoor      ; every slice under the top one
                call    page_bg
                ld      a, (roomnum)
                ld      hl, level + LV_KIDSCRN
                cp      (hl)
                jr      z, dxdoor
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
                ld      c, a            ; the top slat alone: the highest
                ld      a, (dxonly)     ; slice and the one under it hold
                or      a               ; those four rows between them
                jr      z, dxloop
                ld      a, c
                ld      hl, blockthr
                sub     (hl)
                and     3
                add     a, (hl)
                add     a, 4
                cp      c
                jr      c, dxo1
                ld      a, c
dxo1:           ld      (yco), a
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

dxtop:          ld      a, (dxonly)     ; the repair sits above those rows
                or      a
                ret     nz
                ld      a, (ay)         ; part of the C section, really
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
dxonly:         db      0               ; the door's top slat, and no more

; A flask in an odd column: see flask_front.

fr_dx:          call    tab_frontx
                ld      c, a
                ld      a, (frxfix)
                neg
                add     a, c
                ret

frxfix          equ     SYSVARS + 30
frydy:          db      0


; drawfrnt: a flask of potion 2, 3 or 4 is the taller bottle.  In: A = the
; front piece, with the block in hand.  Out: A = the one to draw.

flask_front:    ld      c, a
                xor     a
                ld      (frxfix), a
                ld      (frydy), a
                ld      a, (objid)
                cp      BG_SLICER
                jr      z, ffslicer
                cp      BG_FLASK
                ld      a, c
                ret     nz
                ld      a, 2            ; and two pixels lower, clear of the
                ld      (frydy), a      ; cell its bubbles colour: flask_ma
                ld      a, (blockcol)   ; odd: a byte back and two pixels on,
                and     1               ; as flask_ma has it
                ld      (frxfix), a
                add     a, a
                ld      (bgshift), a
                ld      a, (state)
                and     0xe0
                cp      0xa0
                ld      a, c
                ret     z
                ld      a, (state)
                and     0xe0
                cp      0x40
                ld      a, c
                ret     c
                ld      a, (bgtables + T_SPECIALFLASK)
                ret

; drawslicerf: a slicer has a front piece of its own for every picture of
; its jaws, where fronti has none.

ffslicer:       call    slicer_x
                ld      a, c
                ld      hl, bgtables + T_SLICERFRNT
                jp      bgentry


; The rows of the piece that land, in imgbuf, moved (bgshift) pixels to the
; right within their own bytes -- seven pixels in bits 7 to 1 of each -- with
; clear pixels coming in on the left, or kept ones for a mask, and whatever
; goes off the right of the last byte lost.

bg_shift:       ld      a, (bgsh)
                or      a
                ret     z
                ld      c, a
bshpass:        ld      hl, imgbuf
                ld      a, (bgn)
                ld      d, a
bshrow:         ld      a, (imgw)
                ld      b, a
                ld      a, (bgop)
                cp      BG_AND
                scf
                jr      z, bshbyte      ; a mask keeps what comes in
                or      a
bshbyte:        ld      a, (hl)
                rra                     ; the pixel coming in at the top, and
                ld      e, a            ; the last one down at bit 0
                and     0xfe
                ld      (hl), a
                ld      a, e
                rra                     ; which is the carry into the next
                inc     hl
                djnz    bshbyte
                dec     d
                jr      nz, bshrow
                dec     c
                jr      nz, bshpass
                ret

bgshift         equ     SYSVARS + 31    ; asked for, for the next bglay
bgsh            equ     SYSVARS + 32    ; and taken by it

; drawfrnt: what goes over the characters.  Stamped rather than ORed for the
; posts and the arches, so the neighbour's B section does not show through.

draw_front:     call    page_bg
                ld      a, (objid)
                call    tab_fronti
                call    flask_front
                or      a
                ret     z
                ld      (frimg), a
                ld      a, (objid)
                call    fr_dx
                ld      c, a
                ld      a, (xco)
                add     a, c
                ld      (xco), a
                ld      a, (objid)
                call    tab_fronty
                ld      hl, frydy
                add     a, (hl)
                call    bgay
                ld      a, (objid)      ; maddfore: a halo cleared round it,
                ld      c, BG_MASK      ; as POP lays it -- for the bottle,
dfpost:         cp      BG_POSTS        ; and in the palace the posts too:
                jr      z, dfsta        ; the dungeon's are stamped, and
                cp      BG_FLASK        ; newroom points this at dfgo for
                jr      z, dfgo         ; the palace's
                cp      BG_BLOCK        ; a block's face is stamped, as
                jr      z, dfsta        ; drawfrnt has it: it covers the
                                        ; spikes' B half, which is laid in it
                ld      c, BG_ORA
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
                call    fr_dx
                ld      c, a
                ld      a, (xco)
                sub     c
                ld      (xco), a
                ret

; ---------------------------------------------------------------- a room
;
; Three rows of ten blocks, left to right and bottom to top, exactly as the
; screen redraw of FRAMEADV.S walks them.

setblock:       ld      a, (blockrow)
                inc     a
                jr      z, sbceil       ; row -1: the ceiling, kept aside
                ld      a, (blockcol)
                call    blockatr        ; getobjid: the id is the low five bits
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
sbat:           call    blockat
                ld      (below), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (sbelow), a
                ret

; The ceiling block comes out of aboverow, and what is below and to its left
; is this room's own top row -- column zero's from the room to the left, the
; way compose lays the row down.

sbceil:         ld      a, (blockcol)
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
                ld      a, (blockcol)
                or      a
                jr      z, sbcprev
                dec     a
                ld      c, a
                ld      b, 0
                jr      sbat
sbcprev:        ld      a, (prevblk)
                ld      (below), a
                ld      a, (prevblk + 1)
                ld      (sbelow), a
                ret

; getprev and getbelow: what the rooms next door put into this one's edges.
;
; PRECED for column zero is the rightmost column of the room to the left --
; its wall face hangs over into this one, and a gate in its last column draws
; its bars here -- and the bottom row's C sections come out of the room
; underneath.  With no room that way POP puts a solid block; below, floor.

prevblk:        ds      6
                                        ; belowrow and aboverow are under the
                                        ; loader now: the ceiling is the bottom
                                        ; row of the room above, D sections

; B = row, C = column.  Out: HL = where that block's id sits, A = the id.

blockatr:       ld      c, a            ; the row (blockrow), column A
                ld      a, (blockrow)
                ld      b, a
blockat:        ld      a, b
                call    mul10           ; ten to the row
                ld      e, c
                ld      d, 0
                add     hl, de
                ld      de, roomids
                add     hl, de
                ld      a, (hl)         ; and A = the id, getobjid's five bits
                and     0x1f
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

; These the drawing sets before it reads them, and they live under the
; loader's stack, where 48K BASIC kept its channels: see LOWVARS.

imgnum          equ     LOWVARS
imgw            equ     LOWVARS + 1
imgh            equ     LOWVARS + 2
xco             equ     LOWVARS + 3
yco             equ     LOWVARS + 4
bgop            equ     LOWVARS + 5
bgrow           equ     LOWVARS + 6
bgsrc           equ     LOWVARS + 7     ; two
frimg           equ     LOWVARS + 9
objid           equ     LOWVARS + 10
state           equ     LOWVARS + 11
preced          equ     LOWVARS + 12
spreced         equ     LOWVARS + 13
below           equ     LOWVARS + 14
sbelow          equ     LOWVARS + 15
dy              equ     LOWVARS + 16
ay              equ     LOWVARS + 17
blockrow        equ     LOWVARS + 18
blockcol        equ     LOWVARS + 19
LOWVARLEN       equ     20

roomnum:        db      START_ROOM      ; the way into the level
blockbot:       db      2, 65, 128, 191, 254
; And for a tall bottle's bubbles, the same place in the table as a row's
; floor line: 23 under their top row, which is the one that keeps all six of
; them in the cell row flask_attrs colours -- seven over the short bottle's
; in the lower two block rows, as they always were, and eight in the top
; one, sixty five rows down, where seven ran them a row into the next.
talltop:        db      34 + 23, 98 + 23, 162 + 23
imgbuf:         ds      312             ; the largest piece laid is 312 bytes;
                                        ; a redraw's batch is a slice's rows,
                                        ; sixteen at most

; ---------------------------------------------------------------- repack
;
; The canvas holds the room the Apple's way, seven pixels to a byte on a seven
; pixel boundary; the room wants eight to a byte.  Forty bytes
; in, thirty five out, and the two banks are never in together, so a row goes
; through a buffer down here.

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
                ld      a, (frontok)    ; the list is for build_fore, made
                or      a               ; once as the room is entered: a
                ret     z               ; redraw would only pile up copies
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

frbodyx         equ     SYSVARS + 35
frbodyw         equ     SYSVARS + 36

; Which rows the mask has anything on, and where each of them sits in it.

recfront        equ     SYSVARS + 37
frontok         equ     SYSVARS + 38    ; a room is being built, not redrawn
nfront:         db      0
                                        ; frontlist is under the loader now:
                                        ; five bytes an entry, as frontrec
                                        ; writes and frontrect reads them --
                                        ; at four, the last six ran on into
                                        ; halfpiece and the code after it

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

FLOORCAN        equ     MASKCAN         ; in the pixels' bank, past the canvas
HALFCAN         equ     FLOORCAN + CANVAS_W * 45

; DRAWHALF's piece for the tile: CUpiece for the tiles that have a half
; piece, and in the palace CUpost for a post and the foot of an arch -- the
; set's table says, halfimg.  Out: NZ and A the piece, or Z for none, and
; the whole floorpiece instead, exactly as FRAMEADV.S does.  The bank in.

halfpiece:      ld      a, (objid)
                ld      hl, bgtables + T_HALFIMG
                call    bgentry
                or      a
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
                jr      z, fpwhole
                push    af
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
                pop     af
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
                jr      nz, fpnotloose
                call    loose_y
                ld      hl, bgtables + T_LOOSEA
                call    bgentry
                jr      fpgo
fpnotloose:     cp      BG_SWORD
                jr      nz, fppiece
                call    sword_gleam
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

maskblock:      call    mbsetup
                ld      a, 1
                call    maskone
                ld      a, 2
                call    maskone
mbout:          xor     a               ; and out of mask mode
                ld      (bgmask), a
                ret

; The queue's two steps: A = 0 the floor's mask, 1 the half's.  Out: carry
; when the half's is still to come.

mb_step:        push    af
                call    mbsetup
                pop     af
                inc     a
                push    af
                call    maskone
                call    mbout
                pop     af
                cp      2
                ret

mbsetup:        ld      a, (blockcol)   ; four bytes to a block
                add     a, a
                add     a, a
                ld      (xco), a
                ld      a, (blockrow)
                ld      hl, blockbot + 1
                add     a, l
                ld      l, a
                ld      a, (hl)
                ld      (dy), a
                sub     3
                ld      (ay), a

                ld      a, (blockrow)   ; fifteen rows to a band, in the order
                ld      b, a            ; mkassets lays them down
                add     a, a
                add     a, a
                add     a, a
                add     a, a            ; sixteen of them
                sub     b               ; less one is fifteen
                ld      (mbband), a

                ld      a, (blockcol)   ; PREV, the same as compose has it
                or      a
                jr      nz, mbleft
                ld      a, (blockrow)
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, prevblk
                add     hl, de
                jr      mbtake
mbleft:         dec     a
                call    blockatr
                ld      (preced), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (spreced), a
                ret

mbtake:         ld      a, (hl)
                ld      (preced), a
                inc     hl
                ld      a, (hl)
                ld      (spreced), a
                ret

; A = which mask.  Wipes the block's four columns over its own band, draws
; the piece again and repacks the one group of eight that holds them.

maskone:        ld      (bgmask), a
                dec     a
                ld      hl, FLOORCAN
                ld      de, floormask
                jr      z, mo1
                ld      hl, HALFCAN
                ld      de, halfmask
mo1:            ld      (mocan), hl
                ld      (momask), de

                ld      a, (mbband)
                ld      (morow), a
                ld      a, (xco)        ; the wipe works in the block's own
                ld      (mooff), a      ; four bytes
                call    page_pixels
                call    c1mowipe

                call    setblock
                call    floorpiece

                ld      a, (blockcol)   ; eight Apple bytes to a group, and a
                srl     a               ; block of four never straddles two --
                ld      (mogrp), a      ; but an odd column sits in the second
                add     a, a            ; half of its group, so the repack
                add     a, a            ; starts four bytes before the block
                add     a, a
                ld      (mooff), a
                ld      a, (mbband)
                ld      (morow), a
                ld      b, 15
mopack:         push    bc
                call    page_pixels
                call    mocanrow
                ld      de, cvbuf
                ld      bc, 8
                ldir

                call    page_art
                ld      a, (morow)
                call    mul35
                ld      de, (momask)
                add     hl, de
                ld      a, (mogrp)      ; seven bytes out to a group
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

                ld      hl, morow
                inc     (hl)
                pop     bc
                djnz    mopack
                ret

; HL = where this row's four bytes start in the mask's canvas.

mocanrow:       ld      a, (morow)
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl          ; eight
                ld      d, h
                ld      e, l
                add     hl, hl
                add     hl, hl          ; and thirty two
                add     hl, de          ; forty to the row
                ld      de, (mocan)
                add     hl, de
                ld      a, (mooff)
                ld      e, a
                ld      d, 0
                add     hl, de
                ret

mocan           equ     SYSVARS + 39
mooff           equ     SYSVARS + 41
momask          equ     SYSVARS + 42
mbband          equ     SYSVARS + 44
mogrp           equ     SYSVARS + 45
morow:          db      0

; Forty five rows of forty Apple bytes into forty five of thirty five.

bgmask:         db      0

; ---------------------------------------------------------------- next room
;
; A level is twenty four rooms and the blueprint says which is which way: the
; four bytes at MAP are the room to the left, to the right, above and below,
; and a zero means there is nothing there.  Walking off an edge takes him to
; the room on that side, and everything about the new one -- its picture, its
; three masks, its torches -- is made on the way in.

; The rooms stack 189 scanlines apart -- the bottom of the row below the
; screen against the bottom of the top row of the next one -- so falling
; through takes that off his height and puts him on the top row.

; CUT in AUTO.S: three block rows and 189 scanlines, whichever way he went.

; Which way he went, and no more than that: taking him there runs only at a
; room change, when the code that builds a room is paged back in anyway, so
; it lives in that block and these four stubs are all that stay here.

nrup:           ld      a, (links + 2)
                ld      c, 0
                jr      nrcall
nrdown:         ld      a, (links + 3)
                ld      c, 1
                jr      nrcall
nrleft:         ld      a, (links)
                ld      c, 2
                jr      nrcall
nrright:        ld      a, (links + 1)
                ld      c, 3
nrcall:         or      a
                ret     z               ; no room that way, and nothing done:
                push    bc              ; putting the block back would take the
                push    af              ; working copy's first rows with it,
                call    roomrest        ; and nothing would repaint them
                pop     af
                pop     bc
                push    bc
                push    af
                call    leave_room      ; the guard goes too, or stays behind:
                pop     af              ; in the block, so after it is back
                pop     bc
                ld      (roomnum), a
                ld      a, c
                ld      (nrwhich), a
                jp      nrcut

nrwhich         equ     SYSVARS + 46

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

; 1: a level follows this one on the tape, and 2 once he has gone up the
; stairs, when the next level is loaded; 0 when there is none.

lvflag:         db      LV_ARMED1

nextroom:       ld      a, (lvflag)     ; up the stairs to a level the tape
                cp      2               ; has: LoadNextLevel, by way of the
                jr      c, cutchar      ; room change it is so much like --
                ld      a, 0xbf         ; once the tune up the stairs is heard
                in      a, (254)        ; out, the torches burning on as it
                rra                     ; plays, or ENTER has cut it short, as
                call    nc, ststop      ; a key does POP's PlaySong.  ENTER and
                                        ; nothing else: the button is SPACE,
                                        ; and a hand resting on it took every
                                        ; tune away the moment it began
                ld      a, (sfxtimer)
                or      a
                ret     nz
                ld      c, 4
                ld      a, c
                jr      nrcall

cutchar:        ld      a, (charact)    ; falling: only the bottom counts
                cp      3
                jr      z, ccnotup
                cp      4
                jr      z, ccnotup
                cp      5
                jr      z, ccnotup
                ld      a, (chary)
                cp      TOPCUTPL
                jr      c, nrup
                cp      TOPCUTMI
                jr      nc, nrup
ccnotup:        ld      a, (chary)
                cp      BOTCUT
                jr      nc, nrdown

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
                call    page_art        ; as it always left it
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
                call    mul10           ; ten blocks to the row
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

char_edges:     ld      a, (nowbank)    ; called from the control code in the
                push    af              ; canvas bank too: put back what was in
                call    page_canvas
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
                pop     af
                jp      pageset

edgel           equ     SYSVARS + 47
edger           equ     SYSVARS + 49
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

; A block redraw goes a band at a time, from its floor line up: each band
; wiped, every pass laid down again over it alone -- bgdraw keeps to the rows
; between bandtop and bandbot -- and repacked into the room, so a band done
; is a band finished, whatever comes after it.  redblock does them all at
; once; the redraw queue does one a frame, which keeps any step small: the
; exit door alone was 58000 T in one pass and its repack 46000 more.

RQBAND          equ     16

redblock:       xor     a               ; every band of it, at once
rbloop:         push    af
                call    rb_step
                jr      nc, rbend
                pop     af
                inc     a
                jr      rbloop
rbend:          pop     af
                call    redshow         ; and on to the screen
                xor     a
                ld      (redwide), a
                ret

; One band.  In: (blockrow), (blockcol), (redh), (redwide), A = which band,
; counted up from the floor line.  Out: carry when there is another above.

rb_step:        push    af
                call    rb_setup
                pop     af
                push    af
                call    rbband          ; the top band: the door's top first
                ld      a, 0
                ld      (rbdoor), a
                call    nc, rbdoortop
                pop     af
                call    rbband
                push    af
                call    rbwipe
                call    setblock
                call    draw_c
                call    draw_mc
                call    draw_b
                call    draw_mb
                call    draw_d
                call    draw_md
                call    draw_a
                call    draw_front
                call    rbband0
                call    rb_pack
                ld      a, (rbdoor)     ; the door's top: those rows are the
                or      a               ; band's too from here on, for the view
                call    nz, rbdoorrows  ; and for the screen
                ld      a, (rbh)        ; and a view being made wants those
                ld      b, a            ; rows of the room again
                ld      a, (rbbot)
                sub     b
                inc     a
                call    vw_mark
                pop     af
                ret

; The exit's door is drawn from its foot up to four rows short of the block
; above -- dy - 67 -- and so its top slat is in that block's rows, above the
; block's own band.  POP draws the moving door over whatever is there, with
; its mask; wiping those rows would take the block above's pixels with them.
; So the top band draws the door alone over them, unwiped, and packs them.

EXITTOP         equ     67

rbdoortop:      ld      a, (preced)
                cp      BG_EXIT
                ret     nz
                ld      a, (dy)
                sub     EXITTOP - 1
                ret     c
                ld      (bandtop), a
                add     a, 3
                ld      (bandbot), a
                ld      (rbbot), a
                ld      a, 4
                ld      (rbh), a
                ld      (dxonly), a     ; any value but zero
                xor     a               ; what is there, the whole of it,
                call    rb_fetch        ; out of the room
                call    draw_mb
                xor     a
                ld      (dxonly), a
                call    rbband0
                call    rb_pack
                ld      a, 1
                ld      (rbdoor), a
                ret

rbdoorrows:     ld      a, (dy)         ; the band's rows reach up to them
                ld      b, a
                ld      a, (rbbot)
                sub     b
                add     a, EXITTOP
                ld      (rbh), a
                ld      a, EXITTOP      ; and redblock's redshow as well
                ld      (redh), a
                ret

rbdoor          equ     SYSVARS + 51

; The rows of band A: RQBAND of them up from the floor line and each band
; above the last, the top one stopping where the block's own band does.
; What falls outside the block's band is redrawn exactly as it was, so
; leaving it alone is the same picture for a third of the work.

rbband:         add     a, a            ; sixteen rows to a band
                add     a, a
                add     a, a
                add     a, a
                ld      b, a
                ld      a, (dy)
                sub     b
                ld      (bandbot), a
                ld      (rbbot), a
                sub     RQBAND - 1
                jr      nc, rbbfull
                xor     a               ; the ceiling sits at the top of the
rbbfull:        ld      c, a            ; screen: no band starts above it
                ld      a, (redh)
                ld      b, a
                ld      a, (dy)
                sub     b
                inc     a
                ld      d, a            ; D = the top of the block's band
                cp      c
                jr      nc, rbbtop      ; which ends in this one
                ld      a, c
rbbtop:         ld      (bandtop), a
                ld      e, a
                ld      a, (bandbot)
                sub     e
                inc     a
                ld      (rbh), a
                ld      a, d            ; carry: rows still above this band
                cp      e
                ret

rbband0:        xor     a               ; the next whole room wants them all
                ld      (bandtop), a
                ld      a, 191
                ld      (bandbot), a
                ret

rb_setup:       xor     a               ; the room is built: note no more
                ld      (frontok), a    ; front pieces
                ld      a, (blockrow)
                ld      hl, blockbot + 1
                add     a, l
                ld      l, a
                ld      a, (hl)
                ld      (dy), a
                sub     3
                ld      (ay), a

                ld      a, (blockrow)   ; the ceiling's neighbour is in the
                inc     a               ; row the room above lent us, and its
                jr      nz, rbsown      ; column zero has nothing to the left,
                ld      a, (blockcol)   ; as SURE leaves PRECED empty there
                or      a
                jr      z, rbsnone
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, aboverow - 2
                add     hl, de
                ld      a, (hl)
                ld      (preced), a
                inc     hl
                ld      a, (hl)
                ld      (spreced), a
                jr      rbxco
rbsnone:        xor     a
                ld      (preced), a
                ld      (spreced), a
                jr      rbxco

rbsown:         ld      a, (blockcol)   ; the piece to its left, for drawc
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
                jr      rbxco
rbleft:         dec     a
                call    blockatr
                ld      (preced), a
                ld      de, 30
                add     hl, de
                ld      a, (hl)
                ld      (spreced), a

rbxco:          ld      a, (rbfrz)      ; the queue's pass: take the state
                or      a               ; of the piece to the left -- a gate,
                jr      z, rbx1         ; the exit -- or keep what was taken
                dec     a
                ld      a, (spreced)
                jr      nz, rbxkeep
                ld      (rqfrzv), a
                jr      rbx0
rbxkeep:        ld      a, (rqfrzv)
                ld      (spreced), a
rbx0:           xor     a
                ld      (rbfrz), a
rbx1:           ld      a, (blockcol)   ; four bytes to a block
                add     a, a
                add     a, a
                ld      (xco), a
                ret

; The canvas is not kept while the game runs -- building a room is all it
; is whole for, and the bank it is in has better uses the rest of the time
; (see CODE1).  A band is laid in a slice at the canvas's start instead: its
; groups of eight Apple bytes come back out of the room first, as they were
; when it was built, since the room is the canvas repacked and nothing else
; -- and the passes and the repacking then find the canvas they always did.
; cvbasep is where the canvas would start for the band's top row to be the
; slice's first: canvasrow counts from it.

rbwipe:         ld      a, 1            ; all but the block's own four
                call    rb_fetch        ; columns, and those wiped
                jp      c1wipe

; A = nought for the whole of the groups, or all but the block's own half.

rb_fetch:       ld      (fmode), a
                ld      a, (blockcol)   ; the groups rb_pack takes: the one
                and     1               ; that holds the block, and the next
                ld      b, a            ; if a piece runs on out of an odd
                ld      a, (redwide)    ; block
                and     b
                ld      (rbwide), a
                ld      a, (blockcol)   ; four bytes to a block, eight to a
                srl     a               ; group: the column halved
                ld      (rbgroup), a
                ld      hl, CANVAS      ; the band's top row at the slice's
                ld      (cvbasep), hl   ; start: CANVAS less forty rows for
                ld      a, (bandtop)    ; each above it
                call    canvasrow
                ex      de, hl
                ld      hl, 2 * CANVAS - 65536
                or      a
                sbc     hl, de
                ld      (cvbasep), hl
                call    page_art
                ld      a, (bandtop)
                call    roomrow
                ld      a, (rbgroup)    ; seven room bytes to a group
                ld      c, a
                add     a, a
                add     a, a
                add     a, a
                sub     c
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      de, imgbuf
                ld      a, (rbh)
                ld      b, a
rf1:            push    bc
                push    hl
                ld      bc, 7
                ld      a, (rbwide)
                or      a
                jr      z, rf2
                ld      c, 14
rf2:            ldir
                pop     hl
                ld      c, ROOM_BYTES
                add     hl, bc
                pop     bc
                djnz    rf1
                call    page_pixels
                jp      c1unpack

; The groups of eight Apple bytes that cover it, repacked into the room.  A
; block starts on a multiple of four, so it is either the first half of a
; group or the second, and one group either side takes in whatever a piece
; spilled -- a second group only if the piece spills out of the block's own:
; from an even column it runs on into the other half of the same group, and
; packing the next as well was 42000 T for nothing.  rb_fetch has worked out
; which.

rb_pack:        ld      a, (rbh)        ; only the band drawn goes back into
                ld      b, a            ; the room
                ld      a, (rbbot)
                sub     b
                inc     a
                jr      nc, rbtop
                xor     a
rbtop:          ld      (rbrow), a
                ld      l, a            ; the rows the band holds, stopped at
                ld      a, 192          ; the bottom of the screen
                sub     l
                ld      b, a
                ld      a, (rbh)
                cp      b
                jr      c, rbn1
                ld      a, b
rbn1:           ld      (rbleftn), a

                ld      a, (rbrow)      ; where they start in the canvas and
                call    canvasrow       ; in the room
                ld      a, (rbgroup)
                add     a, a
                add     a, a
                add     a, a
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (rbcanp), hl
                ld      a, (rbrow)
                call    roomrow
                ld      a, (rbgroup)
                ld      c, a
                add     a, a
                add     a, a
                add     a, a
                sub     c
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      (rbroomp), hl

; A batch at a time: the canvas and the room are in two banks, and paging
; both for every row was a fifth of the work.  imgbuf is free by now and
; holds 39 rows of one group, or 19 of two -- more than the slice's sixteen.

rbbatch:        ld      a, (rbleftn)
                or      a
                jr      z, rbdone
                ld      b, 39
                ld      a, (rbwide)
                or      a
                jr      z, rbb1
                ld      b, 19
rbb1:           ld      a, (rbleftn)
                cp      b
                jr      c, rbb2
                ld      a, b
rbb2:           ld      (rbbn), a
                ld      b, a
                ld      a, (rbleftn)
                sub     b
                ld      (rbleftn), a

                call    page_pixels     ; the batch out of the canvas
                ld      hl, (rbcanp)
                ld      de, imgbuf
                ld      a, (rbbn)
                ld      b, a
                call    c1copy
                ld      (rbcanp), hl

                call    page_art        ; and into the room
                ld      hl, imgbuf
                ld      de, (rbroomp)
                ld      a, (rbbn)
                ld      b, a
rbconv:         push    bc
                push    de
                call    cv8to7
                ld      a, (rbwide)    ; a piece that reaches past its own
                or      a               ; block wants the next group too
                call    nz, cv8to7
                pop     de
                ex      de, hl
                ld      bc, 35
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    rbconv
                ld      (rbroomp), de
                jr      rbbatch

rbdone:         jp      page_art        ; redshow reads the room

redwide         equ     SYSVARS + 52
rbrow:          db      0
rbleftn         equ     0x5C0B
rbbn            equ     0x5C0C          ; the rows in this batch
rbwide          equ     0x5C0D          ; two groups to pack, not one
rbcanp          equ     0x5C0E          ; where the next batch starts in the
rbroomp         equ     0x5C10          ; canvas and in the room
rbgroup         equ     0x5C12
rbbot           equ     0x5C13          ; the band in hand: its bottom row
rbh             equ     0x5C14          ; and how many

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

MAXTR           equ     12              ; POP keeps 31: six filled up with
                                        ; plates, their gates and loose floors
                                        ; shaking, and a floor's plate then
                                        ; opened nothing
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
                ld      hl, (blueptr)   ; what a copy of it would show
                ld      a, (hl)
                and     0x1f
                push    af
                ld      a, (trobst)
                ld      c, a
                pop     af
                call    subplate
                ld      b, a
                call    onscreen
                jr      nz, tsceil
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

; And the ceiling has a copy of its own: the bottom row of the room above,
; read once when the room was built and drawn from there ever since.

tsceil:         ld      a, (links + 2)
                ld      hl, trscrn
                cp      (hl)
                ret     nz
                ld      a, (trloc)
                sub     20
                ret     c
                add     a, a
                ld      l, a
                ld      h, 0
                ld      de, aboverow
                add     hl, de
                ld      (hl), b
                inc     hl
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
                call    frame_check     ; is his foot on the floor at all
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
cprow:          ld      a, (roomnum)    ; the row above the top one is the
                ld      (trscrn), a     ; bottom row of the room above, and
                ld      a, b            ; that is where RDBLOCK's handler goes
                inc     a               ; to break a loose floor in the ceiling
                jr      nz, cprow1
                call    ceilroom
                ret     z
                ld      b, 2
cprow1:         ld      a, b
                cp      3
                ret     nc              ; and off the screen is nothing
                call    mul10           ; ten blocks to the row
                ld      a, l
                add     a, c
                ld      (trloc), a

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

; BREAKLOOSE: it only starts once, and then animfloor has it -- though a floor
; still wiggling from a jar gives way all the same, and one marked as required
; (reqmask, bit 5 of its type) never does.

breakloose:     ld      hl, (blueptr)
                ld      a, (hl)
                and     0x20
                ret     nz              ; blocked below
                ld      a, (trobst)
                or      a
                jr      z, blok
                ret     p               ; already triggered
blok:           ld      a, 1
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
slrow:          ld      c, a
                ld      a, (roomnum)    ; jaru from the top row shakes the
                ld      (trscrn), a     ; ceiling, which is the bottom row of
                ld      a, c            ; the room above: SHAKEM reads its
                inc     a               ; blocks through rdblock1, and that
                jr      nz, slrow1      ; goes there for a row of -1
                call    ceilroom
                ret     z
                ld      c, 2
slrow1:         ld      a, c
                cp      3
                ret     nc
                ld      (slrow2), a

; SHAKEM1: the row named by (slrow2) in room (trscrn), whoever asked for it.

shakerow:       ld      a, 9
                ld      (slcol), a
slloop:         ld      a, (slrow2)
                call    mul10           ; ten blocks to the row
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

; The room above, for the two places that act on a block rather than read
; one: POP's RDBLOCK handler goes there for a row of -1.  Out: Z when there
; is no room that way, and (trscrn) is the room when there is.

ceilroom:       ld      a, (links + 2)
                ld      (trscrn), a
                or      a
                ret

slrow2          equ     SYSVARS + 53
slcol:          db      0
cpabove:        db      0

; ------------------------------------------------------------ falling floors
;
; MOVER.S's MOBs.  A loose floor that has broken off is no longer part of the
; room: it falls under its own weight, passes through empty floor planes,
; knocks out any loose floor it meets on the way, and turns what it lands on
; into rubble.  They live in a list of their own, each with the room it is
; falling through, since one that comes out of a ceiling belongs to the room
; above and finishes in this one.

MAXMOB          equ     4               ; POP keeps 15: with only two, a third
                                        ; floor let go while two fell was lost,
                                        ; and never came down on its plate
MOBLEN          equ     5
FFACCEL         equ     3
FFTERMVEL       equ     29
CRUMBLETIME     equ     2               ; frames of it crumbling where it hit
DISAPPEARTIME   equ     2               ; or falling off the world
CRUSHDIST       equ     30

nummob:         db      0
moblist:        ds      MOBLEN * MAXMOB ; in the fixed half: the buffers under
                                        ; the loader have no room for more

mobx:           db      0               ; the one in hand, the same five bytes
moby:           db      0               ; in the same order as a record
mobroom:        db      0
mobvel:         db      0
moblevel:       db      0

; C = an entry.  Load it into the five the routines work on, or put it back.

mobat:          ld      a, c            ; five bytes to a record
                add     a, a
                add     a, a
                add     a, c
                ld      l, a
                ld      h, 0
                ld      de, moblist
                add     hl, de
                ld      de, mobx
                ld      bc, MOBLEN
                ret

mobload:        call    mobat
                ldir
                ret

mobsave:        call    mobat
                ex      de, hl
                ldir
                ret

; The five in hand as a block of the room: its column and row, so trobat,
; trobtype and PUSHPP can work on the piece it is over.

mobtrob:        ld      a, (moblevel)   ; ten blocks to a row
                call    mul10
                call    mobcol
                ld      e, a
                ld      d, 0
                add     hl, de
                ld      a, l
                ld      (trloc), a
                ld      a, (mobroom)
                ld      (trscrn), a
                jp      trobat          ; A = the piece, trobst and blueptr set

mobcol:         ld      a, (mobx)       ; four Apple bytes to a block
                rrca
                rrca
                and     0x3f
                ret

; A = a room.  Out: A = the one below it.  POP's GETDOWN, through the same
; step of the map that RDBLOCK's handler takes.

roomdown:       ld      (tirroom), a
                ld      a, (nowbank)
                push    af
                call    page_bg
                ld      e, 3
                call    tirstep
                pop     af
                call    pageset
                ld      a, (tirroom)
                ret

; The block (trloc) in room (trscrn) has just come away: it starts falling
; from the floor line of its own row, at rest.

mobstart:       call    trrowcol        ; UNINDEX: its row and its column
                ld      a, (blockcol)
                add     a, a            ; four Apple bytes to a block
                add     a, a
                ld      (mobx), a
                ld      a, (blockrow)
                ld      (moblevel), a
                ld      hl, blockbot + 1
                add     a, l
                ld      l, a
                ld      a, (hl)
                ld      (moby), a
                ld      a, (trscrn)
                ld      (mobroom), a
                xor     a
                ld      (mobvel), a

addmob:         ld      a, (nummob)     ; and on to the list, if there is room
                cp      MAXMOB
                ret     nc
                ld      c, a
                inc     a
                ld      (nummob), a
                jr      mobsave

; ---- one step of everything falling ----

animmobs:       ld      a, (rqn)        ; a floor that has just given way
                or      a               ; stays where it was, over its own
                jr      z, anm0         ; picture, until the blocks it leaves
                ld      a, (rqq + 3)    ; are drawn without it: while the line
                rla                     ; has pictures going first, nothing
                ret     c               ; falls
anm0:           ld      a, (nummob)
                or      a
                ret     z
                ld      b, a
                ld      c, 0
anml:           push    bc
                call    mobload
                call    mobfloor
                call    mobcrush
                pop     bc
                push    bc
                call    mobsave
                pop     bc
                inc     c
                djnz    anml

; and drop whatever has finished, closing the list up over it

                xor     a
                ld      (mbsrc), a
                ld      (mbdst), a
mbcl:           ld      a, (mbsrc)
                ld      hl, nummob
                cp      (hl)
                jr      nc, mbcdone
                ld      c, a
                call    mobload
                ld      a, (mobvel)
                inc     a               ; -1: it is not there any more
                jr      z, mbcnext
                ld      a, (mbdst)
                ld      c, a
                call    mobsave
                ld      hl, mbdst
                inc     (hl)
mbcnext:        ld      hl, mbsrc
                inc     (hl)
                jr      mbcl
mbcdone:        ld      a, (mbdst)
                ld      (nummob), a
                ret

mbsrc:          db      0
mbdst:          db      0
mobunder:       db      0               ; what it is about to land on

; MOBFLOOR.  It gathers speed to a limit, and where it crosses the floor
; line of the row it is in, what is there decides: empty space lets it
; through to the next row and the room below, a loose floor is knocked out
; and falls with it, and anything else stops it.  A negative velocity is the
; count while it crumbles where it landed, or falls off the world.

mobfloor:       ld      a, (mobvel)
                bit     7, a
                jr      nz, mobcount
                cp      FFTERMVEL
                jr      nc, mbftv
                add     a, FFACCEL
                ld      (mobvel), a
mbftv:          ld      b, a
                ld      a, (moby)
                add     a, b
                ld      (moby), a

                ld      a, (mobroom)    ; nothing that way: it falls out of
                or      a               ; the world
                jr      z, mobnull
                ld      a, (moby)
                cp      226             ; still above the top of the room
                ret     nc
                ld      a, (moblevel)   ; the floor line of its row
                ld      hl, blockbot + 1
                add     a, l
                ld      l, a
                ld      a, (hl)
                sub     3               ; POP's BlockAy, the floor's own line
                ld      b, a
                ld      a, (moby)
                cp      b
                ret     c               ; not down to it yet

                ld      a, (moblevel)   ; what is in the way
                ld      c, a
                call    mobcol
                ld      b, a
                ld      a, (mobroom)
                call    blk_in
                ld      (mobunder), a
                or      a
                jr      z, mobpass      ; space: straight through
                cp      BG_LOOSE
                jr      z, mobknock
                jr      mobcrash

mobcount:       inc     a               ; crumbling: count up to nothing
                ld      (mobvel), a
                ret

mobnull:        ld      a, (moby)       ; off a null screen and gone
                cp      192 + 17
                ret     c
                ld      a, -DISAPPEARTIME
                ld      (mobvel), a
                ret

; PASSTHRU: down a row, and past the bottom one into the room below.

mobpass:        ld      hl, moblevel
                inc     (hl)
                ld      a, (hl)
                cp      3
                ret     c
                ld      a, (moby)
                sub     192
                ld      (moby), a
                xor     a
                ld      (moblevel), a
                ld      a, (mobroom)
                call    roomdown
                ld      (mobroom), a
                ret

; KNOCKLOOSE: the floor it met is knocked out and falls too, half a block
; below this one, and this one goes on at half the speed.

mobknock:       call    mobtrob         ; that floor is space now
                ld      a, BG_SPACE
                call    trobtype
mkspace1:       ld      a, 0            ; MAKESPACE: the palace's space has
                ld      (trobst), a     ; its stripe, spec 1 -- see newroom
                call    trobsave
                ld      a, (mobvel)
                srl     a
                ld      (mobvel), a
                ld      a, (mbsrc)      ; keep this one where it was
                push    af
                ld      a, (moby)       ; and start the other just under it
                add     a, 6
                ld      (moby), a
                call    mobpass
                call    addmob
                pop     af
                ld      c, a
                call    mobload
                jr      mobmark

; It lands: the row it hit is shaken, it crumbles where it stopped, and what
; it landed on becomes rubble.

mobcrash:       ld      a, SND_LOOSECRASH
                call    addsound
                ld      a, (mobroom)
                ld      (trscrn), a
                ld      a, (moblevel)
                ld      (slrow2), a
                call    shakerow
                ld      a, (moblevel)
                ld      hl, blockbot + 1
                add     a, l
                ld      l, a
                ld      a, (hl)
                sub     3
                ld      (moby), a
                ld      a, -CRUMBLETIME
                ld      (mobvel), a

; MAKERUBBLE: a plate is pushed and jammed first, and only a floor, spikes,
; a flask or a torch can become rubble at all.

mobrubble:      call    mobtrob
                cp      BG_PRESSPLATE
                jr      z, mbrpp
                cp      BG_UPRESSPLATE
                jr      z, mbrjam
                cp      BG_FLOOR
                jr      z, mbrput
                cp      BG_SPIKES
                jr      z, mbrput
                cp      BG_FLASK
                jr      z, mbrput
                cp      BG_TORCH
                ret     nz
                jr      mbrput
mbrjam:         ld      a, BG_RUBBLE    ; jammed: the gates it holds stay open
                call    trobtype        ; -- PUSHPP reads the block, rubble
                ld      a, BG_RUBBLE    ; now, and its gates open for good
                jr      mbrpush
mbrpp:          ld      a, (mobunder)
mbrpush:        call    pushpp
                call    mobtrob
mbrput:         ld      a, BG_RUBBLE
                call    trobtype

; MARKMOB: the block it landed on and the one to its right, redrawn.

mobmark:        ld      a, (mobroom)    ; and it waits its turn in the queue:
                ld      (trscrn), a     ; rubble stays put, so nothing is lost
                ld      a, LOOSEWIPE    ; by drawing it a frame or two later,
                ld      (redh), a       ; and a landing is heavy enough to put
                jp      redplate        ; a frame over its three periods

; CHECKCRUSH: it comes down on him if he is under it in the same column, and
; POP takes a life for it -- and kills him outright when that was his last.

mobcrush:       ld      a, (mobroom)
                ld      hl, roomnum
                cp      (hl)
                ret     nz
                call    base_x
                call    blockcol_of
                ld      b, a
                call    mobcol
                sub     b
                ret     nz              ; not in his column
                ld      a, (moby)
                ld      hl, chary
                cp      (hl)
                ret     nc              ; below him altogether
                ld      a, (chary)
                sub     CRUSHDIST
                ld      b, a
                ld      a, (moby)
                cp      b
                ret     c               ; and not yet on him
                ld      a, (charact)    ; POP lets a runner escape it
                cp      2
                jr      c, mbcr1
                cp      7
                ret     nz
mbcr1:          ld      a, (frame)      ; crouched under it already: POP
                cp      109             ; leaves him alone
                ret     z
                ld      a, (blocky)     ; put him on the floor of his row
                inc     a
                ld      l, a
                ld      h, 0
                ld      de, floory
                add     hl, de
                ld      a, (hl)
                ld      (chary), a

                ld      a, 1            ; a life for it, as POP takes one
                call    decstr
                ld      b, SQ_CRUSH
                jr      nz, mbcr2
                ld      b, SQ_HARDLAND  ; that was the last of his strength
mbcr2:          ld      a, (nowbank)    ; the sequences are in the canvas
                push    af              ; bank and animmobs runs with the
                call    page_canvas     ; level's in: jumpseq read its table
                ld      a, b            ; out of the wrong bank, and he went
                call    jumpseq         ; off into whatever the rubbish said
                pop     af
                jp      pageset

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
                ld      a, SND_PLATEDOWN
                call    addsound
                call    trobsave        ; so the copy shows it pushed down
                ld      a, PLATEWIPE
                ld      (redh), a
                ld      a, 1            ; and first in the line: a plate is
                ld      (rqprio), a     ; down for a count, and a press that
                call    redplate        ; waited behind shaking floors was
                xor     a               ; drawn as it came back up
                ld      (rqprio), a
                jr      trigger
ppagain:        ld      a, PPTIMER
                call    chgtimer
                jr      trigger

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
                cp      BG_SWORD
                jp      z, aosword
                cp      BG_FLASK
                jp      z, aoflask
                cp      BG_SPIKES
                jp      z, aospikes
                cp      BG_SPACE
                jr      z, aodone       ; the floor that was here has gone
                ld      hl, aoslicer    ; a slicer, in CODE1 -- or none of
                jp      c1jp            ; these, and off the list

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
                jr      z, agsame
                jr      c, aglow        ; the lower of the two: the foot that
                ld      a, (hl)         ; is further down, ay - (v + 1)
aglow:          cp      12              ; near the floor it puts the floor back
                jr      c, aostart0     ; under itself: from the bottom band
                add     a, 4            ; else nothing below its foot changes,
aostart:        rrca                    ; and the pass starts at the band the
                rrca                    ; foot is in: dy - foot is v + 4
                rrca
                rrca
                and     3
                ld      (rqstart), a
                jr      aodone
aostart0:       xor     a
                ld      (rqstart), a
                jr      aodone
agsame:         xor     a               ; the bars are where they were
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
aoexit:         ld      a, (trobst)     ; the door's height before and
                push    af              ; after, the lower of the two:
                call    animexit        ; nothing below its foot changes --
                pop     bc              ; after, when it is coming down
                ld      a, (trobst)
                cp      b
                jr      c, aoex1
                ld      a, b
aoex1:          rrca
                rrca
                and     0x3f
                add     a, 17
                jr      aostart
aofloor:        call    animfloor

aodone:         call    trobsave
                ld      a, (redwant)    ; a plate that is only counting down
                or      a               ; looks no different from one that is
                ret     z               ; not, and a redraw is not cheap
                ld      a, (aoid)
                cp      BG_GATE
                jr      nz, aonotg
                call    redgate
                jr      aonostart
aonotg:         cp      BG_EXIT
                jr      nz, aonotx
                call    redright
aonostart:      xor     a
                ld      (rqstart), a
                ret
aonotx:         cp      BG_FLASK        ; the bubbles: the block's own band
                jr      nz, aonotf      ; they are in, and only that
                call    onscreen
                ret     nz
                call    trrowcol
                call    rq_block
                jr      aonostart
aonotf:         cp      BG_PRESSPLATE   ; a plate coming back up goes first too
                jr      z, aoprio
                cp      BG_UPRESSPLATE
                jr      z, aoprio
                cp      BG_LOOSE        ; and a floor that has been jarred: it
                jr      nz, aoplain     ; wobbles for four frames and settles,
aoprio:         ld      a, 1            ; and a redraw that waits for the view
                ld      (rqprio), a     ; to step arrives after it is over
aoplain:        call    redplate        ; the pictures, going first -- a
                xor     a               ; floor that has gone waits for them:
                ld      (rqprio), a     ; see animmobs -- and after them the
                ld      hl, mskwant     ; masks: a floor that has gone takes
                or      (hl)            ; its own wedge with it and gives one
                ld      (hl), 0         ; to the block on its right
                ret     z
ao_masks:       call    onscreen
                ret     nz
                call    trrowcol
                call    rq_mask
                ld      a, (blockcol)
                cp      9
                ret     nc
                inc     a
                ld      (blockcol), a
                jp      rq_mask

; ANIMSWORD in MOVER.S.  Out of sight it comes off the list.  The state
; counts down a frame at a time; at 1 DRAWSWORDA draws the bright picture,
; and at nought the wait starts again, 40 to 103 frames.  POP redraws it
; every frame; the picture only changes as the gleam comes and as it goes,
; so only those two are drawn.

aosword:        call    onscreen
                jp      nz, stopobj
                ld      a, (trobst)
                dec     a
                jr      z, aoswnew
                ld      (trobst), a
                cp      1
                jp      nz, aodone
                jr      aoswred
aoswnew:        ld      a, r
                and     0x3f
                add     a, 40
                ld      (trobst), a
aoswred:        ld      a, 1
                ld      (redwant), a
                ld      a, SWORDWIPE
                ld      (redh), a
                jp      aodone

redwant         equ     SYSVARS + 54
mskwant         equ     SYSVARS + 55

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
                ld      a, SND_RAISINGGATE
                jp      c, addsound
                ld      a, SND_GATETOP  ; the CPC's, all the way up
                call    addsound
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
                jr      z, agshut
                cp      GMAXVAL         ; waiting at the top makes no noise
                ret     nc
                jp      lowersound
agshut:         ld      a, SND_GATEDOWN
                call    addsound
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
                ld      a, SND_GATESLAM
                call    addsound
                jp      stopobj

; The exit door opens, and stops when it is all the way up; the one a
; level is come into by comes down behind him, as fast as a gate.

animexit:       ld      a, 1
                ld      (redwant), a
                ld      a, 63
                ld      (redh), a
                ld      a, (trdirec)
                and     0x80
                ret     nz
                ld      a, (trdirec)    ; 3 on: coming down fast, as a gate
                cp      3               ; does -- the entrance closing
                jr      nc, agfast
                ld      a, SND_RAISINGEXIT
                call    addsound
                ld      a, (trobst)
                add     a, EXITINC
                ld      (trobst), a
                cp      EMAXVAL
                ret     c
                ld      a, SND_GATETOP  ; the CPC's, all the way up
                call    addsound
                ld      a, SONG_STAIRS
                ld      c, 15
                call    cue_song
                ld      a, 1            ; open for good: the way out of here
                ld      (exitopen), a
                jp      stopobj

exitopen        equ     SYSVARS + 56

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
                ld      a, SND_PLATEUP
                call    addsound
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
                ld      a, 1            ; and the wedges with it
                ld      (mskwant), a
                ld      a, (mkspace1 + 1)       ; the id stays the loose floor's, so
                ld      (trobst), a     ; that the space it leaves goes to the
                call    mobstart        ; front of the queue; and it falls
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
                jr      nz, rpceil
                call    trrowcol
                call    rq_block
                ld      a, (blockcol)
                cp      9
                ret     nc
                inc     a
                ld      (blockcol), a
                jr      rq_block

; The bottom row of the room above is this screen's ceiling, and POP marks it
; in topbuf, which RedDFast redraws as D sections alone.  Here it is a queue
; entry with a row of -1, whose floor line blockbot puts at 2 and whose three
; rows are all of it that show.

rpceil:         ld      a, (links + 2)
                ld      hl, trscrn
                cp      (hl)
                ret     nz
                ld      a, (trloc)
                sub     20
                ret     c               ; only its bottom row reaches us
                ld      (blockcol), a
                ld      a, 0xff
                ld      (blockrow), a
                ld      a, 3
                ld      (redh), a
                call    rq_block
                ld      a, (blockcol)
                cp      9
                ret     nc
                inc     a
                ld      (blockcol), a
                jr      rq_block

; ---------------------------------------------------------------- the queue
;
; A redraw is not done where it is asked for but queued, and the queue is
; worked through once a frame, only as far as the frame has room for.  The
; prince's own work is the same whatever the room is doing, so nothing that
; happens around him -- a plate going down, a gate going up, a floor giving
; way -- can make his frame late.  The state of a thing moves on at once;
; only its picture waits, and the picture drawn is always the latest, so a
; gate that moves while it waits simply comes out further up.  A block goes
; a band of RQBAND rows at a time, a step each, and a floor's two masks a
; step each.
;
; An entry: row, column, band, flags -- bit 0 wide, bit 1 a floorpiece mask
; rather than the picture, bits 2 and 3 the step it is on, bit 6 asked for
; again while under way, bit 7 first in the line: a plate, whose press lasts
; a count and is lost if its picture waits.
;
; How much a frame has room for is not guessed: the queue is worked at the
; end of the frame, when his own work is all done, and a step is begun only
; while the ROM's frame count says the frame is still in the first two of
; its three periods.  No step costs as much as a period -- a band of the
; exit door, the heaviest, is under 40000 T -- so one begun in time is done
; before the third period ends.  A frame
; that was heavy on its own, a run or a scroll, leaves the queue for the
; next, and on the real machine the clock counts what contended memory
; costs as well.

; A floor that breaks fills more of the line than the comment above allowed
; for -- its own block and the one to its right, both floorpiece masks, and
; the rubble where it lands -- and a full line is drawn on the spot, which is
; the one thing the queue exists to avoid: two frames of the loose floors ran
; to four periods that way.  Twelve entries, and the line holds.  What waits
; to be shown is one rectangle a pass, so eight is plenty there.

RQMAX           equ     12
RQSMAX          equ     8

rq_block:       xor     a               ; the picture of the block in hand
                jr      rq_add
rq_mask:        ld      a, 2            ; its floorpiece masks
rq_add:         ld      c, a
                ld      a, (redwide)    ; and wide, which redblock would have
                or      c               ; spent
                ld      c, a
                ld      a, (rqprio)     ; and first in the line, if it is
                or      a
                jr      z, rqa1
                set     7, c
rqa1:           ld      a, (rqstart)    ; and the band it starts at: the step
                and     3               ; it is on, and bits 4 and 5 to come
                jr      z, rqa2         ; back to
                rlca
                rlca
                ld      b, a
                rlca
                rlca
                or      b
                or      c
                ld      c, a
rqa2:
                xor     a
                ld      (redwide), a
                ld      a, (rqn)
                or      a
                jr      z, rqnew
                ld      b, a
                ld      hl, rqq
rqfind:         ld      a, (blockrow)   ; the same block already waiting?
                cp      (hl)
                jr      nz, rqnext
                inc     hl
                ld      a, (blockcol)
                cp      (hl)
                dec     hl
                jr      nz, rqnext
                inc     hl
                inc     hl
                inc     hl
                ld      a, (hl)         ; and the same kind
                xor     c
                and     2
                jr      nz, rqback
                ld      a, (hl)         ; the start it has and the new one:
                rrca                    ; it starts at the lower
                rrca
                rrca
                rrca
                and     3
                ld      d, a
                ld      a, c
                rrca
                rrca
                rrca
                rrca
                and     3
                cp      d
                jr      nc, rqs0
                ld      d, a
rqs0:           ld      a, (hl)         ; under way: its step is past its start
                rrca
                rrca
                xor     (hl)
                and     0x0c
                jr      nz, rqsway
                ld      a, d            ; not yet: the start is its step too
                rlca
                rlca
                ld      e, a
                rlca
                rlca
                or      e
                ld      e, a
                ld      a, (hl)
                and     0xc3
                or      e
                jr      rqsw1
rqsway:         ld      a, d            ; under way: once more after it, from
                rlca                    ; that start
                rlca
                rlca
                rlca
                ld      e, a
                ld      a, (hl)
                and     0xcf
                or      e
                or      0x40
rqsw1:          ld      b, a
                ld      a, c            ; and any width, and going first
                and     0x81
                or      b
rqset:          ld      (hl), a
                dec     hl              ; and the taller band
                ld      a, (redh)
                cp      (hl)
                jr      c, rqs1
                ld      (hl), a
rqs1:           bit     7, c            ; up the line, if it goes first
                ret     z
                dec     hl
                dec     hl
                jr      rqfront
rqback:         dec     hl
                dec     hl
                dec     hl
rqnext:         inc     hl
                inc     hl
                inc     hl
                inc     hl
                djnz    rqfind
rqnew:          ld      a, (rqn)
                cp      RQMAX
                jr      c, rqput
                ld      a, c            ; full, which a frame never fills: do
                and     1               ; it now, the old way
                ld      (redwide), a
                bit     1, c
                jp      nz, maskblock
                jp      redblock
rqput:          ld      l, a
                inc     a
                ld      (rqn), a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      de, rqq
                add     hl, de
                ld      a, (blockrow)
                ld      (hl), a
                inc     hl
                ld      a, (blockcol)
                ld      (hl), a
                inc     hl
                ld      a, (redh)
                ld      (hl), a
                inc     hl
                ld      (hl), c
                bit     7, c            ; up the line, if it goes first
                ret     z
                dec     hl
                dec     hl
                dec     hl

; The entry at HL goes up the line, to just behind any others that go first.

rqfront:        push    hl
                ld      de, rqtmp       ; aside
                ld      bc, 4
                ldir
                pop     hl
                ld      de, rqq
rqf1:           or      a               ; nothing ahead of it but those that
                sbc     hl, de          ; go first: it is where it belongs
                add     hl, de
                ret     z
                inc     de
                inc     de
                inc     de
                ld      a, (de)
                inc     de
                bit     7, a
                jr      nz, rqf1        ; that one goes first too: past it
                dec     de
                dec     de
                dec     de
                dec     de
                push    de              ; the rest move down one
                or      a
                sbc     hl, de
                ld      b, h
                ld      c, l
                add     hl, de
                dec     hl
                ld      d, h
                ld      e, l
                inc     de
                inc     de
                inc     de
                inc     de
                lddr
                pop     de              ; and it goes in there
                ld      hl, rqtmp
                ld      bc, 4
                ldir
                ret

; Once a frame, at its end: as much of the queue as the clock allows.

; A step of the view that is due and not yet made comes first: while a gate
; went up, each band the queue put into the room was a band the view had to
; copy again, and the view was never ready -- the camera did not move until
; the gate was done.  So the queue waits, the view has the whole of what a
; frame leaves over, and a frame or two later it is taken and the queue goes
; on where it was; what the gate is doing moves on meanwhile regardless.

rq_run:         xor     a
                ld      (rqdid), a
rqloop:         ld      a, (rqn)
                or      a
                ret     z
                ld      a, (vwwait)     ; the view due: only what goes first
                or      a               ; goes on, a plate's short press
                jr      z, rqgo
                ld      a, (rqq + 3)
                bit     7, a
                ret     z
rqgo:           call    rqtime
                ret     nc
                ld      hl, rqq         ; the head, in hand
                ld      a, (hl)
                ld      (blockrow), a
                inc     hl
                ld      a, (hl)
                ld      (blockcol), a
                inc     hl
                ld      a, (hl)
                ld      (redh), a
                inc     hl
                ld      a, (hl)
                ld      (rqflags), a
                and     1
                ld      (redwide), a
                ld      a, (rqflags)    ; the step it is on
                rrca
                rrca
                and     3
                ld      c, a
                ld      a, (rqflags)
                bit     1, a
                ld      a, c
                jr      nz, rqmaskgo

; A pass is its bands, a frame or more apart, and a gate or the exit door
; moves meanwhile: the bars came out a pixel out between one band and the
; next.  So the height of what moves is taken at the pass's first band and
; kept for the rest -- a pass shows one whole position, the latest when it
; began -- unless another block's pass came in between.

                ld      b, 1            ; take it
                ld      a, (rqflags)
                rrca
                rrca
                ld      hl, rqflags
                xor     (hl)
                and     0x0c            ; the step is past the start: keep what
                jr      z, rqfrz1       ; was taken, if it was this block's
                ld      a, (blockrow)
                ld      hl, rqfrzr
                cp      (hl)
                jr      nz, rqfrz1
                ld      a, (blockcol)
                inc     hl
                cp      (hl)
                jr      nz, rqfrz1
                inc     b
rqfrz1:         ld      a, b
                ld      (rbfrz), a
                ld      a, (blockrow)
                ld      (rqfrzr), a
                ld      a, (blockcol)
                ld      (rqfrzc), a
                ld      a, c
                call    rb_step         ; carry: another band to come
                jr      c, rqmore

; And only the whole pass goes to the screen, when its last band is in: one
; rectangle from the band it started at up to the top, so the screen goes
; from one whole position to the next and never shows the bars at two
; heights at once while a pass is under way.

                ld      a, (rbh)        ; the last band's top row
                ld      b, a
                ld      a, (rbbot)
                sub     b
                inc     a
                ld      b, a
                ld      a, (rqflags)    ; and the band the pass began at
                rlca
                rlca
                rlca
                rlca
                and     0x30            ; sixteen rows to each
                ld      c, a
                ld      a, (dy)
                sub     c
                ld      (rbbot), a      ; its bottom
                sub     b
                inc     a
                ld      (rbh), a        ; and all its rows
                call    rq_showadd
                jr      rqlast
rqmore:         ld      hl, rqq + 3     ; on to its next step
                ld      a, (hl)
                add     a, 4
                ld      (hl), a
                jp      rqloop
rqmaskgo:       call    mb_step
                jr      c, rqmore
rqlast:         ld      hl, rqq + 3
                bit     6, (hl)         ; moved again meanwhile: from the top
                jr      z, rqdone
                ld      a, (hl)
                and     0xb3            ; width, kind, start and going first
                ld      b, a            ; are all it keeps, and the step goes
                rrca                    ; back to the start
                rrca
                and     0x0c
                or      b
                ld      (hl), a

; And not in this frame: the pass just done goes to the screen next frame,
; copied out of the room, and a first band of the next one drawn into the
; room meanwhile went with it -- the bars at two heights after all.  It goes
; to the back of the line as well, or a gate that keeps moving would keep
; the head of it and nothing behind it would be drawn until it stopped.

                ld      a, (rqn)
                dec     a
                ret     z
                add     a, a
                add     a, a
                ld      c, a
                ld      b, 0
                push    bc
                ld      hl, rqq
                ld      de, rqtmp
                ld      bc, 4
                ldir
                pop     bc
                push    bc
                ld      hl, rqq + 4
                ld      de, rqq
                ldir
                pop     bc
                ld      hl, rqq
                add     hl, bc
                ex      de, hl
                ld      hl, rqtmp
                ld      bc, 4
                ldir
                ret
rqdone:         ld      a, (rqn)        ; off the head
                dec     a
                ld      (rqn), a
                jp      z, rqloop
                add     a, a
                add     a, a
                ld      c, a
                ld      b, 0
                ld      hl, rqq + 4
                ld      de, rqq
                ldir
                jp      rqloop

; Carry: a step may begin.  The first of a frame goes whatever the clock
; says: on the machine a frame's own work often ends in its third period, and
; holding the queue back then drew nothing at all -- floors did not wiggle, a
; flask taken stayed, gates did not rise.  After that the clock counts whole
; periods and a step can be most of one -- the exit door's bands run to
; seventy thousand cycles -- so: any more while the frame is in its first
; period, one more begun in its second, and none in its third.

rqtime:         ld      hl, rqdid
                ld      a, (hl)
                or      a
                jr      z, rqtyes       ; the first
                ld      a, (FRAMES)
                ld      de, frstart
                ex      de, hl
                sub     (hl)
                ex      de, hl
                jr      z, rqtyes       ; still the first period
rqcp:           cp      FRAME_WAIT - 1
                ret     nc              ; the last: nothing more
                bit     1, (hl)         ; the middle one: a single step
                ret     nz
                set     1, (hl)
rqtyes:         set     0, (hl)
                scf
                ret

; A block that has gone back into the room still has to reach the working
; copy, and at the end of a frame he has just been drawn into it: the room
; would go down over him.  So it waits for the next frame, where rq_shows
; does it after he has been rubbed out and before he is drawn again.

rq_showadd:     ld      a, (rqsn)
                cp      RQSMAX
                jr      c, rqsa1
                ld      a, 1            ; more than that: the whole screen
                ld      (fullshow), a   ; from the room, next frame
                xor     a
                ld      (redwide), a
                ret
rqsa1:          ld      l, a
                inc     a
                ld      (rqsn), a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                ld      de, rqs
                add     hl, de
                ld      a, (blockrow)
                ld      (hl), a
                inc     hl
                ld      a, (blockcol)
                ld      (hl), a
                inc     hl
                ld      a, (rbh)        ; the band just drawn
                ld      (hl), a
                inc     hl
                ld      a, (rbbot)      ; how far up from the floor line it
                ld      b, a            ; sits, and wide
                ld      a, (dy)
                sub     b
                add     a, a
                ld      b, a
                ld      a, (redwide)
                or      b
                ld      (hl), a
                xor     a
                ld      (redwide), a
                ret

rq_shows:       ld      a, (rqsn)
                or      a
                ret     z
                ld      b, a
                ld      hl, rqs
rqsh1:          push    bc
                ld      a, (hl)
                ld      (blockrow), a
                inc     hl
                ld      a, (hl)
                ld      (blockcol), a
                inc     hl
                ld      a, (hl)
                ld      (redh), a
                inc     hl
                ld      a, (hl)
                ld      (redwide), a
                inc     hl
                push    hl
                ld      a, (blockrow)   ; its floor line, and the band that
                ld      hl, blockbot + 1        ; far above it
                add     a, l
                ld      l, a
                ld      a, (redwide)
                srl     a
                ld      c, a
                ld      a, (hl)
                sub     c
                ld      (dy), a
                ld      a, (redwide)
                and     1
                ld      (redwide), a
                call    page_art
                call    redshow
                xor     a
                ld      (redwide), a
                pop     hl
                pop     bc
                djnz    rqsh1
                xor     a
                ld      (rqsn), a
                ret

rqn             equ     SYSVARS + 57    ; entries waiting
rqflags:        db      0
rqprio          equ     0x5C15          ; the next request goes first
rqstart         equ     0x5C16          ; and the band it starts at
rbfrz           equ     0x5C17          ; rb_setup: 1 take, 2 keep the state
rqfrzv          equ     0x5C18          ; the state taken
rqfrzr:         db      0               ; for this block
rqfrzc:         db      0
rqtmp:          ds      4               ; an entry, on its way up the line
rqdid:          db      0               ; a step done this frame
rqsn:           db      0               ; blocks waiting to be shown

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
                jp      rq_block        ; into the block after this one

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

                ld      a, (blockrow)   ; getprev's answer was taken when the
                add     a, a            ; room was entered, and the bars have
                ld      l, a            ; risen since: a redraw of column zero
                ld      h, 0            ; reads that cached column and would
                ld      de, prevblk     ; keep drawing the gate as it stood
                add     hl, de
                ld      a, (aoid)
                ld      (hl), a
                inc     hl
                ld      a, (trobst)
                ld      (hl), a

                xor     a               ; its leftmost column
                ld      (blockcol), a

rgdraw:         call    rq_block
                xor     a               ; the block above: from its bottom
                ld      (rqstart), a
                ld      a, (blockrow)
                or      a
                ret     z
                dec     a
                ld      (blockrow), a
                jp      rq_block

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
trloc           equ     0x5C19
trscrn          equ     0x5C1A
trdirec         equ     0x5C1B
trobst          equ     0x5C1C
aoid            equ     0x5C1D
linkindex:      db      0
pptype          equ     0x5C1E
blueptr         equ     0x5C1F
tcsrc:          db      0
tcdst:          db      0
gateinc:        db      -1, 4, 4
gatevel:        db      0, 0, 0, 20, 40, 60, 80, 100, 120
