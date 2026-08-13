; vectors.s - everything interrupt dispatch can reach.
;
; The 65816 fetches its native-mode vectors as 16-bit addresses with the
; program bank forced to zero, so every vector target - and the reset path,
; and the jump table whose addresses are the KERNAL's public ABI - lives in
; the bank-0 ROM window this file owns.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import k_cold
.import k_idle
.import k_input_push
.import kbd_test
.import k_plot
.import k_puts
.import k_setattr
.import k_unimpl
.import k_vpu_sync
.import k_warm
.import tty_cls

.export hexdigits
.export int_default
.export nmi_exit

; ----------------------------------------------------------------------------
; The jump table: 32 four-byte jml slots at $00C000. The table itself is the
; ABI - slots are appended, never reordered, and a slot that has no
; implementation yet lands on k_unimpl, which returns carry set.
; ----------------------------------------------------------------------------

.segment "JUMPTABLE"

        jml reset               ; $C000 KCOLD
        jml k_warm              ; $C004 KWARM
        jml chrin_entry         ; $C008 CHRIN
        jml chrout_entry        ; $C00C CHROUT
        jml chrin_wait_entry    ; $C010 CHRIN_WAIT
        jml rdline_entry        ; $C014 RDLINE
        jml k_puts              ; $C018 PUTS
        jml k_idle              ; $C01C IDLE
        jml tty_cls             ; $C020 CLS
        jml k_plot              ; $C024 PLOT
        jml k_setattr           ; $C028 SETATTR
        jml k_input_push        ; $C02C INPUT_PUSH
        jml k_vpu_sync          ; $C030 VPU_SYNC
        jml nmi_exit            ; $C034 NMI_EXIT
        jml kbd_test            ; $C038 KBD_TEST
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
; Reset and the interrupt handlers.
; ----------------------------------------------------------------------------

.segment "LOWCODE"

; Native mode is entered at the first instruction and never left: stack at the
; top of the bank-0 work-RAM window, direct page at zero, data bank zero. The
; cold-start body is far code.
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
        jml k_cold

; The vblank NMI: count the frame, raise the tick flag, and leave through the
; hookable vector. Everything is long-addressed because the interrupted code
; owns D and DBR; the handler never touches video memory or a serial port, so
; no interrupt can race a block move or a half-written cell. A hook installed
; in V_NMI_HOOK runs after the jiffy update, with A, X and Y pushed 16-bit,
; and ends by jumping to NMI_EXIT.
nmi_handler:
        rep #$30
        .a16
        .i16
        pha
        phx
        phy
        lda f:MB_JIFFY
        inc a
        sta f:MB_JIFFY
        bne @low_carried
        lda f:MB_JIFFY+2
        inc a
        sta f:MB_JIFFY+2
@low_carried:
        lda f:MB_NMICOUNT
        inc a
        sta f:MB_NMICOUNT
        lda #$0001
        sta f:KV_TICK
        jml [V_NMI_HOOK]

nmi_exit:
        rep #$30
        .a16
        .i16
        ply
        plx
        pla
        rti

; IRQ, BRK and COP dispatch through their RAM vectors so user code can hook
; them; the ROM default is a plain return. Cold start installs the defaults
; before any interrupt path is unmasked, so the vectors are never dispatched
; while they still hold zeroes.
irq_handler:
        jml [V_IRQ]

brk_handler:
        jml [V_BRK]

cop_handler:
        jml [V_COP]

int_default:
        rti

unused_handler:
        rti

; The console calls dispatch through their RAM vectors, so a driver can be
; hooked in front of - or in place of - the ROM's own.
chrin_entry:
        jml [V_CHRIN]

chrout_entry:
        jml [V_CHROUT]

chrin_wait_entry:
        jml [V_CHRIN_WAIT]

rdline_entry:
        jml [V_RDLINE]

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
