; ---------------------------------------------------------------- controls
;
; After the titles, before the first level, the controls are chosen: the
; keyboard, with the keys as they are defined -- by default the arrows of
; an emulator, 5 6 7 8, and space -- a Kempston joystick, a Sinclair one
; (keys 6 to 0, as the 128's own joystick port gives them); the keys can be
; defined afresh, which chooses the keyboard.  An arrow marks the one
; chosen, and 0 starts the game.  The screen is the story's (T_PROLOG), its border and its
; blue, the story cleared off it.  Run once, from start, out of the start
; block: the working copy goes over it with the first room.
;
; keytab is read_input's: five of row, mask, the button first, then up,
; down, left and right; a Kempston joystick is a jr +0 in read_input
; (kjpatch), in the canvas bank, and port 31 read after the keys.
;
; The words, the names of the keys and the routines that write them are
; ctldata.asm's, at the top of the art bank past the canvas bank's code,
; which is in all the while; the start block has no room for them.

                include "ctldata.inc"   ; the words, in the art bank
CM_TOP          equ     3               ; the rows inside the border
CM_BOT          equ     20
CM_LIST         equ     19              ; the keys
CM_ASK          equ     17              ; and which one is being defined

ctlmenu:        ei
                ld      a, 0x80         ; laid out behind the black screen
                call    setvis
                ld      hl, T_PROLOG
                call    unpack
                ld      a, CM_TOP
cmclr:          push    af
                call    cmrow
                pop     af
                inc     a
                cp      CM_BOT + 1
                jr      c, cmclr
                ld      hl, cmtext
                call    cmblock
                call    cmkeys
                ld      a, 1            ; the keyboard, to begin with
                call    cmarrow
                xor     a
                call    setvis

cmwait:         call    cmup            ; a key: 0 to 4
cm1:            halt
                ld      a, 0xef         ; 0: the game
                in      a, (254)
                rra
                jr      nc, cmgo
                ld      a, 0xf7
                in      a, (254)
                cpl
                and     0x0f
                jr      z, cm1
                ld      c, 0            ; 1 to 3: that one, marked
                rrca
                jr      c, cmpick
                inc     c
                rrca
                jr      c, cmpick
                inc     c
                rrca
                jr      c, cmpick
                call    cmdef           ; 4: the keys, and the keyboard
                ld      c, 0
cmpick:         push    bc
                xor     a               ; the arrow off where it was
                call    cmarrow
                pop     bc
                ld      a, c
                ld      (cmsel), a
                ld      a, 1            ; and on where it is now
                call    cmarrow
                jr      cmwait

cmgo:           ld      a, (cmsel)
                dec     a
                jr      z, cmkemp
                dec     a
                jr      nz, cmkbd
                ld      hl, keysinc     ; Sinclair: its keys for the game's
                ld      de, keytab
                ld      bc, 10
                ldir
cmkbd:          ld      a, rikd - kjpatch - 2   ; the keys
                jr      cmset
cmkemp:         xor     a               ; port 31 after them
cmset:          push    af
                ld      a, BANK_CANVAS
                call    pageset
                pop     af
                ld      (kjpatch + 1), a
                call    cmup
                call    black7          ; both screens black again, as the
                ld      hl, 0x4000      ; titles leave them
                call    clear
                di
                ret

cmsel:          db      0               ; 0 the keyboard, 1 Kempston, 2 Sinclair

; The arrow by the one chosen, A = 1; A = 0 rubs it out.

cmarrow:        push    af
                ld      a, (cmsel)
                add     a, a
                add     a, CM_ITEM
                ld      e, 4
                call    cmat
                pop     af
                ld      c, CM_HI
                ld      hl, cmarw
                or      a
                jp      nz, cmglyph
                ld      hl, 0x3d00      ; the ROM's space
                jp      cmglyph

; Every key up.

cmup:           halt
                xor     a
                in      a, (254)
                cpl
                and     0x1f
                jr      nz, cmup
                ret

; Define Keys: left, right, up and down, the button; a key already given
; this time round is not taken again.

cmdef:          ld      b, 0
cmd1:           push    bc
                ld      a, CM_ASK       ; what for
                call    cmrow
                pop     bc
                push    bc
                ld      hl, cmasks
                inc     b
                jr      cmd3
cmd2:           ld      a, (hl)         ; the B'th word
                inc     hl
                or      a
                jr      nz, cmd2
cmd3:           djnz    cmd2
                ld      a, CM_ASK
                ld      c, CM_HI
                call    cmcentre
cmd4:           call    cmup
cmd5:           halt                    ; a key down: D = its row, C its bit
                ld      a, 0xfd         ; -- the caps shift row last: an
cmd6:           ld      d, a            ; emulator's arrow keys are caps
                in      a, (254)        ; shift with 5 to 8, and the shift
                cpl                     ; was taken for every one of them
                and     0x1f
                jr      nz, cmd7
                ld      a, d
                cp      0xfe
                jr      z, cmd5
                rlca                    ; on round to 7F, then FE
                jr      cmd6
cmd7:           ld      c, 1
cmd8:           rrca
                jr      c, cmd9
                sla     c
                jr      cmd8
cmd9:           pop     hl              ; H = which, as B was
                push    hl
                ld      b, h            ; given already?
                ld      hl, cmofs
cmd10:          ld      a, b
                or      a
                jr      z, cmd11
                ld      a, (hl)
                inc     hl
                push    hl
                ld      hl, keytab
                add     a, l
                ld      l, a
                ld      a, (hl)
                cp      d
                jr      nz, cmd12
                inc     hl
                ld      a, (hl)
                cp      c
cmd12:          pop     hl
                jr      z, cmd4         ; that one: another
                dec     b
                jr      cmd10
cmd11:          ld      a, (hl)         ; into its place
                ld      hl, keytab
                add     a, l
                ld      l, a
                ld      (hl), d
                inc     hl
                ld      (hl), c
                call    cmkeys
                pop     bc
                inc     b
                ld      a, b
                cp      5
                jr      c, cmd1
                ld      a, CM_ASK
                jp      cmrow

; The keys, in a row: left, right, up, down, the button, by name.

cmkeys:         ld      a, CM_LIST
                call    cmrow
                ld      de, cmbuf
                ld      hl, cmofs
                ld      b, 5
cmk1:           push    hl
                push    bc
                ld      a, (hl)
                ld      hl, keytab
                add     a, l
                ld      l, a
                ld      a, (hl)         ; the row: which of its bits is 0
                inc     hl
                ld      c, (hl)
                ld      b, -5
cmk2:           inc     b               ; five names to a row
                inc     b
                inc     b
                inc     b
                inc     b
                rrca
                jr      c, cmk2
                ld      a, c            ; and the bit
cmk3:           rrca
                jr      c, cmk4
                inc     b
                jr      cmk3
cmk4:           ld      hl, keynames
                ld      a, l
                add     a, b
                ld      l, a
                jr      nc, cmk5
                inc     h
cmk5:           ldi
                pop     bc
                pop     hl
                inc     hl
                dec     b
                jr      z, cmk6
                ld      a, ','
                ld      (de), a
                inc     de
                ld      a, ' '
                ld      (de), a
                inc     de
                jr      cmk1
cmk6:           xor     a
                ld      (de), a
                ld      hl, cmbuf
                ld      a, CM_LIST
                ld      c, CM_INK
                jp      cmcentre

keydef:         db      0x7f, 0x01, 0xef, 0x08, 0xef, 0x10, 0xf7, 0x10
                db      0xef, 0x04      ; space, 7, 6, 5, 8

cmbuf           equ     imgbuf          ; the names in a row, put together
