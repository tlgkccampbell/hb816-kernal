; kernal.s - cold and warm start, the background tick, and the RAM vectors.
;
; Far code: everything here runs with the program bank in the ROM's long
; window and returns with rtl. Data reads from this bank go through f: long
; addressing, because the data bank stays zero.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import init_uart
.import int_default
.import nmi_exit
.import tx_pump
.import tx_putc

.export k_cold
.export k_idle
.export k_no_input
.export k_unimpl

.segment "FARCODE"

; Cold start, entered from the reset stub in native mode with A 8-bit, X/Y
; 16-bit, S at STACK_TOP, D and DBR zero. Order matters twice over: the RAM
; vectors must be installed before any interrupt path is unmasked, and
; unmasking NMI is the last thing done.
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
        lda #$01
        sta MB_STEP

        ; Both serial ports; the console's RTS stays low until it can poll.
        ldx #$0000
        jsl init_uart
        ldx #UART_STRIDE
        jsl init_uart
        lda #$02
        sta MB_STEP

        ; The banner goes out on the console port.
        ldx #$0000
@banner:
        lda f:banner,x
        beq @banner_done
        jsl tx_putc
        inx
        bra @banner
@banner_done:
        lda #$03
        sta MB_STEP

        ; Ready: report it, then unmask the vblank NMI - the one interrupt
        ; this firmware takes - as the very last act of initialization.
        lda #$04
        sta MB_STEP
        lda #BOOT_READY
        sta MB_BOOTFLAG
        lda #(ICR_INTEN | ICR_NMIEN)
        icr_store

@loop:
        jsl K_IDLE
        bra @loop

; One background iteration: pump the transmitter. The receive poll and the
; cursor blink join this loop with the console phase.
k_idle:
        .a8
        .i16
        jsl tx_pump
        rtl

; Default CHRIN target while no input driver exists: no character, ever.
k_no_input:
        clc
        rtl

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
        .faraddr k_no_input     ; V_CHRIN
        .byte $00
        .faraddr k_unimpl       ; V_CHROUT
        .byte $00
        .faraddr k_unimpl       ; V_CHRIN_WAIT
        .byte $00
        .faraddr k_unimpl       ; V_RDLINE
        .byte $00
        .faraddr nmi_exit       ; V_NMI_HOOK
        .byte $00
        .faraddr int_default    ; V_IRQ
        .byte $00
        .faraddr int_default    ; V_BRK
        .byte $00
        .faraddr int_default    ; V_COP
        .byte $00
vec_defaults_end:
