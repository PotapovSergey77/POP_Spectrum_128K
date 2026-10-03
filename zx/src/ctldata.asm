; ---------------------------------------------------------------- controls
;
; The controls screen's words and the keys' names (ctlmenu.asm), and the
; routines that write them, which call nothing of the game's, at the top
; of the art bank past the canvas bank's code: assembled before the game,
; which takes their addresses from ctldata.inc (build.sh), and put on the
; end of the art bank's tape block.  Nothing writes there before the game
; begins, when the art bank is cleared for the room.

CMDATA          equ     0xFE20

CM_INK          equ     0x0F            ; the story's white on blue
CM_HI           equ     0x0E            ; and its border's yellow line
CM_ITEM         equ     7               ; the first of the four's rows

                org     CMDATA

; HL = the words, at row A in the middle, in colour C.

cmcentre:       push    af
                push    hl
                ld      b, 32
cmc1:           ld      a, (hl)
                inc     hl
                or      a
                jr      z, cmc3
                cp      5
                jr      nc, cmc2
                push    hl              ; a key's name in full
                call    cmword
cmcw:           ld      a, (hl)
                inc     hl
                dec     b
                rla
                jr      nc, cmcw
                pop     hl
                jr      cmc1
cmc2:           dec     b
                jr      cmc1
cmc3:           srl     b
                ld      e, b
                pop     hl
                pop     af
                push    hl
                call    cmat
                pop     hl

; HL = the words, at DE on the screen, in colour C.

cmstr:          ld      a, (hl)
                inc     hl
                or      a
                ret     z
                cp      5
                jr      nc, cms2
                push    hl              ; a key's name: its last letter has
                call    cmword          ; bit 7 set
cms1:           ld      a, (hl)
                inc     hl
                push    af
                call    cmchar
                pop     af
                rla
                jr      nc, cms1
                pop     hl
                jr      cmstr
cms2:           call    cmchar
                jr      cmstr

; HL = the name of key A, 1 to 4.

cmword:         ld      hl, cmwords
                dec     a
                ret     z
cmwd1:           bit     7, (hl)
                inc     hl
                jr      z, cmwd1
                dec     a
                jr      nz, cmwd1
                ret

; A letter of the ROM's at DE, colour C; DE on a cell.  HL kept.

cmchar:         push    hl
                and     0x7f
                add     a, 0x80         ; 0x3C00 + 8A
                ld      l, a
                ld      h, 0x07
                add     hl, hl
                add     hl, hl
                add     hl, hl
                call    cmglyph
                pop     hl
                ret

; The eight bytes at HL, the same.

cmglyph:        push    de
                ld      b, 8
cmch1:          ld      a, (hl)
                ld      (de), a
                inc     hl
                inc     d
                djnz    cmch1
                pop     de
                ld      a, d            ; its colour
                rrca
                rrca
                rrca
                and     3
                or      0x58
                ld      h, a
                ld      l, e
                ld      (hl), c
                inc     e
                ret

; Row A, column E: DE its first cell on bank 5's screen.

cmat:           ld      d, a
                and     0x18
                or      0x40
                ld      h, a
                ld      a, d
                and     7
                rrca
                rrca
                rrca
                add     a, e
                ld      e, a
                ld      d, h
                ret

; Row A inside the border cleared: its pixels, and the story's colour.

cmrow:          ld      e, 2
                call    cmat
                ex      de, hl
                ld      c, 8
cmr1:           push    hl
                ld      b, 28
cmr2:           ld      (hl), 0
                inc     l
                djnz    cmr2
                pop     hl
                inc     h
                dec     c
                jr      nz, cmr1
                ld      a, h
                sub     8
                rrca
                rrca
                rrca
                and     3
                or      0x58
                ld      h, a
                ld      b, 28
cmr3:           ld      (hl), CM_INK
                inc     l
                djnz    cmr3
                ret

; Words at places: row, column, colour, the letters, 0; and 0xFF.

cmblock:        ld      a, (hl)
                inc     a
                ret     z
                dec     a
                inc     hl
                ld      e, (hl)
                inc     hl
                ld      c, (hl)
                inc     hl
                push    hl
                call    cmat
                pop     hl
                call    cmstr
                jr      cmblock

cmofs:          db      6, 8, 2, 4, 0   ; left, right, up, down, the button
cmasks:         db      "LEFT", 0, "RIGHT", 0, "UP", 0, "DOWN", 0, "FIRE", 0


cmtext:         db      4, 12, CM_HI, "CONTROLS", 0
                db      7, 6, CM_HI, "1", 0
                db      7, 9, CM_INK, "Keyboard", 0
                db      9, 6, CM_HI, "2", 0
                db      9, 9, CM_INK, "Kempston Joystick", 0
                db      11, 6, CM_HI, "3", 0
                db      11, 9, CM_INK, "Sinclair Joystick", 0
                db      13, 6, CM_HI, "4", 0
                db      13, 9, CM_INK, "Define Keys", 0
                db      15, 6, CM_HI, "0", 0
                db      15, 9, CM_INK, "Start Game", 0
                db      0xff

; The keys by row and bit, as IN A,(254) has them; 1 to 4 are names.

keynames:       db      1, "ZXCV", "ASDFG", "QWERT", "12345", "09876"
                db      "POIUY", 2, "LKJH", 3, 4, "MNB"
cmwords:        db      "CAP", "S" + 0x80, "ENTE", "R" + 0x80
                db      "SPAC", "E" + 0x80, "SYM", "B" + 0x80

keysinc:        db      0xef, 0x01, 0xef, 0x02, 0xef, 0x04, 0xef, 0x10
                db      0xef, 0x08      ; 0, 9, 8, 6, 7

cmarw:          db      0x00, 0x10, 0x18, 0x7c, 0x18, 0x10, 0x00, 0x00 ; the arrow

cmdend:
