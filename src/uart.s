; uart.s - the 16550 drivers.
;
; The transmit path never blocks: bytes go into a RAM ring and tx_pump hands
; one to the port per call whenever the holding register is empty; a full ring
; drops the byte. The line status register is read in exactly one routine,
; rx_status, because reading it is what clears the overrun bit - so that is
; the one place overruns are counted.
;
; The hot path lives in the bank-0 window; init_uart is far code. Everything
; here runs under the KERNAL ABI state: A 8-bit, X/Y 16-bit, D = 0, DBR = 0.

.p816

.include "hb816.inc"
.include "kernal.inc"

.export init_uart
.export tx_putc
.export tx_pump
.export rx_status

.segment "LOWCODE"

; Queues the byte in A for UART0; a full ring drops it. Preserves X and Y.
tx_putc:
        .a8
        .i16
        phx
        phy
        pha
        rep #$20
        .a16
        lda KV_TXHEAD
        tay
        inc a
        and #TXRING_MASK
        cmp KV_TXTAIL
        beq @full
        tax
        sep #$20
        .a8
        pla
        sta TXRING,y
        rep #$20
        .a16
        txa
        sta KV_TXHEAD
        lda MB_TXCOUNT
        inc a
        sta MB_TXCOUNT
        sep #$20
        .a8
        ply
        plx
        rtl
@full:
        sep #$20
        .a8
        pla
        ply
        plx
        rtl

; Hands UART0 one ring byte whenever its holding register is empty.
tx_pump:
        .a8
        .i16
        phx
        jsl rx_status
        and #LSR_THRE
        beq @done
        rep #$20
        .a16
        lda KV_TXTAIL
        cmp KV_TXHEAD
        beq @empty
        tax
        inc a
        and #TXRING_MASK
        sta KV_TXTAIL
        sep #$20
        .a8
        lda TXRING,x
        sta UART0 + U_DATA
@done:
        plx
        rtl
@empty:
        sep #$20
        .a8
        plx
        rtl

; UART0's line status -> A. This is the only routine that reads the LSR,
; because the read clears the overrun bit; every overrun is counted here.
rx_status:
        .a8
        .i16
        lda UART0 + U_LSR
        pha
        and #LSR_OE
        beq @clean
        rep #$20
        .a16
        lda MB_RXLOST
        inc a
        sta MB_RXLOST
        sep #$20
        .a8
@clean:
        pla
        rtl

.segment "FARCODE"

; Programs the port whose window offset is in X (0 for UART0, UART_STRIDE for
; UART1): 98,340 baud 8N1, FIFOs on with the receive trigger at eight, DTR
; raised but RTS held low - nothing may arrive before the console is ready to
; poll - and the receive interrupt enabled only so the IIR reports the trigger
; level, since the decoder's IRQ path stays masked.
init_uart:
        .a8
        .i16
        lda #LCR_DLAB
        sta UART0 + U_LCR,x
        lda #<BAUD_DIVISOR
        sta UART0 + U_DLL,x
        lda #>BAUD_DIVISOR
        sta UART0 + U_DLM,x
        lda #LCR_8N1
        sta UART0 + U_LCR,x
        lda #FCR_ENABLE
        sta UART0 + U_FCR,x
        lda #MCR_DTR
        sta UART0 + U_MCR,x
        lda #IER_RX
        sta UART0 + U_IER,x
        rtl
