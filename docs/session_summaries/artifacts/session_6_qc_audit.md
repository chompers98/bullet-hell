# Session 6 — QC audit of `player_bullet.v`

**Source:** qc-agent invocation 2026-04-19, native `Agent(subagent_type: "qc-agent")`.
**Target:** `ee354_bullet_hell/src/player_bullet.v` (written session 5).
**References:** `docs/SPEC.md` §10.2 (full), `docs/GOTCHAS.md` §§G9, G13, G14, G15, G18, `docs/CONVENTIONS.md`.

This file captures the qc-agent's audit notes, findings table, and verdict **verbatim** — no orchestrator-side editing, summarization, or reordering. Triage and classification live in `session_6_qc_triage.md`.

---

## Audit notes (brief, by step)

1. **Interface:** All 10 SPEC ports present; names, widths, and directions match §10.2.1 L552-569 exactly. No extra ports.
2. **Behavioral:** Per-tick order (advance → despawn → spawn) implemented in a single comb block reading post-previous-step state. `shoot_latch` priority chain in separate seq block matches §10.2.3 template verbatim. Spawn uses lowest-index-first scan with `found` guard, sets `player_x`/`player_y-16` per §10.2.2 step 3. Overflow drop and pool-full re-trigger semantics follow from latch reset on every game_tick per §10.2.5.
3. **Gotchas:** G9 ✓ (flat 64-bit buses). G13 ✓ (no SV syntax). G14 ✓ (no `initial`). G15 ✓ (game_tick treated as a single-cycle enable; stateful block is a no-op when low). G18 ✓ (all next-state signals defaulted at top of `always @*`).
4. **Reset:** All 4 state categories per §10.2.6 (pb_x, pb_y, pb_active, shoot_latch) reset to the specified values. Combinational regs correctly not reset.
5. **Timing:** Single clock domain (`pixel_clk`). Two `always @(posedge pixel_clk)` blocks, both sync-reset. No latches, no async reset, no comb loops.
6. **Synthesis:** Verilog-2001 clean. No SV. No `initial`. No memory inference applies here.
7. **Uncertainty:** No inline `⚠ UNCERTAINTY`. The `hit_mask` Q9 inline note (L37-40) and IMPL DECISION entry (L24-26) are forward-flags per SPEC §10.2.1's own ⚠ annotation — not a CRITICAL per SPEC §0 rules. All cited SPEC references in IMPL DECISIONS block resolve correctly.

## Findings

| # | Severity | File:Line(s) | Finding | SPEC/GOTCHA citation |
|---|----------|--------------|---------|----------------------|
| 1 | STYLE | player_bullet.v:84-91 | Magic number `8'd2` (bullet Y-advance) repeated 8×; no named constant ties it to Q7 = N. A `localparam BULLET_DY = 8'd2;` with a `// Q7` comment would document the tunable. | SPEC §10.2.5 (Q7) |
| 2 | STYLE | player_bullet.v:95-102 | Magic number `8'd150` (FB height = despawn threshold) repeated 8×. A `localparam FB_H = 8'd150;` would document the link to SPEC §1.3. | SPEC §1.3, §10.2.2 step 2 |
| 3 | STYLE | player_bullet.v:111,117,123,129,135,141,147,153 | Magic number `8'd16` (sprite height / spawn offset) repeated 8×. A `localparam SPRITE_H = 8'd16;` would document the link to §10.2.5 rationale. | SPEC §10.2.5 |
| 4 | STYLE | player_bullet.v:37-40 | Q9 forward-flag is duplicated across IMPL DECISIONS (L24-26) and port comment. Acceptable; the SPEC's ⚠ annotation justifies it, but the inline copy restates rather than points. | SPEC §10.2.1 (⚠ Q9 marker) |

## Verdict

```
VERDICT: PASS
Critical: 0  Warning: 0  Style: 4
Anti-gaming downgrade applied: no
```

Every row carries a file:line and a SPEC/GOTCHA citation, so the anti-gaming rule is not triggered. No CRITICAL, no WARNING — clean on spec compliance, reset enumeration, port list, Verilog-2001 compliance, G15 edge handling, and G18 latch avoidance. Only STYLE findings for named constants remain, none of which block PASS.

Relevant files reviewed:
- `/Users/bcable/ee354finalproject/ee354_bullet_hell/src/player_bullet.v`
- `/Users/bcable/ee354finalproject/docs/SPEC.md` (§§0, 1.1-1.8, 10.2)
- `/Users/bcable/ee354finalproject/docs/GOTCHAS.md` (§§G9, G13, G14, G15, G18)
- `/Users/bcable/ee354finalproject/docs/CONVENTIONS.md`
