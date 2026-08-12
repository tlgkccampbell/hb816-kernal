; vectors.s - everything interrupt dispatch can reach.
;
; The 65816 fetches its native-mode vectors as 16-bit addresses with the
; program bank forced to zero, so every vector target - and the reset path,
; and the jump table whose addresses are the KERNAL's public ABI - lives in
; the bank-0 ROM window this file owns.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import k_unimpl

; ----------------------------------------------------------------------------
; The jump table: 32 four-byte jml slots at $00C000. The table itself is the
; ABI - slots are appended, never reordered, and a slot that has no
; implementation yet lands on k_unimpl, which returns carry set.
; ----------------------------------------------------------------------------

.segment "JUMPTABLE"

        jml reset               ; $C000 KCOLD
        jml k_unimpl            ; $C004 KWARM
        jml k_unimpl            ; $C008 CHRIN
        jml k_unimpl            ; $C00C CHROUT
        jml k_unimpl            ; $C010 CHRIN_WAIT
        jml k_unimpl            ; $C014 RDLINE
        jml k_unimpl            ; $C018 PUTS
        jml k_unimpl            ; $C01C IDLE
        jml k_unimpl            ; $C020 CLS
        jml k_unimpl            ; $C024 PLOT
        jml k_unimpl            ; $C028 SETATTR
        jml k_unimpl            ; $C02C INPUT_PUSH
        jml k_unimpl            ; $C030 VPU_SYNC
        jml k_unimpl            ; $C034 NMI_EXIT
        jml k_unimpl            ; $C038 reserved
        jml k_unimpl            ; $C03C reserved
        jml k_unimpl            ; $C040 reserved
        jml k_unimpl            ; $C044 reserved
        jml k_unimpl            ; $C048 reserved
        jml k_unimpl            ; $C04C reserved
        jml k_unimpl            ; $C050 reserved
        jml k_unimpl            ; $C054 reserved
        jml k_unimpl            ; $C058 reserved
        jml k_unimpl            ; $C05C reserved
        jml k_unimpl            ; $C060 reserved
        jml k_unimpl            ; $C064 reserved
        jml k_unimpl            ; $C068 reserved
        jml k_unimpl            ; $C06C reserved
        jml k_unimpl            ; $C070 reserved
        jml k_unimpl            ; $C074 reserved
        jml k_unimpl            ; $C078 reserved
        jml k_unimpl            ; $C07C reserved

; ----------------------------------------------------------------------------
; Reset and the interrupt stubs.
; ----------------------------------------------------------------------------

.segment "LOWCODE"

; Native mode is entered at the first instruction and never left: stack at the
; top of the bank-0 work-RAM window, direct page at zero, data bank zero.
reset:
        sei
        clc
        xce
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
@spin:                          ; the cold-start body arrives in a later phase
        bra @spin

nmi_handler:
        rti

irq_handler:
        rti

brk_handler:
        rti

cop_handler:
        rti

unused_handler:
        rti

.segment "LOWRODATA"

hexdigits:
        .byte "0123456789ABCDEF"

; ----------------------------------------------------------------------------
; Vector tables. Both are populated: a native-mode machine that fills only the
; emulation table jumps to $0000 on its first interrupt.
; ----------------------------------------------------------------------------

.segment "NATIVEVECTORS"

        .addr cop_handler       ; $FFE4 COP
        .addr brk_handler       ; $FFE6 BRK
        .addr unused_handler    ; $FFE8 ABORT
        .addr nmi_handler       ; $FFEA NMI
        .addr unused_handler    ; $FFEC reserved
        .addr irq_handler       ; $FFEE IRQ

.segment "VECTORS"

        .addr unused_handler    ; $FFF4 COP
        .addr unused_handler    ; $FFF6 reserved
        .addr unused_handler    ; $FFF8 ABORT
        .addr nmi_handler       ; $FFFA NMI
        .addr reset             ; $FFFC RESET
        .addr irq_handler       ; $FFFE IRQ
