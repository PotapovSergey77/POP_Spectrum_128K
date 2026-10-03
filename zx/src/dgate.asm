; The controller, through the TR-DOS ROM: its ports answer only while that
; ROM is in, and it is in only while the program runs there -- paged in by
; going to 0x3D2F (a RET, the address taken off the stack), and out again by
; the RET that brings the program back.  The Beta's WD1793: 0x1F the command
; and status, 0x3F the track, 0x5F the sector, 0x7F the data, and 0xFF the
; drive, side and density, and read, its INTRQ and DRQ.  DE goes.  The way
; in is dout.asm's, which the game keeps apart from this.

; A, a command, and then the ROM's 0x3FE5 until it is done: that loop takes
; each byte DRQ offers through port C into HL on, and returns on INTRQ.

dcmd:           ld      c, 0x1F
                call    dout
                ld      c, 0x7F
                ld      de, 0x3FE5
                jp      dgo
