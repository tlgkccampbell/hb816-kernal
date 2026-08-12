; vpu.s - the glass TTY over the VPU2's text mode.
;
; The card's registers are write-only, so every one of them is written through
; a helper that stores its RAM shadow first; VPU_SYNC replays the shadows
; after anything that might have scribbled on the register window. Video
; memory is addressed as base + row * $100 + col * 2 - a text row is a page -
; and all of it is reached with long addressing, because the data bank stays
; zero. The card's own cursor is parked at init and stays parked: the software
; cursor saves the cell under it and rewrites the attribute with its nibbles
; swapped.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import fontdata

.export cursor_draw
.export cursor_undraw
.export k_plot
.export k_setattr
.export k_vpu_sync
.export tty_cls
.export tty_putc
.export video_init

.segment "LOWCODE"

; Prints the byte in A at the cursor. CR returns the column, LF advances the
; row (scrolling at the bottom), BS backs up without erasing, FF clears the
; screen; every other control byte is ignored, and printable bytes land as
; glyph plus the current attribute. Preserves X and Y.
tty_putc:
        .a8
        .i16
        phx
        pha
        jsl cursor_undraw
        pla
        cmp #$0D
        beq @cr
        cmp #$0A
        beq @lf
        cmp #$08
        beq @bs
        cmp #$0C
        beq @ff
        cmp #$20
        bcc @out
        pha
        rep #$20
        .a16
        lda KV_CROW
        xba
        sta z:ZCELL
        lda KV_CCOL
        asl a
        ora z:ZCELL
        tax
        sep #$20
        .a8
        pla
        sta f:VRAM,x
        lda KV_CATTR
        sta f:VRAM+1,x
        rep #$20
        .a16
        lda KV_CCOL
        inc a
        sta KV_CCOL
        cmp #TEXT_COLS
        sep #$20
        .a8
        bcc @out
        jsl tty_do_cr
        jsl tty_newline
        bra @out
@cr:
        jsl tty_do_cr
        bra @out
@lf:
        jsl tty_newline
        bra @out
@bs:
        rep #$20
        .a16
        lda KV_CCOL
        beq @bs_home
        dec a
        sta KV_CCOL
@bs_home:
        sep #$20
        .a8
        bra @out
@ff:
        jsl tty_cls
@out:
        jsl cursor_draw
        plx
        rtl

; Returns the cursor to column zero.
tty_do_cr:
        .a8
        .i16
        rep #$20
        .a16
        stz KV_CCOL
        sep #$20
        .a8
        rtl

; Advances the cursor one row, scrolling when it stands on the last.
tty_newline:
        .a8
        .i16
        rep #$20
        .a16
        lda KV_CROW
        inc a
        cmp #TEXT_ROWS
        bcc @store
        sep #$20
        .a8
        jsl tty_scroll
        rtl
@store:
        sta KV_CROW
        sep #$20
        .a8
        rtl

; Draws the cursor: the cell under it is saved and rewritten with the
; foreground and background nibbles of its attribute swapped.
cursor_draw:
        .a8
        .i16
        phx
        lda KV_CURDRAWN
        bne @done
        rep #$20
        .a16
        lda KV_CROW
        xba
        sta z:ZCELL
        lda KV_CCOL
        asl a
        ora z:ZCELL
        tax
        lda f:VRAM,x
        sta KV_CURSAVE
        sep #$20
        .a8
        xba
        pha
        and #$0F
        asl a
        asl a
        asl a
        asl a
        sta z:ZTMP
        pla
        lsr a
        lsr a
        lsr a
        lsr a
        ora z:ZTMP
        xba
        rep #$20
        .a16
        sta f:VRAM,x
        lda #$0001
        sta KV_CURDRAWN
        sep #$20
        .a8
@done:
        plx
        rtl

; Restores the cell the cursor covers. Callers undraw before every matrix
; write or cursor move, so the saved cell always matches the position.
cursor_undraw:
        .a8
        .i16
        phx
        lda KV_CURDRAWN
        beq @done
        rep #$20
        .a16
        lda KV_CROW
        xba
        sta z:ZCELL
        lda KV_CCOL
        asl a
        ora z:ZCELL
        tax
        lda KV_CURSAVE
        sta f:VRAM,x
        stz KV_CURDRAWN
        sep #$20
        .a8
@done:
        plx
        rtl

.segment "FARCODE"

