# EE354 Final Project — Week 1 Implementation Handoff

**Project:** Bullet Hell — A Touhou-Style Boss Fight on Nexys A7 FPGA
**Student:** Beaux Cable (partner: Leyaa George)
**Course:** EE354 (USC, likely Prof. Gandhi Puvvada)
**Board:** Digilent Nexys A7 (Xilinx Artix-7 XC7A100T)
**Language:** Verilog-2001 (working assumption — see §8 Q1)
**Toolchain:** Xilinx Vivado

> **Revision note (2026-04-16):** Sections 3, 4.3, 5.6, 5.7, 7, and 8 updated
> after reviewing the actual class-provided code and cloned reference repos.
> The big change: the VGA timing module we're using is `display_controller.v`
> (from the `EE354L_vga_demo` A7 supplement), *not* `hvsync_generator.v`.
> Port list and interface in §4.3 corrected accordingly.

---

## 1. Scope of this handoff

This document covers **Week 1 (Apr 6 – Apr 13)** — specifically Beaux's two assigned tasks from the project timeline:

1. **VGA + timing verified on board** — get a VGA signal out of the Nexys A7 using the class-provided `display_controller.v` (from the `EE354L_vga_demo` A7 supplement), confirm timing on a real monitor, and display a test pattern.
2. **Renderer module (VRAM framebuffer)** — a synchronous dual-port BRAM framebuffer at 200×150 that is read by the VGA scanout logic and scaled to 640×480 on output. Pixel format: **4-bit palette index** (16 colors via a small LUT), mapped to 12-bit RGB on output.

Leyaa is handling the bottom two Week 1 items (Player controller + movement, Sprite ROMs / `.mem` files) in parallel.

---

## 2. Full project context (carried over from prior conversations)

### 2.1 Game concept
Single-screen boss fight in the style of a Touhou "danmaku" bullet hell. The player dodges dense patterns of enemy bullets while firing back to deplete the boss's health bar.

- **Two phases.** Phase 1: aimed spread pattern. Phase 2 (triggers at ≤50% boss HP): faster ring-burst pattern. Boss defeated at 0 HP → S_WIN. Player lives reach 0 → S_LOSE.
- **Controls.** Move = U/D/L/R buttons in *toggle* mode (press once to start moving in that direction, press again to stop). Shoot = hold center button, fires upward from player position. Start = any button on title screen.
- **HUD.** Player lives on 5 onboard LEDs. Boss HP (00–99) on the 7-segment display.
- **Invincibility frames.** 2 seconds of i-frames after a player hit.

### 2.2 System clocking
- **100 MHz input** from the onboard oscillator.
- **25 MHz pixel clock** derived via clock divider or MMCM. This drives VGA (640×480 @ 60 Hz standard needs 25.175 MHz; 25.0 MHz is close enough for virtually all monitors and is the standard EE354 approach).
- **60 Hz game tick** generated from the pixel clock by asserting a single-cycle pulse on the rising edge of `vblank` (transition from active video to blanking region). All game logic (player move, bullet advance, collision, boss update) runs on this tick. This keeps the game framerate locked to the display refresh.

### 2.3 Module architecture (all nine modules)
From slide 6 of the proposal:

| Module | Responsibility | Owner |
|---|---|---|
| `top` | Top-level FSM + wiring | Week 3 |
| `display_controller` | Class provided — VGA timing (see §4.3 for exact ports) | Week 1 (Beaux) — **instantiate only, with one-line port-list patch to expose `clk25_out`** |
| `renderer` | VRAM + rdprogress FSM | Week 1 (Beaux) |
| `player_controller` | Position, toggle movement | Week 1 (Leyaa) |
| `player_bullet` | 8-bullet pool (spawn + move) | Week 2 (Beaux) |
| `boss_controller` | Patrol, HP, phase tracking | Week 2 (Beaux) |
| `boss_bullet` | 16-bullet pool, 2 patterns | Week 2 (Leyaa) |
| `collision` | 24 bounding-box comparators | Week 2 (Leyaa) |
| `hud` | LEDs + 7-segment BCD | Week 3 |

### 2.4 Top-level FSM (for context, not yet implemented)
Five states: `S_TITLE → S_PLAYING → {S_WIN | S_LOSE} → S_RESET → S_TITLE`.
- `S_TITLE → S_PLAYING` on any `start_btn` press.
- `S_PLAYING → S_WIN` on `boss_death_flag`.
- `S_PLAYING → S_LOSE` on `player_death_flag`.
- `S_WIN`/`S_LOSE → S_RESET` on `start_btn`; `S_RESET → S_TITLE` unconditionally when `!BDF && !PDF` (clears flags).

Inside `S_PLAYING`, each `game_tick` triggers a parallel update: player_controller and boss_controller run simultaneously (they are independent hardware modules), both feed into collision, and the renderer consumes final positions during vblank.

### 2.5 Resource budget (from slide 8)
Artix-7 XC7A100T has 4,860 Kbit BRAM and 63,400 LUTs.
- Framebuffer (200×150 × 4 bpp = 120 Kbit): ~2.5% of BRAM
- Sprite ROMs (estimate ~20 Kbit total): negligible
- Collision comparators: ~24 bounding-box comparators ≈ well under 1% of LUTs
- Bullet registers: ~448 bits total — negligible

**Key risk noted in the proposal:** the `rdprogress` renderer FSM must write all sprite pixels to VRAM within vblank (~40K pixel clocks at 25 MHz). Mitigation: only write pixels within each sprite's bounding box, not the full 200×150 screen. Background fill + ~40 sprites × 256 px ≈ 40K writes, which fits the budget but is tight. **This affects Week 1 renderer design — see §5.**

---

## 3. Research & references (cloned into `_refs/`)

These repos are structural references only. **Do not copy code from any of them — the goal is to build clean original implementations using these as architectural examples.**

- **`_refs/TouhouChaoYiYe/`** (blowingwind05, USTC, SystemVerilog) — the single most relevant reference. `lab8.srcs/sources_1/new/renderer.sv` implements a 14-stage painter's-algorithm FSM against a dual-port BRAM VRAM. Sprite blitting in vblank; scanout reads freely during active video. Study the stage structure; don't copy.
- **`_refs/EE354FinalProj/`** (YutongGu, USC EE354 2018, Verilog-2001) — contains the canonical class-provided `hvsync_generator.v` (ISE-era), `ee201_debounce_DPB_SCEN_CCEN_MCEN.v`, and a 7-state game `fsm.v`. Useful for the debouncer; our VGA timing uses `display_controller.v` instead (see §4.3).
- **`_refs/Verilog_Pacman/`** (Savcab, USC EE354 2022, SystemVerilog) — button-toggle movement + procedural bounding-box sprite rendering. Good reference for `player_controller` (Leyaa's module) and for the debouncer chain in the top.
- **`_refs/doom-nexys4/`** (ccorduroy, Verilog) — ROM-per-sprite + direct-from-ROM priority scanout (no framebuffer). An alternative architecture; we chose the framebuffer approach instead.

**Reference dropped — flagged in review:**
- ~~evangabe / tic-tac-toe~~: the only repo under that user named something-final-project is `ee301_finalproject`, which is a QAM digital-communications Jupyter notebook project — *not* FPGA. No tic-tac-toe repo exists under the referenced user. Use `_refs/Verilog_Pacman/` for the debouncer + button-to-pixel pipeline instead.

**Universal patterns confirmed across the kept repos:**
- 12-bit color (4-4-4 RGB) is standard on the Nexys A7 VGA PMOD.
- ROM-per-sprite stored in `.mem` files loaded via `$readmemh` (one hex word per whitespace-separated token — see note in §5.8).
- Game logic runs on a vblank-derived game_tick, never on the raw pixel clock.

---

## 4. Task 1 detailed spec — VGA verification

### 4.1 Goal
Produce a working VGA signal out of the Nexys A7 that any standard monitor can display, proving the `hvsync_generator.v` module, pixel clock, and VGA PMOD wiring all work correctly. This is a foundational sanity check — everything downstream depends on it.

### 4.2 Deliverables
1. `vga_test_top.v` — top-level module that:
   - Takes the 100 MHz board clock as input.
   - Instantiates `display_controller.v` (which internally divides to 25 MHz and exposes `clk25_out`).
   - Generates a test pattern (see §4.4).
   - Drives `vgaR[3:0]`, `vgaG[3:0]`, `vgaB[3:0]`, `hSync`, `vSync` on the board's VGA PMOD.
2. `constraints/nexys_a7.xdc` — Xilinx constraint file pinning out the VGA signals, clock, buttons. Derived from the class's `A7_nexys7.xdc` (Sharath Krishnan) in the A7 supplement.
3. `vga_test_tb.v` — simple testbench that simulates long enough to verify at least one full frame of hsync/vsync timing.

### 4.3 Interface to `display_controller.v` (class-provided, A7 supplement)

**This is the class-provided VGA timing module.** Sourced from `EE354L_vga_demo/src/display_controller.v` in the A7 supplement zip. It takes the raw 100 MHz board clock and internally derives a 25 MHz pixel clock; the 10-bit `hCount`/`vCount` counters and the `bright` active-display signal are all driven on that internal 25 MHz domain.

**Original port list (from the A7 supplement, verbatim):**
```verilog
module display_controller(
    input clk,                    // 100 MHz board clock
    output hSync, vSync,          // VGA sync (see timing note below)
    output reg bright,            // 1 during active 640x480 region
    output reg [9:0] hCount,      // 0..799 (full line including blanking)
    output reg [9:0] vCount       // 0..524 (full frame including blanking)
);
```

**Our one-line modification** (in `ee354_bullet_hell/provided/display_controller.v`): we added `output clk25_out` so that the renderer's BRAM can be clocked off the exact same 25 MHz edge that generates `hCount`/`vCount`, avoiding a gratuitous clock-domain crossing. This is the minimum viable change — no counter, sync, or bright logic is touched.

**Instantiation template:**
```verilog
display_controller u_dc (
    .clk       (ClkPort),   // 100 MHz
    .hSync     (hSync),
    .vSync     (vSync),
    .bright    (bright),
    .hCount    (hCount),
    .vCount    (vCount),
    .clk25_out (pixel_clk)  // feed into renderer / BRAM
);
```

**Active region:** `bright == 1` when `hCount > 143 && hCount < 784 && vCount > 34 && vCount < 516`. So active 640×480 spans `hCount ∈ [144, 783]`, `vCount ∈ [35, 515]`. Outside active, RGB must be 0.

**Sync-timing note:** `hSync = (hCount < 96) ? 1 : 0` and `vSync = (vCount < 2) ? 1 : 0`. This is *inverted* from the VESA spec (which has active-low sync pulses). Most LCDs and VGA-to-HDMI adapters tolerate either polarity; the class demos on the A7 supplement are known to sync on real hardware. If a specific monitor refuses to lock, invert these outputs in the top module.

### 4.4 Test pattern requirements
A static test pattern is fine, but a small moving element makes it much easier to confirm the clock is actually running and not frozen. Recommendation:
- **Background:** 8 vertical color bars (black, blue, green, cyan, red, magenta, yellow, white) — industry-standard SMPTE-style bars confirm all three color channels work.
- **Moving box:** a 20×20 white square that bounces around the screen, advancing its position once per vblank. Confirms the game_tick mechanism works end-to-end.
- When `display_on` is low (in blanking regions), RGB must be forced to 0, or the monitor may refuse to sync.

### 4.5 Verification steps (on the physical board)
1. Synthesize and generate bitstream in Vivado.
2. Program the Nexys A7 via USB.
3. Connect VGA PMOD to a monitor via VGA cable.
4. Confirm: color bars visible, moving square traverses screen, monitor reports 640×480 @ 60 Hz.
5. Test the reset button (usually `BTNC` or a designated reset button) clears the square position.

---

## 5. Task 2 detailed spec — Renderer module

### 5.1 Goal
A `renderer` module that owns the framebuffer BRAM, exposes a simple sprite-drawing interface to the rest of the design, and outputs the correct pixel color for each (hpos, vpos) during active video. This is the single most complex module in the project and must be correct before any bullets/player/boss can be visualized.

### 5.2 Architecture — dual-port BRAM framebuffer

```
                     ┌───────────────────────────────┐
                     │  FRAMEBUFFER BRAM 200×150×4b  │
                     │        (dual-port)            │
                     └───────────────────────────────┘
                        ▲ Port A              │ Port B
                        │ write (rdprogress)  │ read (scanout)
                        │ during vblank       │ during active video
                        │                     ▼
           ┌────────────────────┐      ┌────────────────────┐
           │ rdprogress FSM     │      │ scanout logic      │
           │ - iterate sprites  │      │ - (hpos,vpos)/SCALE│
           │ - read sprite ROMs │      │ - lookup palette   │
           │ - write to FB      │      │ - drive 12b RGB    │
           └────────────────────┘      └────────────────────┘
                    ▲                           ▲
                    │                           │
             sprite list in               VGA hpos/vpos
             (x,y,sprite_id)
```

### 5.3 Pixel format decision: 4-bit palette index
**Rationale for 4-bit over 1-bit or 12-bit direct:**
- **1-bit** is too limiting — can't distinguish player bullets (usually white/cyan) from boss bullets (red/magenta) in Touhou-style games, which is critical for gameplay readability.
- **12-bit direct** means 200×150×12 = 360 Kbit FB, 3× the cost, and requires sprite ROMs to also store 12-bit pixels — bloats sprite storage.
- **4-bit palette** gives 16 colors (plenty: black BG, white player, red boss, 4 bullet colors, 4 HUD colors, spare), keeps FB at 120 Kbit, sprite ROMs store 4-bit indices, and a tiny 16-entry × 12-bit palette LUT on the scanout side translates to final RGB.

### 5.4 Suggested 16-color palette (all values are 4-4-4 RGB hex)
| Index | Name | 12b hex | Purpose |
|---|---|---|---|
| 0 | Transparent/BG | 000 | Sprites use 0 for transparent pixels |
| 1 | Background | 112 | Dark blue stage backdrop |
| 2 | White | FFF | Player sprite |
| 3 | Red | F00 | Boss body |
| 4 | Dark red | 800 | Boss shadow/detail |
| 5 | Pink | F8C | Boss detail |
| 6 | Cyan | 0FF | Player bullets |
| 7 | Yellow | FF0 | Boss bullets phase 1 |
| 8 | Magenta | F0F | Boss bullets phase 2 |
| 9 | Orange | F80 | Boss bullets alt / explosion |
| 10 | Green | 0F0 | Powerups / reserved |
| 11 | Dark gray | 333 | HUD borders |
| 12 | Light gray | AAA | HUD text |
| 13–15 | Reserved | — | Future / polish |

Stored as a combinational case statement or a 16×12 ROM. Palette index 0 should be special-cased in sprite-write logic as transparent (skip write).

### 5.5 Scanout logic (Port B, during active video)
```
logical_x = hpos / scale_x   // scale_x such that 200*scale_x ≥ 640
logical_y = vpos / scale_y   // scale_y such that 150*scale_y ≥ 480
```
Simplest workable integer scale: **×3 horizontal, ×3 vertical** → 600×450 active region, centered in 640×480 with a 20-pixel horizontal and 15-pixel vertical border (fill with palette index 1 = background).

Alternative: **×4 vertical / ×3 horizontal** to fill more of the screen — but this is non-uniform and distorts sprites. Recommend ×3/×3 with border for cleanliness.

Divide-by-3 is not a cheap hardware op. Implement with counters: increment a mod-3 counter each pixel, and only increment the framebuffer address when the counter rolls over. Same trick vertically at the end of each line.

### 5.6 rdprogress FSM (Port A, write side)
Painter's-algorithm sprite blitter. States in the current implementation (`src/renderer.v`):

```
S_WAIT_VBL:   wait for vCount to cross 480 (start of vertical blanking)
S_CLEAR:      fill entire FB with palette index 1 (background)
              — iterates 200×150 = 30K writes
S_DRAW_PL:    16×16 player sprite, skip palette index 0 (transparent)
S_DRAW_BOSS:  16×16 boss sprite
S_DRAW_PB:    8 player bullets × 16×16, gated by pb_active bitmask
S_DRAW_BB:    16 boss bullets × 16×16, gated by bb_active, sprite picked from
              phase-1 / phase-2 ROM based on bb_pattern bit 0
S_DONE:       single-cycle; return to S_WAIT_VBL
```

**Timing budget (critical, from slide 8):** vblank on 640×480 @ 60 Hz is 45 lines × 800 pixel clocks = 36,000 pixel clocks at 25 MHz (1.44 ms).

**Week 1 decision: go naive — full clear + sprite draws.** Writes per frame:
30,000 clear + 256 player + 256 boss + 8×256 pb + 16×256 bb ≈ **36,500 cycles**, ~500 over raw vblank. The spill bleeds into the first couple active scanlines of the next frame. For a static Week 1 scene this is invisible (written data equals previously-written data). Matches the Touhou reference's approach; avoids speculative optimization.

**Week 2 mitigation (deferred):** when live bullet counts push total writes past the frame-time budget, replace `S_CLEAR` with dirty-region tracking — track previous-frame sprite bounding boxes and clear only those regions. For ~40 sprites at 16×16, that's 40 × 256 = ~10K clear writes, bringing the total well under 36K. A `TODO` comment in `src/renderer.v` marks the swap-in point.

### 5.7 Interface to the rest of the system (Verilog-2001, flat-bus)
Packed arrays require SystemVerilog; the working assumption (see §8 Q1) is Verilog-2001, so bullet lists pack into flat buses. Bullet `i` occupies bits `[i*8 +: 8]` of the `_x_flat`/`_y_flat` buses and `[i*2 +: 2]` of `bb_pattern_flat`. Slot 0 is the LSB.

```verilog
module renderer (
    input  wire         pixel_clk,       // 25 MHz (from display_controller.clk25_out)
    input  wire         reset,
    // from display_controller
    input  wire         bright,
    input  wire [9:0]   hCount,          // 0..799
    input  wire [9:0]   vCount,          // 0..524
    // from game logic (logical framebuffer coords, 0..199 / 0..149)
    input  wire [7:0]   player_x,
    input  wire [7:0]   player_y,
    input  wire [7:0]   boss_x,
    input  wire [7:0]   boss_y,
    input  wire [63:0]  pb_x_flat,       // 8 player bullets, 8 bits each
    input  wire [63:0]  pb_y_flat,
    input  wire [7:0]   pb_active,       // one bit per bullet
    input  wire [127:0] bb_x_flat,       // 16 boss bullets
    input  wire [127:0] bb_y_flat,
    input  wire [15:0]  bb_active,
    input  wire [31:0]  bb_pattern_flat, // 2 bits per bullet; bit0 picks p1/p2 ROM
    // VGA output
    output reg  [3:0]   vga_r,
    output reg  [3:0]   vga_g,
    output reg  [3:0]   vga_b
);
```

**Game-logic packing convention (for Leyaa / the Week 2 bullet pools):**
```verilog
// Concatenation is MSB-first, so slot 0 = LSB. Example with 8 slots:
assign pb_x_flat = {pb_x[7], pb_x[6], pb_x[5], pb_x[4],
                    pb_x[3], pb_x[2], pb_x[1], pb_x[0]};
```
If the instructor confirms SystemVerilog is permitted (§8 Q1), the packed-array form from the earlier draft is strictly easier to read — revisit then.

### 5.8 Sprite ROM integration (coordination note)
Leyaa is generating the real `.mem` files. Week 1 uses ugly-but-unambiguous stubs in `mem/` (player = solid white square, boss = solid red square, bullets = 4×4 colored dot centered in a 16×16 transparent frame). Her real sprites drop in by overwriting these files with no RTL changes.

**Agreed ROM interface** (combinational read; LUT-inferred because 16×16×4b = 128 B per sprite is small):
```verilog
module sprite_rom_player (
    input  wire [7:0] addr,    // {row[3:0], col[3:0]}
    output wire [3:0] data
);
    reg [3:0] mem [0:255];
    initial $readmemh("player.mem", mem);
    assign data = mem[addr];
endmodule
```
One ROM per sprite type: `sprite_rom_player`, `sprite_rom_boss`, `sprite_rom_pbullet`, `sprite_rom_bbullet_p1`, `sprite_rom_bbullet_p2`. Five ROMs × 16×16×4b = 5 × 1 Kbit = 5 Kbit total.

**`.mem` format gotcha:** `$readmemh` treats each whitespace-separated token as one memory word sized to the array's element width. For a 4-bit array, each token must be a single hex digit — writing `2222222222222222` on one line is read as *one* oversized 64-bit word and the rest of the array stays X. Write one hex digit per entry, separated by spaces or newlines. The stubs in `mem/` already use this form (16 tokens per line = one 16-pixel row).

### 5.9 Deliverables for Task 2
1. `renderer.v` — the full module.
2. `framebuffer.v` or inferred BRAM via Xilinx block memory generator.
3. `palette_lut.v` (or inlined combinational case).
4. Integration with `vga_test_top.v` from Task 1 — replace the test pattern with a call to the renderer, driven by hardcoded sprite positions for Week 1 (actual movement is Leyaa's task). A static scene with player + boss + a few bullets at fixed positions proves the renderer works.
5. `renderer_tb.v` — testbench simulating one full frame and dumping the framebuffer contents.

---

## 6. Integration target at end of Week 1
At the end of Week 1, running the combined bitstream on the Nexys A7 should produce:
- A 640×480 @ 60 Hz VGA output on a real monitor
- A dark blue background
- A white player sprite at the bottom-center of the screen
- A red boss sprite at the top-center
- A few hardcoded colored dots (stand-ins for bullets) placed around the screen
- Everything scaled ×3 from the 200×150 logical framebuffer
- Nothing moving yet (Leyaa's player_controller is still in progress; bullet movement is Week 2)

This proves the "graphics pipeline" end-to-end and unblocks all of Week 2's gameplay work.

---

## 7. File structure (as scaffolded)

```
ee354_bullet_hell/
├── src/
│   ├── vga_test_top.v          # Task 1 top: color bars + bouncing square
│   ├── top.v                   # Task 2 integrated top: display_controller + renderer
│   ├── renderer.v              # 200x150 FB + rdprogress FSM + ×3 scanout
│   ├── framebuffer.v           # 30000×4b dual-port BRAM
│   ├── palette_lut.v           # 16-entry combinational palette
│   ├── sprite_rom_player.v     # 5x LUT-inferred ROMs, $readmemh
│   ├── sprite_rom_boss.v
│   ├── sprite_rom_pbullet.v
│   ├── sprite_rom_bbullet_p1.v
│   └── sprite_rom_bbullet_p2.v
├── provided/
│   └── display_controller.v    # class-provided (A7 supplement) + clk25_out patch
├── constraints/
│   └── nexys_a7.xdc
├── sim/
│   ├── vga_test_tb.v           # one-frame sync/bright sanity check
│   └── renderer_tb.v           # two-frame sim; spot-checks fb[] after frame 1
└── mem/
    ├── player.mem              # 16×16 solid '2' (white) — stub, Leyaa replaces
    ├── boss.mem                # 16×16 solid '3' (red)   — stub
    ├── pbullet.mem             # 4×4 '6' (cyan) dot in 16×16 transparent — stub
    ├── bbullet_p1.mem          # 4×4 '7' (yellow) dot    — stub
    └── bbullet_p2.mem          # 4×4 '8' (magenta) dot   — stub
```

Reference repos live in `_refs/` at project root (TouhouChaoYiYe, EE354FinalProj, Verilog_Pacman, doom-nexys4). Extracted class demos live in `_extracted/`.

---

## 8. Open questions to resolve with instructor / Leyaa
1. **Is SystemVerilog permitted, or strict Verilog-2001?** Working assumption: Verilog-2001, because it's the safer default and every class-provided artifact (display_controller.v, ee201_debounce.v, hvsync_generator.v in the YutongGu repo) is Verilog-2001. The renderer interface uses flat buses (§5.7). If the instructor confirms SV is allowed, swap the bullet flat buses for packed arrays — it's a small interface-only refactor, not a rewrite.
2. ~~Exact file name & interface of the class-provided `hvsync_generator.v`~~ — **moot.** We're using `display_controller.v` from the `EE354L_vga_demo` A7 supplement (see §4.3 for the verified port list). `hvsync_generator.v` exists in `_refs/EE354FinalProj/` as an alternative with a different signal-naming convention (`CounterX`/`CounterY`, `inDisplayArea`, `vga_h_sync`/`vga_v_sync`); no need to switch unless the instructor explicitly mandates it.
3. **Palette agreement with Leyaa** — the 16-color palette in §5.4 is still a proposal. Confirm before she exports real sprite `.mem` files so indices match. The stubs in `mem/` already match the palette.
4. **Reset button** — using `BtnC` (N17) as a synchronous active-high reset in `vga_test_top.v` and `top.v`. `CPU_RESETN` (active-low) is reserved. Revisit once `player_controller` defines its own reset semantics.
