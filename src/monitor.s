; monitor.s - the machine-language monitor.
;
; The loop is banner, prompt, RDLINE, parse, dispatch. Commands are one
; letter, case-insensitive, with whitespace-separated hex operands; addresses
; are up to six hex digits and byte values up to two. A parse error prints a
; question mark and the offending column, sets MB_LASTERR, and reprompts.
;
; Everything here is far code in one bank: internal calls are jsr/rts, and
; only KERNAL entry points are reached with jsl. Memory operands are walked
; through direct-page long pointers, so a command reaches all sixteen
; megabytes of the address space - including, deliberately, the I/O rows,
; where a dump performs real reads exactly as the bus would see them.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import banner
.import hexdigits

.export mon_parse_hex
.export mon_error
.export monitor_entry
.export print_crlf
.export print_hex_byte
.export print_space

; Monitor direct page, within DP_MON ($80-$BF).
MPARSE          = DP_MON + 0    ; 16-bit: parse cursor into LINEBUF
MVAL            = DP_MON + 2    ; 32-bit: hex operand accumulator
MADDR           = DP_MON + 6    ; 32-bit: first address operand / walk pointer
MEND            = DP_MON + 10   ; 32-bit: second address operand
MDST            = DP_MON + 14   ; 32-bit: third address operand / walk pointer
MTMP            = DP_MON + 18   ; 16-bit scratch
MCNT            = DP_MON + 20   ; 16-bit: bytes on the current dump line
MCUR            = DP_MON + 22   ; 32-bit: where a bare M continues

.segment "FARCODE"

; Entered from cold start (and, through KWARM, from warm start) with the ABI
; register state; never returns.
monitor_entry:
        .a8
        .i16
        lda #^banner
        ldx #.loword(banner)
        jsl K_PUTS
        rep #$20
        .a16
        stz z:MCUR
        stz z:MCUR+2
        sep #$20
        .a8
mon_loop:
        rep #$20
        .a16
        lda MB_PROMPTS
        inc a
        sta MB_PROMPTS
        stz z:MPARSE
        sep #$20
        .a8
        lda #^mon_prompt
        ldx #.loword(mon_prompt)
        jsl K_PUTS
        jsl K_RDLINE
        jsr mon_skip_spaces
        jsr mon_next
        beq mon_loop            ; an empty line just reprompts
        jsr mon_upper
        cmp #'M'
        beq @m
        cmp #'E'
        beq @e
        cmp #'F'
        beq @f
        cmp #'T'
        beq @t
        cmp #'C'
        beq @c
        cmp #'R'
        beq @r
        cmp #'H'
        beq @h
        cmp #'X'
        beq @x
        cmp #'D'
        beq @d
        lda #ERR_COMMAND
        jsr mon_error
        jmp mon_loop
@m:
        jsr mon_counted
        jsr cmd_dump
        jmp mon_loop
@e:
        jsr mon_counted
        jsr cmd_deposit
        jmp mon_loop
@f:
        jsr mon_counted
        jsr cmd_fill
        jmp mon_loop
@t:
        jsr mon_counted
        jsr cmd_transfer
        jmp mon_loop
@c:
        jsr mon_counted
        jsr cmd_compare
        jmp mon_loop
@r:
        jsr mon_counted
        jsr cmd_registers
        jmp mon_loop
@h:
        jsr mon_counted
        lda #^help_text
        ldx #.loword(help_text)
        jsl K_PUTS
        jmp mon_loop
@x:
        jsl K_WARM
@d:
        lda #^reserved_text
        ldx #.loword(reserved_text)
        jsl K_PUTS
        jmp mon_loop

; Counts a dispatched command.
mon_counted:
        .a8
        .i16
        rep #$20
        .a16
        lda MB_CMDS
        inc a
        sta MB_CMDS
        sep #$20
        .a8
        rts

; Reports the error code in A: the code lands in MB_LASTERR, and the console
; shows a question mark with the parse column.
mon_error:
        .a8
        .i16
        rep #$20
        .a16
        and #$00FF
        sta MB_LASTERR
        sep #$20
        .a8
        lda #'?'
        jsl K_CHROUT
        jsr print_space
        lda z:MPARSE
        jsr print_hex_byte
        jsr print_crlf
        rts

; ----------------------------------------------------------------------------
; Commands.
; ----------------------------------------------------------------------------

; M [addr [end]] - dump memory, sixteen bytes to a line, hex then ASCII. With
; no operands it continues for 128 bytes from where the last walk stopped;
; with one it dumps 128 bytes from there.
cmd_dump:
        .a8
        .i16
        jsr mon_parse_hex
        bcc @from_cursor
        rep #$20
        .a16
        lda z:MVAL
        sta z:MADDR
        lda z:MVAL+2
        sta z:MADDR+2
        sep #$20
        .a8
        jsr mon_parse_hex
        bcc @default_end
        rep #$20
        .a16
        lda z:MVAL
        sta z:MEND
        lda z:MVAL+2
        sta z:MEND+2
        bra @lines
@from_cursor:
        rep #$20
        .a16
        lda z:MCUR
        sta z:MADDR
        lda z:MCUR+2
        sta z:MADDR+2
        sep #$20
        .a8
@default_end:
        rep #$20
        .a16
        lda z:MADDR
        clc
        adc #127
        sta z:MEND
        lda z:MADDR+2
        adc #0
        sta z:MEND+2
@lines:
        sep #$20
        .a8
@line:
        jsr dump_line
        jsr addr_past_end
        bcc @line
        rep #$20
        .a16
        lda z:MADDR
        sta z:MCUR
        lda z:MADDR+2
        sta z:MCUR+2
        sep #$20
        .a8
        rts

; One dump line at MADDR, clipped to MEND, advancing MADDR past what it
; printed.
dump_line:
        .a8
        .i16
        phx
        phy
        ; How many of the sixteen columns are inside the range.
        rep #$20
        .a16
        lda z:MEND
        sec
        sbc z:MADDR
        sta z:MTMP
        lda z:MEND+2
        sbc z:MADDR+2
        bne @sixteen
        lda z:MTMP
        cmp #16
        bcs @sixteen
        inc a
        bra @counted
@sixteen:
        lda #16
@counted:
        sta z:MCNT
        sep #$20
        .a8
        lda z:MADDR+2
        jsr print_hex_byte
        lda #':'
        jsl K_CHROUT
        rep #$20
        .a16
        lda z:MADDR
        sep #$20
        .a8
        xba
        jsr print_hex_byte
        xba
        jsr print_hex_byte
        jsr print_space
        ldy #$0000
@hex:
        cpy z:MCNT
        bcs @pad
        jsr print_space
        lda [MADDR],y
        jsr print_hex_byte
        iny
        cpy #16
        bne @hex
        bra @ascii
@pad:
        jsr print_space
        jsr print_space
        jsr print_space
        iny
        cpy #16
        bne @hex
@ascii:
        jsr print_space
        jsr print_space
        ldy #$0000
@glyphs:
        cpy z:MCNT
        bcs @advance
        lda [MADDR],y
        cmp #$20
        bcc @dot
        cmp #$7F
        bcc @keep
@dot:
        lda #'.'
@keep:
        jsl K_CHROUT
        iny
        bra @glyphs
@advance:
        jsr print_crlf
        rep #$20
        .a16
        lda z:MADDR
        clc
        adc z:MCNT
        sta z:MADDR
        bcc @done
        lda z:MADDR+2
        inc a
        sta z:MADDR+2
@done:
        sep #$20
        .a8
        ply
        plx
        rts

; Carry set once MADDR has walked past MEND.
addr_past_end:
        .a8
        .i16
        rep #$20
        .a16
        lda z:MADDR+2
        cmp z:MEND+2
        bcc @inside
        bne @past
        lda z:MADDR
        cmp z:MEND
        bcc @inside
        beq @inside
@past:
        sep #$20
        .a8
        sec
        rts
@inside:
        sep #$20
        .a8
        clc
        rts

; E addr bb .. - deposit the bytes where they are told to go.
cmd_deposit:
        .a8
        .i16
        jsr mon_parse_hex
        bcc @bad
        rep #$20
        .a16
        lda z:MVAL
        sta z:MADDR
        lda z:MVAL+2
        sta z:MADDR+2
        sep #$20
        .a8
        jsr mon_parse_hex
        bcc @bad                ; at least one byte
@store:
        lda z:MVAL
        sta [MADDR]
        rep #$20
        .a16
        lda z:MADDR
        inc a
        sta z:MADDR
        bne @next
        lda z:MADDR+2
        inc a
        sta z:MADDR+2
@next:
        sep #$20
        .a8
        jsr mon_parse_hex
        bcs @store
        jsr mon_at_end
        bcc @bad                ; trailing junk that was not hex
        rep #$20
        .a16
        lda z:MADDR
        sta z:MCUR
        lda z:MADDR+2
        sta z:MCUR+2
        sep #$20
        .a8
        rts
@bad:
        lda #ERR_OPERAND
        jsr mon_error
        rts

; F addr end bb - fill the inclusive range with the byte.
cmd_fill:
        .a8
        .i16
        jsr mon_parse_hex
        bcc @bad
        rep #$20
        .a16
        lda z:MVAL
        sta z:MADDR
        lda z:MVAL+2
        sta z:MADDR+2
        sep #$20
        .a8
        jsr mon_parse_hex
        bcc @bad
        rep #$20
        .a16
        lda z:MVAL
        sta z:MEND
        lda z:MVAL+2
        sta z:MEND+2
        sep #$20
        .a8
        jsr mon_parse_hex
        bcc @bad
@fill:
        lda z:MVAL
        sta [MADDR]
        rep #$20
        .a16
        lda z:MADDR
        inc a
        sta z:MADDR
        bne @check
        lda z:MADDR+2
        inc a
        sta z:MADDR+2
@check:
        sep #$20
        .a8
        jsr addr_past_end
        bcc @fill
        rts
@bad:
        lda #ERR_OPERAND
        jsr mon_error
        rts

; T addr end dst - copy the inclusive range to the destination, choosing the
; walk direction so an overlapping copy never eats its own tail.
cmd_transfer:
        .a8
        .i16
        jsr mon_three_operands
        bcc @bad
        ; Length - 1 into MVAL as a 32-bit count.
        rep #$20
        .a16
        lda z:MEND
        sec
        sbc z:MADDR
        sta z:MVAL
        lda z:MEND+2
        sbc z:MADDR+2
        sta z:MVAL+2
        ; A destination above the source copies from the top down.
        lda z:MDST+2
        cmp z:MADDR+2
        bcc @up
        bne @down
        lda z:MDST
        cmp z:MADDR
        bcc @up
        beq @done16
@down:
        ; Point both walks at the last byte.
        lda z:MADDR
        clc
        adc z:MVAL
        sta z:MADDR
        lda z:MADDR+2
        adc z:MVAL+2
        sta z:MADDR+2
        lda z:MDST
        clc
        adc z:MVAL
        sta z:MDST
        lda z:MDST+2
        adc z:MVAL+2
        sta z:MDST+2
        sep #$20
        .a8
@down_loop:
        lda [MADDR]
        sta [MDST]
        jsr transfer_step_down
        bcs @finish
        bra @down_loop
@up:
        sep #$20
        .a8
@up_loop:
        lda [MADDR]
        sta [MDST]
        jsr transfer_step_up
        bcs @finish
        bra @up_loop
@done16:
        sep #$20
        .a8
        lda [MADDR]
        sta [MDST]
@finish:
        rts
@bad:
        lda #ERR_OPERAND
        jsr mon_error
        rts

; Steps both transfer walks up one byte; carry set when the count runs out.
transfer_step_up:
        .a8
        .i16
        rep #$20
        .a16
        lda z:MVAL
        bne @count
        lda z:MVAL+2
        beq @out
        dec a
        sta z:MVAL+2
        lda #$FFFF
        sta z:MVAL
        bra @step
@count:
        dec a
        sta z:MVAL
@step:
        lda z:MADDR
        inc a
        sta z:MADDR
        bne @dst
        lda z:MADDR+2
        inc a
        sta z:MADDR+2
@dst:
        lda z:MDST
        inc a
        sta z:MDST
        bne @go
        lda z:MDST+2
        inc a
        sta z:MDST+2
@go:
        sep #$20
        .a8
        clc
        rts
@out:
        sep #$20
        .a8
        sec
        rts

; Steps both transfer walks down one byte; carry set when the count runs out.
transfer_step_down:
        .a8
        .i16
        rep #$20
        .a16
        lda z:MVAL
        bne @count
        lda z:MVAL+2
        beq @out
        dec a
        sta z:MVAL+2
        lda #$FFFF
        sta z:MVAL
        bra @step
@count:
        dec a
        sta z:MVAL
@step:
        lda z:MADDR
        dec a
        sta z:MADDR
        cmp #$FFFF
        bne @dst
        lda z:MADDR+2
        dec a
        sta z:MADDR+2
@dst:
        lda z:MDST
        dec a
        sta z:MDST
        cmp #$FFFF
        bne @go
        lda z:MDST+2
        dec a
        sta z:MDST+2
@go:
        sep #$20
        .a8
        clc
        rts
@out:
        sep #$20
        .a8
        sec
        rts

; C addr end dst - compare the range against the destination, printing one
; "BB:HHHH aa bb" line per difference.
cmd_compare:
        .a8
        .i16
        jsr mon_three_operands
        bcc @bad
@loop:
        lda [MADDR]
        sta z:MTMP
        lda [MDST]
        cmp z:MTMP
        beq @step
        phy
        lda z:MADDR+2
        jsr print_hex_byte
        lda #':'
        jsl K_CHROUT
        rep #$20
        .a16
        lda z:MADDR
        sep #$20
        .a8
        xba
        jsr print_hex_byte
        xba
        jsr print_hex_byte
        jsr print_space
        lda z:MTMP
        jsr print_hex_byte
        jsr print_space
        lda [MDST]
        jsr print_hex_byte
        jsr print_crlf
        ply
@step:
        rep #$20
        .a16
        lda z:MDST
        inc a
        sta z:MDST
        bne @src
        lda z:MDST+2
        inc a
        sta z:MDST+2
@src:
        lda z:MADDR
        inc a
        sta z:MADDR
        bne @check
        lda z:MADDR+2
        inc a
        sta z:MADDR+2
@check:
        sep #$20
        .a8
        jsr addr_past_end
        bcc @loop
        rts
@bad:
        lda #ERR_OPERAND
        jsr mon_error
        rts

; R - display the saved user register frame; R reg val sets one register.
; The names are A, X, Y, S, P, D, B (data bank), K (program bank) and PC.
cmd_registers:
        .a8
        .i16
        jsr mon_skip_spaces
        jsr mon_peek
        bne @set
        ; PC=BB:HHHH A=HHHH X=HHHH Y=HHHH S=HHHH D=HHHH B=HH P=HH
        lda #'P'
        jsl K_CHROUT
        lda #'C'
        jsl K_CHROUT
        lda #'='
        jsl K_CHROUT
        lda RF_PBR
        jsr print_hex_byte
        lda #':'
        jsl K_CHROUT
        ldx RF_PC
        jsr print_hex_x
        lda #'A'
        jsr print_reg_word_prefix
        ldx RF_C
        jsr print_hex_x
        lda #'X'
        jsr print_reg_word_prefix
        ldx RF_X
        jsr print_hex_x
        lda #'Y'
        jsr print_reg_word_prefix
        ldx RF_Y
        jsr print_hex_x
        lda #'S'
        jsr print_reg_word_prefix
        ldx RF_S
        jsr print_hex_x
        lda #'D'
        jsr print_reg_word_prefix
        ldx RF_D
        jsr print_hex_x
        lda #'B'
        jsr print_reg_word_prefix
        lda RF_DBR
        jsr print_hex_byte
        lda #'P'
        jsr print_reg_word_prefix
        lda RF_P
        jsr print_hex_byte
        jsr print_crlf
        rts
@set:
        jsr mon_next
        jsr mon_upper
        sta z:MCNT              ; parse_hex owns MTMP, so the letter lives here
        cmp #'P'
        bne @named
        jsr mon_peek
        jsr mon_upper
        cmp #'C'
        bne @named
        jsr mon_next
        lda #'*'                ; marks "PC" past the single letters
        sta z:MCNT
@named:
        jsr mon_parse_hex
        bcc @bad
        lda z:MCNT
        cmp #'*'
        beq @pc
        cmp #'A'
        beq @a
        cmp #'X'
        beq @x
        cmp #'Y'
        beq @y
        cmp #'S'
        beq @s
        cmp #'P'
        beq @p
        cmp #'D'
        beq @d
        cmp #'B'
        beq @b
        cmp #'K'
        beq @k
@bad:
        lda #ERR_OPERAND
        jsr mon_error
        rts
@pc:
        rep #$20
        .a16
        lda z:MVAL
        sta RF_PC
        sep #$20
        .a8
        lda z:MVAL+2
        sta RF_PBR
        rts
@a:
        rep #$20
        .a16
        lda z:MVAL
        sta RF_C
        sep #$20
        .a8
        rts
@x:
        rep #$20
        .a16
        lda z:MVAL
        sta RF_X
        sep #$20
        .a8
        rts
@y:
        rep #$20
        .a16
        lda z:MVAL
        sta RF_Y
        sep #$20
        .a8
        rts
@s:
        rep #$20
        .a16
        lda z:MVAL
        sta RF_S
        sep #$20
        .a8
        rts
@p:
        lda z:MVAL
        sta RF_P
        rts
@d:
        rep #$20
        .a16
        lda z:MVAL
        sta RF_D
        sep #$20
        .a8
        rts
@b:
        lda z:MVAL
        sta RF_DBR
        rts
@k:
        lda z:MVAL
        sta RF_PBR
        rts

; Prints " <letter>=" for the register display.
print_reg_word_prefix:
        .a8
        .i16
        pha
        jsr print_space
        pla
        jsl K_CHROUT
        lda #'='
        jsl K_CHROUT
        rts

; ----------------------------------------------------------------------------
; Parsing.
; ----------------------------------------------------------------------------

; Parses whitespace-separated hex digits into MVAL as a 32-bit value; carry
; clear when no digits stood at the cursor.
mon_parse_hex:
        .a8
        .i16
        phx
        jsr mon_skip_spaces
        rep #$20
        .a16
        stz z:MVAL
        stz z:MVAL+2
        sep #$20
        .a8
        ldx #$0000              ; digit count
@loop:
        jsr mon_peek
        jsr mon_upper
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcc @digit
        cmp #'A'
        bcc @end
        cmp #'F'+1
        bcs @end
        sbc #'A'-11             ; carry is clear: A-'A'+10 lands in 10..15
        bra @accept
@digit:
        sec
        sbc #'0'
@accept:
        sta z:MTMP
        rep #$20
        .a16
        asl z:MVAL
        rol z:MVAL+2
        asl z:MVAL
        rol z:MVAL+2
        asl z:MVAL
        rol z:MVAL+2
        asl z:MVAL
        rol z:MVAL+2
        lda z:MVAL
        ora z:MTMP
        sta z:MVAL
        sep #$20
        .a8
        jsr mon_advance
        inx
        bra @loop
@end:
        cpx #$0000
        beq @none
        plx
        sec
        rts
@none:
        plx
        clc
        rts