; Scrolls the matrix one row - a single ascending block move of the
; twenty-nine lower rows onto the top - and clears the freed bottom row.
tty_scroll:
        .a8
        .i16
        phx
        phy
        rep #$30
        .a16
        .i16
        lda #TEXT_SCROLL_SIZE - 1
        ldx #TEXT_ROW_STRIDE
        ldy #$0000
        phb
        mvn #$A0, #$A0
        plb
        lda KV_CATTR
        and #$00FF
        xba
        ora #$0020
        ldx #$0000
@fill:
        sta f:VRAM + (TEXT_ROWS - 1) * TEXT_ROW_STRIDE,x
        inx
        inx
        cpx #TEXT_ROW_STRIDE
        bne @fill
        sep #$20
        .a8
        ply
        plx
        rtl

; Clears the whole matrix to spaces in the current attribute and homes the
; cursor. The cell the cursor had saved went with everything else, so the
; drawn flag is simply cleared.
tty_cls:
        .a8
        .i16
        phx
        rep #$20
        .a16
        lda KV_CATTR
        and #$00FF
        xba
        ora #$0020
        ldx #$0000
@fill:
        sta f:VRAM,x
        inx
        inx
        cpx #TEXT_MATRIX_SIZE
        bne @fill
        stz KV_CROW
        stz KV_CCOL
        stz KV_CURDRAWN
        sep #$20
        .a8
        plx
        rtl

; Brings the display up in the one order that never shows garbage: blank
; forced first, the palette's entry zero before anything else - the blanking
; level itself routes through the palette - then the rest of the identity
; palette, the font, the font base, a parked cursor, a cleared matrix, and
; only then the unblanked text mode.
video_init:
        .a8
        .i16
        phx
        phy

        ; The mode shadow starts where the card starts. Cold start zeroed it,
        ; and a zero shadow describes bitmap 1 bpp, not the text mode the card
        ; actually comes up in - so any byte composed from it would be wrong.
        lda #MODE_TEXT
        sta KV_SHMODE

        lda #(MODE_TEXT | MODE_BLANK | (MAP_SLOT << MODE_BASE_SHIFT))
        jsl vpu_set_mode
        lda #$00
        sta f:CLUT
        ldx #$0000
@clut:
        sta f:CLUT,x
        inc a
        inx
        inx
        cpx #$0200
        bne @clut
        rep #$30
        .a16
        .i16
        lda #FONT_SIZE - 1
        ldx #.loword(fontdata)
        ldy #FONT_PAGE * $1000
        phb
        mvn #^fontdata, #$A0
        plb
        sep #$20
        .a8
        lda #$0F
        sta KV_CATTR
        lda #FONT_PAGE
        jsl vpu_set_fontbase

        ; The card's cursor comes up visible at cell (0,0), where it would
        ; blink under the software cursor. Park it.
        lda #CURY_PARK
        sta VPU_CURY

        jsl tty_cls
        lda #(MODE_TEXT | (MAP_SLOT << MODE_BASE_SHIFT))
        jsl vpu_set_mode
        rep #$20
        .a16
        lda #$0001
        sta MB_VIDREADY
        sep #$20
        .a8
        ply
        plx
        rtl

; C=0: move the cursor to row Y, column X. C=1: read it back into Y and X.
k_plot:
        .a8
        .i16
        bcs @read
        jsl cursor_undraw
        rep #$20
        .a16
        tya
        sta KV_CROW
        txa
        sta KV_CCOL
        sep #$20
        .a8
        jsl cursor_draw
        rtl
@read:
        ldy KV_CROW
        ldx KV_CCOL
        rtl

; A = the new text attribute; returns the previous one in A.
k_setattr:
        .a8
        .i16
        sta z:ZTMP
        lda KV_CATTR
        pha
        lda z:ZTMP
        sta KV_CATTR
        pla
        rtl

; Replays every write-only register from its shadow. Warm start and the
; monitor's return path call this, because user code may have written the
; register window. The cursor row has no shadow: the KERNAL wants the card's
; cursor parked at all times, so the park value is simply written again.
k_vpu_sync:
        .a8
        .i16
        lda KV_SHMODE
        sta VPU_MODE
        lda KV_SHFONT
        sta VPU_FONTBASE
        lda #CURY_PARK
        sta VPU_CURY
        rtl

; The register helpers: shadow first, then the register, with plain single
; stores - the card's write strobe tolerates nothing read-modify-write. The
; mode helper is the only way the display base moves, because the base has no
; register of its own: a caller composes the whole byte it wants.
vpu_set_mode:
        .a8
        .i16
        sta KV_SHMODE
        sta VPU_MODE
        rtl

vpu_set_fontbase:
        .a8
        .i16
        sta KV_SHFONT
        sta VPU_FONTBASE
        rtl
