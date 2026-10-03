; A out to port C, through the TR-DOS ROM (dgate.asm).

dout:           ld      de, 0x2A53      ; OUT (C), A: RET
dgo:            push    de
                jp      0x3D2F
