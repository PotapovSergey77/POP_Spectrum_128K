; ---------------------------------------------------------------- the loader
;
; The tape's own loader, as Spectrum games had one: BASIC loads this and no
; more, and this loads the rest -- the title first, the palace with Prince of
; Persia over it, line by line as LOAD SCREEN$ would, and then everything
; else with how much of it is in, in per cent, at the bottom right: white
; on black, under the title.
;
; The blocks are bare data blocks one after another, and they are read with
; the ROM's LD-BYTES -- the same code, copied here so that it can count:
; every 256 bytes the count is added up and, when it has gone up by one per
; cent, the figures that change are drawn.  That is done between two bytes,
; where the ROM itself only gets ready for the next bit, and the time it
; takes is given back to the first bit's edge count (LD B,$B2 + k): the bit
; is read exactly as the ROM would read it.  Here, at the top of the fixed
; map, the code is out of the ULA's way, which LD-BYTES's timing needs.
;
; The last block is the part of the program this loader sits in: a stub low
; down loads it with the ROM's LD-BYTES and goes into the game.
;
; maketap.py assembles it, with ldrtab.inc: the blocks, the step of the count,
; where the stub goes and where the game is entered.

                include "ldrtab.inc"

                org     LDRORG

; The figures, a page to themselves so that a figure's row is an INC L away:
; the 48K ROM's 0 to 9, its %, and a blank.

GL_PCT          equ     10
GL_BLANK        equ     11

font:           db      0x00, 0x3C, 0x46, 0x4A, 0x52, 0x62, 0x3C, 0x00  ; 0
                db      0x00, 0x18, 0x28, 0x08, 0x08, 0x08, 0x3E, 0x00  ; 1
                db      0x00, 0x3C, 0x42, 0x02, 0x3C, 0x40, 0x7E, 0x00  ; 2
                db      0x00, 0x3C, 0x42, 0x0C, 0x02, 0x42, 0x3C, 0x00  ; 3
                db      0x00, 0x08, 0x18, 0x28, 0x48, 0x7E, 0x08, 0x00  ; 4
                db      0x00, 0x7E, 0x40, 0x7C, 0x02, 0x42, 0x3C, 0x00  ; 5
                db      0x00, 0x3C, 0x40, 0x7C, 0x42, 0x42, 0x3C, 0x00  ; 6
                db      0x00, 0x7E, 0x02, 0x04, 0x08, 0x10, 0x10, 0x00  ; 7
                db      0x00, 0x3C, 0x42, 0x3C, 0x42, 0x42, 0x3C, 0x00  ; 8
                db      0x00, 0x3C, 0x42, 0x42, 0x3E, 0x02, 0x3C, 0x00  ; 9
                db      0x00, 0x62, 0x64, 0x08, 0x10, 0x26, 0x46, 0x00  ; %
                db      0, 0, 0, 0, 0, 0, 0, 0                          ; blank

PCROW           equ     0x50FC          ; character row 23, column 28
PCATTR          equ     0x5AFC
PCINK           equ     0x47            ; bright white on black

; From RANDOMIZE USR, with the 128's BASIC paged and nothing of the game in.

entry:          di
                ld      sp, LDRSTACK    ; over this code, under the window
                ld      ix, 0x4000      ; the title: no count yet (kvar 0)
                ld      de, 6912
                call    ldblk
                ld      hl, PCATTR      ; then the count's four cells
                ld      b, 4
arm1:           ld      (hl), PCINK
                inc     l
                djnz    arm1
                ld      a, GL_BLANK
                ld      e, PCROW & 0xff
                call    drawd
                ld      a, GL_BLANK
                ld      e, (PCROW & 0xff) + 1
                call    drawd
                xor     a
                ld      e, (PCROW & 0xff) + 2
                call    drawd
                ld      a, GL_PCT
                ld      e, (PCROW & 0xff) + 3
                call    drawd
                ld      hl, KSTEP
                ld      (kvar), hl

                ld      hl, blocks      ; bank (0xff: none), where, how long
nextb:          ld      a, (hl)
                cp      0xfe
                jr      z, last
                inc     hl
                cp      8
                jr      nc, nopage
                or      0x10            ; and the 48K ROM, always
                ld      bc, 0x7ffd
                out     (c), a
nopage:         ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                push    de
                pop     ix
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                push    hl
                call    ldblk
                pop     hl
                jr      nextb

; The stub, low down, out of the way of the last block, and into it.

last:           ld      hl, stubsrc
                ld      de, STUBAT
                ld      bc, stubend - stubsrc
                ldir
                jp      STUBAT

; IX where, DE how long: until it loads.  A block that went wrong is waited
; for again -- the tape wound back to it.

ldblk:          push    ix
                push    de
                ld      a, 0xff
                scf
                call    ldbytes
                pop     de
                pop     ix
                ret     c
                jr      ldblk

; LD-BYTES, 0556 in the 48K ROM, all but its way out through SA/LD-RET.

ldbytes:        inc     d
                ex      af, af'
                dec     d
                di
                ld      a, 0x0f
                out     (0xfe), a
                in      a, (0xfe)
                rra
                and     0x20
                or      0x02
                ld      c, a
                cp      a
ldbreak:        ret     nz
ldstart:        call    ldedge1
                jr      nc, ldbreak
                ld      hl, 0x0415
