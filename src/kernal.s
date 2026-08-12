; kernal.s - cold and warm start, the background tick, and the RAM vectors.
;
; Far code: everything here runs with the program bank in the ROM's long
; window and returns with rtl.

.p816

.include "hb816.inc"
.include "kernal.inc"

.export k_unimpl

.segment "FARCODE"

; Target of every jump-table slot that has no implementation yet: report
; failure through the ABI's carry channel.
k_unimpl:
        sec
        rtl

.segment "FARDATA"

kernal_version:
        .byte "HB816 KERNAL 0.1", 0
