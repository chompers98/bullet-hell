# Session 3 — player_bullet SPEC dry-run (spec-agent)

**Invoked:** 2026-04-16, session 3, step 5.
**Agent:** `spec-agent` (system prompt inlined into `general-purpose` runner).
**Purpose:** surface SPEC gaps for `player_bullet` now — before a real spec→rtl→qc→verification cycle starts — so Beaux can close them cheaply rather than under mid-cycle pressure.
**Inputs:** `docs/SPEC.md`, `docs/GOTCHAS.md`.

---

# `player_bullet` contract dry-run — spec-agent reply

## §A — Full contract summary for `player_bullet`

### A.1 Module existence and ownership

- Listed in the module index: `player_bullet`, file `src/player_bullet.v` (TBD), Owner: **Beaux**, Week 2. Cited: `SPEC.md §2` (module index, line 174).
- Substantive description lives in `SPEC.md §10.2` ("Modules planned for Week 2/3 (interfaces only)"), which the section header explicitly labels as **sketches**, not full specs ("Full per-module specs land when each module starts implementation." `SPEC.md §10` preamble, lines 531–533).

### A.2 Port list — what SPEC pins down

SPEC does **not** publish a `module player_bullet (...)` block anywhere. The port contract has to be reconstructed from three separate sections:

**Outputs** (named, widths pinned):
- `pb_x_flat [63:0]` — 8 player bullets × 8 bits, slot `i` at bits `[i*8 +: 8]`, slot 0 = LSB. `SPEC.md §1.7` (lines 123), `§1.8` (packing, lines 136–145), `§10.2` (line 546).
- `pb_y_flat [63:0]` — same packing. `SPEC.md §1.7` line 123, `§10.2` line 546.
- `pb_active [7:0]` — one bit per slot, 1 = drawn, slot 0 = LSB. `SPEC.md §1.7` line 124, `§10.2` line 546.

**Inputs** (named in §10.2 prose, but no port block):
- `shoot_pulse` — single-cycle pulse; drives spawn. Declared as an **output of `player_controller`** at `SPEC.md §10.1` line 538. `player_bullet` must accept it but SPEC does not restate the direction/width in §10.2.
- Position inputs for spawning (`player_x`, `player_y`) — implied by "Spawn on `shoot_pulse`" (`§10.2` line 545) but not listed as ports. Widths would be 8 each per `§1.7` line 121.

**Inputs required by system contract but not listed in §10.2:**
- `pixel_clk` — "single clock domain in Week 1: every RTL module synchronous to `pixel_clk` (25 MHz)." `SPEC.md §1.1` line 53. `§1.7` line 113 lists it as canonical.
- `reset` — "Reset signal name is `reset` in every module port list." `SPEC.md §1.2` line 58. Active-high sync, `§1.2` line 58 and `§1.7` line 114.
- `game_tick` — implied by "Advance Y up by N (TBD ⚠) per tick." `§10.2` line 545. `game_tick` is defined in `§1.1` line 54 and `§1.7` line 128 ("Driven by `top.v`; not yet exposed as an inter-module port — game logic modules will subscribe in Week 2.").
- A "collision hit" input ("Despawn on Y leaving screen or on collision hit." `§10.2` line 545). The `collision` module at `§10.5` line 561 outputs `boss_hit_pulse` — a scalar pulse, not per-slot. SPEC does not say what signal `player_bullet` subscribes to.

### A.3 Behavioral contract — what SPEC pins down

From `SPEC.md §10.2` lines 544–546 in full:

1. **Pool size:** 8 slots. Each slot carries `(x, y, active)`.
2. **Spawn rule:** "Spawn on `shoot_pulse` if a free slot exists."
3. **Advance rule:** "Advance Y up by N (TBD ⚠) per tick."
4. **Despawn rule:** "Despawn on Y leaving screen **or** on collision hit."
5. **Output bus packing:** per `§1.7` naming + `§1.8` packing convention.

No other behavior is pinned.

### A.4 Timing — what SPEC pins down

- Clock: `pixel_clk` at 25 MHz. `§1.1` line 53. Not explicitly restated for `player_bullet`.
- Reset: synchronous active-high on `reset`. `§1.2` lines 58–62.
- Advancement: "per tick" = per `game_tick` pulse. `§10.2` line 545. `game_tick` is defined as a single-cycle pulse on the rising edge of `vCount == 10'd480`. `§1.1` line 54, `§1.7` line 128, and `GOTCHAS.md §G15` lines 162–171.
- Spawn timing: "on `shoot_pulse`" — `shoot_pulse` is a single-cycle pulse per `§10.1` line 538. SPEC does not say whether the spawn happens the cycle `shoot_pulse` is high, or on the next `game_tick`, or on a combination.

### A.5 Interaction with adjacent modules — what SPEC pins down

- **`player_controller` → `player_bullet`:** `shoot_pulse` (producer: `§10.1` line 538). Spawn position is nowhere stated explicitly; SPEC only implies it via the verb "spawn on `shoot_pulse`."
- **`player_bullet` → `renderer`:** `pb_x_flat`, `pb_y_flat`, `pb_active` per `§4.1` lines 252–254, and `§1.7` canonical names.
- **`collision` → `player_bullet`:** implied by "Despawn on … collision hit." `§10.2` line 545. `§10.5` lists `boss_hit_pulse` (line 561) as `collision`'s output — but it's a single scalar, and SPEC does not say how a single-bit pulse tells `player_bullet` **which slot** to deactivate.

### A.6 Resource / width constraints — what SPEC pins down

- Slot count: 8. `§10.2` line 545; `§1.7` line 124 ("8 player bullets × 8 bits"); `§4.1` line 254.
- Per-slot coordinate width: 8 bits. `§1.7` line 123, `§1.8` lines 138–145.
- Flat-bus packing: MSB-first concatenation, slot 0 at LSB, indexed `[i*8 +: 8]`. `§1.8` lines 138–145. `GOTCHAS.md §G9` reinforces.
- No packed arrays in port lists. `§1.8` line 147, `GOTCHAS.md §G9`.
- Verilog-2001 only (until Q1 resolves). `§0 Q1` line 34, `GOTCHAS.md §G13`.

### A.7 Cross-references (implicit contracts)

- Bullet-bus packing rule lives in `§1.8`, **not** in `§10.2`.
- Reset behavior has a canonical shape in `§4.7` and in `§1.2`. `§10.2` does **not** provide an equivalent enumerated reset list.

---

## §B — Ambiguities and gaps that would block rtl-agent today

```
⚠ GAP/UNDECIDED: What is the Y advance rate N (logical pixels per game-tick)?
Decision owner: Beaux
What SPEC currently says: "Advance Y up by N (TBD ⚠) per tick." SPEC.md §10.2 line 545.
What the rtl-agent cannot decide today: The integer decrement applied to each active slot's y register per game_tick.
```

```
⚠ GAP/UNDECIDED: Does player_bullet have a full port block with declared widths and directions?
Decision owner: Beaux
What SPEC currently says: Nothing. §10.2 (lines 543–546) is prose-only; no `module player_bullet (...)` block exists anywhere in SPEC.
What the rtl-agent cannot decide today: The exact port list to emit — which inputs are wires vs regs, which are single-bit vs multi-bit, which signals are even in the port list at all.
```

```
⚠ GAP/UNDECIDED: Is game_tick a port on player_bullet?
Decision owner: Beaux
What SPEC currently says: §1.7 line 128 — "Driven by top.v; not yet exposed as an inter-module port — game logic modules will subscribe in Week 2." §10.2 requires "per tick" advancement but does not list game_tick as an input.
What the rtl-agent cannot decide today: Whether to add `input wire game_tick` (and what its semantics are — edge vs level).
```

```
⚠ GAP/UNDECIDED: Is shoot_pulse a port on player_bullet?
Decision owner: Beaux
What SPEC currently says: §10.1 line 538 declares shoot_pulse as an output of player_controller (single-cycle). §10.2 line 545 says "Spawn on shoot_pulse" but does not list it as a port.
What the rtl-agent cannot decide today: Port entry for shoot_pulse (direction, width).
```

