; console.s - the device-independent console.
;
; Output fans out: one CHROUT byte goes to the serial transmit ring and to the
; glass TTY, so the console is on both sinks at once. Input merges: every
; source pushes translated bytes through INPUT_PUSH into one ring, and CHRIN
; drains the ring without knowing what fed it - the serial poll today, a
; keyboard driver later. Echo belongs to RDLINE alone; no driver and no read
; call echoes anything.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import rts_resume
.import tty_putc
.import tx_pump
.import tx_putc

.export con_chrin
.export con_chrin_wait
.export con_chrout
.export con_rdline
.export k_input_push
.export k_puts

.segment "FARCODE"

; Non-blocking read: C=1 with the character in A, C=0 with none. Pumps the
; transmitter first, so a caller spinning on CHRIN alone still makes the
; machine go; consuming a byte frees ring room, so RTS gets a chance to come
; back up. Both input sources fill the ring from the interrupt handler, which
; is why nothing is polled here.
con_chrin:
        .a8
        .i16
        phx
        jsl tx_pump
        rep #$20
        .a16
        lda KV_INTAIL
        cmp KV_INHEAD
        beq @none
        tax
        inc a
        and #INRING_MASK
        sta KV_INTAIL
        sep #$20
        .a8
        lda INRING,x
        pha
        jsl rts_resume
        pla
        plx
        sec
        rtl
@none:
        sep #$20
        .a8
        plx
        clc
        rtl

; Blocking read: loops CHRIN against IDLE until a character arrives.
con_chrin_wait:
        .a8
        .i16
@wait:
        jsl K_CHRIN
        bcs @got
        jsl K_IDLE
        bra @wait
@got:
        rtl

; A -> both sinks: the serial ring first, the glass TTY second, then one pump
; so the byte starts down the wire without waiting for the next IDLE.
con_chrout:
        .a8
        .i16
        pha
        jsl tx_putc
        pla
        pha
        jsl tty_putc
        jsl tx_pump
        pla
        rtl

; The line editor: reads through CHRIN_WAIT into LINEBUF, echoing accepted
; characters through CHROUT - so echo reaches both sinks - and rubbing out
; with BS SP BS. CR or LF ends the line, echoed as CR LF; the buffer is
; NUL-terminated and Y returns the length.
con_rdline:
        .a8
        .i16
        phx
        ldx #$0000
@loop:
        jsl K_CHRIN_WAIT
        cmp #$0D
        beq @done
        cmp #$0A
        beq @done
        cmp #$08
        beq @rubout
        cmp #$7F
        beq @rubout
        cmp #$20
        bcc @loop
        cpx #LINEBUF_MAX
        bcs @loop
        sta LINEBUF,x
        inx
        jsl K_CHROUT
        bra @loop
@rubout:
        cpx #$0000
        beq @loop
        dex
        lda #$08
        jsl K_CHROUT
        lda #$20
        jsl K_CHROUT
        lda #$08
        jsl K_CHROUT
        bra @loop
@done:
        lda #$00
        sta LINEBUF,x
        txy
        lda #$0D
        jsl K_CHROUT
        lda #$0A
        jsl K_CHROUT
        plx
        rtl

; A -> the console input ring; carry reports acceptance. This is the seam
; every input source shares: the serial drain calls it, a keyboard driver
; will call it, and a test can call it to type without a port.
k_input_push:
        .a8
        .i16
        phx
        phy
        pha
        rep #$20
        .a16
        lda KV_INHEAD
        tay
        inc a
        and #INRING_MASK
        cmp KV_INTAIL
        beq @full
        tax
        sep #$20
        .a8
        pla
        sta INRING,y
        rep #$20
        .a16
        txa
        sta KV_INHEAD
        sep #$20
        .a8
        ply
        plx
        sec
        rtl
@full:
        sep #$20
        .a8
        pla
        ply
        plx
        clc
        rtl

; Emits the NUL-terminated string at bank A, address X through CHROUT.
k_puts:
        .a8
        .i16
        phy
        sta z:PTR0+2
        rep #$20
        .a16
        txa
        sta z:PTR0
        sep #$20
        .a8
        ldy #$0000
@loop:
        lda [PTR0],y
        beq @done
        jsl K_CHROUT
        iny
        bra @loop
@done:
        ply
        rtl