ldwait:         djnz    ldwait
                dec     hl
                ld      a, h
                or      l
                jr      nz, ldwait
                call    ldedge2
                jr      nc, ldbreak
ldleader:       ld      b, 0x9c
                call    ldedge2
                jr      nc, ldbreak
                ld      a, 0xc6
                cp      b
                jr      nc, ldstart
                inc     h
                jr      nz, ldleader
ldsync:         ld      b, 0xc9
                call    ldedge1
                jr      nc, ldbreak
                ld      a, b
                cp      0xd4
                jr      nc, ldsync
                call    ldedge1
                ret     nc
                ld      a, c
                xor     0x03
                ld      c, a
                ld      h, 0
                ld      b, 0xb0
                jr      ldmarker
ldloop:         ex      af, af'
                jr      nz, ldflag
                jr      nc, ldverify
                ld      (ix + 0), l
                jr      ldnext
ldflag:         rl      c
                xor     l
                ret     nz
                ld      a, c
                rra
                ld      c, a
                inc     de
                jr      lddec
ldverify:       ld      a, (ix + 0)
                xor     l
                ret     nz
ldnext:         inc     ix
lddec:          dec     de
                ex      af, af'
                ld      a, e            ; another 256 in: the count
                or      a
                jr      z, hook
                ld      b, 0xb2
ldmarker:       ld      l, 1
ld8bits:        call    ldedge2
                ret     nc
                ld      a, 0xcb
                cp      b
                rl      l
                ld      b, 0xb0
                jp      nc, ld8bits
                ld      a, h
                xor     l
                ld      h, a
                ld      a, d
                or      e
                jr      nz, ldloop
                ld      a, h
                cp      1
                ret
ldedge2:        call    ldedge1
                ret     nc
ldedge1:        ld      a, 0x16
lddelay:        dec     a
                jr      nz, lddelay
                and     a
ldsample:       inc     b
                ret     z
                ld      a, 0x7f
                in      a, (0xfe)
                rra
                ret     nc
                xor     c
                and     0x20
                jr      z, ldsample
                ld      a, c
                cpl
                ld      c, a
                and     7
                or      8
                out     (0xfe), a
                scf
                ret

; Every 256 bytes: KSTEP more of a per cent in 65536ths, and when that goes
; over, one per cent more, and the figures it changes drawn.  In the other
; registers, all of them free; each way back to the bits gives the first
; bit's count the time it took, in its sampling loop's 59 T-states a round
; (the ROM's own path from LD-DEC is LD B,$B2, 7 T: what is over that is made
; up).

hook:           exx
                ld      hl, (acc)
                ld      de, (kvar)
                add     hl, de
                ld      (acc), hl
                jr      c, hkinc
                exx                     ; 115 T: 108 over
                ld      b, 0xb2 + 2
                jp      ldmarker
hkinc:          ld      hl, pcunit
                inc     (hl)
                ld      a, (hl)
                cp      10
                jr      z, hkcarry
                ld      e, (PCROW & 0xff) + 2
                call    drawd
                exx                     ; 402 T: 395 over
                ld      b, 0xb2 + 7
                jp      ldmarker
hkcarry:        ld      (hl), 0
                dec     hl              ; the tens, blank before ten
                ld      a, (hl)
                cp      GL_BLANK
                jr      nz, hkten
                xor     a               ; blank: one, as nought would be
hkten:          inc     a
                cp      10
                jr      z, hk100
                ld      (hl), a
                ld      e, (PCROW & 0xff) + 1
                call    drawd
                xor     a
                ld      e, (PCROW & 0xff) + 2
                call    drawd
                exx                     ; 718 T: 711 over
                ld      b, 0xb2 + 12
                jp      ldmarker
hk100:          ld      (hl), 0
                dec     hl
                ld      (hl), 1
                ld      a, 1
                ld      e, PCROW & 0xff
                call    drawd
                xor     a
                ld      e, (PCROW & 0xff) + 1
                call    drawd
                xor     a
                ld      e, (PCROW & 0xff) + 2
                call    drawd
                exx                     ; 993 T: 986 over
                ld      b, 0xb2 + 17
                jp      ldmarker

; Figure A in the cell at PCROW's row, column E.  216 T.

drawd:          add     a, a
                add     a, a
                add     a, a
                ld      l, a
                ld      h, font / 256
                ld      d, PCROW / 256
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ld      a, (hl)
                ld      (de), a
                inc     l
                inc     d
                ret

acc:            dw      0
kvar:           dw      0               ; nought while the title loads
pchund:         db      GL_BLANK
pcten:          db      GL_BLANK
pcunit:         db      0

; The last block, by the ROM's LD-BYTES from where SA/LD-RET would be pushed
; -- with our own way back instead, so that SPACE held is no BREAK into a
; BASIC that is gone -- and then the game.  Moved to STUBAT before it runs:
; its jumps are relative, its one address worked out for there.

stubsrc:        ld      sp, STUBAT
stagain:        ld      ix, POPB_AT
                ld      de, POPB_LEN
                ld      a, 0xff
                scf
                inc     d
                ex      af, af'
                dec     d
                di
                ld      a, 0x0f
                out     (0xfe), a
                ld      hl, STUBAT + stret - stubsrc
                push    hl
                jp      0x0562
stret:          jr      nc, stagain
                jp      ENTRY
stubend:

blocks:
                include "ldrblk.inc"
                db      0xfe

ldrend:
