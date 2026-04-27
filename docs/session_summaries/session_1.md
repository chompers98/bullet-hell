# Session 1 — 2026-04-16

## Goal
Onboard into the EE354 final project. Read the handoff doc, clone/review the GitHub references it cites, flag inaccuracies, and scaffold Week 1 code.

## What was reviewed
- `handoff_doc.md` — full spec for Beaux's Week 1 tasks (VGA bring-up + 200×150×4bpp renderer).
- `links.txt`, `EE354L_VGA_A7_supplement.txt` — class-provided context.
- Extracted class demo zips into `_extracted/` (`EE354L_vga_demo`, `vga_moving_block`, A7 supplements). Read `display_controller.v`, `vga_top.v`, `vga_bitchange.v`, `A7_nexys7.xdc`.
- `ee354_optimized_sprite_script.py` — image-to-12-bit-ROM Python generator.

## Reference repos cloned into `_refs/`
| Repo | Language | Role |
|---|---|---|
| `TouhouChaoYiYe` (blowingwind05, USTC) | SystemVerilog | Painter's-algorithm renderer with dual-port BRAM VRAM; closest structural match. |
| `EE354FinalProj` (YutongGu, USC 2018) | Verilog-2001 | Canonical class `hvsync_generator.v` + `ee201_debounce`. |
| `Verilog_Pacman` (Savcab, USC 2022) | SystemVerilog | Button-toggle movement + procedural bounding-box sprite fill. |
| `doom-nexys4` (ccorduroy) | Verilog | ROM-per-sprite priority scanout (no framebuffer). |

## Handoff corrections applied
Five items, all edited into `handoff_doc.md` in place:

1. **Module name fixed.** Handoff assumed `hvsync_generator.v`; the class actually ships `display_controller.v` in the A7 supplement. §4.3 rewritten with verbatim original port list and documented our one-line `clk25_out` output patch.
2. **Reference dropped.** `evangabe/tic-tac-toe` doesn't exist; `evangabe/ee301_finalproject` is a QAM digital-communications Jupyter project, not FPGA. Replaced with pointer to `_refs/Verilog_Pacman/` for the debouncer pattern.
3. **Renderer interface.** §5.7 switched from SV packed arrays to Verilog-2001 flat buses (`pb_x_flat[63:0]`, `bb_x_flat[127:0]`, etc., slot 0 = LSB). Added a packing-convention example for Leyaa.
4. **Vblank strategy.** §5.6 committed to naive full clear + sprite draws for Week 1 (matches Touhou reference, fits the 36K-cycle budget with ~500 cycle overrun that's invisible on a static scene). Dirty-region mitigation noted as Week-2 fallback with a `TODO` comment anchor in `renderer.v`.
5. **`.mem` format note added to §5.8** — `$readmemh` needs whitespace-separated hex tokens, one per array element. Packing `2222222222222222` on one line silently misparses as a single oversized word.

## Code scaffolded — `ee354_bullet_hell/`
```
src/            vga_test_top.v (Task 1)   top.v (Task 2)   renderer.v
                framebuffer.v   palette_lut.v
                sprite_rom_{player,boss,pbullet,bbullet_p1,bbullet_p2}.v
provided/       display_controller.v   (class demo + clk25_out patch)
constraints/    nexys_a7.xdc
sim/            vga_test_tb.v   renderer_tb.v
mem/            player.mem  boss.mem  pbullet.mem  bbullet_p1.mem  bbullet_p2.mem
```

### Stub sprites
- `player.mem`: 16×16 solid palette index 2 (white).
- `boss.mem`: 16×16 solid index 3 (red).
- `pbullet.mem`: 4×4 index-6 dot (cyan) centered in 16×16 transparent (index 0).
- `bbullet_p1.mem`: 4×4 index-7 dot (yellow).
- `bbullet_p2.mem`: 4×4 index-8 dot (magenta).

Ugly but unambiguous on-screen; Leyaa's real sprites replace these by overwriting the `.mem` files, no RTL changes needed.

### Hardcoded Task-2 scene (`top.v`)
Player white square at logical (92, 126); boss red square at (92, 8); one cyan player-bullet dot at (30, 70); one yellow boss-bullet at (150, 40) pattern 0; one magenta boss-bullet at (170, 60) pattern 1.

## Verification
All source compiles clean under Icarus Verilog 13.0 (`iverilog -g2005`). `renderer_tb` simulates 18 ms (one full frame + FSM settling) and the 6 framebuffer spot-checks all pass:

```
fb[26095] (player square) = 2 (white)   ✓
fb[2095]  (boss square)   = 3 (red)     ✓
fb[15437] (p-bullet dot)  = 6 (cyan)    ✓
fb[9557]  (bb-p1 dot)     = 7 (yellow)  ✓
fb[13577] (bb-p2 dot)     = 8 (magenta) ✓
fb[0]     (background)    = 1 (dark blue) ✓
```

Not verified: real-hardware bitstream. Still need Vivado to synth + program the Nexys A7.

## Open questions (kept in handoff §8)
- Q1 SystemVerilog permission — proceeding on Verilog-2001 assumption; refactor to packed arrays if instructor confirms SV is allowed.
- Q3 Palette agreement with Leyaa before she exports real sprites.
- Q4 Reset button choice — currently using `BtnC` (N17) as active-high sync reset.

User is emailing Puvvada for Q1/Q3 in parallel.

## Next steps
1. Open Vivado, create project, add `ee354_bullet_hell/` sources + xdc.
2. Synthesize `vga_test_top` first, generate bitstream, program board. Verify color bars + bouncing square on real monitor.
3. Switch top to `top` (Task 2), re-synthesize, program. Verify hardcoded static scene renders.
4. Integrate with Leyaa's `player_controller.v` and real sprite `.mem` files when she delivers them.
5. Begin Week 2 tasks: `player_bullet` (8-slot pool, Beaux) and `boss_controller` (patrol + HP + phase tracking, Beaux).
