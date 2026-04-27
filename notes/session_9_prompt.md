# Session 9 — Bring-up prep: gameplay TB + Vivado synth

## Where you are

`main` is at commit `dc4acc4` (PR #2 merged). The full game pipeline lives
in `ee354_bullet_hell/src/top.v`, wired through six game modules
(`player_controller`, `player_bullet`, `boss_controller`, `boss_bullet`,
`collision`, `hud`) plus the existing `display_controller` and `renderer`.
A 3-bit `lives` counter decrements on `player_hit_pulse` and saturates at 0.

Sim status:
- Six unit TBs all green under `iverilog -Wall -g2001`.
- `renderer_tb` passes 6/6 — but only validates the **reset state**
  (player + boss render at spawn positions, no spurious bullets, lives LEDs
  lit). No gameplay stimulus runs.

`docs/` was removed in earlier cleanup commits. The canonical references are
now:
- `notes/session_8.md` — what landed in PR #2 + open items
- IMPL DECISIONS blocks at the top of every module under
  `ee354_bullet_hell/src/`
- This prompt

## Goal of this session

Get the design to a point where loading it onto the Nexys A7 is low-risk:
prove the gameplay loop in simulation, then synthesize in Vivado and
triage any warnings.

## Tasks (in order)

### 1. Gameplay stimulus in a new TB (don't extend renderer_tb)

Write `ee354_bullet_hell/sim/top_gameplay_tb.v`. It should drive the full
`top` module, but bypass the slow `ee201_debouncer` so tests run in seconds
not minutes. The default `ee201_debouncer` `N_dc = 25` means a button takes
~1.34 s @ 25 MHz to register a stable level — too slow for sim.

Two viable approaches:
- (a) **Hierarchical force** on the debouncer outputs (`force
  dut.u_db_u.DPB = 1'b1; ...`). Simplest. iverilog supports it.
- (b) **Parameter override** on the debouncer instances at sim time
  (`defparam dut.u_db_u.N_dc = 4;` or use `#(.N_dc(4))` syntax). Cleaner
  but requires touching debouncer instantiation patterns.

Pick (a) for speed unless you find a reason. Cite the choice in the TB
header.

Cover at minimum:
- **Movement:** force `BtnR_db = 1` for ~5 game_ticks, sample `dut.u_pc.player_x`
  — should advance by 5 (1 px/tick per SPEC §10.1). Repeat for L/U/D.
- **Shoot + bullet:** force `BtnC_db = 1` for one game_tick, sample
  `dut.u_pb.pb_active[0]` — should be 1 by the next tick. Watch the bullet
  Y advance toward the boss.
- **Boss hit pipeline:** position player so `pb_x` overlaps the boss after
  bullets travel. Verify `boss_hit_pulse` fires, `boss_hp` decrements,
  `pb_active[i]` clears (despawn via `hit_mask`).
- **Player hit + i-frames:** wait for the boss to fire (~26 game_ticks
  after reset), let one `bb` reach the player, verify `player_hit_pulse`
  fires once, `lives` decrements, and the next `bb` overlap during the next
  120 game_ticks does NOT fire `player_hit_pulse` (i-frame suppression).
- **HUD reflects state:** after lives drops to 4, `Ld` should be `16'h000F`.

Run with `cwd = ee354_bullet_hell/mem` so `$readmemh` resolves the sprite
ROMs.

### 2. Vivado synthesis (you may need to ask the user to run this)

iverilog won't catch BRAM-inference issues, latch warnings on incomplete
combinational paths, or timing closure problems. The user has Vivado
locally — ask them to:

1. Open Vivado, point at `ee354_bullet_hell/`.
2. Add all `.v` files under `provided/` and `src/` as design sources.
3. Add `constraints/nexys_a7.xdc` as a constraint.
4. Add `mem/*.mem` files as design sources (Vivado's `$readmemh` path
   resolution from the project root).
5. Run synthesis. Capture warnings.
6. Run implementation. Capture warnings.
7. Generate bitstream. Capture warnings + utilization report.

Triage findings:
- Critical warnings → fix in RTL.
- BRAM inference: framebuffer must hit BRAM (`u_renderer.u_fb`).
- LUT-RAM: 5× sprite ROMs.
- Latch warnings: zero tolerance; fix.

Document in `notes/session_9.md`.

### 3. Update `notes/session_9.md`

Mirror `session_8.md`'s structure. Lead with what landed, decisions logged,
tests run, open items.

## Constraints to honor

- Verilog-2001 only — no `logic`, no `always_ff`, no packed arrays in port
  lists, no `enum`/`typedef`/`struct`. (See module IMPL DECISIONS blocks
  for the full set; the `\`timescale 1ns / 1ps` header + IMPL DECISIONS
  block is mandatory for new RTL.)
- Active-high synchronous reset, named `reset`, sampled inside
  `always @(posedge pixel_clk)`.
- Single `pixel_clk` (25 MHz) clock domain. Game-tick is a single-cycle
  pulse, generated in `top.v`.
- Flat buses for bullet positions/active masks (slot 0 at LSB):
  `pb_*_flat[63:0]`, `bb_*_flat[127:0]`, `bb_pattern_flat[31:0]`.
- TBs derive expected values from convention/SPEC reasoning, never from
  the RTL under test. Cite the source in each `check(...)` call.
- `iverilog -Wall -g2001` clean per-module + cross-RTL before declaring
  done.
- Don't push directly to `main` — feature branch + PR. Sandbox blocks
  direct main pushes anyway.

## Lab style notes (caught last session)

- 7-seg digit "9" uses the EE354 lab convention "no bottom base" — `Cd`
  is off, lit `a,b,c,f,g`. Already encoded in `hud.v`.
- The lab's `seven_segment_display_revised_tb.v` uses 8-bit
  `Cout = {Cg, Cf, Ce, Cd, Cc, Cb, Ca, Dp}` packing; ours splits as
  `seg [6:0] = {Ca,..,Cg}` + `dp`. Functionally identical.

## Open items NOT in scope this session

- Real sprite art (5× `mem/*.mem` files; Leyaa-owned).
- Game-over flow (lives==0 or boss_death_flag==1 — currently no gating).
- Re-introducing some form of SPEC documentation. The current source of
  truth is module headers + session notes; consider whether that's enough
  for the team to keep moving or whether a leaner SPEC.md belongs at
  `notes/spec.md`.

## How to start this session

1. `git fetch origin && git checkout main && git pull --ff-only`.
2. Read `ee354_bullet_hell/src/top.v` end-to-end. Trace the module graph.
3. Read each module's IMPL DECISIONS block.
4. Branch off main: `git checkout -b session-9-bringup`.
5. Start with Task 1 (gameplay TB). Get one test green before adding more.
