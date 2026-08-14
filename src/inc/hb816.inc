; hb816.inc - hardware truth for the HB816 board, and nothing else.
;
; Every address and bit in this file describes the machine: the decoder's
; register file, the two 16550 serial ports, the VPU2's write-only registers,
; and the video memory windows. RAM layout, mailboxes and the KERNAL ABI live
; in kernal.inc.

.ifndef HB816_INC
HB816_INC = 1

; ----------------------------------------------------------------------------
; Decoder register file, $000000-$00000F.
;
; These addresses are below $100, so a bare "lda DSR" assembles as direct page
; - which reads the right bytes only while D = $0000, and direct page ignores
; DBR. All decoder access goes through these macros, which force absolute
; addressing so the code stays correct in any context.
; ----------------------------------------------------------------------------

DSR             = $000000       ; status, read-only; D7 mirrors the NMI input
ICR             = $000001       ; interrupt control, read/write

DSR_NMISTAT     = $80           ; NMI input (vblank level) asserted

ICR_INTEN       = $01           ; global interrupt enable (set at reset)
ICR_ABORTEN     = $20           ; abort path enable
ICR_IRQEN       = $40           ; IRQ path enable
ICR_NMIEN       = $80           ; NMI path enable

; A -> ICR, with explicit absolute addressing.
.macro  icr_store
        sta a:ICR
.endmacro

; DSR -> A, with explicit absolute addressing.
.macro  dsr_load
        lda a:DSR
.endmacro

; ----------------------------------------------------------------------------
; Serial ports: two 16550s, eight registers each in sixteen-byte windows.
; Both are clocked at phi-2, so a divisor is counted in system clocks:
; 3,146,875 / (16 * divisor) = baud.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; VIA0, sixteen registers at $008000. Port A and CA1 carry the keyboard; port
; B, CA2 and CB1/CB2 are unattached. A byte arrives on port A and the decoder
; board announces it with a low pulse into CA1, which sets the CA1 flag and -
; with latching enabled - captures the byte where the next one cannot disturb
; it. Reading ORA returns the byte and clears the flag.
; ----------------------------------------------------------------------------

VIA0            = $008000       ; the 6522

V_ORB           = 0             ; output register B
V_ORA           = 1             ; output register A; a read clears CA1 and CA2
V_DDRB          = 2             ; port B data direction
V_DDRA          = 3             ; port A data direction
V_T1CL          = 4             ; timer 1 counter low
V_T1CH          = 5             ; timer 1 counter high
V_T1LL          = 6             ; timer 1 latch low
V_T1LH          = 7             ; timer 1 latch high
V_T2CL          = 8             ; timer 2 counter low
V_T2CH          = 9             ; timer 2 counter high
V_SR            = 10            ; shift register
V_ACR           = 11            ; auxiliary control
V_PCR           = 12            ; peripheral control
V_IFR           = 13            ; interrupt flags
V_IER           = 14            ; interrupt enable
V_ORANH         = 15            ; port A without the handshake: reads the same
                                ;   byte and leaves the flags alone

ACR_PALATCH     = $01           ; latch port A on CA1's active edge

; PCR bit 0 chooses CA1's active edge - clear for the falling one - and bits
; 3:1 choose what CA2 does. 100 is handshake output: CA2 goes low when ORA is
; read at the handshaking address and returns high on CA1's next active edge,
; which is the acknowledge the keyboard board waits on.
PCR_CA1_FALLING = $00
PCR_CA2_HANDSHAKE = $08
PCR_CA1POS      = $01           ; CA1 active on the rising edge; clear is falling
IFR_CA1         = $02           ; CA1 transition seen
IER_SET         = $80           ; in a write to IER, set the named bits
IER_CA1         = $02           ; CA1 interrupt enable

; ----------------------------------------------------------------------------
; The keyboard's byte stream, as the decoder board presents it. $01-$7F is a
; character with shift, control and caps lock already applied; $80 and $81
; introduce a two-byte key event whose second byte is a USB HID usage ID; $00
; is never sent. Neither lead byte can occur as a character, so a reader never
; needs a timeout to tell one from the other.
;
; The authority for this is protocol.h in the hb816-keyboard repository, and
; the emulator's Ps2KeyboardDevice mirrors it; all three move together.
; ----------------------------------------------------------------------------

KBD_PRESS       = $80           ; key press; the next byte is the usage ID
KBD_RELEASE     = $81           ; key release; likewise

; The usage IDs of the keys the keyboard's typematic never repeats: the three
; locks, whose repeats would toggle them over and over, and the eight modifiers
; at $E0-$E7, which are held rather than typed.
KBD_CAPSLOCK    = $39
KBD_SCROLLLOCK  = $47
KBD_NUMLOCK     = $53
KBD_LCTRL       = $E0
KBD_RGUI        = $E7

UART0           = $008010       ; the console port
UART1           = $008020       ; the auxiliary port
UART_STRIDE     = UART1 - UART0

