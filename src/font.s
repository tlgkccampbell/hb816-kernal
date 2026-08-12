; font.s - the console font.
;
; The first 4 KiB tileset of the vendored vga16.bin: 256 glyphs of 8x16
; pixels, one byte per row, most significant bit leftmost - already the VPU2's
; packing, so cold start uploads it to video memory with a single block move.
; The copy under assets/ must stay byte-identical to the emulator repository's
; Norristown.Emulator.Machine/Assets/vga16.bin: the emulator's screen tests
; compare rendered glyphs against that image.

.p816

.include "hb816.inc"

.export fontdata

.segment "FONTDATA"

fontdata:
        .incbin "vga16.bin", 0, FONT_SIZE