; Parses addr end dst into MADDR, MEND and MDST; carry clear on any miss.
mon_three_operands:
        .a8
        .i16
        jsr mon_parse_hex
        bcc @bad
        rep #$20
        .a16
        lda z:MVAL
        sta z:MADDR
        lda z:MVAL+2
        sta z:MADDR+2
        sep #$20
        .a8
        jsr mon_parse_hex
        bcc @bad
        rep #$20
        .a16
        lda z:MVAL
        sta z:MEND
        lda z:MVAL+2
        sta z:MEND+2
        sep #$20
        .a8
        jsr mon_parse_hex
        bcc @bad
        rep #$20
        .a16
        lda z:MVAL
        sta z:MDST
        lda z:MVAL+2
        sta z:MDST+2
        sep #$20
        .a8
        sec
        rts
@bad:
        clc
        rts

; The character at the parse cursor -> A, with Z reflecting the terminator.
mon_peek:
        .a8
        .i16
        phx
        ldx z:MPARSE
        lda a:LINEBUF,x
        plx
        cmp #$00                ; plx replaced the flags; Z must follow the character
        rts

; mon_peek, and the cursor moves past anything it read.
mon_next:
        .a8
        .i16
        jsr mon_peek
        beq @done
        pha
        jsr mon_advance
        pla
@done:
        rts

; Moves the parse cursor one character on.
mon_advance:
        .a8
        .i16
        rep #$20
        .a16
        lda z:MPARSE
        inc a
        sta z:MPARSE
        sep #$20
        .a8
        rts

; Leaves the cursor on the first character that is not a space.
mon_skip_spaces:
        .a8
        .i16
@loop:
        jsr mon_peek
        cmp #' '
        bne @done
        jsr mon_advance
        bra @loop
@done:
        rts

; Carry set when nothing but spaces stands between the cursor and the end.
mon_at_end:
        .a8
        .i16
        jsr mon_skip_spaces
        jsr mon_peek
        beq @yes
        clc
        rts
@yes:
        sec
        rts

; A -> its upper-case letter, when it holds a lower-case one.
mon_upper:
        .a8
        .i16
        cmp #'a'
        bcc @done
        cmp #'z'+1
        bcs @done
        and #$DF
@done:
        rts

; ----------------------------------------------------------------------------
; Printing.
; ----------------------------------------------------------------------------

; Prints the byte in A as two hex digits. Preserves X and Y.
print_hex_byte:
        .a8
        .i16
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr print_hex_nibble
        pla
        jsr print_hex_nibble
        rts

; Prints the word in X as four hex digits.
print_hex_x:
        .a8
        .i16
        phx
        rep #$20
        .a16
        txa
        sep #$20
        .a8
        xba
        jsr print_hex_byte
        xba
        jsr print_hex_byte
        plx
        rts

; Prints one hex digit for the low nibble of A. The full sixteen-bit
; accumulator is preserved, because callers print a word's two halves by
; swapping them through B with xba - CHROUT and the masking here would
; otherwise eat the half still waiting its turn.
print_hex_nibble:
        .a8
        .i16
        phx
        rep #$20
        .a16
        pha
        and #$000F
        tax
        sep #$20
        .a8
        lda a:hexdigits,x
        jsl K_CHROUT
        rep #$20
        .a16
        pla
        sep #$20
        .a8
        plx
        rts

print_space:
        .a8
        .i16
        lda #' '
        jsl K_CHROUT
        rts

print_crlf:
        .a8
        .i16
        lda #$0D
        jsl K_CHROUT
        lda #$0A
        jsl K_CHROUT
        rts

.segment "FARDATA"

mon_prompt:
        .byte "* ", 0

reserved_text:
        .byte "? (reserved)", $0D, $0A, 0

help_text:
        .byte "M [A [B]]   dump memory", $0D, $0A
        .byte "E A BB ..   deposit bytes", $0D, $0A
        .byte "F A B VV    fill A..B with VV", $0D, $0A
        .byte "T A B D     transfer A..B to D", $0D, $0A
        .byte "C A B D     compare A..B with D", $0D, $0A
        .byte "L           load S-records", $0D, $0A
        .byte "G [A]       call A; rtl returns", $0D, $0A
        .byte "R [reg VV]  registers", $0D, $0A
        .byte "X           warm start", $0D, $0A
        .byte "H           help", $0D, $0A, 0