U_DATA          = 0             ; RBR (read) / THR (write)
U_IER           = 1             ; interrupt enable
U_DLL           = 0             ; divisor low, behind the divisor latch bit
U_DLM           = 1             ; divisor high, behind the divisor latch bit
U_IIR           = 2             ; interrupt identification (read)
U_FCR           = 2             ; FIFO control (write)
U_LCR           = 3             ; line control
U_MCR           = 4             ; modem control
U_LSR           = 5             ; line status (read)
U_MSR           = 6             ; modem status (read)
U_SCR           = 7             ; scratch

LCR_8N1         = $03           ; eight data bits, no parity, one stop
LCR_DLAB        = $83           ; 8N1 with the divisor latch banked in
FCR_ENABLE      = $87           ; FIFOs on, both emptied, receive trigger at 8
IER_RX          = $01           ; receive interrupt enable (drives the IIR only;
                                ;   the decoder's IRQ path stays masked)
IIR_ID_MASK     = $0E
IIR_RXRDY       = $04           ; receive FIFO at trigger level
MCR_DTR         = $01           ; DTR alone: far end told to wait
MCR_DTR_RTS     = $03           ; DTR and RTS: far end may send
LSR_DR          = $01           ; data ready
LSR_OE          = $02           ; overrun error
LSR_THRE        = $20           ; transmit holding register empty

BAUD_DIVISOR    = 2             ; 3,146,875 / (16 * 2) = 98,340 baud

; ----------------------------------------------------------------------------
; Video: the VPU2's registers and memory windows.
;
; The registers are write-only - a read of the window returns nothing the card
; drives - so every one of them is shadowed in RAM (kernal.inc) and written
; with plain single stores, never a read-modify-write.
; ----------------------------------------------------------------------------

VPUREG          = $00A000
VPU_MODE        = VPUREG + $0   ; mode, display base and cell effect, one byte
; Offsets $1-$4 are reserved and ignore writes. $1 and $2 were CURX and CURY,
; before the hardware cursor was evicted to buy back CPLD capacity; a cursor is
; now software's job, or an expansion card's.
VPU_FONTBASE    = VPUREG + $5   ; glyph table base, 4 KiB granularity
VPU_YCMP        = VPUREG + $6   ; raster compare: scan line 4*YCMP, /IRQ for
                                ;   its duration; YCMP_PARK never matches

; One MODE byte is a whole display description - family, geometry, options,
; cell effect and the display base - and every write of it carries all of them.
; There is no separate base register, so a caller composes the byte it means
; from the shadow rather than updating a field. D0 picks the family, and the
; two readings share only D0 and D4:
;
;   bitmap  D7:D5 BASE  D4 FBLANK  D3 PIXDBL  D2:D1 BPP     D0 = 0
;   text    D7:D6 BASE  D5 HEIGHT  D4 FBLANK  D3:D2 BLINKMODE  D1 DEPTH  D0 = 1
;
; A bit's meaning never crosses families: a bitmap write cannot arm a cell
; effect, and any bitmap write clears BLINKMODE outright.
MODE_TEXT       = $01           ; 80x30 text cells, classic attributes; never
                                ;   write $00 - that is bitmap 1 bpp, not "off"
MODE_BLANK      = $10           ; force blank (composes with the mode bits)
MODE_BASE_SHIFT = 6             ; text base, D7:D6, four 128 KiB slots; a
                                ;   bitmap base is three bits and shifts by 5

; BLINKMODE, D3:D2 in text modes: one effect for the whole screen, applied to
; the cells whose attribute flags them - bit 4 in classic cells, bit 7 in
; palette cells. Any non-zero value costs classic backgrounds their intensity
; bit, screen-wide.
MODE_BLINK_OFF    = $00         ; the flag bit is an ordinary colour bit
MODE_BLINK_HIDE   = $04         ; flagged cells wink out to background, ~0.94 Hz
MODE_BLINK_SHADE  = $08         ; flagged cells dither to a static 50% checkerboard
MODE_BLINK_INVERT = $0C         ; flagged cells invert, ~0.94 Hz

; The card powers up as if MODE $01 had been written - text, every base zero.
; Its raster compare powers up at 0, naming line 0 of every frame; YCMP_PARK
; names a line past the end of the frame, which is how the compare is put away.
YCMP_PARK       = $FF

VRAM            = $A00000       ; flat one-megabyte video memory window
CLUT            = VRAM + $FFE00 ; palette window: entry n is the even byte at 2n

TEXT_COLS       = 80
TEXT_ROWS       = 30
TEXT_ROW_STRIDE = $100          ; a text row is a page; 96 trailing bytes are slack
TEXT_MATRIX_SIZE = TEXT_ROWS * TEXT_ROW_STRIDE          ; $1E00
TEXT_SCROLL_SIZE = (TEXT_ROWS - 1) * TEXT_ROW_STRIDE    ; $1D00

FONT_SIZE       = $1000         ; 256 glyphs x 16 rows

MAP_SLOT        = 0             ; text matrix in display slot 0 (MODE D7:D6)
FONT_PAGE       = 2             ; font at VRAM + $2000 (FONTBASE steps 4 KiB)

.endif
