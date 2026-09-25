; ---------------------------------------------------------------- the titles
;
; ATTRACTMODE in MASTER.S, as far as the game: the splash with its credits,
; the title, the story, the princess's room, the story's end -- and then not
; the demo but the first level, as a key pressed at any moment gives.
;
; The Apple keeps a double hi-res page 2 behind the one shown, the splash
; clean, and a credit is drawn into page 1 while page 2 is on the screen, so
; it appears whole; CleanScreen shows page 2 again and copies it back.  Here
; page 1 is the ordinary screen, bank 5, and page 2 the 128's second, bank 7:
; setvis shows one or the other.  The screens come packed in the art bank --
; see titlescr.py -- and are unpacked onto bank 5 with that bank paged in.
;
; The music is the Amstrad CPC's (cpcmusic.py): its first tune from the
; splash, its second with the story, and three of its own in the princess's
; room -- the CPC starts each where these do, and each plays on until the
; next or its end.  The pauses are still the ones PlaySongI makes when it is
; off.  TPAUSE counts twice round 256 calls of StartGame?, some 32
; milliseconds a count.

intro:          ld      (introsp), sp
                ei
                call    black7          ; blackout: the second screen, black,
                ld      a, 0x80         ; shown
                call    setvis

                xor     a               ; the CPC's title music
                call    itune
                ld      hl, T_SPLASH    ; PubCredit: the splash, all at once,
                call    unpack          ; and a copy of it behind
                xor     a
                call    setvis
                call    copy57
                ld      a, 44
                call    tpause
                ld      hl, roomblk + T_PRESENTS
                ld      bc, 80 * 256 + 42
                call    credit
                ld      hl, roomblk + T_BYLINE  ; AuthorCredit
                ld      bc, 80 * 256 + 38
                call    credit
                ld      hl, T_TITLE     ; TitleScreen, and the splash after
                ld      bc, 255 * 256 + 38      ; it for as long as the CPC's
                call    credit          ; first tune still has to play: 772
                ld      hl, roomblk + T_PORT    ; counts in all is its 1206
                ld      bc, 172 * 256 + 23      ; fiftieths -- with the
                call    credit          ; port's own credit in the middle,
                                        ; where the Apple has only the
                                        ; splash.  The credits are where
                                        ; start left them: where the room's
                                        ; code goes

                ld      a, 0x80         ; Prolog1: unpacked out of sight and
                call    setvis          ; wiped on from the left, the way
                ld      a, 1            ; the story's
                call    itune
                ld      hl, T_PROLOG    ; DBLEXPAND lays its columns down
                call    unpack
                call    wipe
                xor     a
                call    setvis
                ld      a, 250          ; the story for as long as its tune:
                call    tpause          ; 785 fiftieths
                ld      a, 252
                call    tpause

                call    princess        ; PrincessScene

                call    black7          ; Prolog2, after a blackout: all at
                ld      a, 0x80         ; once
                call    setvis
                ld      hl, T_PROLOG    ; the story's end is packed on its
                call    unpack          ; beginning
                ld      hl, T_SUMUP
                call    unpack
                xor     a
                call    setvis
                ld      a, 250
                call    tpause

introend:       ld      sp, (introsp)   ; and the game: the key let go, as
                call    ststop          ; the music stopped,
iewait:         halt                    ; the Apple clears its strobe, and both
                xor     a               ; screens black
                in      a, (254)
                cpl
                and     0x1F
                jr      nz, iewait
                call    black7
                ld      hl, 0x4000
                call    clear
                xor     a
                call    setvis
                di
                ret

; A credit laid over the splash: HL = it, B = how long it stays, C = the
; pause before the next.  CleanScreen after.

credit:         push    bc
                call    credit1
                pop     bc
                ld      a, c
                jr      tpause

credit1:        push    bc
                ld      a, 0x80         ; DELTAEXPPOP: drawn while the clean
                call    setvis          ; copy is shown
                call    unpack
                xor     a
                call    setvis
                pop     af
                call    tpause
                ld      a, 0x80         ; CleanScreen
                call    setvis
                ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0xC000
                ld      de, 0x4000
                ld      bc, 6912
                ldir
                xor     a
                jp      setvis

; HL = a packed screen, onto bank 5.  titlescr.py says what the tokens are.

unpack:         ld      a, BANK_ART
                ld      de, 0x4000
                jr      unpackto

; Bank 5 onto the second screen, shown, a character column at a time from
; the left: two columns in three fiftieths, near enough the time DBLEXPAND
; takes over its eighty.

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

; TPAUSE: A counts of 32 milliseconds, a count and a half and a sixteenth in
; fiftieths; a key ends the titles, as StartGame? does.

tpause:         ld      c, a
                ld      l, a
                ld      h, 0
                srl     c
                ld      b, 0
                add     hl, bc
                srl     c
                srl     c
                srl     c
                add     hl, bc
tploop:         halt
                xor     a
                in      a, (254)
                cpl
                and     0x1F
                jp      nz, introend
                dec     hl
                ld      a, h
                or      l
                jr      nz, tploop
                ret

introsp:        dw      0
tunes:          dw      TUNE0, TUNE1, TUNE2, TUNE3, TUNE4, TUNE5

; The princess's room, PlayCut0: cutplay.asm, with what is kept where for
; it here -- the room and the pictures in bank 1's canvas, the clean band
; past the title screens -- and the key ending the titles.

CUT_BANK        equ     BANK_CVS
CUT_CLEAN       equ     0xC000 + CUT_CLEAN_OFF
CUT_TUNE        equ     1               ; the room's tunes are 2, 3 and 4
CUT_HOLD        equ     0
cutkey          equ     introend

                include "cutplay.asm"

