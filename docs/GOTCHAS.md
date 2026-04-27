# GOTCHAS.md — EE354 Bullet Hell Project Traps

Project-specific traps that have already bitten us (or the references we cloned, or known-bad EE354 student attempts). Each entry: **Trap → Fix → SPEC pointer**.

Read this before writing or reviewing any module.

---

## §G1  RGB outside `bright` must be forced to 0

- **Trap:** Driving any non-zero RGB during blanking. The monitor sees junk on the wire during the front porch / sync / back porch and refuses to lock onto the signal — symptom is a black screen with the monitor reporting "no signal" or "out of range," even though sync polarity and timing are correct.
- **Fix:** Final RGB stage is gated on `bright`:
  ```verilog
  always @(posedge pixel_clk) begin
      if (bright_r) begin
          vga_r <= px_rgb[11:8]; vga_g <= px_rgb[7:4]; vga_b <= px_rgb[3:0];
      end else begin
          vga_r <= 4'd0; vga_g <= 4'd0; vga_b <= 4'd0;
      end
  end
  ```
  Use the registered `bright_r` (one cycle delayed) so the gating timing matches the scanout pipeline.
- **Spec:** SPEC.md §1.6 (Pixel format → blanking rule); §4.3 (Scanout).

---

## §G2  BRAM inference pattern (Artix-7 / Vivado)

- **Trap:** Vivado falls back to LUT-RAM (or worse, distributed registers) for a 30,000×4 array if the always-block shape doesn't match its template. Symptom: synth report shows zero BRAMs used, LUT count balloons, place-and-route fails or barely fits. Sometimes the fallback is silent until utilization reports are examined.
- **Fix:** Use exactly this single-clock dual-port template:
  ```verilog
  reg [3:0] mem [0:29999];
  always @(posedge clk) begin
      if (we) mem[wr_addr] <= wr_data;
      rd_data <= mem[rd_addr];
  end
  ```
  Specifically:
  - **Single `always` block** containing both write and read. Splitting into two blocks defeats inference on some Vivado versions.
  - **Registered read address.** The `rd_data <=` line is what tells Vivado this is the read port of a synchronous BRAM. Combinational read forces LUT-RAM.
  - **No `initial` to populate it.** ROM-init bloats bitstream and adds restrictions on which BRAM modes are inferred.
  - **No reset on `mem` or `rd_data`.** A reset on the BRAM contents kills inference.
- **Spec:** SPEC.md §5.3 (framebuffer BRAM inference pattern).

---

## §G3  Vblank cycle budget — naive write spills, on purpose

- **Trap (1):** Believing the naive renderer fits in vblank. It does not. 30,000 + 256 + 256 + 8·256 + 16·256 = 36,864 cycles vs. vblank's 36,000 cycles.
- **Trap (2):** Panicking and pre-optimizing in Week 1 with a half-baked dirty-region scheme that has subtle race conditions. The Touhou reference repo's renderer ships the naive scheme for the same reason.
- **Fix:** Ship the naive scheme. The ~864-cycle overrun bleeds into the first ~1 active scanline of the next frame. For a static or slow-moving scene the data being written equals the data that's about to be read at that location — invisible. Mark a `TODO(Week 2)` comment at the `S_CLEAR` entry of the renderer FSM as the dirty-region swap-in point.
- **Watch:** if Week 2 bullet density grows the per-frame writes much past the budget, the spill becomes visible as a flicker on the top scanlines. That's the trigger for the dirty-region rewrite.
- **Spec:** SPEC.md §4.5 (Vblank timing budget).

---

## §G4  `$readmemh` parsing — one token per array element

- **Trap:** Writing a sprite row as a single 16-character hex string `2222222222222222`. `$readmemh` reads that as **one** 64-bit word and assigns it to `mem[0]`; the rest of the array stays X. On hardware the screen shows scrambled garbage that looks like the file loaded.
- **Fix:** One whitespace-separated hex token per array element. For a `reg [3:0]` array, that's a single hex digit per token. 16 tokens per line is conventional for a 16-pixel sprite row:
  ```
  2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2
  ```
  Same applies to `bbullet_p1.mem`, `bbullet_p2.mem`, `pbullet.mem`, etc.
- **Spec:** SPEC.md §7.3 (`.mem` format).

---

## §G5  Reset polarity — Nexys A7 silk-screen `CPU_RESETN` is active-LOW

- **Trap:** Wiring `CPU_RESETN` directly into a module's `reset` input that the rest of the spec defines as active-high. The board immediately holds the design in reset whenever the user is *not* pressing the button, i.e., the design never runs.
- **Fix:** Project convention is **active-high synchronous reset** named `reset` everywhere. The reset source for `top.v` and `vga_test_top.v` is `BtnC` (pin N17), wired in straight (no inversion). `CPU_RESETN` is **reserved** — if we ever wire it, it must be inverted on entry to the design.
- **Spec:** SPEC.md §1.2 (Reset).

---

## §G6  `display_controller` — confusion with `hvsync_generator`

- **Trap:** Two different VGA timing modules circulate in the EE354 lab corpus. Treating one's port list as the other's silently breaks the build:
  | Module | Source | Outputs use |
  |--------|--------|-------------|
  | `hvsync_generator.v` | older ISE-era class material; lives in `_refs/EE354FinalProj/` | `CounterX`, `CounterY`, `inDisplayArea`, `vga_h_sync`, `vga_v_sync` |
  | `display_controller.v` | A7 supplement (current) — ours | `hCount`, `vCount`, `bright`, `hSync`, `vSync` |
- **Fix:** **We use `display_controller.v` only.** It lives at `ee354_bullet_hell/provided/display_controller.v`. Our one modification is adding an `output clk25_out` port wired to the internal 25 MHz reg. Any reference to `CounterX`/`inDisplayArea` in our codebase is a bug — those names belong to a module we are not using.
- **Spec:** SPEC.md §3 (`display_controller`).

---

## §G7  VGA sync polarity is inverted from VESA (and that's fine)

- **Trap:** Reading the `display_controller` source (`hSync = (hCount < 96) ? 1 : 0`) and "fixing" it to active-low to match the VESA spec. This breaks compatibility with monitors that the class demos sync on.
- **Fix:** Leave it alone. `hSync` is high during the sync pulse, low otherwise — opposite of VESA but accepted by every monitor we've tested and by the VGA-to-HDMI adapter pictured in `EE354L_VGA_to_HDMI_Adapter.pdf`. If a specific monitor refuses to lock, invert in the top module — but only for that monitor.
- **Spec:** SPEC.md §3.3 (Sync polarity).

---

## §G8  12-bit color packing (4:4:4 RGB)

- **Trap:** Treating `vga_r`, `vga_g`, `vga_b` as 8-bit (the most common color depth in non-Nexys VGA contexts) or as bit-fields of a single 24-bit register. The Nexys A7 VGA PMOD only routes **4 bits per channel** through the resistor-ladder DAC; the high 4 bits would be ignored if we sized it that way.
- **Fix:** Each channel is `[3:0]`. Store palette entries as `[11:0] {R,G,B}`. Output stage splits:
  ```verilog
  vga_r <= px_rgb[11:8];
  vga_g <= px_rgb[7:4];
  vga_b <= px_rgb[3:0];
  ```
- **Spec:** SPEC.md §1.5 (Palette), §1.6 (Pixel format).

---

## §G9  Flat buses, not packed arrays

- **Trap:** Writing the bullet inputs as `input [7:0] pb_x [0:7]` (Verilog-2001 unpacked port array — illegal) or `input [7:0][7:0] pb_x` (SystemVerilog packed array — depends on Q1 still being open). Synthesis fails or quietly mis-elaborates.
- **Fix:** Use single flat buses: `input wire [63:0] pb_x_flat`, slot `i` at bits `[i*8 +: 8]`, slot 0 at the LSB. Pack on the writer side using `assign pb_x_flat = {pb_x[7], pb_x[6], ..., pb_x[0]};`. This survives both Verilog-2001 and SystemVerilog cleanly.
- **Spec:** SPEC.md §1.7 (Naming), §1.8 (Packing convention), §4.1 (Renderer interface).

