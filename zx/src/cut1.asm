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
;
; The ending (CUT_ENDING) is PlayCut7 the same way, off the tape after the
; last level as the scene before a level would be -- YouWin in TOPCTRL.S --
; and then the Epilog, whose screens and tune levelgo has brought in with
; it, as the next level, into the background bank.  It never goes back:
; nothing of the room's code is kept, and its band goes past this code.

                include "popsyms.inc"
                include "cutsel.inc"    ; the scene's: build.sh

                org     work

cut1go:         ld      (c1sp), sp
                if      CUT_ENDING = 0
                ld      a, BANK_ART     ; the room's code put by
                call    pageset
                ld      hl, roomblk
                ld      de, CUT1_RBSAVE
                ld      bc, RB1LEN
                ldir
                endif
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
                if      CUT_ENDING
                jp      epilog
                else
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
                endif

c1sp:           dw      0

CUT_BANK        equ     BANK_ART
CUT_TUNE        equ     0xFF            ; its one tune
                if      CUT_ENDING
CUT_HOLD        equ     0               ; its tune is over long before
CUT_BUFOFF      equ     0x400           ; the band past this code: see build.sh
                else
CUT_HOLD        equ     1
CUT_BUFOFF      equ     0               ; its pictures are in its own block
                endif
cutkey          equ     c1key

tunes:          dw      CUT1_TUNE, CUT1_TUNEND

                include "cutplay.asm"

                if      CUT_ENDING

; ---------------------------------------------------------------- the Epilog
;
; EPILOG and Epilog in MASTER.S, once PlayCut7 is over.  A blackout, and the
; story's end unpacked out of sight and shown at once; s_Epilog, which no
; key stops (PlaySongNI) -- the CPC's tune 8, the Amstrad's whole ending;
; a pause, and the splash laid over it a column at a time from the left, as
; DBLEXPAND lays it on the page shown; a longer pause, s_Curtain -- which
; the CPC has no tune for -- and a pause; a blackout.  Then a key, and the
; Apple goes to its titles; they are far back along the tape, and the
; machine starts again instead.
;
; pauseNI's count is twenty times round 256 of a five cycle loop, some 25
; milliseconds: 15, 75 and 60 of them in fiftieths.

EPIPAUSE1       equ     19
EPIPAUSE2       equ     94
EPIPAUSE3       equ     75

epilog:         call    black7          ; blackout: the second screen, black,
                ld      a, 0x80         ; shown
                call    setvis
                ld      hl, EPI_SCREEN  ; the story's end, all at once
                ld      de, 0x4000
                ld      a, BANK_BG
                call    unpackto
                xor     a
                call    setvis
                ld      a, BANK_BG      ; s_Epilog, to its end
                ld      (sfxbank), a
                ld      de, EPI_TUNE
                ld      bc, EPI_TUNEND
                call    ituneat
epsong:         halt
                ld      a, (sfxtimer)
                or      a
                jr      nz, epsong
                ld      a, EPIPAUSE1
                call    epause
                call    copy57          ; unpacksplash: the story on the
                ld      a, 0x80         ; second screen, shown, the splash
                call    setvis          ; under it, and wiped on
                ld      hl, EPI_SPLASH
                ld      de, 0x4000
                ld      a, BANK_BG
                call    unpackto
                call    wipe
                xor     a
                call    setvis
                ld      a, EPIPAUSE2
                call    epause
                ld      a, EPIPAUSE3    ; (s_Curtain)
                call    epause
                call    black7          ; blackout
                ld      a, 0x80
                call    setvis

epup:           halt                    ; and a key, new
                call    epkey
                jr      nz, epup
epdown:         halt
                call    epkey
                jr      z, epdown
                di                      ; the 128's own ROM, and its start
                ld      bc, 0x7FFD
                xor     a
                out     (c), a
                rst     0

epkey:          xor     a               ; any key: NZ
                in      a, (254)
                cpl
                and     0x1F
                ret

; A fiftieths.

epause:         halt
                dec     a
                jr      nz, epause
                ret

; Bank 5 onto the second screen, shown, a character column at a time from
; the left, as intro.asm wipes the story on.

wipe:           ld      a, BANK_CANVAS
                call    pageset
                ld      c, 0
wpcol:          ld      l, c
                ld      h, 0x40
                ld      e, c
                ld      d, 0xC0
                ld      b, 24 + 192
wprow:          ld      a, (hl)
                ld      (de), a
                push    bc
                ld      bc, 32
                add     hl, bc
                ex      de, hl
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    wprow
                halt
                bit     0, c
                jr      z, wpnext
                halt
wpnext:         inc     c
                ld      a, c
                cp      32
                jr      nz, wpcol
                ret

                endif

cutfixed:       incbin  "cutsel.bin"
cut1end:
