; ---------------------------------------------------------------- the princess's room
;
; What plays a scene in the princess's room: PlayCut0 in the titles (see
; intro.asm) and PlayCut1 between levels one and two (cut1.asm, loaded off
; the tape with the level).  Whoever includes it says where things are:
;
;   CUT_BANK    the bank the room, the pictures and the script are in
;   CUT_CLEAN   the clean band, in the art bank
;   CUT_TUNE    one before the first of the tunes the scene starts
;   CUT_HOLD    1: after the last frame, that frame again until the tune
;               has played out
;   cutkey      where a key goes
;   tunes       the tunes, where each begins and the last one's end
;   cutfixed    the pictures kept in fixed memory
;
; and the CUT_ equates of princessscr.py.

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

; A = the bank it is in, HL = it, DE = where it goes.

unpackto:       call    pageset
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


; A = one of the CPC's tunes, TUNE0 on, in the art bank: from its first tick,
; over whatever was playing.

itune:          add     a, a
                ld      l, a
                ld      h, 0
                ld      de, tunes
                add     hl, de
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      c, (hl)
                inc     hl
                ld      b, (hl)
                di
                ld      (sfxptr), de
                ld      (sfxstart), de
                ld      (sfxend), bc
                ld      a, 255
                ld      (sfxprio), a
                ld      (sfxcur), a
                ld      a, 1
                ld      (sfxtimer), a
                call    sfx_quiet
                ei
                ret


ctune:          db      0

; ---------------------------------------------------------------- the princess
;
; PrincessScene and PlayCut0 in SUBS.S: the vizier comes to the princess and
; turns the hourglass over.  princessscr.py says what is kept where; the
; scene itself -- which picture each of them shows, where, and what happens
; on which frame -- is princess.py's run of ANIMCHAR over SEQTABLE.S, a
; record a frame, and what goes by RND is run here as the Apple runs it:
; the torches (PBURN), the stars (PSTARS) and the sand (PFLOW).
;
; The Apple keeps both hi-res pages the room and lays the characters on the
; hidden one over peels of what was under them.  Here the lines anything
; moves in, the band, are composed in fixed memory, where the room-build
; code lies when the game is on -- it is put by in its bank at start, and
; roomrest puts it back -- over a clean copy of them kept in the art bank,
; past the title screens; then the band goes to whichever screen is not
; shown, and that one is shown on an interrupt.  The pictures are in bank 1,
; in the room the canvas has once the game begins.  Between levels, when the
; room's code is running, cut1.asm puts it by for the scene.

cutbuf          equ     roomblk + CUT_BUFOFF
CUT_Q7          equ     59              ; eighths of a fiftieth a frame at
CUT_Q12         equ     65              ; SPEED 7 and at SPEED 12
BAND_BYTES      equ     CUT_BAND_ROWS * 32

princess:       call    black7          ; blackout, and the room unpacked
                ld      a, 0x80         ; out of sight
                call    setvis
                ld      a, 0x80
                ld      (cvis), a
                ld      hl, CUT_ROOM
                ld      de, 0x4000
                ld      a, CUT_BANK
                call    unpackto
                ld      hl, CUT_PACKED  ; the pictures and the script, where
                ld      de, CUT_SPRTAB  ; they lie
                ld      a, CUT_BANK
                call    unpackto
                ld      a, BANK_ART     ; the band as it is, clean, and in
                call    pageset         ; the band being composed
                ld      de, CUT_CLEAN
                ld      a, CUT_BAND_TOP
bandin:         push    af
                push    de
                call    scrrow
                pop     de
                ld      bc, 32
                ldir
                pop     af
                inc     a
                cp      CUT_BAND_TOP + CUT_BAND_ROWS
                jr      nz, bandin
                ld      hl, CUT_CLEAN
                ld      de, cutbuf
                ld      bc, BAND_BYTES
                ldir

                ld      a, CUT_TUNE
                ld      (ctune), a
                ld      hl, cutinit     ; INITIT
                ld      de, cutvars
                ld      bc, CUTVARS
                ldir
                ld      a, (FRAMES)
                ld      (clast), a

; PLAY, a frame at a time: RND, the frame's record, the lightning, and
; FrameAdv -- what DoFast draws, the flip, and the lightning off.

cutloop:        call    rnd
                ld      a, CUT_BANK
                call    pageset
                ld      hl, (cptr)
                ld      a, (hl)
                ld      (cflags), a
                inc     hl
                ld      de, cchars
                ld      bc, 4
                ldir
                ld      (cptr), hl

                ld      a, (cflags)     ; FLASHON: the screen white
                and     2
                jr      z, cnoflash
                call    visattr
                ld      d, h
                ld      e, l
                inc     de
                ld      (hl), 0x7F
                ld      bc, 767
                ldir
cnoflash:
                ld      a, BANK_ART     ; what the characters covered last
                call    pageset         ; frame, back from the clean band
                ld      hl, boxes
                call    unbox
                call    unbox

                ld      a, (cflags)     ; the hourglass, when it appears or
                bit     2, a            ; changes: into the clean band and
                jr      z, cnoglass     ; the one being composed
                ld      hl, CUT_GL0
                and     8
                jr      z, cglass
                ld      hl, CUT_GL1
cglass:         push    hl
                ld      de, CUT_CLEAN + CUT_GL_AT
                call    glass
                pop     hl
                ld      de, cutbuf + CUT_GL_AT
                call    glass
cnoglass:
                ld      a, (cflags)     ; and the sand starts
                and     16
                jr      z, cnosand
                xor     a
                ld      (psand), a
cnosand:
                ld      a, (cflags)     ; one of the CPC's tunes for the room:
                rla                     ; the next of the three
                jr      nc, cnotune
                ld      a, (ctune)
                inc     a
                ld      (ctune), a
                call    itune
cnotune:
                ld      a, 1            ; DoFast: two flames and the stars
                call    pburn
                xor     a
                call    pburn
                call    pstars

                ld      a, CUT_BANK     ; the vizier, then the princess
                call    pageset
                ld      hl, cchars
                ld      de, boxes
                call    chdraw
                ld      hl, cchars + 2
                ld      de, boxes + 4
                call    chdraw

                ld      hl, CUT_PO      ; DRAWPOST: the post in front of
                ld      de, cutbuf + CUT_PO_AT  ; them, ORed
                ld      b, CUT_PO_H
cpost:          rept    CUT_PO_W
                ld      a, (de)
                or      (hl)
                ld      (de), a
                inc     hl
                inc     de
                endm
                ex      de, hl
                ld      a, 32 - CUT_PO_W
                add     a, l
                ld      l, a
                adc     a, h
                sub     l
                ld      h, a
                ex      de, hl
                djnz    cpost

                call    pflow           ; and the sand over them
                call    cshow           ; and the band to the screen not shown

; PAUSE, SPEED long: seven and three eighths fiftieths a frame at 7, and
; eight and an eighth at 12 -- well over twice the three the game's frame
; takes: any faster went ahead of the music.  What a frame does not take whole is
; carried to the next, and a frame shown late takes it from the next one's
; time, so the scene keeps to the tune.  The screen changes on an
; interrupt, never in the middle of one being shown, and a key ends the
; scene.

                ld      a, (cflags)
                rrca                    ; carry: SPEED 12
                ld      a, CUT_Q7
                jr      nc, cq1
                ld      a, CUT_Q12
cq1:            ld      hl, ctog        ; eighths of a fiftieth, and what
                add     a, (hl)         ; was left of the last frame's
                ld      c, a
                and     7
                ld      (hl), a
                ld      a, c
                rrca
                rrca
                rrca
                and     0x1F
                ld      (cper), a
                call    cwait
                ld      hl, clast       ; when the next is due from: when
                ld      a, (cper)       ; this one was
                add     a, (hl)
                ld      (hl), a
                call    cflip           ; PAGEFLIP

                ld      a, (cflags)     ; FLASHOFF: the screen that was
                and     2               ; white has the other's colours back
                jr      z, cnounflash
                ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0x5800
                ld      de, 0xD800
                ld      a, (cvis)
                or      a
                jr      z, cunflash
                ex      de, hl
cunflash:       ld      bc, 768
                ldir
cnounflash:
                ld      a, (cfirst)     ; and after the first frame, the room
                or      a               ; on the second screen too
                jr      z, cnotfirst
                xor     a
                ld      (cfirst), a
                call    copy57
cnotfirst:
                ld      hl, ccount
                dec     (hl)
                jr      nz, cmid
                if      CUT_HOLD
                ld      a, (sfxtimer)   ; PlaySong: until the tune has
                or      a               ; played out, the last frame again
                ret     z
                inc     (hl)
                ld      hl, (cptr)
                ld      de, -5
                add     hl, de
                ld      (cptr), hl
                else
                ret
                endif

; Halfway to the next frame, a picture the Apple does not show: the same
; frame with the torches burnt on a flame, so that they burn about as fast
; as they do in the game, at twice the pace of the frames the music holds
; the scene to.  Only the torches: where the vizier stands in front of the
; right one, it waits for the next frame, that draws him over it.

cmid:           ld      a, (cflags)
                and     0x60
                jr      nz, cmid1
                inc     a
                call    pburn
cmid1:          xor     a
                call    pburn
                call    cshow
                ld      a, (cper)
                rrca
                and     0x7F
                call    cwait
                call    cflip
                jp      cutloop

; The band to the screen not shown, and the right flame's colours on it,
; or white where the vizier is in its cells.

cshow:          ld      a, (cvis)
                xor     0x80
                ld      (chid), a
                ld      a, BANK_CANVAS
                call    pageset
                ld      hl, cutbuf + CUT_COL0
                ld      a, CUT_BAND_TOP
bandout:        push    af
                push    hl
                call    scrrow
                ld      a, (chid)
                or      h
                ld      d, a
                ld      a, l
                add     a, CUT_COL0
                ld      e, a
                pop     hl
                push    hl
                rept    32 - CUT_COL0
                ldi
                endm
                pop     hl
                ld      bc, 32
                add     hl, bc
                pop     af
                inc     a
                cp      CUT_BAND_TOP + CUT_BAND_ROWS
                jr      nz, bandout

                ld      hl, 0x5800 + CUT_T1_TIP
                ld      a, (chid)
                or      h
                ld      h, a
                ld      a, (cflags)
                ld      c, CUT_INK_TIP
                bit     5, a
                jr      z, cfltip
                ld      c, CUT_INK_WHITE
cfltip:         ld      (hl), c
                ld      de, CUT_T1_BODY - CUT_T1_TIP
                add     hl, de
                ld      c, CUT_INK_BODY
                bit     6, a
                jr      z, cflbody
                ld      c, CUT_INK_WHITE
cflbody:        ld      (hl), c
                ret

; Until A fiftieths from when the last frame was due; a key ends the scene.

cwait:          ld      c, a
cwait1:         halt
                xor     a
                in      a, (254)
                cpl
                and     0x1F
                jp      nz, cutkey
                ld      a, (clast)
                ld      b, a
                ld      a, (FRAMES)
                sub     b
                cp      c
                jr      c, cwait1
                ret

; The screen composed shown.

cflip:          ld      a, (chid)
                ld      (cvis), a
                jp      setvis

; The screen shown, its colours: HL, the bank paged if it is the second.

visattr:        ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0x5800
                ld      a, (cvis)
                or      a
                ret     z
                ld      h, 0xD8
                ret

; A = a line: HL = its address on the ordinary screen.

scrrow:         ld      c, a
                and     7
                ld      h, a
                ld      a, c
                rrca
                rrca
                rrca
                and     0x18
                or      h
                or      0x40
                ld      h, a
                ld      a, c
                rlca
                rlca
                and     0xE0
                ld      l, a
                ret

; HL = a box a character was drawn in (where in the band, bytes across,
; rows), put back from the clean band.  Out: HL past it.  The art bank in.

unbox:          ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      c, (hl)
                inc     hl
                ld      b, (hl)
                inc     hl
                push    hl
                ld      a, b
                or      a
                jr      z, ubdone
                ld      hl, CUT_CLEAN
                add     hl, de
                push    hl
                ld      hl, cutbuf
                add     hl, de
                ex      de, hl
                pop     hl              ; HL = clean, DE = band
ubrow:          push    bc
                push    hl
                push    de
                ld      b, 0
                ldir
                pop     hl
                ld      bc, 32
                add     hl, bc
                ex      de, hl
                pop     hl
                add     hl, bc
                pop     bc
                djnz    ubrow
ubdone:         pop     hl
                ret

; The hourglass, state HL, at DE.  DRAWGLASS: opaque.

glass:          ld      bc, CUT_GL_EXT
                ld      (lext), bc
                ld      bc, CUT_GL_H * 256 + CUT_GL_W
                jr      lay

