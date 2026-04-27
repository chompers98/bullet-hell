# Session 5 — spec-agent §10.2 contract check

**Invoked:** 2026-04-18. Agent: `spec-agent` (native subagent, Claude Code).

**Prompt given:**
> Review SPEC.md §10.2 (all subsections §10.2.1 through §10.2.8). Question: is the contract complete enough that an rtl-agent could implement `src/player_bullet.v` today without any ⚠ UNCERTAINTY markers beyond the known Q9 default?
>
> Enumerate any gap or ambiguity you find, citing SPEC line numbers. If you find none, say so explicitly and list the per-tick behavioral invariants you derived from §10.2.2 so the rtl-agent has a canonical summary to check against.

---

## Agent output (verbatim)

# Report: §10.2 `player_bullet` contract completeness review

## Verdict: **PASS — contract complete**

An rtl-agent can implement `src/player_bullet.v` today with only the named Q9 default as a pending uncertainty. All other dimensions (port list, widths, directions, per-tick behavior, latch semantics, packing, reset values, hazards) are pinned.

---

## Per-tick behavioral invariants (canonical summary)

Derived strictly from §10.2.1 (lines 550–569), §10.2.2 (lines 571–585), §10.2.3 (lines 587–602), §10.2.4 (lines 604–613), §10.2.5 (lines 615–622), §10.2.6 (lines 624–633), §10.2.7 (lines 635–640), with cross-references to §1.1, §1.2, §1.7, §1.8.

### Clocking & reset

- **I1 (single clock).** Every `always @(posedge pixel_clk)` block. `game_tick` is an **enable**, never a clock. (§1.1 line 57; GOTCHAS §G12, §G15.)
- **I2 (reset priority).** `if (reset) … else if (game_tick) …`. Reset wins over tick in the same cycle. Pattern shown in §10.2.3 lines 593–599.
- **I3 (reset values).** `pb_x[0..7] <= 0`, `pb_y[0..7] <= 0`, `pb_active[0..7] <= 0`, `shoot_latch <= 0`. One cycle after reset deassert, `pb_active == 8'd0`. (§10.2.6 lines 628–633.)
- **I4 (sync active-high).** Per §1.2 lines 61, 64. No async resets.

### Per-`game_tick` state transition (strict order)

- **I5 (advance first).** For each `i` where `pb_active[i] == 1`, compute `pb_y_next[i] = pb_y[i] − 8'd2` (N=2 per Q7). 8-bit unsigned; underflow wraps to ≥240. (§10.2.2 line 577; §10.2.5 line 617.)
- **I6 (despawn second).** For each `i`: if `pb_y_next[i] >= 8'd150` OR `hit_mask[i]`, then `pb_active_next[i] = 0`. The `>= 150` test catches both legitimate top-exit (y decremented past 0) and the spawn-underflow case from I9. (§10.2.2 lines 578–580.)
- **I7 (spawn third, reads post-step-2 state).** If `shoot_latch == 1`, scan `pb_active_next[7:0]` **LSB-first** for the first clear slot. If found: set `pb_active_next[i]=1`, `pb_x_next[i]=player_x`, `pb_y_next[i]=player_y − 8'd16`. (§10.2.2 lines 581–584.)
- **I8 (slot-freed-this-tick is reusable).** Because step 3 reads `pb_active_next` (the post-despawn vector), a slot despawned at step 2 is spawnable at step 3 in the same tick. (§10.2.2 line 581, explicit.)
- **I9 (spawn-underflow despawn on next tick).** If `player_y < 16`, `pb_y_next` wraps to the 240-range on spawn; next tick's step 1 advances by −2 and step 2's `>= 150` check despawns it. Expected and accepted behavior. (§10.2.2 line 584 parenthetical.)
- **I10 (freshly-spawned bullet does NOT get advanced this tick).** Step 3 writes the spawn values after step 1 has already committed its advance for this tick; first advance applied next tick.
- **I11 (x is write-once).** `pb_x[i]` is only written at spawn and preserved for the slot's lifetime. Only `y` changes per tick. No angled shots. (§10.2.5 line 622.)
- **I12 (`hit_mask` on inactive slot is a no-op).** Clearing an already-clear bit is benign; no guard required. Implicit from §10.2.2 line 580.
- **I13 (overflow drops silently).** `shoot_latch` clears every tick regardless of whether a free slot was found. (§10.2.5 line 620; §10.2.2 line 585.)

### `shoot_pulse` latching (every pixel_clk)

- **I14 (latching block is verbatim).** The always-block at §10.2.3 lines 591–600 is the implementation. Reset clears latch; `game_tick` clears latch; `shoot_pulse` sets it. Else-chain priority is exactly as written. (§10.2.3.)
- **I15 (multiple shoot_pulses collapse to one).** Between two ticks, any number of `shoot_pulse` assertions produce at most one spawn attempt. (§10.2.3 line 602; §10.2.5 line 621.)
- **I16 (pool-full lockout).** If the spawn attempt finds no free slot, the press is lost; user must re-press. (§10.2.3 line 602.)

### Output packing

- **I17 (flat buses, slot 0 = LSB).** Packing exactly as §10.2.4 lines 607–610 and §1.8 lines 141–142: `{pb_x[7], pb_x[6], …, pb_x[0]}`. Slot `i` lives at `[i*8 +: 8]`. (§10.2.4, §1.7 line 126, §1.8; GOTCHAS §G9.)
- **I18 (outputs are wires driven by continuous assign).** No combinational output path. Internal state is registered; top-level outputs are `wire`. (§10.2.7 line 637.)

### Interface identity

- **I19 (port names load-bearing).** Exactly as listed in §10.2.1 lines 553–568. qc-agent fails renames. (§1.7 line 135.)
- **I20 (Q9 default pinned).** `hit_mask[7:0]` is the per-slot despawn mask. If Leyaa ships scalar+index, Beaux updates §10.2.1 — until then, the mask form is the contract. (§10.2.1 lines 562–563; §10.2.8 line 644; §10.5 line 662.)

---

## Minor wording frictions (informational, not blocking)

These do not create decisions the rtl-agent must make. Flagging for Beaux's next SPEC pass.

- **§10.2.4 line 613** says `pb_active` is "already a flat 8-bit reg; drive directly", while the port at line 567 is `output wire [7:0] pb_active`. A Verilog-2001 module cannot have both a `wire` port and a same-named internal `reg`. Intent is clear (internal `pb_active_reg`, continuous `assign pb_active = pb_active_reg;`, consistent with §10.2.7 line 637); wording is loose.
- **§10.2.2 step 3 line 585** says "Clear `shoot_latch_next` unconditionally," written in next-state-reg style. §10.2.3 lines 591–600 uses the direct-latch style (`else if (game_tick) shoot_latch <= 1'b0;`). Both produce identical behavior; the two styles sit adjacent without a cross-note. An rtl-agent following §10.2.3 verbatim automatically satisfies step 3's statement.

---

## Files referenced

- `/Users/bcable/ee354finalproject/docs/SPEC.md` §10.2 (lines 546–644), §1.1 (line 57), §1.2 (lines 61–65), §1.7 (lines 126–131), §1.8 (lines 137–150), §10.5 (lines 656–663).
- `/Users/bcable/ee354finalproject/docs/GOTCHAS.md` §G9 (flat buses), §G12 (single clock domain), §G14 (no `initial` for state), §G15 (game_tick is a single-cycle pulse).

---

## Orchestrator disposition

**Verdict:** clean PASS. Proceeding to Step 2 (verification-agent). Two minor wording frictions flagged for Beaux's next SPEC pass — non-blocking for this session because the intent is unambiguous and §10.2.7 / §10.2.3 already disambiguate in the direction the rtl-agent will implement.
