; ---------------------------------------------------------------- PlayCut1
;
; The princess waiting, between levels one and two: PlayCut1 in SUBS.S,
; which TOPCTRL.S plays before level two begins -- the room, the hourglass
; with its sand running, the princess standing, and the song, s_Timer, the
; Amstrad CPC's tune 6.  A key ends it, as a button does the Apple's.
; Assembled once for each scene the tape has (build.sh): PlayCut2, before
; level four, is the same but for the princess lying down.
;
; It is not in the program.  The tape has it before level two, a block of
; its own that levelgo loads into the art bank with the level, and runs at
; 0xC000 once the tape is stopped: a few bytes there put this code where it
; runs, in the working copy -- whose room is not wanted until the next room
; is built -- and jump to it (see build.sh).  The rest of the block is the
; room and the pictures packed, and the tune.  What the scene needs besides,
; princessscr.py puts at the top of the art bank: everything in it is free
; while a level changes, and none of it outlives the scene.
;
; The engine is the titles' own, cutplay.asm.  It composes its band where
; the room's code lies, and that code is running -- levelgo called this --
; so it is put by in the art bank first, and back before the return.  And
; the art bank is left nought, as start leaves it for the first room.

                include "popsyms.inc"
                include "cutsel.inc"    ; the scene's: build.sh

                org     work

cut1go:         ld      (c1sp), sp
                ld      a, BANK_ART     ; the room's code put by
                call    pageset
                ld      hl, roomblk
                ld      de, CUT1_RBSAVE
                ld      bc, RB1LEN
                ldir
                ld      a, BANK_ART     ; the tune is in the art bank
                ld      (sfxbank), a
c1up:           halt                    ; ENTER or SPACE may still be down
                xor     a               ; from stopping the tape
                in      a, (254)
                cpl
                and     0x1F
                jr      nz, c1up
                call    princess

c1key:          ld      sp, (c1sp)      ; the end, or a key
                call    ststop
                ld      a, BANK_CVS     ; and the game's sounds its own
                ld      (sfxbank), a
                ld      a, BANK_ART
                call    pageset
                ld      hl, CUT1_RBSAVE ; the room's code back
                ld      de, roomblk
                ld      bc, RB1LEN
                ldir
                ld      hl, 0xC000      ; the art bank nought, up to the
                ld      de, 0xC001      ; interrupt's way in
                ld      bc, 0x4000 - ISRSTUBLEN - 1
                ld      (hl), 0
                ldir
                call    black7          ; and both screens black, the
                ld      hl, 0x4000      ; ordinary one shown
                call    clear
                xor     a
                jp      setvis

c1sp:           dw      0

CUT_BANK        equ     BANK_ART
CUT_TUNE        equ     0xFF            ; its one tune
CUT_HOLD        equ     1
CUT_BUFOFF      equ     0               ; its pictures are in its own block
cutkey          equ     c1key

tunes:          dw      CUT1_TUNE, CUT1_TUNEND

                include "cutplay.asm"

cutfixed:       incbin  "cutsel.bin"
cut1end:
