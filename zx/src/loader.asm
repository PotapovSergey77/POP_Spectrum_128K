; ---------------------------------------------------------------- the loader
;
; The disk's loader.  The disk's BASIC, boot, has TR-DOS load it into the
; screen, black, and calls it there; the sector in front of it (maketrd.py)
; copies the rest down to the buffers under the program, whose game has not
; begun, and goes to boot.  From there it is the one thing that reads the
; disk: the program, and each bank as the tape's loader paged them and
; loaded them -- straight off the disk, through dload.asm, TR-DOS left
; alone -- and then start, with the game's DPOS at the first level's block,
; which follows the banks on the disk as it did on the tape.
;
; It is read again, over the same buffers, when the game is over: by
; levelgo when the hour has run out, which comes in at timeup -- PlayCut6
; off the disk into the art bank, and played as the scenes before a level
; are -- and by that scene and the Epilog when they are done, which come in
; at boot: the game from the start, its titles first, as the Apple goes to
; them.
;
; ldr.inc (build.sh) has where everything is on the disk, how long, and
; what of the game it wants.

                include "ldr.inc"

                org     LDRORG

                jp      boot            ; the game, from the start
                jp      timeup          ; PlayCut6

boot:           di
                ld      sp, LDRSTACK
                xor     a
                out     (254), a
                ld      a, 0x10         ; the 48K ROM, bank 0, the ordinary
                ld      bc, 0x7FFD      ; screen, black
                out     (c), a
                ld      hl, 0x5800
                ld      de, 0x5801
                ld      bc, 767
                ld      (hl), 0
                ldir
                ld      a, 8            ; and the AY quiet
                ld      d, 0
bq:             ld      bc, 0xFFFD
                out     (c), a
                ld      b, 0xBF
                out     (c), d
                inc     a
                cp      11
                jr      nz, bq
                ld      hl, MAINPOS
                ld      (dpos), hl
                ld      hl, MAINORG     ; the program
                ld      de, MAINLEN
                call    dload
                ld      hl, banks       ; and the banks, at the window
bk:             ld      a, (hl)
                inc     hl
                or      a
                jp      m, bkdone
                or      0x10
                ld      bc, 0x7FFD
                out     (c), a
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                push    hl
                ld      hl, 0xC000
                call    dload
                pop     hl
                jr      bk
bkdone:         ld      hl, (dpos)      ; where the levels begin
                ld      (GDPOS), hl
                ld      a, 0x10
                ld      bc, 0x7FFD
                out     (c), a
                jp      START

; The hour run out (lgdead): PlayCut6 into the art bank, as levelgo loads a
; scene, and run.  Its own code takes it from there.

timeup:         di
                ld      a, 0x10 + BANK_ART
                ld      bc, 0x7FFD
                out     (c), a
                ld      hl, CUT6POS
                ld      (dpos), hl
                ld      hl, 0xC000
                ld      de, CUT6LEN
                call    dload
                ei
                jp      0xC000

dpos:           dw      0
DPOS            equ     dpos
DBUF            equ     0x5B00          ; REVTAB, which start makes

                include "dload.asm"
                include "dgate.asm"
                include "dout.asm"

banks:                                  ; bank, length, a line each
                include "ldrbanks.inc"
                db      0xFF
ldrend:
