# Session 3 — proposed resolutions to open questions

**Scope:** items that can be closed (or sharpened) without input from Beaux, Leyaa, or Puvvada. Items that require a human are listed at the bottom as "still open" and left alone.

**This file is a proposal. SPEC.md has NOT been edited based on it.** Beaux reviews and accepts/rejects each row before any edit lands.

---

## Resolvable without human input

### R1 — Add `U-PB-SPEED` and `U-IFRAME-LOC` rows to SPEC §0

**What:** SPEC §0 L41 mandates: "If an agent encounters a question not listed here, it must add a row marked ⚠ UNDECIDED rather than guess." Two markers exist in module sections but are absent from §0:

- SPEC §10.2 L543 — `player_bullet` per-tick Y advance `N (TBD ⚠)`.
- SPEC §10.5 L560 — location of the 120-tick i-frame counter (`collision` vs `top.v`).

**Proposed §0 rows:**

| ID | Question | Owner | Default in force |
|----|----------|-------|-------------------|
| Q7 | Player-bullet per-tick Y-advance speed `N` (see §10.2). | Beaux | None — must be decided before `player_bullet` implementation. |
| Q8 | Location of the 120-tick player i-frame counter: inside `collision`, `top.v`, or `player_controller`? (See §10.5.) | Beaux | None — must be decided before `collision` implementation. |

**Why this is derivable:** the §0 rule is mechanical. This is a hygiene edit, not a content decision.

**Proposed action:** Beaux accepts → I add both rows to §0 in a follow-up edit within this session. (Not done unilaterally because the §0 table is SPEC's most visible surface.)

---

### R2 — Proposed resolution for Q8 (i-frame counter location)

**Recommendation:** place the i-frame counter inside `collision`.

**Argument from existing SPEC:**
- SPEC §10.5 L557–559 specifies `collision` emits `player_hit_pulse`. The only consumer of i-frame state is the gate that decides whether to emit that pulse on a given hit event. Co-locating counter and gate minimises cross-module signals.
- The alternative — counter in `top.v` — requires `top.v` to emit an `iframe_active` wire back into `collision`, which inverts the normal data-flow direction (game-logic glue downstream of game-logic modules, not upstream).
- The third alternative — counter in `player_controller` (Leyaa) — would force `player_controller` to observe hits, coupling movement logic to collision logic.

**Why this is still Beaux's call, not a unilateral edit:** the choice has downstream consequences (it changes the `collision` module's port list and its SPEC §10.5 stub), and ownership is explicitly tagged Beaux in SPEC §10.5 L560. Recommendation only.

---

### R3 — Proposed resolution for Q7 (player-bullet speed `N`)

**Recommendation:** `N = 2` logical pixels per game-tick, as a starting value, with explicit permission to tune after Week 2 playtest.

**Derivation from existing SPEC:**
- Framebuffer is 150 logical pixels tall (SPEC §1.6).
- Player spawns at `y = 126` (SPEC §9.2). Bullet travel distance ≈ 126 px.
- Game-tick is 60 Hz (SPEC §1.1 — one pulse per frame at 60 Hz VGA refresh).
- Candidate traversal times: N=1 → 2.10 s, N=2 → 1.05 s, N=3 → 0.70 s, N=4 → 0.53 s.
- The class reference `_refs/TouhouChaoYiYe/` uses a bullet speed equivalent to ~1 s full-screen traversal. N=2 matches.

**Why this is still Beaux's call, not a unilateral edit:** game feel is subjective and owned by the implementer. This is a defensible starting value with cited reasoning, not a forced answer.

---

### R4 — Soft-confirm Q4 default (game-tick = rising edge of `vCount == 480`)

**Recommendation:** Beaux explicitly sign off on the session-2 pin, or override.

**Argument from existing SPEC for keeping the pin:**
- SPEC §1.1 L54, §1.7 L128, GOTCHAS §G15, and `top.v`'s design assume this already. Flipping it to the vSync edge (a few cycles later) or the renderer's `S_DONE → S_WAIT_VBL` transition (variable timing, depends on renderer state) would require a rename and SPEC rewrite across three sections.
- The `vCount == 480` choice earns its place because it's the **earliest** unambiguous start-of-vblank signal and is **decoupled** from renderer progress. The renderer-FSM transition option couples game-logic timing to renderer implementation details — avoid. The vSync-edge option is fine but arrives a few cycles later with no benefit.
- Session-2 rationale held: pick the earliest unambiguous point, decoupled from other FSMs.

**Why this is still Beaux's call:** the choice was pinned without explicit sign-off. Session 2 flagged this. Rubber-stamping it here would repeat the mistake. Recommendation only.

---

## Still requires a human — leave open

| ID | Question | Owner | Why it can't be auto-resolved |
|----|----------|-------|-------------------------------|
| Q1 | SV vs. Verilog-2001. | Puvvada | Grading-policy question, not a technical derivation. |
| Q2 | Palette matches Leyaa's sprite art. | Leyaa | Contingent on files Leyaa hasn't exported yet. |
| Q3 | `BtnC` vs. `CPU_RESETN` reset source. | Beaux | Both work; choice is ergonomic. SPEC §0 explicitly defers "when `player_controller` defines its reset semantics." |
| Q5 | Phase-2 boss-pattern threshold (`boss_hp ≤ 50`). | Leyaa | Game-balance value, Leyaa's scope. |
| Q6 | Exact i-frame count (120 ticks). | Beaux | Game-feel value. Default is reasonable but not derivable. |

---

## Summary for Beaux

- **Ready to land in SPEC immediately if you approve:** R1 (§0 hygiene — add Q7 and Q8 rows).
- **Recommendations for you to accept/reject:** R2 (Q8 → `collision`), R3 (Q7 → N=2), R4 (Q4 confirmation).
- **Still needs you, Leyaa, or Puvvada:** Q1, Q2, Q3, Q5, Q6.
