; monitor.s - the machine-language monitor.
;
; The loop is banner, prompt, RDLINE, dispatch. The command set arrives with
; the next phase; until then every line comes back to a fresh prompt.

.p816

.include "hb816.inc"
.include "kernal.inc"

.import banner

.export monitor_entry

.segment "FARCODE"

; Entered from cold start (and, through KWARM, from warm start) with the ABI
; register state; never returns.
monitor_entry:
        .a8
        .i16
        lda #^banner
        ldx #.loword(banner)
        jsl K_PUTS
@loop:
        rep #$20
        .a16
        lda MB_PROMPTS
        inc a
        sta MB_PROMPTS
        sep #$20
        .a8
        lda #^mon_prompt
        ldx #.loword(mon_prompt)
        jsl K_PUTS
        jsl K_RDLINE
        bra @loop

.segment "FARDATA"

mon_prompt:
        .byte "* ", 0
