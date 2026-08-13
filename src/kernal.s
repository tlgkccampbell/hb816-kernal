; kernal.s - cold and warm start, the background tick, and the RAM vectors.
;
; Far code: everything here runs with the program bank in the ROM's long
; window and returns with rtl. Data reads from this bank go through f: long
; addressing, because the data bank stays zero.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import brk_default
.import con_chrin
.import con_chrin_wait
.import con_chrout
.import con_rdline
.import cursor_draw
.import cursor_undraw
.import init_uart
.import kbd_init
.import kbd_poll
.import int_default
.import monitor_entry
.import nmi_exit
.import rts_resume
.import rx_poll
.import tx_pump
.import video_init

.export banner
.export k_cold
.export k_idle
.export k_unimpl
.export k_warm

.segment "FARCODE"

; Cold start, entered from the reset stub in native mode with A 8-bit, X/Y
; 16-bit, S at STACK_TOP, D and DBR zero. Order matters three times over: the
; RAM vectors are installed before any interrupt path is unmasked, the
; console's RTS stays low until the whole console can poll, and unmasking NMI
; is the last thing done before the monitor takes over.
k_cold:
        .a8
        .i16

        ; Clear the KERNAL's low RAM - identity block, vectors, variables,
        ; mailboxes, rings and buffers - in one sweep.
        rep #$20
        .a16
        lda #$0000
        ldx #ID_BASE
@clear:
        sta a:$0000,x
        inx
        inx
        cpx #USER_BASE
        bne @clear

        ; Install the ROM defaults into the RAM indirection vectors.
        ldx #$0000
@vectors:
        lda f:vec_defaults,x
        sta a:V_CHRIN,x
        inx
        inx
        cpx #vec_defaults_end - vec_defaults
        bne @vectors

        sep #$20
        .a8

        ; The register frame starts in the ABI state, so G enters a program
        ; with an eight-bit accumulator and sixteen-bit indexes even before
        ; anything is run or set through R.
        lda #$24                ; M and I set
        sta RF_P

        lda #$01
        sta MB_STEP

        ; Both serial ports; the console's RTS stays low until it can poll.
        ldx #$0000
        jsl init_uart
        ldx #UART_STRIDE
        jsl init_uart
        lda #$02
        sta MB_STEP

        ; The display, in its mandatory order.
        jsl video_init
        lda #$03
        sta MB_STEP

        ; The keyboard port. Nothing before this reads it, so a byte the
        ; decoder board strobed while the machine was still coming up is
        ; discarded rather than decoded out of context.
        jsl kbd_init

        ; The console is whole - transmit ring, input ring, glass TTY - so
        ; the far end may talk now.
        jsl rts_resume
        lda #$04
        sta MB_STEP

        ; Ready: report it, then unmask both interrupt paths and hand the
        ; machine to the monitor. IRQ comes last of all, because from here the
        ; keyboard and the serial port fill the input ring on their own.
        lda #BOOT_READY
        sta MB_BOOTFLAG
        lda #(ICR_INTEN | ICR_NMIEN | ICR_IRQEN)
        icr_store
        cli
        jml monitor_entry

; Warm start: a fresh stack, direct page and data bank, the write-only video
; registers replayed from their shadows, and the monitor re-entered. The
; rings and the screen survive.
k_warm:
        rep #$30
        .a16
        .i16
        ldx #STACK_TOP
        txs
        lda #$0000
        tcd
        sep #$20
        .a8
        lda #$00
        pha
        plb
        jsl K_VPU_SYNC
        jml monitor_entry

; One background iteration: pump the transmitter and blink the cursor off the
; vblank tick. Neither input source is polled here - the interrupt handler
; fills the ring, and a second caller of rx_poll would race it over the
; receive FIFO.
k_idle:
        .a8
        .i16
        jsl tx_pump
        rep #$20
        .a16
        lda KV_TICK
        beq @done
        stz KV_TICK
        lda KV_BLINK
        inc a
        cmp #30
        bcc @keep
        sep #$20
        .a8
        lda KV_CURDRAWN
        beq @draw
        jsl cursor_undraw
        bra @mark
@draw:
        jsl cursor_draw
@mark:
        rep #$20
        .a16
        lda KV_CURDRAWN
        sta MB_CURSOR
        lda #$0000
@keep:
        sta KV_BLINK
@done:
        sep #$20
        .a8
        rtl

; The IRQ, which both input sources share: the decoder has one interrupt
; input and the adapter and both serial ports pull the same net. Neither
; source is asked whether it was the one that interrupted - each poll is cheap
; and finds nothing when it was not - and each empties its own source before
; returning, so a level-triggered line is always released.
;
; The interrupted code owns the register widths, the direct page and the data
; bank, so all three are saved and set to what the routines below expect: A
; eight-bit, X and Y sixteen-bit, D zero, DBR zero.
irq_service:
        rep #$30
        .a16
        .i16
        pha
        phx
        phy
        phd
        phb
        lda #$0000
        tcd
        sep #$20
        .a8
        lda #$00
        pha
        plb
        jsl kbd_poll
        jsl rx_poll
        rep #$30
        .a16
        .i16
        plb
        pld
        ply
        plx
        pla
        rti

; Target of every jump-table slot that has no implementation yet: report
; failure through the ABI's carry channel.
k_unimpl:
        sec
        rtl

.segment "FARDATA"

kernal_version:
        .byte "HB816 KERNAL 0.1", 0

banner:
        .byte "HB816 KERNAL 0.1", $0D, $0A, 0

; ROM defaults for the RAM indirection vectors, in V_CHRIN..V_COP order:
; four bytes each, a 24-bit target and a pad.
vec_defaults:
        .faraddr con_chrin      ; V_CHRIN
        .byte $00
        .faraddr con_chrout     ; V_CHROUT
        .byte $00
        .faraddr con_chrin_wait ; V_CHRIN_WAIT
        .byte $00
        .faraddr con_rdline     ; V_RDLINE
        .byte $00
        .faraddr nmi_exit       ; V_NMI_HOOK
        .byte $00
        .faraddr irq_service    ; V_IRQ
        .byte $00
        .faraddr brk_default    ; V_BRK
        .byte $00
        .faraddr brk_default    ; V_COP
        .byte $00
vec_defaults_end:
