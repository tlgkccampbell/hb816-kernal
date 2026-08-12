; colors.s - a text-mode colour chart, and the shape of a KERNAL program.
;
; Linked to run from work RAM at $010000 and loaded through the monitor as
; S-records, this walks all sixteen RGBI text colours: each gets a row with
; its index, its name in its own colour, and a swatch of full-block glyphs,
; and the bottom carries a bar of every colour as a background. Everything
; goes through the KERNAL jump table - SETATTR to change colours, CHROUT and
; PUTS to print - so the same text also lands on the serial console, plainly.
;
; The program is entered by G with the ABI register state and comes back to
; the monitor with rtl, leaving the console attribute the way it found it.

.p816

.include "kernal.inc"

.segment "CODE"

entry:
        .a8
        .i16
        lda #$0F                ; white on black to start
        jsl K_SETATTR
        pha                     ; the attribute the monitor was using
        jsl K_CLS
        lda #^title
        ldx #.loword(title)
        jsl K_PUTS

        ; One row per colour: index digit, name, swatch.
        ldy #$0000
@row:
        lda #$0F
        jsl K_SETATTR
        tya                     ; the colour index, 0-15
        cmp #10
        bcc @digit
        adc #'A'-11             ; carry is set: +('A'-10)
        bra @index
@digit:
        adc #'0'                ; carry is clear
@index:
        jsl K_CHROUT
        lda #' '
        jsl K_CHROUT

        ; The name wears its own colour; black would vanish, so it stands on
        ; light grey instead.
        tya
        bne @colour
        lda #$E0                ; black on light grey
        bra @named
@colour:
        ; the colour as foreground on black - the index is the attribute
@named:
        jsl K_SETATTR
        rep #$20
        .a16
        tya
        asl a
        tax
        lda f:name_table,x
        tax
        sep #$20
        .a8
        lda #^name_table
        jsl K_PUTS

        ; A swatch of four full blocks in the same colour.
        lda #$DB
        jsl K_CHROUT
        lda #$DB
        jsl K_CHROUT
        lda #$DB
        jsl K_CHROUT
        lda #$DB
        jsl K_CHROUT

        lda #$0F
        jsl K_SETATTR
        jsr crlf
        iny
        cpy #$0010
        bne @row

        ; The bar: every colour as a background, two columns each.
        jsr crlf
        ldy #$0000
@bar:
        tya
        asl a
        asl a
        asl a
        asl a                   ; the colour as background, black foreground
        jsl K_SETATTR
        lda #' '
        jsl K_CHROUT
        lda #' '
        jsl K_CHROUT
        iny
        cpy #$0010
        bne @bar

        ; Leave things as they were found.
        pla
        jsl K_SETATTR
        jsr crlf
        rtl

crlf:
        lda #$0D
        jsl K_CHROUT
        lda #$0A
        jsl K_CHROUT
        rts

.segment "RODATA"

title:
        .byte "HB816 TEXT MODE COLORS", $0D, $0A, $0D, $0A, 0

; The RGBI nibble runs R:G:B:I from the high bit down, which is why the
; ordering below reads unlike CGA's.
name_table:
        .word .loword(name_black)
        .word .loword(name_dark_grey)
        .word .loword(name_blue)
        .word .loword(name_bright_blue)
        .word .loword(name_green)
        .word .loword(name_bright_green)
        .word .loword(name_cyan)
        .word .loword(name_bright_cyan)
        .word .loword(name_red)
        .word .loword(name_bright_red)
        .word .loword(name_magenta)
        .word .loword(name_bright_magenta)
        .word .loword(name_brown)
        .word .loword(name_yellow)
        .word .loword(name_light_grey)
        .word .loword(name_white)

name_black:
        .byte "BLACK           ", 0
name_dark_grey:
        .byte "DARK GREY       ", 0
name_blue:
        .byte "BLUE            ", 0
name_bright_blue:
        .byte "BRIGHT BLUE     ", 0
name_green:
        .byte "GREEN           ", 0
name_bright_green:
        .byte "BRIGHT GREEN    ", 0
name_cyan:
        .byte "CYAN            ", 0
name_bright_cyan:
        .byte "BRIGHT CYAN     ", 0
name_red:
        .byte "RED             ", 0
name_bright_red:
        .byte "BRIGHT RED      ", 0
name_magenta:
        .byte "MAGENTA         ", 0
name_bright_magenta:
        .byte "BRIGHT MAGENTA  ", 0
name_brown:
        .byte "BROWN           ", 0
name_yellow:
        .byte "YELLOW          ", 0
name_light_grey:
        .byte "LIGHT GREY      ", 0
name_white:
        .byte "WHITE           ", 0
