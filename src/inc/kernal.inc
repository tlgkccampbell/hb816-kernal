; kernal.inc - the KERNAL's RAM map, mailboxes, and ABI.
;
; This is the one file user programs include: everything a program needs to
; call the KERNAL or to be found by the emulator's tests is named here. The
; emulator repository mirrors the mailbox addresses in its test suite - a
; change here is a change to that contract and both must move together.
;
; The KERNAL and monitor own $000000-$000FFF and the top of the bank-0 stack.
; User space is $001000-$007DFF and all of $010000-$3FFFFF: the KERNAL never
; touches a byte of either except when a monitor command is told to.

.ifndef KERNAL_INC
KERNAL_INC = 1

; ----------------------------------------------------------------------------
; Direct page (D = $0000 everywhere).
; ----------------------------------------------------------------------------

DP_HW           = $00           ; $00-$0F: the decoder register file, never variables
DP_KERNAL       = $10           ; $10-$3F: KERNAL persistent pointers/counters
DP_SCRATCH      = $40           ; $40-$7F: clobbered by any KERNAL call
DP_MON          = $80           ; $80-$BF: monitor parse state
DP_USER         = $C0           ; $C0-$FF: reserved for user programs, never touched

STACK_TOP       = $7FFF         ; KERNAL + monitor stack budget is 512 bytes

; ----------------------------------------------------------------------------
; Low RAM.
; ----------------------------------------------------------------------------

ID_BASE         = $000200       ; identity block: ROM version word, ABI version byte

; RAM indirection vectors, four bytes each: a 24-bit target plus one pad byte.
; The KERNAL dispatches through these with jml [vector]; cold start installs
; the ROM defaults, and a program hooks one by saving the old entry, storing
; its own long address, and chaining to what it saved.
V_CHRIN         = $000210
V_CHROUT        = $000214
V_CHRIN_WAIT    = $000218
V_RDLINE        = $00021C
V_NMI_HOOK      = $000220
V_IRQ           = $000224
V_BRK           = $000228
V_COP           = $00022C

KVAR            = $000240       ; KERNAL variable block, through $0002FF

; ----------------------------------------------------------------------------
; Mailboxes, $000300-$00037F: fixed bytes the firmware reports through so the
; emulator's tests can watch progress without depending on cycle counts.
; 16- and 32-bit fields are even-aligned.
; ----------------------------------------------------------------------------

MB_BOOTFLAG     = $000300       ; BOOT_READY once cold start has finished
MB_STEP         = $000301       ; highest init step completed, for hang bisection
MB_NMICOUNT     = $000302       ; 16-bit: vblank NMIs serviced
MB_JIFFY        = $000304       ; 32-bit: frames since cold start
MB_RXCOUNT      = $000308       ; 16-bit: bytes received on UART0
MB_TXCOUNT      = $00030A       ; 16-bit: bytes queued to UART0
MB_RXLOST       = $00030C       ; 16-bit: receive overruns the port reported
MB_FLOWHOLDS    = $00030E       ; 16-bit: times RTS was dropped for flow control
MB_VIDREADY     = $000310       ; 16-bit: nonzero once the glass TTY is up
MB_PROMPTS      = $000312       ; 16-bit: times the monitor printed its prompt
MB_CMDS         = $000314       ; 16-bit: commands dispatched
MB_SRECRECS     = $000316       ; 16-bit: S-records accepted
MB_SRECERRS     = $000318       ; 16-bit: S-records rejected
MB_LASTERR      = $00031A       ; 16-bit: last error code
MB_BRKCOUNT     = $00031C       ; 16-bit: BRK/COP re-entries
MB_GACTIVE      = $00031E       ; 16-bit: nonzero while user code is running
MB_CURSOR       = $000320       ; 16-bit: cursor blink state

BOOT_READY      = $A5

; ----------------------------------------------------------------------------
; Rings and buffers.
; ----------------------------------------------------------------------------

INRING          = $000400       ; console input ring
INRING_MASK     = $FF
TXRING          = $000500       ; UART0 transmit ring
TXRING_MASK     = $3FF
LINEBUF         = $000900       ; RDLINE buffer, NUL-terminated
LINEBUF_MAX     = 255
MONSTATE        = $000A00       ; monitor state, including the user register frame

USER_BASE       = $001000       ; start of bank-0 user space

; ----------------------------------------------------------------------------
; The KERNAL jump table, at the start of the bank-0 ROM window. Every entry is
; one four-byte jml, so the addresses below can never move; callers use jsl.
;
; ABI: native mode, A 8-bit, X/Y 16-bit, D = $0000, DBR = $00 on entry and
; exit. X and Y are preserved unless a call returns a value in them; A is an
; argument/result register and never preserved. Where a call reports success,
; carry is the channel.
; ----------------------------------------------------------------------------

K_COLD          = $00C000       ; cold start (jml target; never returns)
K_WARM          = $00C004       ; warm start: stack/D/DBR reset, VPU resync, monitor
K_CHRIN         = $00C008       ; non-blocking read: C=1 char in A, C=0 none
K_CHROUT        = $00C00C       ; A -> serial ring + glass TTY
K_CHRIN_WAIT    = $00C010       ; blocking read: char in A
K_RDLINE        = $00C014       ; line editor into LINEBUF; Y = length
K_PUTS          = $00C018       ; A = bank, X = address of NUL-terminated string
K_IDLE          = $00C01C       ; one background tick: pumps, polls, blink
K_CLS           = $00C020       ; clear the text matrix, home the cursor
K_PLOT          = $00C024       ; C=0 set cursor Y=row X=col; C=1 read it back
K_SETATTR       = $00C028       ; A = new attribute; returns the old in A
K_INPUT_PUSH    = $00C02C       ; A -> input ring; C=1 accepted (the keyboard seam)
K_VPU_SYNC      = $00C030       ; rewrite the VPU registers from their shadows
K_NMI_EXIT      = $00C034       ; tail for V_NMI_HOOK interposers

.endif
