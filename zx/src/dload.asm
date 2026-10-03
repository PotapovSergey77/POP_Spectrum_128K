; ---------------------------------------------------------------- the disk
;
; What the disk version reads its blocks with, where the tape's took LD-BYTES:
; DE bytes off the disk to HL, in whatever bank is paged, from the sector
; DPOS says on, and DPOS left at the one after them.  Each block starts a
; sector of its own (maketrd.py), so the next is where the last one left off,
; the way the tape went on.
;
; DPOS: the cylinder in its high byte, and in its low the side times sixteen
; and the sector -- nought to 31 a cylinder, both sides, the way a TR-DOS
; disk's tracks are laid, so that it counts on as a sector number would.
;
; Not through TR-DOS's own entry at 0x3D13: that wants its system variables,
; which the game has long taken for its own.  Only two pieces of its ROM, at
; the addresses every TR-DOS from 5.03 on has them -- OUT (C), A and the loop
; that reads a sector -- and the controller driven here (dgate.asm).  The
; whole sectors straight to where they go, as TR-DOS reads a file, quickly
; enough after each other that the next is not gone by; the last one, of
; which the block wants only some, into DBUF, a page of its own out of its
; way, and from there as far as the block goes.  Interrupts off: the ROM is
; paged in and out under the program at every step, and an interrupt there
; would come back to the wrong one.
;
; Whoever includes it says where DPOS and DBUF are.

dload:          ld      a, d            ; a whole sector of it still
                or      a
                jr      z, dllast
                push    de
                call    dsect
                pop     de
                dec     d
                jr      dload
dllast:         ld      a, e            ; and the few after it
                or      a
                ret     z
                push    de
                push    hl
                ld      hl, DBUF
                call    dsect
                pop     de
                pop     bc
                ld      b, 0
                ld      hl, DBUF
                ldir
                ret

; The sector at DPOS to HL, HL past it, DPOS on.

dagain:         ex      de, hl
dsect:          push    hl              ; where it goes
                ld      hl, (DPOS)
                ld      a, l            ; drive A, the side: 0x3C the first,
                and     0x10            ; 0x2C the second
                xor     0x3C
                ld      c, 0xFF
                call    dout
                ld      a, h            ; the head to the cylinder
                ld      c, 0x7F
                call    dout
                ld      a, 0x18         ; SEEK, the head loaded
                call    dcmd
                ld      a, l            ; the sector, counted from one
                and     15
                inc     a
                ld      c, 0x5F
                call    dout
                pop     hl
                push    hl
                ld      a, 0x80         ; READ SECTOR
                call    dcmd
                pop     de              ; none of it -- the drive coming up
                ld      a, d            ; to speed, say, and the sector not
                inc     a               ; found -- and it is read again
                cp      h
                jr      nz, dagain
                push    hl              ; on to the next
                ld      hl, DPOS
                ld      a, (hl)
                inc     a
                and     31
                ld      (hl), a
                jr      nz, dsnext
                inc     hl
                inc     (hl)
dsnext:         pop     hl
                ret
