# SPEC.md — EE354 Bullet Hell Canonical Reference

**Status:** Authoritative. Every agent reads this. If a fact a future contributor (human or agent) needs to answer "what should this do?" is not here, it does not exist. If something is unsettled it is marked **⚠ UNDECIDED** with a decision owner.

**Project:** Bullet Hell — Touhou-style boss fight on Nexys A7 FPGA.
**Board:** Digilent Nexys A7 (Xilinx Artix-7 XC7A100T).
**Language:** Verilog-2001 (locked unless §0.Q1 resolves otherwise).
**Toolchain:** Xilinx Vivado.

Section index:

- §0  Open questions (UNDECIDED items, owner-tagged)
- §1  System contracts (clocking, reset, coordinates, palette, pixel format, scaling)
- §2  Module index
- §3  Module: `display_controller` (class-provided, +1-line patch)
- §4  Module: `renderer`
- §5  Module: `framebuffer`
- §6  Module: `palette_lut`
- §7  Modules: `sprite_rom_*` (5 ROMs)
- §8  Module: `vga_test_top` (Task 1 deliverable)
- §9  Module: `top` (Task 2 integrated deliverable)
- §10 Modules planned for Week 2/3 (interfaces only — implementation deferred)
- §11 File layout
- §12 Resource budget

---

## §0  Open questions (UNDECIDED)

These must be resolved before the affected modules ship. Each one carries a decision owner.

| ID  | Question | Owner | Default in force |
|-----|----------|-------|-------------------|
| Q1  | Is SystemVerilog permitted, or strict Verilog-2001? | Puvvada | **Verilog-2001.** Renderer interface uses flat buses (§4.4). Refactor to packed arrays only after explicit confirmation. |
| Q2  | Final 16-color palette — does Leyaa's sprite art match the indices in §1.5? | Leyaa | The palette in §1.5 stands. Stub `.mem` files in `mem/` are already index-aligned. |
| Q3  | Reset button choice for the integrated `top.v`. `BtnC` (active-high sync) is in use; `CPU_RESETN` (active-low) is reserved. | Beaux | `BtnC = active-high sync reset`. Revisit when `player_controller` defines its reset semantics. |
| Q4  | Game-tick precise definition: pulse on the rising edge of `vSync` vs. on `vCount` crossing 480 vs. on the `S_DONE → S_WAIT_VBL` transition of the renderer FSM. All three are within microseconds; pick one canonically. | Beaux | **Resolved (session 4).** Rising edge of `vCount == 10'd480` (start of vertical blanking). Chosen because it's the earliest unambiguous vblank signal and is decoupled from renderer FSM state. See §1.1, GOTCHAS §G15. |
| Q5  | Two-phase boss-pattern toggle threshold — proposal says ≤50% boss HP. Confirm. | Leyaa | `boss_hp ≤ 50` (HP scale 0–99). |
| Q6  | Number of i-frames after a player hit. Proposal says ~2 s = 120 game-ticks. Confirm exact count. | Beaux | 120 ticks. |
| Q7  | Player-bullet Y-advance per tick `N`. | Beaux | **Resolved (session 4).** `N = 2` logical pixels per tick. ~1.05 s full-screen traversal at 60 Hz, matches Touhou reference feel. Tunable post-playtest. See §10.2.5. |
| Q8  | Player i-frame counter location: inside `collision`, `top.v`, or `player_controller`. | Beaux | **Resolved (session 4).** Inside `collision`. Co-located with the `player_hit_pulse` gate that consumes it. See §10.5. |
| Q9  | Collision → player_bullet hit signal: per-slot 8-bit mask vs. scalar `hit_pulse` + slot-index bus. | Leyaa | **Default in force:** per-slot `hit_mask [7:0]` input to `player_bullet`. Matches `collision`'s 8 comparators (8 bullets × boss). If Leyaa ships scalar+index instead, `player_bullet` interface changes by ~3 lines. See §10.2.1, §10.5. |

If an agent encounters a question not listed here, it must add a row marked ⚠ UNDECIDED rather than guess.

---

## §1  System contracts

Apply to **every** module unless that module's section says otherwise.

### §1.1  Clocking

- **Board clock:** 100 MHz on input pin `ClkPort` (driven by the onboard oscillator).
- **Pixel clock:** 25 MHz, derived inside `display_controller` by a `÷2 → ÷2` toggle chain (`pulse` → `clk25`). Exposed via the `clk25_out` output we added (see §3).
- **Single clock domain in Week 1:** every RTL module synchronous to `pixel_clk` (25 MHz). Do not invent additional clocks. The 100 MHz is consumed only inside `display_controller`.
- **Game tick:** single-cycle pulse generated on the rising edge of `(vCount == 10'd480)` — the start of vertical blanking. All game-logic state machines advance on this pulse. Display logic (renderer scanout, sync, blanking) keeps running every pixel-clock cycle.

### §1.2  Reset

- **Polarity:** synchronous active-high. Reset signal name is `reset` in every module port list.
- **Source for `top.v` and `vga_test_top.v`:** `BtnC` (Nexys A7 pin N17), wired straight in. ⚠ UNDECIDED Q3 — locked default but revisitable.
- **`CPU_RESETN`** (the silk-screened reset button on the A7) is **active-low**. We do **not** use it as a primary reset. If we ever wire it in, it must be inverted.
- **What reset must do:** clear every state register to a defined value (listed in each module's section). Combinational outputs return to their reset-time defaults within one cycle.
- **Initial blocks:** allowed only for `$readmemh` ROM init. Never for state. State must be reset by `reset`.

### §1.3  Coordinate systems (three of them — keep them straight)

| Space | Range | Where it appears |
|-------|-------|------------------|
| **Raw VGA** | `hCount ∈ [0, 799]`, `vCount ∈ [0, 524]` | Inside `display_controller` and as inputs to `renderer`. |
| **Active VGA** | `hCount ∈ [144, 783]`, `vCount ∈ [35, 515]` | The 640×480 visible window. `bright == 1` here. Outside this window, RGB **must** be 0. |
| **Logical framebuffer** | `fb_x ∈ [0, 199]`, `fb_y ∈ [0, 149]` | All game-logic positions (`player_x`, `boss_x`, bullet x/y) live here. 8-bit unsigned. |

### §1.4  Coordinate scaling — logical → active-VGA

- Integer **×3 horizontal, ×3 vertical**. 200×3 = 600, 150×3 = 450.
- **Centering inside 640×480:** 20-pixel horizontal margin, 15-pixel vertical margin (border filled with palette index 1 = background).
- **Active framebuffer window in raw VGA coords:** `hCount ∈ [164, 763]` and `vCount ∈ [50, 499]`.
  - `H_FB_START = 164`, `H_FB_END = 764` (exclusive).
  - `V_FB_START = 50`,  `V_FB_END  = 500` (exclusive).
- **Divide-by-3 implementation:** in current scaffolded `renderer.v` it is written as `h_off / 10'd3`, which Vivado synthesizes to a constant divider net. The mod-3 counter trick (increment a counter every pixel, advance fb-address only on rollover) is a permitted alternative if synthesis results disappoint — both are spec-equivalent.

### §1.5  Palette (16-color, 4-bit index → 12-bit RGB 4:4:4)

| Index | Name             | 12-bit hex | Purpose                          |
|-------|------------------|------------|----------------------------------|
| 0     | Transparent      | `000`      | **Skip-write** in sprite blitter; never appears in framebuffer except as background-of-background. |
| 1     | Background       | `112`      | Dark blue stage backdrop. Filled by `S_CLEAR`. Also fills the 20/15 px border. |
| 2     | White            | `FFF`      | Player sprite. |
| 3     | Red              | `F00`      | Boss body. |
| 4     | Dark red         | `800`      | Boss shadow / detail. |
| 5     | Pink             | `F8C`      | Boss detail. |
| 6     | Cyan             | `0FF`      | Player bullets. |
| 7     | Yellow           | `FF0`      | Boss bullets phase 1. |
| 8     | Magenta          | `F0F`      | Boss bullets phase 2. |
| 9     | Orange           | `F80`      | Reserve / explosion. |
| 10    | Green            | `0F0`      | Powerups / reserve. |
| 11    | Dark gray        | `333`      | HUD borders. |
| 12    | Light gray       | `AAA`      | HUD text. |
| 13–15 | Reserved         | `000`      | Future. Must read as `000` from `palette_lut` until assigned. |

Palette is implemented as a combinational case statement in `palette_lut.v` (§6). Index 0 must be **transparent in sprite ROMs** — the renderer's sprite-blit logic checks `if (px != 4'd0)` before writing.

### §1.6  Pixel format

- **Framebuffer:** 200 × 150 × 4 bpp. Address width 15 bits (30,000 entries). Address layout: `addr = fb_y * 200 + fb_x`.
- **Sprite ROMs:** 16 × 16 × 4 bpp. 256 entries per sprite. Address layout: `addr = {row[3:0], col[3:0]}`. Combinational read (LUT-inferred), one cycle of latency is **not** assumed.
- **Output RGB:** 12-bit `{vga_r[3:0], vga_g[3:0], vga_b[3:0]}`. Driven on the VGA PMOD per the `nexys_a7.xdc` constraint file.
- **Blanking output:** when `bright == 0`, every RGB bit must be 0. Monitors will refuse to sync otherwise (see GOTCHAS).

### §1.7  Inter-module signal naming (canonical names — agents must use these exactly)

| Signal | Width | Meaning |
|--------|-------|---------|
| `pixel_clk` | 1 | 25 MHz pixel clock. Drives every synchronous element in Week 1. |
| `reset`     | 1 | Active-high synchronous reset. |
| `bright`    | 1 | 1 inside the 640×480 active region, 0 in blanking. From `display_controller`. |
| `hCount`    | 10 | Raw horizontal counter, 0..799. From `display_controller`. |
| `vCount`    | 10 | Raw vertical counter, 0..524. From `display_controller`. |
| `hSync`     | 1 | VGA hsync (polarity inverted from VESA — see §3). |
| `vSync`     | 1 | VGA vsync (polarity inverted from VESA — see §3). |
| `vga_r/g/b` | 4 each | 4-bit color channels to the VGA PMOD. |
| `player_x`, `player_y` | 8 each | Player position, logical FB coords. |
| `boss_x`, `boss_y`     | 8 each | Boss position, logical FB coords. |
| `pb_x_flat`, `pb_y_flat` | 64 each | 8 player bullets × 8 bits. Slot `i` = bits `[i*8 +: 8]`. Slot 0 = LSB. |
| `pb_active`              | 8 | One bit per player-bullet slot, 1 = drawn. Slot 0 = LSB. |
| `bb_x_flat`, `bb_y_flat` | 128 each | 16 boss bullets × 8 bits. Same packing. |
| `bb_active`              | 16 | One bit per boss-bullet slot. |
| `bb_pattern_flat`        | 32 | 16 boss bullets × 2 bits. Bit 0 of each slot picks phase-1 vs phase-2 sprite ROM. |
| `game_tick`              | 1 | Single-cycle pulse on rising edge of `vCount == 480`. (Driven by `top.v`; not yet exposed as an inter-module port — game logic modules will subscribe in Week 2.) |
| `boss_hp`                | 7 | 0..99 (BCD-friendly). Week 2/3. |
| `player_lives`           | 3 | 0..5 (LED-mappable). Week 2/3. |

These names are **load-bearing**. The qc-agent fails any module that renames them without a SPEC change.

### §1.8  Bullet-array packing convention (Verilog-2001 flat buses)

```verilog
// Concatenation is MSB-first, so slot 0 is at the LSB end. Example for 8 slots:
assign pb_x_flat = {pb_x[7], pb_x[6], pb_x[5], pb_x[4],
                    pb_x[3], pb_x[2], pb_x[1], pb_x[0]};
// Read it back the same way:
wire [7:0] pb0_x = pb_x_flat[7:0];   // slot 0
wire [7:0] pb1_x = pb_x_flat[15:8];  // slot 1
// Or via indexed +: select:
wire [7:0] pbi_x = pb_x_flat[i*8 +: 8];
```

No packed arrays anywhere in port lists. (Internal local packed regs are also forbidden in Verilog-2001.)

### §1.9  Synthesis target

- **Device:** Xilinx Artix-7 XC7A100T-CSG324C.
- **Tool:** Xilinx Vivado 2019.x or later (the EE354 lab default).
- **BRAM inference:** the framebuffer must infer block RAM. Pattern: a `reg [3:0] mem [0:29999]` array with **registered read address** in a single `always @(posedge clk)` block. See GOTCHAS §G2.
- **ROM inference (sprite ROMs):** `reg [3:0] mem [0:255]` initialized via `$readmemh` in an `initial` block, combinational read. Vivado infers a 16-deep distributed ROM in LUTs — not a BRAM, by design.

---

## §2  Module index

| Module | File | Owner | Week |
|--------|------|-------|------|
| `display_controller`    | `provided/display_controller.v` | Class (Beaux's 1-line patch only) | 1 |
| `renderer`              | `src/renderer.v`                | Beaux | 1 |
| `framebuffer`           | `src/framebuffer.v`             | Beaux | 1 |
| `palette_lut`           | `src/palette_lut.v`             | Beaux | 1 |
| `sprite_rom_player`     | `src/sprite_rom_player.v`       | Beaux (stubs) → Leyaa (real art) | 1 |
| `sprite_rom_boss`       | `src/sprite_rom_boss.v`         | "" | 1 |
| `sprite_rom_pbullet`    | `src/sprite_rom_pbullet.v`      | "" | 1 |
| `sprite_rom_bbullet_p1` | `src/sprite_rom_bbullet_p1.v`   | "" | 1 |
| `sprite_rom_bbullet_p2` | `src/sprite_rom_bbullet_p2.v`   | "" | 1 |
| `vga_test_top`          | `src/vga_test_top.v`            | Beaux | 1 |
| `top`                   | `src/top.v`                     | Beaux | 1→3 (grows) |
| `player_controller`     | `src/player_controller.v` (TBD) | Leyaa | 1–2 |
| `player_bullet`         | `src/player_bullet.v` (TBD)     | Beaux | 2 |
| `boss_controller`       | `src/boss_controller.v` (TBD)   | Beaux | 2 |
| `boss_bullet`           | `src/boss_bullet.v` (TBD)       | Leyaa | 2 |
| `collision`             | `src/collision.v` (TBD)         | Leyaa | 2 |
| `hud`                   | `src/hud.v` (TBD)               | TBD | 3 |

---

## §3  Module: `display_controller`

**Status:** class-provided, **do not rewrite**. The only modification we own is a one-line addition of an output port to expose the internal 25 MHz clock.

### §3.1  Interface

```verilog
module display_controller(
    input         clk,         // 100 MHz board clock
    output        hSync,       // VGA hsync (see §3.3 polarity note)
    output        vSync,       // VGA vsync
    output reg    bright,      // 1 inside 640x480 active region
    output reg [9:0] hCount,   // 0..799 (full line)
    output reg [9:0] vCount,   // 0..524 (full frame)
    output        clk25_out    // ← OUR PATCH: 25 MHz internal clock
);
```

### §3.2  Behavior

- Internal `÷2 → ÷2` toggle chain: `pulse` flips every 100 MHz edge; `clk25` flips every rising edge of `pulse`. Net result: `clk25` is 25 MHz with significant non-50% duty (acceptable for downstream logic that uses it as a clock).
- All counters and `bright` are driven on the rising edge of `clk25`.
- `hCount` increments 0→799, then resets and `vCount` increments 0→524.

### §3.3  Sync polarity (gotcha — see GOTCHAS §G7)

```
hSync = (hCount < 96) ? 1 : 0;
vSync = (vCount < 2)  ? 1 : 0;
```
**This is inverted from VESA.** VESA spec is active-low for 640×480@60. Most modern LCD monitors and VGA-to-HDMI adapters tolerate either polarity; the class demos sync on real hardware. If a specific monitor refuses to lock, invert these in the top module.

### §3.4  Active-region predicate

`bright == 1` iff `hCount > 143 && hCount < 784 && vCount > 34 && vCount < 516`.
Equivalently: active VGA spans `hCount ∈ [144, 783]` and `vCount ∈ [35, 515]`.

### §3.5  The patch we own

A single output port `clk25_out` wired to the internal `clk25` reg via `assign clk25_out = clk25;`. Rationale: downstream logic (renderer, scanout) must run on the same clock that drives `hCount`/`vCount` — using a separately re-divided 25 MHz domain would be a gratuitous CDC. The patch adds zero logic and changes no existing behavior.

### §3.6  Reset behavior

`display_controller` has no reset port. It relies on Vivado's power-on init (counters start at 0). Acceptable because the worst case is one garbage frame at startup.

---

## §4  Module: `renderer`

The single most complex module. Owns the framebuffer, the rdprogress FSM that writes sprites in vblank, and the scanout logic that reads the framebuffer during active video and converts indices to RGB.

### §4.1  Interface (Verilog-2001, flat-bus)

```verilog
module renderer (
    input  wire         pixel_clk,         // 25 MHz from display_controller.clk25_out
    input  wire         reset,             // active-high sync

    // From display_controller
    input  wire         bright,
    input  wire [9:0]   hCount,
    input  wire [9:0]   vCount,

    // Sprite positions in logical framebuffer coords (0..199 / 0..149)
    input  wire [7:0]   player_x,
    input  wire [7:0]   player_y,
    input  wire [7:0]   boss_x,
    input  wire [7:0]   boss_y,

    // 8 player bullets — flat buses, slot 0 = LSB
    input  wire [63:0]  pb_x_flat,
    input  wire [63:0]  pb_y_flat,
    input  wire [7:0]   pb_active,

    // 16 boss bullets
    input  wire [127:0] bb_x_flat,
    input  wire [127:0] bb_y_flat,
    input  wire [15:0]  bb_active,
    input  wire [31:0]  bb_pattern_flat,   // 2 bits per bullet; bit0 = phase ROM select

    // VGA output
    output reg  [3:0]   vga_r,
    output reg  [3:0]   vga_g,
    output reg  [3:0]   vga_b
);
```

### §4.2  Architecture (dual-port BRAM, painter's algorithm)

```
                  ┌───────────────────────────┐
                  │ FRAMEBUFFER 200×150 × 4b  │
                  │      dual-port BRAM       │
                  └───────────────────────────┘
                     ▲ Port A          │ Port B
                     │ write           │ read
                     │ (rdprogress     │ (scanout, every
                     │  FSM, vblank)   │  pixel)
              ┌───────────────┐  ┌──────────────────┐
              │ rdprogress    │  │ scanout          │
              │ FSM (writes)  │  │ - (h,v)/3        │
              └───────────────┘  │ - palette LUT    │
                                 │ - drive 12b RGB  │
                                 └──────────────────┘
```

### §4.3  Scanout (read side, every pixel clock)

- Sync `hCount`, `vCount`, `bright` into `pixel_clk` domain (1-cycle register).
- `in_fb = bright_r && (hCount_r ∈ [H_FB_START, H_FB_END))
                    && (vCount_r ∈ [V_FB_START, V_FB_END))` per §1.4.
- `fb_x = (hCount_r - H_FB_START) / 3`, `fb_y = (vCount_r - V_FB_START) / 3`.
- `rd_addr = fb_y * 200 + fb_x`.
- `px_idx = in_fb ? fb_pixel : 4'd1` (border = background).
- During blanking (`bright_r == 0`), output RGB must be `4'd0` on all channels — no exceptions (GOTCHAS §G1).
- BRAM has 1-cycle read latency; the displayed pixel lags `hCount` by one cycle. Invisible at 25 MHz.

### §4.4  rdprogress FSM (write side, painter's algorithm)

States:

```
S_WAIT_VBL    Wait for rising edge of (vCount >= 10'd480).
S_CLEAR       Fill all 30,000 fb entries with palette index 1 (background).
S_DRAW_PL     Iterate 16×16 player sprite at (player_x, player_y). Skip index 0.
S_DRAW_BOSS   Iterate 16×16 boss sprite at (boss_x, boss_y). Skip index 0.
S_DRAW_PB     For each of 8 player-bullet slots where pb_active[i]==1, blit
              16×16 pbullet sprite at (pb_x[i], pb_y[i]). Skip index 0.
S_DRAW_BB     For each of 16 boss-bullet slots where bb_active[i]==1, blit
              16×16 boss-bullet sprite at (bb_x[i], bb_y[i]). Sprite ROM
              selected by bb_pattern[i][0] (0 = phase-1, 1 = phase-2).
S_DONE        Single cycle. Returns to S_WAIT_VBL.
```

The FSM's vblank detect may sample either the **raw** `vCount` input or the 1-cycle-synced `vCount_r` from §4.3 — both are in the same `pixel_clk` domain, so the choice is cosmetic (one cycle phase offset, invisible at 25 MHz). Pick one per module and stick with it; the qc-agent will flag mixing.

### §4.5  Vblank timing budget (load-bearing)

- Vblank duration: 45 lines × 800 pixel-clocks = **36,000 pixel-clocks ≈ 1.44 ms**.
- Naive write count per frame: 30,000 (clear) + 256 (player) + 256 (boss) + 8 × 256 (pb) + 16 × 256 (bb) = **36,864 cycles**, ~864 over budget.
- **Week 1 strategy:** ship the naive full-clear. The ~864-cycle overrun bleeds into the first ~1 active scanline of the next frame. For a Week 1 static or slow-moving scene the data being written equals the data being read, so the overrun is invisible. This is the deliberate decision — see GOTCHAS §G3.
- **Week 2 fallback:** if live bullet counts inflate the overrun to a visible level, replace `S_CLEAR` with **dirty-region tracking**: clear only previous-frame sprite bounding boxes. ~40 sprites × 256 px ≈ 10K writes total, comfortably under 36K. A `TODO` comment at the `S_CLEAR` entry in `renderer.v` marks the swap-in point.

### §4.6  Sprite-blit per-pixel rule

For every sprite pixel:

1. Read the 4-bit index from the sprite ROM at address `{spr_row, spr_col}`.
2. **If index == 0, skip the write** (transparent).
3. Compute target framebuffer address: `(cur_sy + spr_row) * 200 + (cur_sx + spr_col)`.
4. **Bounds check:** if `tgt_x >= 200` or `tgt_y >= 150`, skip the write (sprite clipped at right/bottom edge).
5. Otherwise assert `fb_we`, drive `fb_wr_addr` and `fb_wr_data`.

### §4.7  Reset behavior

- `state ← S_WAIT_VBL`
- `fb_we ← 0`, `clear_addr ← 0`
- `spr_row ← 0`, `spr_col ← 0`, `spr_idx ← 0`
- `cur_sx ← 0`, `cur_sy ← 0`
- `vbl_prev ← 0` (so the first vblank rising edge is detected normally one frame after reset)
- VGA outputs go to 0 on the next clock as `bright_r` is registered.

### §4.8  Implementation hazards (cross-reference GOTCHAS)

- The mux into `fb_wr_data` must remain stable for the cycle `fb_we` is asserted. Don't gate `fb_we` combinationally on something that races with the address.
- `bb_x_cur`/`bb_y_cur` use `spr_idx[3:0]` (4-bit) for indexing into a 128-bit bus — `spr_idx*8 +: 8` is fine because `spr_idx <= 15`. For player bullets use `spr_idx[2:0]` (3-bit) into the 64-bit bus; the linter will warn otherwise.

---

## §5  Module: `framebuffer`

### §5.1  Interface

```verilog
module framebuffer (
    input  wire         clk,
    input  wire         we,
    input  wire [14:0]  wr_addr,
    input  wire [3:0]   wr_data,
    input  wire [14:0]  rd_addr,
    output reg  [3:0]   rd_data
);
```

### §5.2  Behavior

- Single-clock dual-port (1-write, 1-read), 30,000 entries × 4 bits.
- Read: registered (1-cycle latency). `rd_data <= mem[rd_addr]` in `always @(posedge clk)`.
- Write: synchronous. `if (we) mem[wr_addr] <= wr_data;` in the same `always` block.

### §5.3  BRAM inference pattern (load-bearing — see GOTCHAS §G2)

```verilog
reg [3:0] mem [0:29999];
always @(posedge clk) begin
    if (we) mem[wr_addr] <= wr_data;
    rd_data <= mem[rd_addr];
end
```

This exact shape is what Vivado XST/Synth recognizes as a true dual-port BRAM on Artix-7. Do not split into two separate `always` blocks. Do not initialize `mem` (BRAM allows it but it bloats bitstream and is unnecessary — `S_CLEAR` paints the first frame).

### §5.4  Reset behavior

`framebuffer` has no reset port. BRAM contents are not reset (would cost 30K cycles). The `S_CLEAR` state of the renderer's FSM is responsible for initializing visible state on the first frame after power-on — for one frame after boot the screen is undefined, then it stabilizes.

---

## §6  Module: `palette_lut`

### §6.1  Interface

```verilog
module palette_lut (
    input  wire [3:0]   index,
    output reg  [11:0]  rgb
);
```

### §6.2  Behavior

Pure combinational. Implements §1.5's table as a `case (index)` statement inside `always @*`. Reserved indices (13–15) return `12'h000` until assigned.

### §6.3  Reset behavior

None — no state.

---

## §7  Modules: `sprite_rom_*` (5 ROMs)

`sprite_rom_player`, `sprite_rom_boss`, `sprite_rom_pbullet`, `sprite_rom_bbullet_p1`, `sprite_rom_bbullet_p2`.

### §7.1  Interface (identical for all five)

```verilog
module sprite_rom_<name> (
    input  wire [7:0]   addr,   // {row[3:0], col[3:0]}
    output wire [3:0]   data
);
```

### §7.2  Implementation pattern

```verilog
reg [3:0] mem [0:255];
initial $readmemh("<name>.mem", mem);
assign data = mem[addr];
```

Combinational read → LUT-inferred ROM (not BRAM). 16×16×4b = 128 B per sprite, trivial.

### §7.3  `.mem` file format (gotcha — see GOTCHAS §G4)

`$readmemh` consumes whitespace-separated hex tokens, **one per array element**. For a 4-bit-wide array each token is a single hex digit. Writing `2222222222222222` on one line is read as **one** oversized 64-bit word with the rest of the array left X.

Correct format (one row per line, 16 hex digits per row, space-separated):

```
2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
... (16 rows total) ...
```

### §7.4  Stub sprites (Week 1)

| File | Content |
|------|---------|
| `player.mem`        | 16×16 solid index 2 (white). |
| `boss.mem`          | 16×16 solid index 3 (red). |
| `pbullet.mem`       | 16×16, index 0 (transparent) everywhere except a 4×4 index-6 (cyan) block centered. |
| `bbullet_p1.mem`    | Same shape as pbullet, 4×4 index-7 (yellow) center. |
| `bbullet_p2.mem`    | Same shape, 4×4 index-8 (magenta) center. |

Leyaa's real art replaces these by overwriting the `.mem` files; no RTL changes.

### §7.5  Reset behavior

None — no state. ROMs are read-only, init-once.

---

## §8  Module: `vga_test_top` (Task 1 deliverable)

The minimum viable bitstream: VGA timing + a static-with-one-moving-element test pattern. Proves the clock divider, sync, and PMOD wiring all work end-to-end before we trust the renderer.

### §8.1  Interface (board-level top — port names must match `nexys_a7.xdc`)

```verilog
module vga_test_top (
    input  wire        ClkPort,         // 100 MHz
    input  wire        BtnC,            // reset (active-high sync)
    output wire [3:0]  vgaR,
    output wire [3:0]  vgaG,
    output wire [3:0]  vgaB,
    output wire        hSync,
    output wire        vSync
);
```

### §8.2  Behavior

- Instantiate `display_controller` with `.clk(ClkPort)` and capture `bright`, `hCount`, `vCount`, `clk25_out`.
- Generate test pattern (see §8.3).
- Drive `vgaR/G/B` from the pattern when `bright == 1`, else 0.
- Pass `hSync`/`vSync` through.

### §8.3  Test pattern (required content)

- **Background:** 8 vertical SMPTE-style color bars across active 640×480: black, blue, green, cyan, red, magenta, yellow, white. Each bar is 80 pixels wide.
- **Moving element:** 20×20 white square. Position advances 1 pixel/frame in each axis, bouncing off the active-region edges. Uses a vblank-rising-edge tick. Confirms clock is alive and game-tick generator works.

### §8.4  Reset behavior

`BtnC` clears the moving-square position to a known origin (pick `(60, 60)` in active-VGA coords).

---

## §9  Module: `top` (Task 2 integrated deliverable, grows over Weeks 2–3)

### §9.1  Week 1 scope

- Instantiates `display_controller` and `renderer`.
- Drives `renderer`'s position inputs from **hardcoded constants** (Leyaa's `player_controller` lands later).
- Bullet active masks all zero except a small set of hardcoded test bullets.
- Outputs `vgaR/G/B`, `hSync`, `vSync` to the board pins.

### §9.2  Hardcoded test scene (Week 1)

| Sprite           | Logical position | Index |
|------------------|------------------|-------|
| Player (white)   | (92, 126)        | 2     |
| Boss (red)       | (92, 8)          | 3     |
| Player bullet 0 (cyan)  | (30, 70)  | 6     |
| Boss bullet 0 (yellow, p1) | (150, 40) | 7  |
| Boss bullet 1 (magenta, p2) | (170, 60) | 8 |

`pb_active = 8'b0000_0001`; `bb_active = 16'b0000_0000_0000_0011`; `bb_pattern_flat` set so slot 0 is p1, slot 1 is p2.

### §9.3  Reset behavior

`BtnC` resets `renderer.reset`; positions revert to the hardcoded constants (which is identical to the running state — no visible effect in Week 1).

### §9.4  Week 2/3 growth path

`top.v` will eventually instantiate `player_controller`, `player_bullet`, `boss_controller`, `boss_bullet`, `collision`, and `hud`. Their interfaces are sketched in §10. Until those modules exist, `top.v` keeps the hardcoded constants as the position source.

---

## §10  Modules planned for Week 2/3 (interfaces only)

These are sketches sufficient to keep the renderer's input contract stable. Full per-module specs land when each module starts implementation.

### §10.1  `player_controller` (Leyaa, Week 1–2)

- **Inputs:** `pixel_clk`, `reset`, `game_tick`, `BtnU`, `BtnD`, `BtnL`, `BtnR` (debounced), `BtnCenter` (shoot).
- **Outputs:** `player_x [7:0]`, `player_y [7:0]`, `shoot_pulse` (single-cycle).
- **Movement model:** hold-to-move. While a debounced direction button is asserted, the player advances 1 logical pixel per `game_tick` in that direction; releasing the button stops movement immediately. (Revised 2026-04-23 from initial "toggle" semantic per Beaux request after hardware bring-up — felt more natural for a bullet-hell game.)
- **Bounds:** `player_x ∈ [0, 184]`, `player_y ∈ [0, 134]` (so 16×16 sprite stays on-screen).
- **Reset:** position to `(92, 126)`. No toggle state to clear (movement is driven directly by live button levels).

### §10.2  Module: `player_bullet` (Beaux, Week 2)

Pool of 8 concurrent player bullets. Each slot tracks `(x, y, active)`. Spawns on the player's `shoot_pulse`, advances vertically per `game_tick`, despawns on exit or collision hit.

#### §10.2.1  Interface (Verilog-2001, flat-bus)

```verilog
module player_bullet (
    input  wire        pixel_clk,     // 25 MHz from display_controller.clk25_out
    input  wire        reset,         // active-high sync

    input  wire        game_tick,     // single-cycle pulse, rising edge of vCount == 480
    input  wire        shoot_pulse,   // single-cycle, from player_controller (§10.1)
    input  wire [7:0]  player_x,      // logical FB coords
    input  wire [7:0]  player_y,

    input  wire [7:0]  hit_mask,      // from collision; bit i = despawn slot i this tick.
                                      // ⚠ Q9 — Leyaa-owned; default semantics pinned here.

    output wire [63:0] pb_x_flat,     // per §1.7, §1.8 packing
    output wire [63:0] pb_y_flat,
    output wire [7:0]  pb_active
);
```

#### §10.2.2  Behavior (per-tick state transition)

All state changes happen on `game_tick`. Between ticks, outputs are stable and `shoot_pulse` is latched (§10.2.3).

Order of operations inside one tick:

1. **Advance.** For each slot where `pb_active[i] == 1`: `pb_y_next[i] = pb_y[i] − 2`. (N=2 per Q7.)
2. **Despawn.** For each slot:
   - If `pb_y_next[i] >= 8'd150`, clear `pb_active_next[i]`. Catches exit-via-top (8-bit unsigned underflow wraps to ≥240).
   - If `hit_mask[i]`, clear `pb_active_next[i]`.