```
⚠ GAP/UNDECIDED: What are the spawn coordinates for a new bullet?
Decision owner: Beaux
What SPEC currently says: "Spawn on shoot_pulse if a free slot exists." §10.2 line 545. No spawn-position rule.
What the rtl-agent cannot decide today: Whether to take player_x/player_y as inputs and copy them (and which offset, since the sprite is 16×16 and player is centered at (92,126) per §9.2).
```

```
⚠ GAP/UNDECIDED: How is "free slot" selected when multiple slots are free?
Decision owner: Beaux
What SPEC currently says: "if a free slot exists." §10.2 line 545. No priority rule.
What the rtl-agent cannot decide today: Priority-encoder direction (lowest-index-first vs round-robin).
```

```
⚠ GAP/UNDECIDED: What happens if shoot_pulse fires when all 8 slots are active?
Decision owner: Beaux
What SPEC currently says: Only "Spawn … if a free slot exists." §10.2 line 545. No else-branch.
What the rtl-agent cannot decide today: Drop silently vs overwrite oldest vs other.
```

```
⚠ GAP/UNDECIDED: What happens if shoot_pulse is asserted for more than one cycle, or if two shoot_pulses arrive in the same game-tick?
Decision owner: Beaux
What SPEC currently says: §10.1 line 538 declares shoot_pulse as "single-cycle." SPEC does not discuss multi-cycle or back-to-back behavior.
What the rtl-agent cannot decide today: Spawn at most one bullet per pulse vs per tick vs per rising edge.
```

```
⚠ GAP/UNDECIDED: Precise "Y leaving screen" despawn threshold.
Decision owner: Beaux
What SPEC currently says: "Despawn on Y leaving screen." §10.2 line 545. Logical fb y-range is 0..149 per §1.3 line 70, sprites are 16×16 per §1.6.
What the rtl-agent cannot decide today: `y == 0` vs `y < 0` (underflow on unsigned 8-bit) vs `y + 16 < 0` vs wrap-check — and whether despawn is same-cycle or next tick.
```

```
⚠ GAP/UNDECIDED: Does player_bullet despawn on left/right/bottom edges?
Decision owner: Beaux
What SPEC currently says: Only "Y leaving screen." §10.2 line 545.
What the rtl-agent cannot decide today: Whether to add any x-bounds check.
```

```
⚠ GAP/UNDECIDED: What signal tells player_bullet "collision hit on slot i"?
Decision owner: Leyaa
What SPEC currently says: §10.2 line 545 says "Despawn on … collision hit." §10.5 line 561 lists collision's outputs as `boss_hit_pulse, player_hit_pulse` — both scalar pulses, not per-slot vectors.
What the rtl-agent cannot decide today: Per-slot despawn mask vs scalar-plus-slot-index vs collision-interface-growth.
```

```
⚠ GAP/UNDECIDED: Is there a per-bullet active-slot reset list in §10.2 equivalent to §4.7?
Decision owner: Beaux
What SPEC currently says: §4.7 lines 336–342 enumerates per-register reset values for renderer. §1.2 lines 58–62 mandates "clear every state register to a defined value (listed in each module's section)." §10.2 has no such enumeration.
What the rtl-agent cannot decide today: Exact reset values for slot regs + any internal arbiter / edge-latch regs.
```

```
⚠ GAP/UNDECIDED: Is shoot_pulse already edge-aligned by player_controller, or does player_bullet need its own edge detector?
Decision owner: Leyaa (player_controller owner)
What SPEC currently says: §10.1 line 538 calls shoot_pulse "(single-cycle)." §10.2 does not discuss edge detection.
What the rtl-agent cannot decide today: Latch prev-pulse and spawn on rising edge vs trust level==1.
```

```
⚠ GAP/UNDECIDED: Does advancement and spawn happen in the same tick, and in what order?
Decision owner: Beaux
What SPEC currently says: §10.2 line 545 sentences are orthogonal. No ordering.
What the rtl-agent cannot decide today: If shoot_pulse coincides with game_tick, whether the new bullet is advanced that same tick or next — affects visible spawn position by N px.
```

```
⚠ GAP/UNDECIDED: Which sprite ROM does player_bullet rely on, and does player_bullet itself reference it?
Decision owner: Beaux
What SPEC currently says: §7 lists sprite_rom_pbullet. §4.4 line 308 puts the blit in the renderer's S_DRAW_PB state.
What the rtl-agent cannot decide today: Nothing to decide (renderer owns the blit) — but SPEC should state this explicitly.
```

```
⚠ GAP/UNDECIDED: What is the player_bullet output timing relative to renderer's scanout?
Decision owner: Beaux
What SPEC currently says: §1.7 line 128 says game-logic modules "will subscribe in Week 2." §4.5 discusses vblank timing. Nothing says whether pb_x_flat/pb_y_flat are expected stable throughout the frame or only at vblank entry.
What the rtl-agent cannot decide today: Register outputs (to guarantee tick-boundary stability) vs drive combinationally.
```

```
⚠ GAP/UNDECIDED: Does player_bullet implement any firing cooldown / rate limit?
Decision owner: Beaux
What SPEC currently says: Nothing in §10.2.
What the rtl-agent cannot decide today: Whether to gate spawns behind a cooldown counter.
```

```
⚠ GAP/UNDECIDED: Is `shoot_pulse` synchronous to pixel_clk, and is any CDC required?
Decision owner: Puvvada (tooling) / Beaux
What SPEC currently says: §1.1 line 53 ("single clock domain in Week 1"), GOTCHAS §G12 ("no CDC"). §10.1 does not restate that player_controller runs on pixel_clk.
What the rtl-agent cannot decide today: Nothing new — defaults are clear — but §10.2 sketch doesn't reference §1.1.
```

```
⚠ GAP/UNDECIDED: Are any slots reserved / is slot 0 special in any way?
Decision owner: Beaux
What SPEC currently says: §1.8 line 139 pins slot 0 = LSB of the bus. §9.2 line 517 uses pb_active = 8'b0000_0001 as a Week 1 hardcoded test scene — implying slot 0 is "first used" but not mandating it.
What the rtl-agent cannot decide today: Whether spawn priority must start at slot 0 (matching §9.2's test expectation).
```

```
⚠ GAP/UNDECIDED: Are the x coordinates updated at all (e.g., for angled shots) or strictly held?
Decision owner: Beaux
What SPEC currently says: "Advance Y up by N per tick." §10.2 line 545. No mention of x.
What the rtl-agent cannot decide today: Write x once at spawn and never update (almost certainly the intent) vs something fancier.
```

```
⚠ GAP/UNDECIDED: Player has 120-tick i-frames (§0 Q6, §10.5 line 562) — does player_bullet care?
Decision owner: Beaux
What SPEC currently says: §10.5 line 562 discusses i-frames for the player but does not mention player_bullet.
What the rtl-agent cannot decide today: Nothing — likely no interaction — but SPEC's silence leaves it unstated.
```

Twenty-one gaps. That is the full set of items a strict reading of SPEC `§10.2` (plus the system contracts in `§1.*` it inherits) leaves unresolved for the `player_bullet` module before an rtl-agent could emit a module body.

---

## Caller-side evaluation

- **Thoroughness:** 21 gaps surfaced from a 3-line SPEC sketch is the expected outcome of promoting a sketch to a full contract. The §10 preamble (lines 531–533) admits §10.2 is a sketch; this dry-run quantifies the gap.
- **Citation discipline:** every gap cites its closest SPEC section or explicitly says "nothing." Owner attribution follows the spec-agent ownership rule (Beaux = module-level decisions, Leyaa = player_controller/collision decisions).
- **Win for the dry-run pattern:** 21 Beaux-side decisions are cheap to make now in one session with coffee. Same 21 decisions discovered mid-rtl-agent cycle would be painful — mid-cycle decision-making stalls the spec→rtl→qc→verification pipeline.
- **Key cluster of questions (for Beaux to close first):** spawn position, spawn priority, collision-hit signal semantics, advance rate N, reset enumeration, game_tick/shoot_pulse port declarations. Answer these six and 15 of the 21 gaps collapse.