---

## §G10  Palette index 0 is transparent — sprite ROMs only, never framebuffer

- **Trap:** Forgetting the transparency rule and writing `index 0` into the framebuffer during a sprite blit. The sprite gets a black hole in it (palette LUT returns `12'h000` for index 0). Or worse: clobbering the background everywhere a sprite has a transparent pixel.
- **Fix:** Sprite-blit logic gates the write on `if (px_rom != 4'd0)`. Index 0 in the framebuffer should be unreachable in normal operation. The palette LUT entry for index 0 is `12'h000` — so even if it leaked through, the screen would show black, not a glitch.
- **Spec:** SPEC.md §1.5 (Palette index 0); §4.6 (Sprite-blit per-pixel rule).

---

## §G11  ×3 scaling — divide-by-3 vs. mod-3 counter

- **Trap (1):** Trying to use a plain barrel shift to divide by 3. Doesn't work — 3 is not a power of 2.
- **Trap (2):** Worrying that a hardware `/ 3` divider will eat too many LUTs. For a constant divisor on a 10-bit operand, Vivado synthesizes a small lookup, not a real divider. It's fine.
- **Fix:** Either is acceptable, both are spec-equivalent:
  - **Divide form** (current): `wire [7:0] fb_x = (hCount_r - H_FB_START) / 10'd3;`
  - **Counter form**: increment a mod-3 counter every pixel; advance `fb_x` only on rollover. Same trick vertically per-line.
  Pick one and stay consistent within `renderer.v`.
- **Spec:** SPEC.md §1.4 (Scaling).

---

## §G12  Single clock domain in Week 1 — no CDC

- **Trap:** Adding a separate clock divider somewhere downstream and clocking renderer or game logic on a *different* 25 MHz signal than the one driving `hCount`/`vCount`. Even though both are nominally 25 MHz, they're separate edges with no defined phase relationship — a CDC bug waiting to happen.
- **Fix:** Use `display_controller.clk25_out` everywhere. That's the entire reason we patched the module to expose it. Inputs from outside the domain (none in Week 1) get a 1-cycle synchronizer; in Week 2, debounced buttons may need this.
- **Spec:** SPEC.md §1.1 (Clocking).

---

## §G13  Verilog-2001 — no SystemVerilog syntax (until Q1 resolves)

- **Trap:** Sprinkling `logic`, `always_ff`, `always_comb`, packed arrays, `.*` port connections, `enum`, or `typedef` into the RTL. Vivado may compile it (it speaks SV), but if Puvvada answers Q1 with "Verilog-2001 only," every such file needs a rewrite.
- **Fix:** Stay inside the Verilog-2001 subset. Use `wire`/`reg`, `always @(posedge clk)`, `always @*`, named port connections, flat buses, `localparam` for state encodings. CONVENTIONS.md spells out the allowed forms.
- **Spec:** SPEC.md §0 (Q1); CONVENTIONS.md.

---

## §G14  Initial blocks are for ROM init only — never for state

- **Trap:** Initializing a state register in an `initial` block (works in simulation, undefined on hardware; some Xilinx tools accept it but downstream synth flows reject it). Symptom: simulation passes, hardware boots into garbage state.
- **Fix:** Reset every state register in the synchronous reset path of its `always @(posedge clk)` block. `initial` is permitted only inside sprite ROMs for `$readmemh` — and there it's a synthesizable idiom Xilinx specifically supports.
- **Spec:** SPEC.md §1.2 (Reset rule); §1.9 (Synthesis target — ROM inference).

---

## §G15  Game tick must be a single-cycle pulse, not a level

- **Trap:** Driving game logic with a level signal like `tick = (vCount >= 480)`. The signal is high for ~36,000 cycles per frame; any state machine that says "advance on tick" advances 36,000 times instead of once.
- **Fix:** Edge-detect:
  ```verilog
  reg vbl_prev;
  always @(posedge pixel_clk) vbl_prev <= (vCount == 10'd480);
  wire game_tick = (vCount == 10'd480) && !vbl_prev;
  ```
  All game logic consumes `game_tick`. (The renderer's FSM uses the same edge for `S_WAIT_VBL → S_CLEAR`; same idea.)
- **Spec:** SPEC.md §1.1 (Game tick).

---

## §G16  Sprite bounds checking — clip at right and bottom edges

- **Trap:** Computing `tgt_x = sprite_x + spr_col` with both as 8-bit unsigned and letting it overflow silently into the wrap-around slot of the framebuffer. A boss sprite at x=190 writes garbage into rows 0..15 column 0..5.
- **Fix:** Compute targets in 9 bits (`{1'b0, sprite_x} + {1'b0, spr_col}`) and check `tgt_x < 200` and `tgt_y < 150` before asserting `fb_we`. Sprites clipped at the right or bottom edge silently lose those pixels — acceptable.
- **Spec:** SPEC.md §4.6 (Sprite-blit per-pixel rule, step 4).

---

## §G17  Indexed `+:` part-select width must match the index width

- **Trap:** `bb_x_flat[spr_idx*8 +: 8]` where `spr_idx` is 4 bits (0..15) — fine. But `pb_x_flat[spr_idx*8 +: 8]` where `spr_idx` is the same 4-bit reg but the bus is only 64 bits wide → for `spr_idx > 7`, the index runs off the end. Some simulators issue a warning; some don't. Vivado will silently slice X.
- **Fix:** Use `spr_idx[2:0]` for indexing into `pb_*` (8-slot) buses, full `spr_idx` for `bb_*` (16-slot) buses. Add a one-liner comment.
- **Spec:** SPEC.md §4.8 (Renderer implementation hazards).

---

## §G18  Don't infer latches from incomplete `always @*` blocks

- **Trap:** A combinational `always @*` block where some path through the case/if doesn't assign every output — Vivado infers a latch to "remember" the unassigned value. Latches in an FPGA are nearly always wrong (timing analysis breaks, glitches sneak in).
- **Fix:** At the top of every combinational `always @*`, assign every output to a default. Then override in the case/if. Or use a continuous `assign` if the logic permits.
- **Spec:** CONVENTIONS.md (combinational style).

---

## §G19  Reference-repo confusion — `evangabe` and `tic-tac-toe`

- **Trap:** Earlier docs cited an `evangabe/tic-tac-toe` GitHub repo as a reference for the debouncer / button pipeline. That repo does not exist. The only repo under that user named something-final-project is `evangabe/ee301_finalproject`, which is a QAM communications Jupyter notebook — not FPGA, not relevant.
- **Fix:** Use `_refs/Verilog_Pacman/` (Savcab, USC EE354 2022) for the debouncer + button-toggle pattern reference. `_refs/EE354FinalProj/` (YutongGu) has the canonical `ee201_debounce_DPB_SCEN_CCEN_MCEN.v` debouncer.
- **Spec:** none — this is a documentation-hygiene gotcha, no RTL implication.

---

## §G20  `display_on` vs `bright` — same thing, two names

- **Trap:** Some EE354 reference materials and the older `hvsync_generator` use `display_on` or `inDisplayArea`. Our convention is `bright` (matches the class-provided `display_controller.v` we patched). Mixing names while wiring modules causes silent disconnects.
- **Fix:** Always `bright`. If a reference snippet says `display_on`, mentally rename it. The qc-agent should fail any module that introduces `display_on` or `inDisplayArea` as a port name.
- **Spec:** SPEC.md §1.7 (Canonical names).
