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
- Interrupts are gated by the decoder's `ICR` (`$000001`). The KERNAL unmasks
  only NMI, which is the vblank level; the machine is otherwise polled.

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
`$000210`, so drivers can be hooked (this is where a keyboard driver joins the
input path later — everything above the input ring is source-agnostic).

| Slot | Name | Contract |
| --- | --- | --- |
| `$C000` | `KCOLD` | cold start (`jml` target; never returns) |
| `$C004` | `KWARM` | warm start: stack/D/DBR reset, VPU resync, monitor re-entry |
| `$C008` | `CHRIN` | non-blocking read; C=1 char in A, C=0 none. Never echoes |
| `$C00C` | `CHROUT` | A → UART0 transmit ring **and** glass TTY |
| `$C010` | `CHRIN_WAIT` | blocking read; char in A |
| `$C014` | `RDLINE` | line editor into `$000900`; Y = length; owns echo |
| `$C018` | `PUTS` | A = bank, X = address of NUL-terminated string |
| `$C01C` | `IDLE` | one background tick (transmit pump, receive poll, blink) |
| `$C020` | `CLS` | clear screen, home cursor |
| `$C024` | `PLOT` | C=0 set cursor (Y=row, X=col); C=1 read it back |
| `$C028` | `SETATTR` | A = new text attribute; returns previous |
| `$C02C` | `INPUT_PUSH` | A → console input ring; C=1 accepted |
| `$C030` | `VPU_SYNC` | rewrite the write-only VPU registers from their shadows |
| `$C034` | `NMI_EXIT` | tail for `V_NMI_HOOK` interposers |

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
| `src/kernal.s` `src/console.s` `src/uart.s` `src/vpu.s` | the KERNAL proper |
| `src/monitor.s` `src/srec.s` | the monitor and the S-record loader |
| `src/font.s` + `assets/vga16.bin` | the console font (must stay byte-identical to the emulator's copy) |
| `hb816-kernal.cfg` | ld65 config; memory areas are image offsets, run addresses are CPU addresses |
