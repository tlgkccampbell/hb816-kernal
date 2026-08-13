; kbd.s - the keyboard driver.
;
; A PS/2 keyboard reaches the machine through a decoder board of its own,
; which presents a byte on VIA0's port A and announces it with a low pulse
; into CA1. The board has already done the work: characters arrive translated,
; with shift, control and caps lock applied, and every key - character keys
; included - is also reported as a press and a release naming it by USB HID
; usage ID. This driver does not decode scancodes and never sees one.
;
; It is a producer into the console input ring, exactly as the serial poll is:
; characters go through INPUT_PUSH and CHRIN cannot tell which source fed it.
; Key events go nowhere near the ring - they maintain the key-state bitmap at
; KBDSTATE, which a program reads directly.
;
; The transport is the CA1 interrupt. Polling was tried and is not enough: the
; decoder paces bytes 253 microseconds apart, port A latches one, and the
; monitor spends longer than that echoing a character - so typing two keys in
; a row loses a byte, and a lost lead byte turns the usage ID behind it into a
; stray character. kbd_poll is still the only place a byte is fetched; the
; interrupt is simply what calls it.

.p816

.include "hb816.inc"
.include "kernal.inc"

.export kbd_init
.export kbd_poll
.export kbd_test

.segment "FARCODE"

; Brings the port up: port A all inputs, the byte latched on CA1's falling
; edge, any edge that arrived before now discarded, and the CA1 interrupt
; enabled. The caller unmasks the decoder's IRQ path afterwards, so no edge
; reaches the processor until the whole console is ready for one.
kbd_init:
        .a8
        .i16
        lda #$00
        sta VIA0 + V_DDRA
        lda #ACR_PALATCH
        sta VIA0 + V_ACR
        lda #$00                ; CA1 active on the falling edge
        sta VIA0 + V_PCR
        lda VIA0 + V_ORA        ; discard a stale byte and its flag
        lda #(IER_SET | IER_CA1)
        sta VIA0 + V_IER
        rep #$20
        .a16
        stz KV_KBDLEAD
        sep #$20
        .a8
        rtl

; Takes every byte the port is holding. The decoder paces bytes about 253
; microseconds apart, so this normally finds one or none; the loop is here
; because a caller that has been away longer may find the next already
; latched.
kbd_poll:
        .a8
        .i16
        phx
        phy
@loop:
        lda VIA0 + V_IFR
        and #IFR_CA1
        beq @done
        lda VIA0 + V_ORA        ; the byte, and the flag goes with it
        jsl kbd_byte
        bra @loop
@done:
        ply
        plx
        rtl

; C=1 while the key whose usage ID is in A is held, C=0 otherwise. X and Y are
; preserved; A is not.
kbd_test:
        .a8
        .i16
        phx
        phy
        jsl kbd_locate          ; X = byte index, A = bit mask
        and KBDSTATE,x
        beq @up
        ply
        plx
        sec
        rtl
@up:
        ply
        plx
        clc
        rtl

; ----------------------------------------------------------------------------
; Internals.
; ----------------------------------------------------------------------------

; One byte of the stream. $80 and $81 introduce a two-byte key event, so the
; lead byte is remembered and the next byte read as its usage ID; anything
; else is a character. $00 is never sent, so it needs no case of its own.
kbd_byte:
        .a8
        .i16
        pha
        rep #$20
        .a16
        inc a:MB_KBDBYTES
        lda KV_KBDLEAD
        bne @usage_id
        sep #$20
        .a8
        pla
        cmp #KBD_PRESS
        beq @lead
        cmp #KBD_RELEASE
        beq @lead
        jsl K_INPUT_PUSH        ; a character; the ring's own overflow rule applies
        rep #$20
        .a16
        inc a:MB_KBDCHARS
        sep #$20
        .a8
        rtl
@lead:
        rep #$20
        .a16
        and #$00FF
        sta KV_KBDLEAD
        sep #$20
        .a8
        rtl
@usage_id:
        sep #$20
        .a8
        pla
        jsl kbd_apply
        rep #$20
        .a16
        stz KV_KBDLEAD
        inc a:MB_KBDKEYS
        sep #$20
        .a8
        rtl

; Sets or clears the bitmap bit for the usage ID in A, according to which lead
; byte is waiting in KV_KBDLEAD.
kbd_apply:
        .a8
        .i16
        phx
        jsl kbd_locate          ; X = byte index, A = bit mask
        ldy KV_KBDLEAD
        cpy #KBD_RELEASE
        beq @clear
        ora KBDSTATE,x
        sta KBDSTATE,x
        plx
        rtl
@clear:
        eor #$FF
        and KBDSTATE,x
        sta KBDSTATE,x
        plx
        rtl

; Usage ID in A becomes X = its byte in the bitmap and A = its bit's mask.
; The index arithmetic is done with a sixteen-bit accumulator so that the
; transfer into a sixteen-bit X carries no stale high byte. The mask is shifted
; rather than looked up because the 65816 has no long-indexed-by-Y mode and X
; is already carrying the byte index by the time the mask is wanted.
kbd_locate:
        .a8
        .i16
        rep #$20
        .a16
        and #$00FF
        pha
        and #$0007
        tay                     ; bit number within the byte
        pla
        lsr a
        lsr a
        lsr a
        tax                     ; byte index, 0 through KBDSTATE_SIZE - 1
        sep #$20
        .a8
        lda #$01
        cpy #$0000
        beq @placed
@shift:
        asl a
        dey
        bne @shift
@placed:
        rtl
