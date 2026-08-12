; srec.s - the Motorola S-record loader behind the monitor's L command.
;
; Records are streamed straight from CHRIN_WAIT rather than through the line
; editor, because a pasted file is bigger than any line buffer; the console's
; RTS backpressure is what makes an arbitrarily long paste lossless. S1, S2
; and S3 records carry data - S2, with its 24-bit addresses, is the one the
; machine is really for - and S7, S8 or S9 end the load and name the entry
; point G will default to. Every record's checksum is verified: the sum of
; count, address, data and checksum bytes must come to $FF.
;
; A failed record reports one diagnostic, swallows the stream until the line
; goes quiet, and returns to the prompt; a Q - or a bare return - at a record
; boundary abandons the load.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import mon_upper
.import print_crlf
.import print_hex_byte

.export cmd_load

; Loader direct page, above the monitor's own block.
SADDR           = DP_MON + 26   ; 32-bit: record address, then store pointer
SSUM            = DP_MON + 30   ; running checksum
SBYTE           = DP_MON + 31   ; assembled hex byte
SCNT            = DP_MON + 32   ; bytes remaining in the record
STYPE           = DP_MON + 33   ; record type digit
SALEN           = DP_MON + 34   ; address bytes remaining
SDONE           = DP_MON + 35   ; nonzero once a terminating record landed

.segment "FARCODE"

; L - load S-records from the console until a terminator, an abort, or an
; error.
cmd_load:
        .a8
        .i16
        lda #$00
        sta z:SDONE
@boundary:
        jsl K_CHRIN_WAIT
        cmp #' '
        beq @boundary
        cmp #$0A
        beq @boundary
        cmp #$0D
        beq @abort
        jsr mon_upper
        cmp #'Q'
        beq @abort
        cmp #'S'
        beq @record
        lda #ERR_SREC_FORMAT
        jsr srec_fail
        rts
@record:
        jsr srec_record
        bcc @failed
        lda z:SDONE
        beq @boundary
@abort:
        rts
@failed:
        rts

; One record, its leading S already consumed; carry reports success.
srec_record:
        .a8
        .i16
        phx
        jsl K_CHRIN_WAIT
        sec
        sbc #'0'
        cmp #10
        bcc :+
        jmp @format
:
        sta z:STYPE
        lda #$00
        sta z:SSUM
        jsr srec_byte
        bcs :+
        jmp @format
:
        sta z:SCNT
        ; The address width falls out of the type - and so does validity.
        lda z:STYPE
        rep #$20
        .a16
        and #$00FF
        tax
        sep #$20
        .a8
        lda f:addr_sizes,x
        bne :+
        jmp @format
:
        sta z:SALEN
        rep #$20
        .a16
        stz z:SADDR
        stz z:SADDR+2
        sep #$20
        .a8
@address:
        jsr srec_byte
        bcs :+
        jmp @format
:
        ; The address builds high byte first: shift what stands and slot the
        ; new byte underneath.
        pha
        lda z:SADDR+2
        sta z:SADDR+3
        lda z:SADDR+1
        sta z:SADDR+2
        lda z:SADDR
        sta z:SADDR+1
        pla
        sta z:SADDR
        dec z:SCNT
        dec z:SALEN
        bne @address
        ; What remains is data plus the checksum byte.
        dec z:SCNT
@data:
        lda z:SCNT
        beq @checksum
        jsr srec_byte
        bcc @format
        ; Only the data records store; S0's payload and a terminator's
        ; nonexistent one are read for the checksum and dropped.
        ldx z:STYPE
        cpx #$0001
        bcc @dropped
        cpx #$0004
        bcs @dropped
        sta [SADDR]
        rep #$20
        .a16
        lda z:SADDR
        inc a
        sta z:SADDR
        bne @stored
        lda z:SADDR+2
        inc a
        sta z:SADDR+2
@stored:
        sep #$20
        .a8
@dropped:
        dec z:SCNT
        bra @data
@checksum:
        jsr srec_byte
        bcc @format
        lda z:SSUM
        cmp #$FF
        bne @sum
        rep #$20
        .a16
        lda MB_SRECRECS
        inc a
        sta MB_SRECRECS
        sep #$20
        .a8
        lda z:STYPE
        cmp #$07
        bcc @trailer
        ; A terminator: its address is the entry point, and the load is done.
        rep #$20
        .a16
        lda z:SADDR
        sta RF_ENTRY
        sep #$20
        .a8
        lda z:SADDR+2
        sta RF_ENTRY+2
        lda #$01
        sta z:SDONE
@trailer:
        jsl K_CHRIN_WAIT
        cmp #$0D
        beq @end
        cmp #$0A
        beq @end
        cmp #' '
        beq @trailer
        lda #ERR_SREC_FORMAT
        bra @report
@end:
        plx
        sec
        rts
@format:
        lda #ERR_SREC_FORMAT
        bra @report
@sum:
        lda #ERR_SREC_SUM
@report:
        jsr srec_fail
        plx
        clc
        rts

; Reports the error in A, counts it, and swallows the stream until the far
; end has gone quiet, so a half-pasted file cannot spray the prompt.
srec_fail:
        .a8
        .i16
        phx
        rep #$20
        .a16
        and #$00FF
        sta MB_LASTERR
        lda MB_SRECERRS
        inc a
        sta MB_SRECERRS
        sep #$20
        .a8
        lda #'?'
        jsl K_CHROUT
        lda #'S'
        jsl K_CHROUT
        rep #$20
        .a16
        lda MB_LASTERR
        sep #$20
        .a8
        jsr print_hex_byte
        jsr print_crlf
        ldx #$0000
@drain:
        jsl K_CHRIN
        bcs @got
        jsl K_IDLE
        inx
        cpx #4096
        bne @drain
        plx
        rts
@got:
        ldx #$0000
        bra @drain

; Two hex characters -> A, folded into the running checksum; carry clear on
; anything that is not hex.
srec_byte:
        .a8
        .i16
        jsl K_CHRIN_WAIT
        jsr srec_digit
        bcc @bad
        asl a
        asl a
        asl a
        asl a
        sta z:SBYTE
        jsl K_CHRIN_WAIT
        jsr srec_digit
        bcc @bad
        ora z:SBYTE
        sta z:SBYTE
        clc
        adc z:SSUM
        sta z:SSUM
        lda z:SBYTE
        sec
        rts
@bad:
        clc
        rts

; A hex character -> its value; carry reports validity.
srec_digit:
        .a8
        .i16
        jsr mon_upper
        cmp #'0'
        bcc @bad
        cmp #'9'+1
        bcc @digit
        cmp #'A'
        bcc @bad
        cmp #'F'+1
        bcs @bad
        sbc #'A'-11             ; carry is clear: A-'A'+10 lands in 10..15
        sec
        rts
@digit:
        sec
        sbc #'0'
        sec
        rts
@bad:
        clc
        rts

.segment "FARDATA"

; Address bytes by record type; zero marks a type this loader rejects.
addr_sizes:
        .byte 2                 ; S0 header
        .byte 2                 ; S1 data, 16-bit
        .byte 3                 ; S2 data, 24-bit
        .byte 4                 ; S3 data, 32-bit
        .byte 0                 ; S4 reserved
        .byte 2                 ; S5 record count, read and dropped
        .byte 0                 ; S6 unsupported
        .byte 4                 ; S7 termination, 32-bit entry
        .byte 3                 ; S8 termination, 24-bit entry
        .byte 2                 ; S9 termination, 16-bit entry
