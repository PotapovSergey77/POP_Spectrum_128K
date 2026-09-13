; ---------------------------------------------------------------- the titles
;
; ATTRACTMODE in MASTER.S, as far as the game: the splash with its credits,
; the title, and the story -- the princess's scene left out -- and then not
; the demo but the first level, as a key pressed at any moment gives.
;
; The Apple keeps a double hi-res page 2 behind the one shown, the splash
; clean, and a credit is drawn into page 1 while page 2 is on the screen, so
; it appears whole; CleanScreen shows page 2 again and copies it back.  Here
; page 1 is the ordinary screen, bank 5, and page 2 the 128's second, bank 7:
; setvis shows one or the other.  The screens come packed in the art bank --
; see titlescr.py -- and are unpacked onto bank 5 with that bank paged in.
;
; No music: the pauses are the ones PlaySongI makes when it is off.  TPAUSE
; counts twice round 256 calls of StartGame?, some 32 milliseconds a count.

intro:          ld      (introsp), sp
                ei
                call    black7          ; blackout: the second screen, black,
                ld      a, 0x80         ; shown
                call    setvis

                ld      hl, T_SPLASH    ; PubCredit: the splash, all at once,
                call    unpack          ; and a copy of it behind
                xor     a
                call    setvis
                call    copy57
                ld      a, 44
                call    tpause
                ld      hl, T_PRESENTS
                ld      bc, 80 * 256 + 42
                call    credit
                ld      hl, T_BYLINE    ; AuthorCredit
                ld      bc, 80 * 256 + 38
                call    credit
                ld      hl, T_TITLE     ; TitleScreen
                ld      b, 140
                call    credit1

                ld      a, 0x80         ; Prolog1: unpacked out of sight and
                call    setvis          ; wiped on from the left, the way
                ld      hl, T_PROLOG    ; DBLEXPAND lays its columns down
                call    unpack
                call    wipe
                xor     a
                call    setvis
                ld      a, 250
                call    tpause

                call    black7          ; Prolog2, after a blackout: all at
                ld      a, 0x80         ; once
                call    setvis
                ld      hl, T_SUMUP
                call    unpack
                xor     a
                call    setvis
                ld      a, 250
                call    tpause

introend:       ld      sp, (introsp)   ; and the game: the key let go, as
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
                jp      tpause

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

; Page 1 to page 2.

copy57:         ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0x4000
                ld      de, 0xC000
                ld      bc, 6912
                ldir
                ret

; The second screen black, pixels and colours.

black7:         ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0xC000
clear:          ld      d, h
                ld      e, l
                inc     de
                ld      bc, 6911
                ld      (hl), 0
                ldir
                ret

; HL = a packed screen, onto bank 5.  titlescr.py says what the tokens are.

unpack:         ld      a, BANK_ART
                call    pageset
                ld      de, 0x4000
uploop:         ld      a, (hl)
                inc     hl
                cp      0x80
                jr      nc, upnlit
                inc     a               ; bytes as they come
                ld      c, a
                ld      b, 0
                ldir
                jr      uploop
upnlit:         cp      0xC0
                jr      nc, upskip
                and     0x3F            ; bytes from further back
                add     a, 3
                ld      c, (hl)
                inc     hl
                ld      b, (hl)
                inc     hl
                push    hl
                push    af
                ld      h, d
                ld      l, e
                or      a
                sbc     hl, bc
                pop     af
                ld      c, a
                ld      b, 0
                ldir
                pop     hl
                jr      uploop
upskip:         inc     a               ; bytes left as they are, or the end
                ret     z
                dec     a
                and     0x3F
                ld      b, a
                ld      c, (hl)
                inc     hl
                inc     bc
                ex      de, hl
                add     hl, bc
                ex      de, hl
                jr      uploop

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