3. **Spawn.** If `shoot_latch` is set, scan `pb_active_next` from bit 0 upward for the first `i` with `pb_active_next[i] == 0`. If found:
   - `pb_active_next[i] = 1`
   - `pb_x_next[i] = player_x`
   - `pb_y_next[i] = player_y − 8'd16` (underflow at `player_y < 16` handled by step 2 on the next tick)
   - Clear `shoot_latch_next` unconditionally.

#### §10.2.3  `shoot_pulse` latching (every pixel_clk)

`shoot_pulse` arrives on an arbitrary pixel_clk cycle; latched so the spawn decision in §10.2.2 step 3 can sample it on `game_tick`:

```verilog
always @(posedge pixel_clk) begin
    if (reset)
        shoot_latch <= 1'b0;
    else if (game_tick)
        shoot_latch <= 1'b0;
    else if (shoot_pulse)
        shoot_latch <= 1'b1;
end
```

Multiple `shoot_pulse` assertions between ticks collapse to one spawn attempt. `shoot_latch` is cleared on every `game_tick` regardless of whether a spawn succeeded — if the pool was full, the user must re-trigger.

#### §10.2.4  Output packing

```verilog
assign pb_x_flat = {pb_x[7], pb_x[6], pb_x[5], pb_x[4],
                    pb_x[3], pb_x[2], pb_x[1], pb_x[0]};
assign pb_y_flat = {pb_y[7], pb_y[6], pb_y[5], pb_y[4],
                    pb_y[3], pb_y[2], pb_y[1], pb_y[0]};
```

`pb_active` is already a flat 8-bit reg; drive directly. Slot 0 at LSB per §1.8.

#### §10.2.5  Design decisions (with rationale)

- **N = 2 logical pixels per tick.** See Q7. Tunable post-playtest.
- **Spawn offset `bullet_y = player_y − 16`.** Bullet sprite (16×16) sits immediately above player sprite (16×16) — no visual overlap. `player_y < 16` edge case handled by the `pb_y ≥ 150` despawn check.
- **Spawn priority: lowest-index-first.** Simplest priority encoder. Matches §9.2's Week 1 test expectation (`pb_active = 8'b0000_0001`).
- **Overflow: drop silently.** `shoot_latch` clears on every `game_tick` regardless of spawn outcome. Max pool-full wait at N=2 ≈ 63 ticks ≈ 1.05 s.
- **shoot_pulse: latch and spawn on next `game_tick`.** Invariant: all `player_bullet` state changes happen on `game_tick`. Simplifies testbenches and collapses multi-pulse-per-tick to single-spawn deterministically.
- **Bullet x is constant across the bullet's lifetime.** Only `y` advances per tick. No angled shots in Week 2.

#### §10.2.6  Reset behavior

Active-high synchronous reset. On `reset`, assign:

- `pb_x[0..7] <= 8'd0`
- `pb_y[0..7] <= 8'd0`
- `pb_active[0..7] <= 1'b0`
- `shoot_latch <= 1'b0`

One cycle after `reset` deasserts: `pb_active_flat == 8'd0`, all slots idle.

#### §10.2.7  Implementation hazards

- Outputs `pb_x_flat`, `pb_y_flat`, `pb_active` are `wire` driven from registered state via continuous `assign`. No combinational output path.
- Lowest-free-slot priority encoder is combinational. No extra state.
- `hit_mask` sampling: read on `game_tick` edge, applied in step 2. Timing alignment depends on `collision`'s output discipline (Q9).
- Do not split the per-slot arrays into separate modules or generate blocks; 8 slots is small enough that a single `always` block with an 8-entry unrolled case is readable and synthesizes cleanly.

#### §10.2.8  Open items specific to this module

- **Q9** — collision-hit signal semantics. Owner: Leyaa. Default pinned in §10.2.1.

### §10.3  `boss_controller` (Beaux, Week 2)

- Boss patrol along top of screen. HP register 0..99, decrement on hit pulse. Phase = `(hp <= 50)` ? 1 : 0 (⚠ Q5).
- Outputs `boss_x`, `boss_y`, `boss_hp`, `phase`, `boss_death_flag`.

### §10.4  `boss_bullet` (Leyaa, Week 2)

- 16-slot pool, two patterns: phase-1 aimed spread, phase-2 ring burst.
- Outputs `bb_x_flat`, `bb_y_flat`, `bb_active`, `bb_pattern_flat` per §1.7.

### §10.5  `collision` (Leyaa, Week 2)

- 24 bounding-box comparators: 8 player-bullets × boss = 8, 16 boss-bullets × player = 16.
- Outputs:
  - `boss_hit_pulse` — single-cycle, asserted when any player-bullet intersects boss this tick.
  - `player_hit_pulse` — single-cycle, asserted when any boss-bullet intersects player **and i-frames are not active**.
  - `hit_mask [7:0]` — per-slot despawn mask for `player_bullet`. Bit `i` = 1 for one `game_tick` when player-bullet slot `i` collided with boss this tick. **⚠ Q9 default** — Leyaa may choose scalar+index instead; if so, notify Beaux so `player_bullet` §10.2.1 interface updates.
- **I-frame counter lives in `collision`** (Q8). Counter decrements per `game_tick`; while `counter > 0`, `player_hit_pulse` is suppressed. Counter resets to 120 (⚠ Q6 default) on each accepted hit.

### §10.6  `hud` (Week 3)

- Inputs `player_lives [2:0]`, `boss_hp [6:0]`. Outputs LED bus + 7-segment cathode/anode patterns.
- Pure combinational + a 7-segment refresh counter.

---

## §11  File layout

```
ee354_bullet_hell/
├── src/
│   ├── vga_test_top.v          # Task 1 deliverable
│   ├── top.v                   # Task 2 integrated top
│   ├── renderer.v              # FB + rdprogress FSM + scanout
│   ├── framebuffer.v           # 30000×4b dual-port BRAM
│   ├── palette_lut.v           # 16-entry palette
│   ├── sprite_rom_player.v
│   ├── sprite_rom_boss.v
│   ├── sprite_rom_pbullet.v
│   ├── sprite_rom_bbullet_p1.v
│   └── sprite_rom_bbullet_p2.v
├── provided/
│   └── display_controller.v    # class-provided + clk25_out patch
├── constraints/
│   └── nexys_a7.xdc
├── sim/
│   ├── vga_test_tb.v
│   └── renderer_tb.v
└── mem/
    ├── player.mem
    ├── boss.mem
    ├── pbullet.mem
    ├── bbullet_p1.mem
    └── bbullet_p2.mem
```

---

## §12  Resource budget (Artix-7 XC7A100T)

Capacity: 4,860 Kbit BRAM, 63,400 LUTs.

| Resource | Item | Estimate | % of capacity |
|----------|------|----------|---------------|
| BRAM | Framebuffer (200×150×4b) | 120 Kbit | ~2.5% |
| LUT-RAM | 5× sprite ROMs (16×16×4b) | 5 Kbit | negligible |
| LUTs | Collision (24 bbox comparators) | a few hundred | <1% |
| Regs | Bullet pools (8+16 × ~14b) | ~448 b | negligible |
| Clocks | 1 (25 MHz from divider) | 1 of N | trivial |

Comfortable margins everywhere. The only tight budget is the **vblank cycle budget** (§4.5), not the device's resource budget.
