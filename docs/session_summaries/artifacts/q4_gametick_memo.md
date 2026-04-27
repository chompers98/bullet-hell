# Q4 Decision Memo — Precise definition of `game_tick`

**Session:** 3 (2026-04-16). **Owner:** Beaux. **Status (entering session):** ⚠ UNDECIDED, session-2 default = rising edge of `vCount == 480`.

## 0. Frame-timing facts (ground truth)

Source: `ee354_bullet_hell/provided/display_controller.v:52-77`.

- `vCount` counts 0..524 (525 lines/frame, wraps 524→0).
- `vCount` increments on the pixel-clock edge that wraps `hCount` 799→0, i.e., end-of-line.
- `bright` active for `vCount ∈ [35, 515]` — 481 lines (slight off-by-one vs. the canonical 480 active lines; harmless).
- **True vertical blanking** (the interval where `bright == 0` vertically) is `vCount ∈ [516, 524] ∪ [0, 34]` — 44 lines, starting at `vCount == 516`.
- `vSync = (vCount < 2) ? 1 : 0` — sync pulse occupies `vCount ∈ [0, 1]`, rises at `vCount` wrap 524→0 (mid-vblank).
- **Current renderer FSM** treats `vCount >= 480` as its write-window trigger (`renderer.v:136-137`). `vCount == 480` is still inside the active-display region. Calling it "vblank start" is a mild misnomer that leaked into both `renderer.v:111` and `SPEC.md §1.1`; no bug, just loose vocabulary.
- No `game_tick` signal exists in RTL today (`grep` across `ee354_bullet_hell/`). Q4 is purely a SPEC-level pin; no module currently consumes it, so there are no downstream edits to propagate on whatever we pick.

## 1. Candidate definitions

### C1 — Rising edge of `vSync`

- **Signal-level:** `reg vs_prev; always @(posedge pixel_clk) vs_prev <= vSync; wire game_tick = vSync && !vs_prev;`
- **When it fires:** `vCount` wraps 524 → 0, i.e., mid-true-vblank. ~44 lines × 800 = 35,200 pixel-clocks *after* the renderer's `S_WAIT_VBL → S_CLEAR` transition at `vCount == 480`.
- **Slack for renderer to finish before scanout of next frame:** renderer start unchanged; scanout of next frame begins at `vCount == 35` (≈ 28,000 pixel-clocks after `game_tick` under this definition). Game logic has that many cycles to settle before it matters for scanout — loose in absolute terms, but *the renderer has already been drawing for 36,000+ cycles with stale positions* (see §4).
- **New signals needed from `display_controller`:** none. `vSync` is already exposed.

### C2 — Rising edge of `vCount == 480` (current SPEC default)

- **Signal-level:** `reg vc480_prev; always @(posedge pixel_clk) vc480_prev <= (vCount == 10'd480); wire game_tick = (vCount == 10'd480) && !vc480_prev;`
- **When it fires:** end of the scanline where `vCount` transitions 479 → 480 — 35 lines before *true* vblank starts, simultaneous with renderer `vbl_rise`.
- **Slack for renderer to finish before scanout of next frame:** 36,000 pixel-clocks (the entire write window). Identical to the other two candidates — the renderer's write window is bounded by its own start edge, not by `game_tick`.
- **New signals needed from `display_controller`:** none. `vCount` already exposed.

### C3 — Renderer FSM `S_DONE → S_WAIT_VBL` transition

- **Signal-level:** `wire game_tick = (state == S_DONE);` inside renderer (one-cycle natural pulse), plus a new output port on `renderer.v`.
- **When it fires:** whenever the FSM finishes drawing. For the Week-1 naive strategy (36,864 cycles starting at `vCount == 480`): ≈ `vCount == 1` of the next frame (864 cycles into the next frame after wrap). **Variable** per frame once bullet counts aren't constant — fewer active bullets → earlier tick; dirty-region optimization will shift it significantly.
- **Slack for renderer to finish before scanout of next frame:** irrelevant — this definition fires *after* the renderer is already done.
- **New signals needed:** **yes — new output port** on `renderer.v` (e.g., `output wire frame_done_pulse`). Small cost, but a real cost: it couples the game-logic clock to a renderer-internal state, violating the current layering where game logic doesn't know the renderer exists.

## 2. Interaction with the existing renderer

The renderer never consumes `game_tick` — it derives its own write-window edge from `vCount` (`renderer.v:136-137`). So none of the three candidates change a single line of `renderer.v`.

| Candidate | Change to `renderer.v` | Change to `vga_test_top.v` |
|-----------|------------------------|----------------------------|
| C1 | none | none (test bouncer already uses `vbl_rise`, doesn't consume `game_tick`) |
| C2 | none; `game_tick` is defined in `top.v`, using the same edge the renderer already derives internally — no new wiring inside the renderer | none |
| C3 | **structural:** add `output wire frame_done_pulse` fed from `(state == S_DONE)`. ~2 lines (`renderer.v:296-298` area). No behavior change, but a new port ripples to `top.v` port map and every renderer testbench. | none |

C2 is the cleanest. C1 is also free. C3 costs one new port.

## 3. Interaction with Week 2 modules that consume `game_tick`

Per SPEC §10.1–§10.5: `player_controller`, `player_bullet`, `boss_controller`, `boss_bullet`, `collision` all advance on `game_tick`. None exist yet.

Gameplay-visible difference between candidates: **none meaningful.** All three fire exactly once per 16.8 ms frame. A bullet that moves 1 logical pixel per tick moves 1 pixel per frame regardless of which instant within the frame the tick happens. The only observable-in-theory difference is phase relative to scanout — which does not exist as something a player can see, because a frame is atomic from the viewer's perspective (one atomic scanout pass per 60 Hz). No difference in input-to-pixel latency, either: button presses are sampled asynchronously, registered into the 25 MHz domain, and their effect shows up on the *next* rendered frame regardless of the tick's in-frame position.

## 4. Race-hazard analysis (the reason this decision matters)

The hazard is **torn sprites**: if `game_tick` fires while the renderer is mid-draw, any input read combinationally by the renderer can change mid-sprite. Let's check each input:

- `player_x`, `player_y`, `boss_x`, `boss_y`: **latched** into `cur_sx`/`cur_sy` at the transition out of `S_CLEAR` (`renderer.v:198-199`) and out of `S_DRAW_PL` (`renderer.v:216-217`). Safe once captured.
- `pb_x_flat`, `pb_y_flat`, `pb_active`: **read combinationally** in `S_DRAW_PB` (`renderer.v:150-151, 247-252`). If these change mid-sprite, the bullet is torn.
- `bb_x_flat`, `bb_y_flat`, `bb_active`, `bb_pattern_flat`: **read combinationally** in `S_DRAW_BB` (`renderer.v:152-155, 272-278`). Same tearing risk.

Boss position also exposes a subtle window: `cur_sx <= boss_x` fires one cycle into `S_DRAW_BOSS`. If `game_tick` fires between `S_DRAW_PL` exit and the first cycle of `S_DRAW_BOSS`, boss_x may have already updated when it's latched — but that's a clean frame-boundary behavior, not tearing.

Now the three candidates under the hazard:

| Candidate | Fires when renderer is in state | Bullets may change mid-draw? |
|-----------|----------------------------------|-------------------------------|
| **C1** (vSync rise, `vCount == 0`) | Depends on bullet count. Naive strategy (36,864 cycles starting at `vCount == 480`) finishes at ~`vCount == 1`; vSync rising is at `vCount == 0` ⇒ renderer is **still in `S_DRAW_BB`**. **HAZARD: torn bullet sprites are possible.** Dirty-region strategy (~10K cycles) would finish much earlier, *inside* active display, so by `vCount == 0` the renderer is idle and the hazard disappears. But the hazard's presence or absence shouldn't depend on which optimization is live. | **Yes — possible today, under naive Week-1 strategy.** |
| **C2** (`vCount == 480` rise) | Exactly at `S_WAIT_VBL → S_CLEAR`. `game_tick` and the renderer's internal `vbl_rise` fire on the same pixel-clock edge. Bullet inputs update in the same cycle; by the time `S_DRAW_PB` begins (~30,000 cycles later), bullets are long stable. | **No.** `game_tick` is a single-cycle pulse; bullets update once per pulse and hold until the next pulse, which is 420,000 cycles away. |
| **C3** (`S_DONE`) | By definition, `S_DONE → S_WAIT_VBL` occurs *after* all drawing completes. Game logic updates; renderer is idle; next write window begins at `vCount == 480` with already-settled positions. | **No.** |

C1 has a hazard under the current Week-1 strategy and the hazard's status flips when optimizations land — that kind of "works only because of an unrelated optimization" coupling is exactly the class of bug we don't want to absorb. C2 and C3 are both race-safe.

## 5. Recommendation

**Keep C2 (rising edge of `vCount == 480`).** One-sentence reason: it's race-safe under both the naive and dirty-region renderer strategies, requires no new signals, and coincides with the renderer's existing internal edge — so there's exactly one frame-timing edge in the design for a reader to learn.

Secondary note (not a decision, just cleanup worth doing alongside): fix the "start of vertical blanking" language in SPEC §1.1 and the `// Triggered at vblank start` comment in `renderer.v:111`. `vCount == 480` is 35 lines *before* true vblank — it's the renderer's write-window start, not vblank start. Low priority but factually wrong as-is.

## 6. Reversibility

- **C2 → C1:** one-line change in `top.v` (once `top.v` generates `game_tick`). Zero RTL ripple, because no module currently reads `game_tick`.
- **C2 → C3:** add an output port to `renderer.v` + a wire in `top.v`. ~3 lines total, across 2 files. Small but non-trivial.
- **After Week 2 modules exist:** still a one-line change in `top.v` (the generator), because those modules only consume the already-packaged `game_tick` signal — they don't know its origin.

Cheap to flip either direction until Week 3. Past that, if game-feel tuning (e.g., bullet speeds chosen by eye) gets locked in, a phase shift from switching candidates is *theoretically* visible but in practice imperceptible (see §3) — so even then the flip is cheap.

## Appendix — signals referenced

- `display_controller.v:33` exposes `clk25_out` (our patch).
- `display_controller.v:52-66` drives `hCount`/`vCount`.
- `display_controller.v:68-69` drives `hSync`/`vSync`.
- `renderer.v:136-137, 169-188` implements `vbl_rise` and its consumer.
- `vga_test_top.v:39-57` uses the same `vbl_rise` pattern for the bouncing-square test — a second datapoint that C2's edge is already the convention.
