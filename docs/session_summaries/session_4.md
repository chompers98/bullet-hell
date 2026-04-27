# Session 4 — 2026-04-18

## Goal
Apply the SPEC edits from Beaux's pre-session-4 decision session. Promote §10.2 (`player_bullet`) from 3-line prose sketch to a full per-module section. Update §0 (formalize Q4, Q7, Q8, Q9) and §10.5 (i-frame counter location, hit-mask interface) to match. SPEC-only edits — no RTL, no testbenches, no agent invocations.

## What was reviewed / read
- `docs/session_summaries/GUIDELINES.md` — summary format.
- `docs/session_summaries/session_3.md` — entry conditions and open questions table.
- `docs/SPEC.md` — full pre-edit baseline before patching.
- `docs/session_summaries/artifacts/session_3_proposed_resolutions.md` — R1–R4 rationale.

Did **not** re-read `GOTCHAS.md`, `CONVENTIONS.md`, `AGENTS_README.md`, or any RTL — patches do not touch those.

## Decisions made, with the why

All decisions were ratified by Beaux pre-session and applied verbatim. No new judgment calls inside this session.

### Sticky decisions (pinned in SPEC §0)
- **R1 — Q7, Q8, Q9 added as formal §0 rows.** Q4 row rewritten from "default in force" to "Resolved (session 4)." Closes the §0 hygiene gap that session-3 spec-agent flagged (markers existed in §10.2 / §10.5 but weren't mirrored to §0).
- **R2 (Q8) — i-frame counter lives inside `collision`.** Co-located with the `player_hit_pulse` gate that consumes it. Avoids inverting the data-flow direction (counter in `top.v`) and avoids coupling movement logic to collision logic (counter in `player_controller`).
- **R3 (Q7) — `N = 2` logical pixels per tick.** ~1.05 s full-screen traversal at 60 Hz; matches the `_refs/TouhouChaoYiYe/` reference feel. Tunable post-playtest.
- **R4 (Q4) — game-tick = rising edge of `vCount == 10'd480`, confirmed.** Earliest unambiguous start-of-vblank signal; decoupled from renderer FSM state. SPEC §1.1, §1.7, GOTCHAS §G15 already assume this.

### Module-level decisions (pinned in SPEC §10.2.5)
- **(b) Spawn offset:** `bullet_y = player_y − 16`. Bullet sprite (16×16) sits immediately above player sprite (16×16) with no visual overlap. Underflow at `player_y < 16` is caught by the `pb_y ≥ 150` despawn check on the next tick.
- **(c) Spawn priority:** lowest-index-first. Simplest priority encoder; matches §9.2's Week 1 test expectation (`pb_active = 8'b0000_0001`).
- **(d) Overflow:** drop silently. `shoot_latch` clears on every `game_tick` regardless of spawn outcome. Pool-full wait at N=2 ≈ 63 ticks ≈ 1.05 s.
- **(e) `shoot_pulse` handling:** latch every pixel_clk; consume on next `game_tick`. Invariant: all `player_bullet` state changes happen on `game_tick`. Multi-pulse-per-tick collapses to single-spawn deterministically.
- **(f) Reset:** all regs to zero. `pb_x[0..7] <= 0`, `pb_y[0..7] <= 0`, `pb_active[0..7] <= 0`, `shoot_latch <= 0`.

### Q9 (Leyaa-owned, default in force)
- `collision → player_bullet` despawn signal = `hit_mask [7:0]`, one bit per bullet slot. Matches `collision`'s 8 player-bullet-vs-boss comparators directly. If Leyaa ships scalar `hit_pulse + slot_index` instead, `player_bullet`'s §10.2.1 port list changes by ~3 lines — the cost of waiting is small enough that the default is locked here, not deferred.

## Code scaffolded / modified

### Edited (SPEC.md only)
| Section | Before | After | Δ lines |
|---------|--------|-------|---------|
| §0 (Open questions table) | 6 rows (Q1–Q6) | 9 rows (Q1–Q9); Q4 row rewritten as "Resolved" | +3 lines |
| §10.2 (`player_bullet`) | 4 lines (header + 3-bullet prose sketch) | 100 lines, 8 subsections (§10.2.1–§10.2.8): port block, behavioral contract, latch logic, output packing, design rationale, reset, hazards, open items | +96 lines |
| §10.5 (`collision`) | 4 lines (header + 3 bullets, i-frame location undecided) | 9 lines: structured outputs (boss_hit_pulse, player_hit_pulse, hit_mask), i-frame counter pinned to `collision` | +5 lines |

Total: SPEC.md grew from 616 → 716 lines (+100, ~16% growth, all in §10.2).

### Untouched
- All RTL under `ee354_bullet_hell/`.
- `GOTCHAS.md`, `CONVENTIONS.md`, `AGENTS_README.md`.
- `.claude/agents/*.md`.
- All other SPEC sections (§1–§9, §11, §12, §10.1/§10.3/§10.4/§10.6).

## Verification

**No agent invocations this session.** No RTL touched. SPEC-only edits.

**Cross-reference grep performed in step 4 (results):**
- §0 table: Q1 → Q9 in order, no duplicates. ✓
- §10.2 ⚠ markers: only the Q9 reference at line 563 (expected — Leyaa-owned). No stale Q7 or Q8 markers. ✓
- §10.5 ⚠ markers: Q9 reference (line 662) and Q6 reference (line 663). Both expected to remain. ✓
- ⚠ markers elsewhere in SPEC: line 62 (Q3), line 648 (Q5). Outside scope, untouched. ✓
- `player_bullet` references outside §10.2: §0 Q9 row (intentional), §2 module index (just a name — no port info to update), §9.4 line 530 (just a name reference in growth-path narrative — no port info). No external section needed updating. ✓
- §1.7 canonical names list (`pb_x_flat`, `pb_y_flat`, `pb_active`) — already correct, no edit needed. ✓

No discrepancies found. No SPEC bugs noticed outside the patched sections during the cross-reference sweep.

## Open questions / blockers

| ID | Status entering session 5 | Owner |
|----|---------------------------|-------|
| Q1 | Open. SystemVerilog vs. Verilog-2001. No reply from Puvvada yet. | Puvvada |
| Q2 | Open. Awaiting sprite export. | Leyaa |
| Q3 | Default in force (`BtnC` active-high sync). Closeable at convenience. | Beaux |
| Q4 | **Closed this session** (session-4-resolved). | — |
| Q5 | Open. Phase-2 boss-pattern threshold. | Leyaa |
| Q6 | Default in force (120 ticks). | Beaux |
| Q7 | **Closed this session** (N = 2). | — |
| Q8 | **Closed this session** (counter inside `collision`). | — |
| Q9 | **Default in force** (`hit_mask [7:0]`). Awaiting Leyaa to confirm or override; if she ships scalar+index, `player_bullet` §10.2.1 port list changes by ~3 lines. | Leyaa |
| NEW-1 | Open. Project-level `.claude/agents/*.md` doesn't auto-register; session 3 forced inline-system-prompt routing. **Gates session 5.** Need `/agents` output (or equivalent) to decide native-vs-inline path before any agent invocation. | Beaux |
| NEW-2 | Mostly closed for `player_bullet` (the new §10.2 covers the 18 Beaux-owned gaps). Three Leyaa-owned gaps remain — collision-hit signal semantics now pinned as Q9 default; shoot_pulse edge-alignment now pinned in §10.2.3; `player_controller` reset semantics still open under Q3. | Leyaa |

## Next steps

Session 5 is the **first production cycle** on `player_bullet`. Order:

1. **(Beaux, before session 5)** Resolve NEW-1: confirm whether project agents (`spec-agent`, `rtl-agent`, `qc-agent`, `verification-agent`) register natively in this Claude Code install, or ratify the inline-system-prompt workflow as standard and update `AGENTS_README.md`. **Blocks step 2.**
2. **(Claude, session 5, gated on step 1)** spec-agent dry-run on the new §10.2: "is the contract complete enough for rtl-agent today?" Expected: clean PASS, since §10.2 was written precisely to close session-3's 21-gap dry-run.
3. **(Claude, session 5)** rtl-agent → `src/player_bullet.v`. Reads SPEC §10.2 + GOTCHAS + CONVENTIONS.
4. **(Claude, session 5, fresh subagent context)** qc-agent audit of the new file. PASS / REVISE / REJECT.
5. **(Claude, session 5)** verification-agent → `sim/player_bullet_tb.v`. Self-checking; assertions cite SPEC §10.2.x lines.
6. **(Beaux, parallel track)** Vivado bring-up for `vga_test_top` and `top.v` — still pending from session 1.
7. **(Beaux, eventually)** Renderer refresh batch (qc #1 vbl_prev placement, qc #2 IMPL DECISIONS retrofit, qc #6 G17 slicing comments, qc #7 width-intent comments).

## Handoff corrections

- **`docs/SPEC.md` §0** — Q4 row text expanded from `"Rising edge of vCount == 480 (start of vertical blanking). See §1.1."` to a multi-sentence "Resolved (session 4)" entry citing §1.1 and GOTCHAS §G15. Three new rows (Q7, Q8, Q9) appended. Existing Q1–Q3, Q5, Q6 untouched.
- **`docs/SPEC.md` §10.2** — full rewrite from prose sketch to subsectioned spec. **§10.2.1 through §10.2.8 must not be renumbered** by future sessions; agent prompts and downstream specs will cite by number.
- **`docs/SPEC.md` §10.5** — i-frame counter location pinned to `collision`; new `hit_mask [7:0]` output declared (Q9 default).
- **No edits made to `GOTCHAS.md`, `CONVENTIONS.md`, `AGENTS_README.md`, or any RTL.** §1.1, §1.7, §4.4, GOTCHAS §G15 are referenced from the new §10.2 but not modified — those references already aligned with the new content.

## Gotchas (new to this session)

- **Spawn offset underflow safety net.** §10.2.2 step 2 catches `player_y < 16` (which underflows the 8-bit `bullet_y = player_y − 16` to ≥240) by checking `pb_y_next >= 8'd150` in the same tick. The despawn check fires on the **next** tick after spawn (one frame of "hidden bullet at y≈240"). Acceptable because at N=2 it's invisible, but rtl-agent should reproduce the comparison **as written** (`>= 150`, not `> 150`, not signed). Verification-agent should hit this edge case explicitly.
- **`shoot_latch` clears on every `game_tick`, even on spawn failure.** Pool-full re-trigger is the user's responsibility, not the module's. This is a deliberate design choice (§10.2.5) and verification-agent must not "fix" it by holding the latch.