; LAY at a place of its own, opaque: HL = the picture, DE = where in a
; band, B rows of C bytes (four at most), and (lext) the C bytes its box
; covers, cleared before it is ORed in.

lay:            push    bc
                push    hl
                ld      a, c            ; into the row's work that many
                add     a, a            ; bytes from its end
                ld      c, a
                add     a, a
                add     a, a
                add     a, c
                ld      c, a
                ld      b, 0
                ld      hl, lyend
                or      a
                sbc     hl, bc
                ld      (lyjp + 1), hl
                pop     hl
                pop     bc
lyrow:          push    bc
                push    de
                ld      bc, (lext)
lyjp:           jp      lyend
                rept    4               ; ten bytes each
                ld      a, (bc)
                inc     bc
                cpl
                ex      de, hl
                and     (hl)
                ex      de, hl
                or      (hl)
                ld      (de), a
                inc     hl
                inc     de
                endm
lyend:          pop     de
                ex      de, hl
                ld      bc, 32
                add     hl, bc
                ex      de, hl
                pop     bc
                djnz    lyrow
                ret

; PBURN: torch A, a new flame for it by GETFLAMEFRAME, and PSETUPFLAME's
; picture of it laid down.

pburn:          ld      (ptcount), a
                ld      e, a
                ld      d, 0
                ld      hl, ptstate
                add     hl, de
                push    hl
                ld      a, (hl)
                call    flameframe
                pop     hl
                ld      (hl), a
                ld      e, a
                ld      d, 0
                ld      hl, CUT_FLTAB
                add     hl, de
                ld      a, (hl)         ; its picture, times the bytes of
                ld      hl, 0           ; one
                ld      de, CUT_FL_W * CUT_FL_H
                or      a
                jr      z, pbm2
pbm1:           add     hl, de
                dec     a
                jr      nz, pbm1
pbm2:           ex      de, hl
                ld      a, (ptcount)
                or      a
                jr      nz, pb2
                ld      hl, CUT_FL0
                add     hl, de
                ld      de, cutbuf + CUT_FL0_AT
                ld      bc, CUT_FL0_EXT
                jr      pb3
pb2:            ld      hl, CUT_FL1
                add     hl, de
                ld      de, cutbuf + CUT_FL1_AT
                ld      bc, CUT_FL1_EXT
pb3:            ld      (lext), bc
                ld      bc, CUT_FL_H * 256 + CUT_FL_W
                jp      lay

; PFLOW: the sand's next picture, once it flows.

pflow:          ld      a, (psand)
                or      a
                ret     m
                inc     a
                cp      3
                jr      c, pf1
                xor     a
pf1:            ld      (psand), a
                ld      hl, CUT_FW
                ld      de, CUT_FW_W * CUT_FW_H
                or      a
                jr      z, pf3
pf2:            add     hl, de
                dec     a
                jr      nz, pf2
pf3:            ld      de, cutbuf + CUT_FW_AT
                ld      bc, CUT_FW_EXT
                ld      (lext), bc
                ld      bc, CUT_FW_H * 256 + CUT_FW_W
                jp      lay

; PSTARS: a twinkle that has run its time is put out, and one frame in
; twenty five or so a star twinkles for five to eight.  TWINKLE puts it
; straight on both screens, as it does on both pages; the band is not copied
; that far left.  Leaves the second screen's bank in.

pstars:         ld      b, 4
ps1:            ld      hl, pstarcnt - 1
                ld      e, b
                ld      d, 0
                add     hl, de
                ld      a, (hl)
                or      a
                jr      z, ps2
                dec     (hl)
                jr      nz, ps2
                push    bc
                ld      a, b
                dec     a
                call    twinkle
                pop     bc
ps2:            djnz    ps1
                call    rnd
                cp      10
                ret     nc
                call    rnd
                and     3
                add     a, 5
                push    af
                call    rnd
                call    rnd
                and     3
                ld      e, a
                ld      d, 0
                ld      hl, pstarcnt
                add     hl, de
                pop     af
                ld      (hl), a
                ld      a, e
twinkle:        ld      e, a
                add     a, a
                add     a, e
                ld      e, a
                ld      d, 0
                ld      hl, CUT_STARS
                add     hl, de
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      c, (hl)
                ld      a, BANK_CANVAS
                call    pageset
                ld      hl, 0x4000
                add     hl, de
                ld      a, (hl)
                xor     c
                ld      (hl), a
                set     7, h
                ld      a, (hl)
                xor     c
                ld      (hl), a
                ret

