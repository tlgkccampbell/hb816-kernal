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
; decoder paced bytes 253 microseconds apart, port A latched one, and the
; monitor spent longer than that echoing a character - so typing two keys in a
; row lost a byte, and a lost lead byte turned the usage ID behind it into a
; stray character. kbd_poll is still the only place a byte is fetched; the
; interrupt is simply what calls it.
;
; The CA2 handshake below has since made that loss impossible rather than
; merely unlikely, but the interrupt stays: it is what makes the acknowledge
; prompt, and a polled driver would now pace the whole interface at whatever
; rate it got round to looking.

.p816

.include "hb816.inc"
.include "kernal.inc"

.export kbd_init
.export kbd_poll
.export kbd_test
.export kbd_expire

.segment "FARCODE"

; Brings the port up: port A all inputs, the byte latched on CA1's falling
; edge, CA2 driving the acknowledge, any edge that arrived before now
; discarded, and the CA1 interrupt enabled. The caller unmasks the decoder's
; IRQ path afterwards, so no edge reaches the processor until the whole console
; is ready for one.
;
; CA2 in handshake output mode is the other half of the interface's flow
; control: reading ORA drives it low, which is what tells the keyboard board
; the byte was taken, and the board's next strobe releases it high again. The
; board holds each byte until it sees that, so nothing here has to be quick -
; the byte cannot be overtaken by the one behind it.
kbd_init:
        .a8
        .i16
        lda #$00
        sta VIA0 + V_DDRA
        lda #ACR_PALATCH
        sta VIA0 + V_ACR
        lda #(PCR_CA1_FALLING | PCR_CA2_HANDSHAKE)
        sta VIA0 + V_PCR
        lda VIA0 + V_ORA        ; discard a stale byte and its flag
        lda #(IER_SET | IER_CA1)
        sta VIA0 + V_IER
        rep #$20
        .a16
        stz KV_KBDLEAD
        stz KV_KBDHELD
        stz KV_KBDSEEN
        sep #$20
        .a8
        rtl

; Takes every byte the port is holding. Each read of ORA acknowledges its byte
; and lets the next one go, so this normally finds one or none; the loop is
; here because a caller that has been away longer may find the next already
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

; Clears the bit of a key whose repeats have stopped, and is called once per
; frame from the background tick.
;
; The keyboard repeats the key it is holding at about eleven a second and its
; press event repeats with it, so a key whose last announcement is older than
; KBD_HOLD_TIMEOUT is a key whose release was lost: the keyboard would still be
; announcing it otherwise.
;
; Only the one key the typematic holds can be timed out this way. A key held
; while a later one is pressed stops repeating on the keyboard itself and never
; starts again, so its silence says nothing about whether it is still down; its
; bit stays set until its release arrives. Modifiers and the locks are excluded
; for the same reason - they do not repeat at all.
kbd_expire:
        .a8
        .i16
        rep #$20
        .a16
        lda KV_KBDHELD
        beq @done
        lda a:MB_JIFFY
        sec
        sbc KV_KBDSEEN
        cmp #KBD_HOLD_TIMEOUT
        bcc @done
        lda KV_KBDHELD
        sep #$20
        .a8
        jsl kbd_clear
        rep #$20
        .a16
        stz KV_KBDHELD
@done:
        sep #$20
        .a8
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
; byte is waiting in KV_KBDLEAD, and moves the typematic's record with it.
kbd_apply:
        .a8
        .i16
        pha
        phx
        jsl kbd_locate          ; X = byte index, A = bit mask
        ldy KV_KBDLEAD
        cpy #KBD_RELEASE
        beq @clear
        ora KBDSTATE,x
        sta KBDSTATE,x
        plx
        pla
        jml kbd_pressed
@clear:
        eor #$FF
        and KBDSTATE,x
        sta KBDSTATE,x
        plx
        pla
        jml kbd_released

; A press: the key becomes the one the typematic is repeating, and its stamp is
; taken. A repeat of a key already held arrives as another press and refreshes
; that stamp, which is exactly what dates the key.
;
; A key that does not repeat leaves the record alone rather than claiming it -
; a modifier held down announces itself once and never again, and a record
; naming it would be timed out within the quarter second.
kbd_pressed:
        .a8
        .i16
        jsl kbd_repeats
        bcc @done
        rep #$20
        .a16
        and #$00FF
        sta KV_KBDHELD
        lda a:MB_JIFFY
        sta KV_KBDSEEN
        sep #$20
        .a8
@done:
        rtl

; A release gives the typematic up only where the key releasing is the one
; holding it, so a modifier coming up leaves a repeating key repeating.
kbd_released:
        .a8
        .i16
        rep #$20
        .a16
        and #$00FF
        cmp KV_KBDHELD
        bne @done
        stz KV_KBDHELD
@done:
        sep #$20
        .a8
        rtl

; C=1 where the usage ID in A is one the keyboard repeats, which is every key
; but the eight modifiers at $E0-$E7 and the three locks. A is unchanged.
kbd_repeats:
        .a8
        .i16
        cmp #KBD_CAPSLOCK
        beq @no
        cmp #KBD_SCROLLLOCK
        beq @no
        cmp #KBD_NUMLOCK
        beq @no
        cmp #KBD_LCTRL
        bcc @yes                ; below the modifiers
        cmp #KBD_RGUI + 1
        bcc @no                 ; within them
@yes:
        sec
        rtl
@no:
        clc
        rtl

; Clears the bitmap bit for the usage ID in A, whatever lead byte is waiting.
kbd_clear:
        .a8
        .i16
        phx
        jsl kbd_locate          ; X = byte index, A = bit mask
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
