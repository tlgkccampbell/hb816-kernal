# hb816-kernal

KERNAL and machine-language monitor firmware for the **HB816**, a homebrew
W65C816S microcomputer. This is the machine's first real software: a small
BIOS layer with a stable console ABI, and a monitor that examines and deposits
memory, loads Motorola S-records over the serial console, and runs what it
loaded.

The HB816 itself — the address decoder, the VPU2 video card, and the machine
around them — is specified in the [hb816-decoder](https://github.com/tlgkccampbell/hb816-decoder)
repository, and emulated by [nt65-emu](https://github.com/tlgkccampbell/nt65-emu)
as `Hb816Machine`. This firmware is developed against that emulator; the
emulator repository builds this ROM into its test corpus (never vendoring it)
and boots it in its automated tests.

## Building

```powershell
pwsh build.ps1
```

Requires cc65 V2.19 or later (`ca65`/`ld65` on `PATH` or in `C:\Tools\cc65\bin`).
The output is `out\hb816-kernal.bin` — the 512 KiB ROM image, exactly 524,288
bytes — plus a VICE label file and a link map. Run it in the emulator with:

```powershell
dotnet run --project <nt65-emu>\Norristown.Emulator.Frontend -- --machine hb816 --console out\hb816-kernal.bin
```

## The machine, in brief

- W65C816S at 3.146875 MHz, running in **native mode** from the first
  instruction. 4 MiB of flat work RAM; 512 KiB of ROM whose image offsets
  `$C000–$FFFF` appear in bank 0 at `$00C000–$00FFFF` (the vector window) and
  whose whole image repeats through `$C00000–$FFFFFF`.
- **UART0** (`$008010`, a 16550) is the console. Input flow control is real:
  the KERNAL raises RTS only while it can accept input, and the emulator's
  host-side typing and paste honor it.
- The **VPU2** video card renders an 80×30 text matrix from VRAM
  (`$A00000` window). Its registers are write-only; the KERNAL shadows them.
- **VIA0** (`$008000`, a 6522) carries the keyboard on port A, with a strobe
  into CA1. A PS/2 keyboard reaches it through a decoder board of its own — an
  ATmega328P whose firmware lives in
  [hb816-keyboard](https://github.com/tlgkccampbell/hb816-keyboard).
- Interrupts are gated by the decoder's `ICR` (`$000001`). The KERNAL unmasks
  NMI, which is the vblank level, and IRQ, which both input sources share.

## RAM map

The KERNAL and monitor own `$000000–$000FFF` plus 512 bytes at the top of the
bank-0 stack (`S` starts at `$7FFF`). **User space is `$001000–$007DFF` and
all of `$010000–$3FFFFF`**; the firmware never touches it except when a
monitor command is told to. Direct page `$C0–$FF` is likewise reserved for
user programs.

| Range | Contents |
| --- | --- |
| `$0000xx` DP `$10–$BF` | KERNAL and monitor direct-page state |
| `$000200` | identity block (ROM version, ABI version) |
| `$000210–$00023F` | RAM indirection vectors (`V_CHRIN` … `V_COP`) |
| `$000240–$0002FF` | KERNAL variables (jiffy clock, rings, screen state, VPU shadows) |
| `$000300–$00037F` | **mailboxes** — fixed bytes the firmware reports progress through |
| `$000400` / `$000500` | console input ring (256 B) / UART0 transmit ring (1 KiB) |
| `$000900` | line-editor buffer |
| `$000A00` | monitor state, including the saved user register frame |

The mailbox addresses are a contract with the emulator's test suite
(`Hb816KernalTests` in nt65-emu mirrors them); both sides move together. The
authoritative list is `src/inc/kernal.inc`.

## The KERNAL ABI

A jump table of four-byte `jml` slots at `$00C000` — the addresses never move;
call them with `jsl`. Calling convention: native mode, **A 8-bit, X/Y
16-bit**, `D = $0000`, `DBR = $00` on entry and exit. X/Y are preserved unless
a call returns a value in them; A is never preserved; carry reports success
where a call can fail. Console calls indirect through RAM vectors at
`$000210`, so drivers can be hooked. The keyboard driver joins the input path
below that seam, through `INPUT_PUSH`, so everything above the input ring
stays source-agnostic.

| Slot | Name | Contract |
| --- | --- | --- |
| `$C000` | `KCOLD` | cold start (`jml` target; never returns) |
| `$C004` | `KWARM` | warm start: stack/D/DBR reset, VPU resync, monitor re-entry |
| `$C008` | `CHRIN` | non-blocking read; C=1 char in A, C=0 none. Never echoes |
| `$C00C` | `CHROUT` | A → UART0 transmit ring **and** glass TTY |
| `$C010` | `CHRIN_WAIT` | blocking read; char in A |
| `$C014` | `RDLINE` | line editor into `$000900`; Y = length; owns echo |
| `$C018` | `PUTS` | A = bank, X = address of NUL-terminated string |
| `$C01C` | `IDLE` | one background tick (transmit pump, cursor blink) |
| `$C020` | `CLS` | clear screen, home cursor |
| `$C024` | `PLOT` | C=0 set cursor (Y=row, X=col); C=1 read it back |
| `$C028` | `SETATTR` | A = new text attribute; returns previous |
| `$C02C` | `INPUT_PUSH` | A → console input ring; C=1 accepted |
| `$C030` | `VPU_SYNC` | rewrite the write-only VPU registers from their shadows |
| `$C034` | `NMI_EXIT` | tail for `V_NMI_HOOK` interposers |
| `$C038` | `KBD_TEST` | A = USB HID usage ID; C=1 while that key is held |

## The keyboard

The decoder board does the work. Characters arrive already translated — shift,
control and caps lock applied — and every key, character keys included, is
also reported as a press and a release naming it by USB HID usage ID. The
driver in `src/kbd.s` never sees a scancode and does not decode one.

| Lead byte | Meaning |
| --- | --- |
| `$01`–`$7F` | a character; goes into the console input ring through `INPUT_PUSH` |
| `$80 <id>` | key press; sets that key's bit in `KBDSTATE` |
| `$81 <id>` | key release; clears it |
| `$00` | never sent, so an idle port is unambiguous |

Neither lead byte can occur as a character, so the driver never needs a
timeout to tell one from the other. The authority for the format is
`protocol.h` in the keyboard repository, and the emulator's
`Ps2KeyboardDevice` mirrors it; all three move together.

Characters are pushed into the same ring the serial port fills, so `CHRIN` and
`RDLINE` cannot tell which source typed. **The console ABI did not change.**

### Reading key state

`KBDSTATE` (`$0002E0`, 32 bytes) holds one bit per usage ID, set while the key
is held — all 256, because the modifiers live at `$E0`–`$E7` and asking
whether shift is down is the point. A program reads it directly:

```
    lda KBDSTATE + (KEY_UP >> 3)
    and #(1 << (KEY_UP & 7))
    bne moving_up
```

`KBD_TEST` (`$C038`) does the same for a usage ID in `A`, returning carry set
while the key is held.

### Why it is interrupt-driven

Polling was tried first and was not enough. The decoder paced bytes about 253
microseconds apart, port A latched one at a time, and the monitor spent longer
than that echoing a single character — so typing two keys in a row lost a
byte, and a lost lead byte turned the usage ID behind it into a stray
character in the ring. That was not a corner case; it was the second
keystroke.

So `ICR_IRQEN` is unmasked at the end of cold start and `irq_service` in
`kernal.s` owns both input sources. It asks each in turn rather than working
out which interrupted — each poll is cheap and finds nothing when it was not —
and each empties its own source before returning, so the level-triggered line
is always released.

**The serial receiver moved with it.** `rx_poll` used to be called from
`CHRIN` and `IDLE`; it is now called only from the handler, because a second
caller would race it over the receive FIFO and the RTS line. Flow control is
unchanged and still keys off the FIFO's trigger level.

### The CA2 handshake

`kbd_init` puts CA2 into handshake output mode, which is the other half of the
interface's flow control. Reading `ORA` drives CA2 low, and that is what tells
the keyboard board its byte was taken; the board's next strobe releases the
line high again. **The board holds each byte until it sees that**, so a byte
can no longer be overtaken by the one behind it — the loss that made polling
unworkable is now impossible rather than merely unlikely.

The fixed 253-microsecond pacing is gone with it. A driver that is reading gets
the next byte about twenty microseconds after it takes the last, and only a
host that never answers — one still in reset, or wedged, or running with the
CA1 interrupt masked — falls back to the board's timeout, which is the old gap.

The interrupt stays, for a reason that has changed: it is no longer about
keeping up, it is about being prompt. A polled driver would now pace the whole
interface at whatever rate it got round to looking.

Reading `ORA` at `$00800F` — the mirror without the handshake — deliberately
does neither: it returns the byte without clearing the flag or acknowledging,
which is what a monitor wanting to look without consuming needs.

### A release that never arrives

A lost release would leave its bit set in `KBDSTATE` forever, so the stream is
built to self-heal: a held key repeats under the keyboard's own typematic and
its press event repeats with it. `kbd_apply` takes each press as a keepalive —
it records the key in `KV_KBDHELD` and stamps `KV_KBDSEEN` from `MB_JIFFY` —
and `kbd_expire`, called once a frame from `IDLE`, clears the bit of a key that
has gone `KBD_HOLD_TIMEOUT` frames unannounced. Fifteen frames is comfortably
more than one repeat interval and far less than a person notices.

**Only one key is watched at a time, and that is a real limit rather than an
oversight.** A PS/2 keyboard repeats the key pressed most recently and hands
the typematic on when a later key goes down; it does not give it back when that
later key comes up. So a key still held while another was pressed has stopped
repeating for reasons of its own, and its silence says nothing about whether it
is still down — timing it out would clear a key the user is holding. Its bit
stays set until its release arrives. Modifiers and the three locks are excluded
for the same reason: they never repeat, so they are never dated.

What still sticks, then, is a release lost for a key that was not the last one
pressed. Closing that needs per-key stamps, and `KVAR` has no room for 256 of
them.

## The monitor

Prompt is `* `. Commands are one letter, case-insensitive, with
whitespace-separated hex operands; addresses are up to six hex digits (24-bit).

| Command | Action |
| --- | --- |
| `M [addr [end]]` | dump memory, 16 bytes per line, hex + ASCII; bare `M` continues |
| `E addr bb …` | deposit bytes |
| `F addr end bb` | fill a range |
| `T addr end dst` | transfer (copy) a range, overlap-safe |
| `C addr end dst` | compare two ranges |
| `L` | load Motorola S-records from the console (S1/S2/S3 data, S7/S8/S9 end) |
| `G [addr]` / `J [addr]` | call an address (default: the loaded entry point); `rtl` returns |
| `R` / `R reg val` | display / set the saved register frame |
| `H` | help |
| `X` | warm start |
| `D` | reserved for the disassembler |

`BRK` in user code re-enters the monitor with the registers captured and
displayed. Load big programs at `$010000`+ (S2 records), small ones at
`$001000`+.

A parse error prints `?` and the offending column; a failed S-record prints
`?S` and an error code, then swallows the stream until it goes quiet. `M`
with one operand dumps 128 bytes; a bare `M` continues from the last walk.
The loader accepts S0 (ignored), S1/S2/S3 data, S5 (ignored), and S7/S8/S9
terminators, whose address becomes `G`'s default target.

## Examples

`examples/` holds programs linked to run from work RAM and loaded through the
monitor. `pwsh examples/build.ps1` assembles each `.s` file with the shared
`example.cfg` (flat binary at `$010000`) and wraps it into
`out/examples/<name>.srec` — S2 data records plus an S8 terminator that names
the entry point, so `G` needs no operand. At the monitor: type `L`, paste the
`.srec` file (Ctrl+Shift+V in the Godot host), then `G`.

`colors.s` paints the sixteen RGBI text colours — each row an index, the
colour's name in its own colour, and a swatch of full blocks, with a
background bar underneath — entirely through the KERNAL jump table, and is
the model for what a program the monitor loads looks like: entered by `G` in
the ABI register state, KERNAL calls for all I/O, `rtl` to come home.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/inc/hb816.inc` | hardware equates — the board and nothing else |
| `src/inc/kernal.inc` | RAM map, mailboxes, jump table, ABI — the contract file |
| `src/vectors.s` | jump table, reset, interrupt stubs, vector tables (bank-0 window) |
| `src/kernal.s` `src/console.s` `src/uart.s` `src/kbd.s` `src/vpu.s` | the KERNAL proper |
| `src/monitor.s` `src/srec.s` | the monitor and the S-record loader |
| `src/font.s` + `assets/vga16.bin` | the console font (must stay byte-identical to the emulator's copy) |
| `hb816-kernal.cfg` | ld65 config; memory areas are image offsets, run addresses are CPU addresses |