; A character: HL = its record (picture, x), DE = where the box it covers
; is kept.  Picture NONE is off the screen.  The table gives the picture's
; rows, bytes across, rows down, the band row it starts on, and for the
; princess's frames that PMASK masks, the row it masks.  Bank 1 in.

chdraw:         ld      (bbox), de
                ld      a, (hl)
                inc     hl
                ld      b, (hl)
                cp      0xFF
                jr      nz, chd1
                ex      de, hl          ; nothing: no box
                inc     hl
                inc     hl
                inc     hl
                ld      (hl), 0
                ret
chd1:           ld      c, a
                and     0x80
                ld      (bmir), a
                ld      a, b
                ld      (bx), a
                ld      a, c
                and     0x7F
                ld      l, a
                ld      h, 0
                add     hl, hl
                ld      e, l
                ld      d, h
                add     hl, hl
                add     hl, de
                ld      de, CUT_SPRTAB
                add     hl, de
                ld      e, (hl)
                inc     hl
                ld      d, (hl)
                inc     hl
                ld      (bsrc), de
                ld      a, (hl)
                ld      (bw), a
                inc     hl
                ld      a, (hl)
                ld      (bh), a
                inc     hl
                ld      a, (hl)
                ld      (btop), a
                inc     hl
                ld      a, (hl)
                ld      (cpmrow), a
                ld      a, bmasked - bjump - 2
                call    blit
                ld      a, (cpmrow)     ; PMASK
                cp      0xFF
                ret     z
                ld      (btop), a
                ld      a, 1
                ld      (bh), a
                ld      hl, CUT_PMASK
                ld      a, (hl)
                ld      (bw), a
                inc     hl
                ld      (bsrc), hl
                xor     a
                ld      (bmir), a
                ld      hl, 0           ; its box is inside hers
                ld      (bbox), hl
                ld      a, bclear - bjump - 2

; A picture laid at any pixel: (bsrc) its rows of (bw) bytes, (bh) of
; them, from band row (btop), its left edge at pixel (bx), mirrored if
; (bmir); A says how it goes in.  Every row goes into rowbuf, shifted to
; its place, and then into the band.  (bbox), unless it is 0, keeps the
; box it covered.

blit:           ld      (bjump + 1), a
                ld      a, (bx)
                and     7
                ld      (bsh), a
                ld      a, (bx)
                rrca
                rrca
                rrca
                and     31
                ld      c, a
                ld      a, 32           ; the bytes it covers, as many as
                sub     c               ; there are before the edge
                ld      b, a
                ld      a, (bw)
                inc     a
                cp      b
                jr      c, bl1
                ld      a, b
bl1:            ld      (bcnt), a
                ld      a, (btop)
                ld      l, a
                ld      h, 0
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                add     hl, hl
                ld      b, 0
                add     hl, bc
                ex      de, hl          ; DE = where in the band
                ld      hl, (bbox)
                ld      a, h
                or      l
                jr      z, bl2
                ld      (hl), e
                inc     hl
                ld      (hl), d
                inc     hl
                ld      a, (bcnt)
                ld      (hl), a
                inc     hl
                ld      a, (bh)
                ld      (hl), a
bl2:            ld      hl, cutbuf
                add     hl, de
                ld      (bdst), hl
                ld      hl, rowbuf + 1  ; a shift of five or more goes the
                ld      a, (bsh)        ; other way: from the byte after,
                cp      5               ; left by what is short of eight
                jr      c, bl3
                inc     hl
bl3:            ld      (bfetch), hl
                ld      a, (bw)         ; the shifts, into their unrolled
                inc     a               ; work as far as the bytes it
                ld      c, a            ; spreads over: three bytes each
                add     a, a
                add     a, c
                ld      c, a
                ld      b, 0
                ld      hl, bsrend
                or      a
                sbc     hl, bc
                ld      (bsrj + 1), hl
                ld      hl, bslend
                sbc     hl, bc
                ld      (bslj + 1), hl
                ld      a, (bw)         ; and left from the byte past them
                ld      c, a
                ld      hl, rowbuf + 2
                add     hl, bc
                ld      (bshl0 + 1), hl
                ld      a, (bh)
                ld      (brows), a

brow:           xor     a               ; the row, from nothing
                ld      hl, rowbuf
                rept    8
                ld      (hl), a
                inc     hl
                endm
                ld      hl, (bsrc)
                ld      a, (bw)
                ld      c, a
                ld      b, 0
                add     hl, bc
                ld      (bsrc), hl      ; and the next one's
                ld      de, (bfetch)
                ld      a, (bmir)
                or      a
                jr      nz, bfmir0
                sbc     hl, bc
                ld      b, c
bfnor:          ld      a, (hl)
                ld      (de), a
                inc     hl
                inc     de
                djnz    bfnor
                jr      bshift
bfmir0:         ld      b, c
bfmir:          dec     hl              ; mirrored: from its end, each byte
                ld      a, (hl)         ; turned about
                push    hl
                ld      h, REVTAB / 256
                ld      l, a
                ld      a, (hl)
                pop     hl
                ld      (de), a
                inc     de
                djnz    bfmir

bshift:         ld      a, (bsh)
                or      a
                jr      z, bput
                cp      5
                jr      nc, bshl
                ld      c, a
bshr:           ld      hl, rowbuf + 1
                or      a
bsrj:           jp      bsrend
                rept    6
                rr      (hl)
                inc     hl
                endm
bsrend:         dec     c
                jr      nz, bshr
                jr      bput
bshl:           sub     8
                neg
                ld      c, a
bshl0:          ld      hl, rowbuf
                or      a
bslj:           jp      bslend
                rept    6
                dec     hl
                rl      (hl)
                endm
bslend:         dec     c
                jr      nz, bshl0

bput:           ld      hl, rowbuf + 1
                ld      de, (bdst)
                ld      a, (bcnt)
                ld      b, a
bjump:          jr      bmasked

; MASKTAB: every lit pixel and the one either side of it cleared, and the
; picture ORed in.  The byte before is done with once its own mask is
; worked out, and holds the part of this one's that comes from it.

bmasked:        dec     hl
                ld      a, (hl)
                rra
                inc     hl
                ld      c, (hl)
                ld      a, c
                rra
                or      c
                dec     hl
                ld      (hl), a
                inc     hl
                inc     hl
                ld      a, (hl)
                dec     hl
                rla
                ld      a, c
                rla
                dec     hl
                or      (hl)
                inc     hl
                cpl
                ex      de, hl
                and     (hl)
                or      c
                ld      (hl), a
                ex      de, hl
                inc     hl
                inc     de
                djnz    bmasked
                jr      bnext

; PMASK's AND: what it clears, cleared.

bclear:         ld      a, (hl)
                cpl
                ex      de, hl
                and     (hl)
                ld      (hl), a
                ex      de, hl
                inc     hl
                inc     de
                djnz    bclear

bnext:          ld      hl, (bdst)
                ld      bc, 32
                add     hl, bc
                ld      (bdst), hl
                ld      hl, brows
                dec     (hl)
                jp      nz, brow
                ret

; INITIT, and where PlayCut0 starts.

cutinit:        dw      CUT_SCRIPT      ; cptr
                db      CUT_FRAMES      ; ccount
                db      1, 0            ; cfirst, ctog
                db      0, 1, 6         ; ptcount, ptstate
                db      0xFF            ; psand: no hourglass yet
                db      0, 0, 0, 0      ; pstarcnt
                dw      0, 0, 0, 0      ; boxes: none
CUTVARS         equ     $ - cutinit

cutvars:
cptr:           dw      0
ccount:         db      0
cfirst:         db      0
ctog:           db      0
ptcount:        db      0
ptstate:        db      0, 0
psand:          db      0
pstarcnt:       db      0, 0, 0, 0
boxes:          dw      0, 0, 0, 0
cvis:           db      0
chid:           db      0
clast:          db      0
cper:           db      0
cflags:         db      0
cchars:         db      0, 0, 0, 0
lext:           dw      0
bsrc:           dw      0
bdst:           dw      0
bbox:           dw      0
bfetch:         dw      0
bw:             db      0
bh:             db      0
btop:           db      0
bx:             db      0
bmir:           db      0
cpmrow:         db      0
bsh:            db      0
bcnt:           db      0
brows:          db      0
rowbuf:         ds      8

